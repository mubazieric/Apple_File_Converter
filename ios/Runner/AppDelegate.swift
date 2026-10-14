import AVFoundation
import CoreMedia
import Flutter
import ImageIO
import Photos
import UIKit
import VideoToolbox

/// Hosts the "com.iwatdigital.apple_file_converter/codec" MethodChannel.
///
/// Only operations that genuinely need iOS APIs live here: HEIC/HEIF decoding through
/// ImageIO, writing finished files into the Photos library, probing image bounds, and asking
/// VideoToolbox whether a hardware encoder exists. Everything else is shared Dart code so both
/// platforms behave identically. When iOS cannot do the work we return `nil`/`false` and the
/// Dart layer reports an honest failure instead of faking success.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static let channelName = "com.iwatdigital.apple_file_converter/codec"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: AppDelegate.channelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      switch call.method {
      case "supportsHeic":
        result(true)
      case "decodeToRgba":
        self.decodeToRgba(call, result)
      case "probeImage":
        self.probeImage(call, result)
      case "saveToPhotoLibrary":
        self.saveToPhotoLibrary(call, result)
      case "hasHardwareEncoder":
        let arguments = call.arguments as? [String: Any]
        result(self.hasHardwareEncoder(arguments?["codec"] as? String))
      case "deviceStorage":
        result(self.deviceStorage())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - Image decoding

  private func decodeToRgba(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard
      let arguments = call.arguments as? [String: Any],
      let path = arguments["path"] as? String
    else {
      result(nil)
      return
    }
    let maxMegapixels = (arguments["maxMegapixels"] as? NSNumber)?.intValue ?? 80
    let url = URL(fileURLWithPath: path)

    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      result(nil)
      return
    }

    var options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    if maxMegapixels > 0,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
      let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
      pixelWidth > 0,
      pixelHeight > 0
    {
      let megapixels = pixelWidth * pixelHeight / 1_000_000.0
      if megapixels > Double(maxMegapixels) {
        let scale = sqrt(Double(maxMegapixels) / megapixels)
        let maxPixel = Int(Double(max(pixelWidth, pixelHeight)) * scale)
        options[kCGImageSourceThumbnailMaxPixelSize] = max(maxPixel, 1)
      }
    }

    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else {
      result(nil)
      return
    }

    let width = image.width
    let height = image.height
    let bytesPerRow = width * 4
    var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard
      let context = CGContext(
        data: &buffer,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo
      )
    else {
      result(nil)
      return
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    result([
      "pixels": FlutterStandardTypedData(bytes: Data(buffer)),
      "width": width,
      "height": height,
      "orientation": 0,
    ])
  }

  private func probeImage(_ call: FlutterMethodCall, _ result: FlutterResult) {
    guard
      let arguments = call.arguments as? [String: Any],
      let path = arguments["path"] as? String
    else {
      result(nil)
      return
    }
    let url = URL(fileURLWithPath: path)
    guard
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else {
      result(nil)
      return
    }
    let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
    let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
    if width <= 0 || height <= 0 {
      result(nil)
      return
    }
    let type = (CGImageSourceGetType(source) as String?) ?? ""
    let hasAlpha = (properties[kCGImagePropertyHasAlpha] as? NSNumber)?.boolValue ?? false
    let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    result([
      "width": width,
      "height": height,
      "format": formatId(for: type),
      "hasAlpha": hasAlpha,
      "orientation": degrees(forExifOrientation: orientation),
    ])
  }

  // MARK: - Saving to the Photos library

  private func saveToPhotoLibrary(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard
      let arguments = call.arguments as? [String: Any],
      let path = arguments["path"] as? String
    else {
      result(nil)
      return
    }
    let isVideo = arguments["isVideo"] as? Bool ?? false
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: url.path) else {
      result(nil)
      return
    }

    ensureAddOnlyPermission { granted in
      guard granted else {
        result(nil)
        return
      }
      var localIdentifier: String?
      PHPhotoLibrary.shared().performChanges({
        let request = PHAssetCreationRequest.forAsset()
        let options = PHAssetResourceCreationOptions()
        options.shouldMoveFile = false
        request.addResource(with: isVideo ? .video : .photo, fileURL: url, options: options)
        localIdentifier = request.placeholderForCreatedAsset?.localIdentifier
      }) { success, _ in
        DispatchQueue.main.async {
          result(success ? localIdentifier : nil)
        }
      }
    }
  }

  private func ensureAddOnlyPermission(_ completion: @escaping (Bool) -> Void) {
    let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    switch status {
    case .authorized, .limited:
      completion(true)
    case .notDetermined:
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
        DispatchQueue.main.async {
          completion(newStatus == .authorized || newStatus == .limited)
        }
      }
    default:
      completion(false)
    }
  }

  // MARK: - Hardware encoder capability

  private func hasHardwareEncoder(_ codec: String?) -> Bool {
    guard let codec else { return false }
    let codecType: CMVideoCodecType
    switch codec {
    case "h264": codecType = kCMVideoCodecType_H264
    case "hevc": codecType = kCMVideoCodecType_HEVC
    case "prores": codecType = kCMVideoCodecType_AppleProRes422
    default: return false
    }
    // The "prefer hardware encoder" hint key only exists in the iOS 17.4+ SDK.
    // On older systems VideoToolbox still selects hardware when available.
    var specification: [CFString: Any] = [:]
    if #available(iOS 17.4, *) {
      specification[kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder] = true
    }
    var session: VTCompressionSession?
    let status = VTCompressionSessionCreate(
      allocator: kCFAllocatorDefault,
      width: 1920,
      height: 1080,
      codecType: codecType,
      encoderSpecification: specification as CFDictionary,
      imageBufferAttributes: nil,
      compressedDataAllocator: nil,
      outputCallback: nil,
      refcon: nil,
      compressionSessionOut: &session
    )
    if let session { VTCompressionSessionInvalidate(session) }
    return status == noErr
  }

  // MARK: - Storage

  private func deviceStorage() -> [String: Any]? {
    let url = URL(fileURLWithPath: NSHomeDirectory())
    guard
      let values = try? url.resourceValues(forKeys: [
        .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
      ]),
      let total = values.volumeTotalCapacity,
      let free = values.volumeAvailableCapacity,
      total > 0
    else {
      return nil
    }
    return ["totalBytes": Int64(total), "freeBytes": Int64(free)]
  }

  // MARK: - Helpers

  private func formatId(for type: String) -> String {
    let lower = type.lowercased()
    if lower.contains("heic") || lower.contains("heif") { return "heic" }
    if lower.contains("jpeg") || lower.contains("jpg") { return "jpeg" }
    if lower.contains("png") { return "png" }
    if lower.contains("webp") { return "webp" }
    if lower.contains("gif") { return "gif" }
    if lower.contains("bmp") { return "bmp" }
    if lower.contains("tiff") { return "tiff" }
    if lower.contains("avif") { return "avif" }
    return "unknown"
  }

  private func degrees(forExifOrientation orientation: Int) -> Int {
    switch orientation {
    case 3, 4: return 180
    case 5, 6: return 90
    case 7, 8: return 270
    default: return 0
    }
  }
}
