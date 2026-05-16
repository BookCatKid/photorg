import Foundation
import SwiftData
import CoreGraphics

@Model
final class PhotoCollection {
    @Attribute(.unique) var id: UUID
    var name: String
    var note: String
    var createdAt: Date
    var coverPhotoID: UUID?

    @Relationship(deleteRule: .cascade, inverse: \Photo.collection)
    var photos: [Photo] = []

    init(name: String, note: String = "") {
        self.id = UUID()
        self.name = name
        self.note = note
        self.createdAt = Date()
    }

    var coverPhoto: Photo? {
        if let coverID = coverPhotoID {
            return photos.first { $0.id == coverID }
        }
        return photos.sorted(by: { $0.capturedAt > $1.capturedAt }).first
    }

    var photoCount: Int { photos.count }
    var itemCount: Int { photos.reduce(0) { $0 + $1.count } }
    var earliestPhoto: Date? { photos.min(by: { $0.capturedAt < $1.capturedAt })?.capturedAt }
    var latestPhoto: Date? { photos.max(by: { $0.capturedAt < $1.capturedAt })?.capturedAt }
}

@Model
final class Photo {
    @Attribute(.unique) var id: UUID
    var capturedAt: Date
    var count: Int = 1

    var cropX: Double?
    var cropY: Double?
    var cropW: Double?
    var cropH: Double?

    var orientationRaw: Int

    var collection: PhotoCollection?

    init(orientation: Int = 1) {
        self.id = UUID()
        self.capturedAt = Date()
        self.orientationRaw = orientation
        self.count = 1
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