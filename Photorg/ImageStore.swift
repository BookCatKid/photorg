import Foundation
import UIKit
import ImageIO
import MobileCoreServices
import UniformTypeIdentifiers
import Photos

/// On-disk store for original image bytes. The DB only references photos by UUID;
/// the bytes live here untouched, so cropping is always non-destructive.
enum ImageStore {
    private static let cameraRollErrorDomain = "ImageStore.CameraRoll"

    static let directory: URL = {
        let fm = FileManager.default
        let base = try! fm.url(for: .applicationSupportDirectory,
                               in: .userDomainMask,
                               appropriateFor: nil,
                               create: true)
        let dir = base.appendingPathComponent("Photorg/originals", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).heic")
    }

    /// Save image data as-is when we already have HEIC/JPEG bytes (preferred — no re-encode).
    static func saveOriginalBytes(_ data: Data, for id: UUID) throws {
        try data.write(to: url(for: id), options: .atomic)
    }

    /// Save a capture to app storage and asynchronously mirror it to Photos.
    static func saveCapture(_ data: Data, for id: UUID) throws {
        try saveOriginalBytes(data, for: id)
        saveToCameraRoll(data)
    }

    /// Fallback: encode a UIImage to HEIC at quality 1.0 (lossless-ish; only used if raw bytes
    /// aren't available, e.g. some PHPicker paths).
    static func saveAsHEIC(_ image: UIImage, for id: UUID) throws {
        let dest = url(for: id)
        guard let cg = image.cgImage,
              let destRef = CGImageDestinationCreateWithURL(dest as CFURL,
                                                            UTType.heic.identifier as CFString,
                                                            1, nil)
        else { throw NSError(domain: "ImageStore", code: 1) }
        let props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 1.0,
            kCGImagePropertyOrientation: image.imageOrientation.cgOrientation.rawValue
        ]
        CGImageDestinationAddImage(destRef, cg, props as CFDictionary)
        if !CGImageDestinationFinalize(destRef) {
            throw NSError(domain: "ImageStore", code: 2)
        }
    }

    static func loadImage(for id: UUID) -> UIImage? {
        UIImage(contentsOfFile: url(for: id).path)
    }

    static func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    /// Save raw photo bytes into the user's Photos library.
    static func saveToCameraRoll(_ data: Data) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }) { success, error in
                if !success {
                    if let error {
                        print("Failed to save to camera roll: \(error)")
                    } else {
                        let fallbackError = NSError(
                            domain: cameraRollErrorDomain,
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to save image to camera roll."]
                        )
                        print("Failed to save to camera roll with unknown Photos error: \(fallbackError)")
                    }
                }
            }
        }
    }
}

extension UIImage.Orientation {
    var cgOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
