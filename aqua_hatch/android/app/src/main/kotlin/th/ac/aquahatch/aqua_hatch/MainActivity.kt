package th.ac.aquahatch.aqua_hatch

import io.flutter.embedding.android.FlutterActivity
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
    override fun onDestroy() {
        getSystemService(ConnectivityManager::class.java).bindProcessToNetwork(null)
        super.onDestroy()
    }
}
