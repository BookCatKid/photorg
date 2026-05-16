import UIKit
import CoreGraphics

enum CropRenderer {

    /// Apply a normalized crop rect (origin top-left, 0…1 in *display* space) to a UIImage.
    /// The source bytes on disk are never modified.
    static func render(image: UIImage, normalizedRect rect: CGRect?) -> UIImage {
        // Always normalize first — raw camera images are stored rotated (landscape) with an
        // EXIF orientation tag. CropEditor operates in display space, so we must render into
        // a correctly-oriented bitmap before cropping, otherwise the rect maps onto rotated pixels.
        let oriented = normalized(image)
        guard let rect, let cg = oriented.cgImage else { return oriented }

        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)

        // CGImage origin is top-left once the image is normalized, so no Y-flip needed here.
        let pixel = CGRect(
            x: floor(rect.origin.x * w),
            y: floor(rect.origin.y * h),
            width: floor(rect.size.width * w),
            height: floor(rect.size.height * h)
        ).integral

        guard pixel.width > 1, pixel.height > 1,
              let cropped = cg.cropping(to: pixel) else { return oriented }
        return UIImage(cgImage: cropped)
    }

    // MARK: - Private

    /// Re-draw the image into a new bitmap context so the resulting CGImage is always
    /// in the .up orientation (pixels match what the user sees on screen).
    private static func normalized(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let size = image.size
        UIGraphicsBeginImageContextWithOptions(size, false, image.scale)
        defer { UIGraphicsEndImageContext() }
        image.draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }
}

