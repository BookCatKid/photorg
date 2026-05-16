import Foundation
import SwiftData
import CoreGraphics

@Model
final class PhotoCollection {
    @Attribute(.unique) var id: UUID
    var name: String
    var note: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Photo.collection)
    var photos: [Photo] = []

    init(name: String, note: String = "") {
        self.id = UUID()
        self.name = name
        self.note = note
        self.createdAt = Date()
    }
}

@Model
final class Photo {
    @Attribute(.unique) var id: UUID
    var capturedAt: Date

    // Non-destructive crop, normalized 0…1 in image coordinates (origin top-left).
    // nil means "no crop" — show the full original.
    var cropX: Double?
    var cropY: Double?
    var cropW: Double?
    var cropH: Double?

    // Stored EXIF orientation (1…8) of the original file; used to render correctly.
    var orientationRaw: Int

    var collection: PhotoCollection?

    init(orientation: Int = 1) {
        self.id = UUID()
        self.capturedAt = Date()
        self.orientationRaw = orientation
    }

    var cropRect: CGRect? {
        get {
            guard let x = cropX, let y = cropY, let w = cropW, let h = cropH else { return nil }
            return CGRect(x: x, y: y, width: w, height: h)
        }
        set {
            if let r = newValue {
                cropX = r.origin.x; cropY = r.origin.y
                cropW = r.size.width; cropH = r.size.height
            } else {
                cropX = nil; cropY = nil; cropW = nil; cropH = nil
            }
        }
    }
}
