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
