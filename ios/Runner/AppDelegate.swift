import Flutter
import UIKit
import Vision
import ImageIO

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
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PicPicScene") else { return }
    let channel = FlutterMethodChannel(name: "picpic/scene", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, reply in
      guard call.method == "classify", let path = call.arguments as? String else {
        reply(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let request = VNClassifyImageRequest()
          let url = URL(fileURLWithPath: path)
          let source = CGImageSourceCreateWithURL(url as CFURL, nil)
          let properties = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
          let orientation = CGImagePropertyOrientation(rawValue: properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1) ?? .up
          try VNImageRequestHandler(url: url, orientation: orientation).perform([request])
          let labels = (request.results ?? []).filter { $0.confidence >= 0.15 }.prefix(30).map { $0.identifier.lowercased() }
          DispatchQueue.main.async { reply(labels) }
        } catch {
          DispatchQueue.main.async { reply(FlutterError(code: "vision", message: "无法识别这张照片", details: nil)) }
        }
      }
    }
  }
}
