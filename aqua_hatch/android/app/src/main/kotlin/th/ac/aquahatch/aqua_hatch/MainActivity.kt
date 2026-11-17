package th.ac.aquahatch.aqua_hatch

import android.Manifest
import android.annotation.TargetApi
import android.content.ContentValues
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        configureGallery(flutterEngine)
        configureVideoFrame(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "th.ac.aquahatch/wifi")
            .setMethodCallHandler { call, result ->
                val manager = getSystemService(ConnectivityManager::class.java)
                when (call.method) {
                    "openWifiSettings" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
                            result.success(null)
                        } catch (_: Exception) {
                            result.error("WIFI_SETTINGS_UNAVAILABLE", "เปิดหน้าตั้งค่า Wi-Fi ไม่ได้", null)
                        }
                    }
                    "bindWifi" -> {
                        val network = manager.allNetworks.firstOrNull {
                            manager.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
                        }
                        result.success(network != null && manager.bindProcessToNetwork(network))
                    }
                    "releaseWifi" -> result.success(manager.bindProcessToNetwork(null))
                    else -> result.notImplemented()
                }
            }
    }

    private fun configureVideoFrame(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "th.ac.aquahatch/video_frame")
            .setMethodCallHandler { call, result ->
                if (call.method != "read") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.arguments as? String
                if (path.isNullOrBlank()) {
                    result.error("invalid_clip", "อ่านเฟรมจากคลิปไม่ได้", null)
                    return@setMethodCallHandler
                }
                Thread {
                    try {
                        val bytes = readVideoFrame(path)
                        runOnUiThread { result.success(bytes) }
                    } catch (_: IllegalArgumentException) {
                        runOnUiThread {
                            result.error("invalid_clip", "เลือกคลิปที่อ่านได้และยาวไม่เกิน 60 วินาที", null)
                        }
                    } catch (_: Exception) {
                        runOnUiThread { result.error("frame_failed", "อ่านเฟรมจากคลิปไม่ได้", null) }
                    }
                }.start()
            }
    }

    private fun readVideoFrame(path: String): ByteArray {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
            require(duration != null && duration in 1..60_000)
            val timeUs = duration * 500
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            // Preserve the native size of small frames. Enlarging them makes
            // the fry larger than the scale used to train the model.
            val frame = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1 && maxOf(width, height) > 3840) {
                retriever.getScaledFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST, 3840, 3840)
            } else {
                retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST)
            } ?: throw IOException("Video frame unavailable")
            try {
                return ByteArrayOutputStream().use {
                    if (!frame.compress(Bitmap.CompressFormat.JPEG, 95, it)) throw IOException("JPEG encoding failed")
                    it.toByteArray()
                }
            } finally {
                frame.recycle()
            }
        } finally {
            retriever.release()
        }
    }

    private fun configureGallery(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "th.ac.aquahatch/gallery")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveJpeg") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val bytes = call.argument<ByteArray>("bytes")
                val name = call.argument<String>("name")
                if (bytes == null || bytes.isEmpty() || name == null || !photoName.matches(name)) {
                    result.error("invalid_photo", null, null)
                    return@setMethodCallHandler
                }
                if (pendingPhoto != null) {
                    result.error("save_in_progress", null, null)
                    return@setMethodCallHandler
                }
                val photo = PendingPhoto(bytes, name, result)
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
                    checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                    pendingPhoto = photo
                    requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), galleryRequest)
                } else {
                    savePhoto(photo)
                }
            }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != galleryRequest) return
        val photo = pendingPhoto ?: return
        pendingPhoto = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            savePhoto(photo)
        } else {
            photo.result.error("permission_denied", null, null)
        }
    }

    private fun savePhoto(photo: PendingPhoto) {
        Thread {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    saveWithMediaStore(photo)
                    runOnUiThread { photo.result.success(null) }
                } else {
                    saveLegacyPhoto(photo)
                }
            } catch (_: Exception) {
                runOnUiThread { photo.result.error("save_failed", null, null) }
            }
        }.start()
    }

    @TargetApi(Build.VERSION_CODES.Q)
    private fun saveWithMediaStore(photo: PendingPhoto) {
        val resolver = contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, photo.name)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/AquaHatch")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val collection = MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = resolver.insert(collection, values) ?: throw IOException("MediaStore insert failed")
        var published = false
        try {
            val output = resolver.openOutputStream(uri) ?: throw IOException("MediaStore file unavailable")
            output.use { it.write(photo.bytes) }
            val ready = ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }
            if (resolver.update(uri, ready, null, null) != 1) throw IOException("MediaStore update failed")
            published = true
        } finally {
            if (!published) resolver.delete(uri, null, null)
        }
    }

    @Suppress("DEPRECATION")
    private fun saveLegacyPhoto(photo: PendingPhoto) {
        val album = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "AquaHatch")
        if (!album.isDirectory && !album.mkdirs() && !album.isDirectory) throw IOException("Pictures unavailable")
        val file = File(album, photo.name)
        // A restarted app can save the same capture again without replacing the first file.
        val destination = if (file.createNewFile()) file else File.createTempFile("AquaHatch_", ".jpg", album)
        try {
            destination.outputStream().use { it.write(photo.bytes) }
            MediaScannerConnection.scanFile(applicationContext, arrayOf(destination.absolutePath), arrayOf("image/jpeg")) { _, uri ->
                if (uri == null) destination.delete()
                runOnUiThread {
                    if (uri == null) photo.result.error("save_failed", null, null)
                    else photo.result.success(null)
                }
            }
        } catch (error: Exception) {
            destination.delete()
            throw error
        }
    }

    private data class PendingPhoto(
        val bytes: ByteArray,
        val name: String,
        val result: MethodChannel.Result,
    )

    private var pendingPhoto: PendingPhoto? = null
    private val photoName = Regex("""AquaHatch_[A-Za-z0-9_-]{1,64}\.jpg""")
    private val galleryRequest = 8412

    override fun onDestroy() {
        getSystemService(ConnectivityManager::class.java).bindProcessToNetwork(null)
        super.onDestroy()
    }
}
