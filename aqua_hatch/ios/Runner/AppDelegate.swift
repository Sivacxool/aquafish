import AVFoundation
import Flutter
import Photos
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let videoFrame = FlutterMethodChannel(
      name: "th.ac.aquahatch/video_frame",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    videoFrame.setMethodCallHandler { call, result in
      guard call.method == "read" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let path = call.arguments as? String, !path.isEmpty else {
        result(FlutterError(code: "invalid_clip", message: "อ่านเฟรมจากคลิปไม่ได้", details: nil))
        return
      }
      Task { @MainActor in
        do {
          let asset = AVURLAsset(url: URL(fileURLWithPath: path))
          let duration = try await asset.load(.duration)
          guard duration.seconds.isFinite, duration.seconds > 0, duration.seconds <= 60 else {
            result(FlutterError(code: "invalid_clip", message: "เลือกคลิปที่อ่านได้และยาวไม่เกิน 60 วินาที", details: nil))
            return
          }
          guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw CocoaError(.fileReadCorruptFile)
          }
          let size = try await track.load(.naturalSize)
          let generator = AVAssetImageGenerator(asset: asset)
          generator.appliesPreferredTrackTransform = true
          if max(size.width, size.height) > 3840 {
            generator.maximumSize = CGSize(width: 3840, height: 3840)
          }
          let frame = try await generator.image(at: CMTimeMultiplyByFloat64(duration, multiplier: 0.5))
          guard let jpeg = UIImage(cgImage: frame.image).jpegData(compressionQuality: 0.95) else {
            throw CocoaError(.fileReadCorruptFile)
          }
          result(FlutterStandardTypedData(bytes: jpeg))
        } catch {
          result(FlutterError(code: "frame_failed", message: "อ่านเฟรมจากคลิปไม่ได้", details: nil))
        }
      }
    }

    let gallery = FlutterMethodChannel(
      name: "th.ac.aquahatch/gallery",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    gallery.setMethodCallHandler { call, result in
      guard call.method == "saveJpeg" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: Any],
            let photo = arguments["bytes"] as? FlutterStandardTypedData,
            !photo.data.isEmpty,
            let name = arguments["name"] as? String,
            name.range(of: #"^AquaHatch_[A-Za-z0-9_-]{1,64}\.jpg$"#, options: .regularExpression) != nil else {
        result(FlutterError(code: "invalid_photo", message: nil, details: nil))
        return
      }
      let data = photo.data
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
        guard status == .authorized || status == .limited else {
          DispatchQueue.main.async {
            result(FlutterError(code: "permission_denied", message: nil, details: nil))
          }
          return
        }
        PHPhotoLibrary.shared().performChanges {
          let options = PHAssetResourceCreationOptions()
          options.originalFilename = name
          PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: options)
        } completionHandler: { saved, _ in
          DispatchQueue.main.async {
            if saved {
              result(nil)
            } else {
              result(FlutterError(code: "save_failed", message: nil, details: nil))
            }
          }
        }
      }
    }
  }
}
