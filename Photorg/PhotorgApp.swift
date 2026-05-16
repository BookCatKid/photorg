import SwiftUI
import SwiftData

@main
struct PhotorgApp: App {
    var body: some Scene {
        WindowGroup {
            CollectionsListView()
        }
        .modelContainer(for: [PhotoCollection.self, Photo.self])
    }
}
