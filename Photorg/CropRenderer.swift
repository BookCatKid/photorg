import UIKit
import CoreImage
import CoreGraphics

enum CropRenderer {
    private static let ctx = CIContext()

    /// Apply a normalized crop rect (origin top-left, 0…1) to a UIImage and return a new UIImage.
    /// The source bytes on disk are never modified.
    static func render(image: UIImage, normalizedRect rect: CGRect?) -> UIImage {
        guard let rect, let cg = image.cgImage else { return image }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        // CGImage has bottom-left origin; our normalized rect uses top-left (UIKit convention),
        // so we must flip the Y axis before cropping.
        let flippedY = 1.0 - rect.origin.y - rect.size.height
        let pixel = CGRect(
            x: floor(rect.origin.x * w),
            y: floor(flippedY * h),
            width: floor(rect.size.width * w),
            height: floor(rect.size.height * h)
        ).integral
        guard pixel.width > 1, pixel.height > 1,
              let cropped = cg.cropping(to: pixel) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}
