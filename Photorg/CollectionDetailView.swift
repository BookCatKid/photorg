import SwiftUI
import SwiftData
import PhotosUI

struct CollectionDetailView: View {
    @Bindable var collection: PhotoCollection
    @Environment(\.modelContext) private var context

    @State private var showingCamera = false
    @State private var pickerItems: [PhotosPickerItem] = []

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(collection.photos.sorted(by: { $0.capturedAt > $1.capturedAt })) { photo in
                    NavigationLink(value: photo) {
                        PhotoThumb(photo: photo)
                            .frame(height: 110)
                            .clipped()
                    }
                }
            }
            .padding(2)
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Photo.self) { p in
            PhotoDetailView(photo: p)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                PhotosPicker(selection: $pickerItems, matching: .images, photoLibrary: .shared()) {
                    Label("Import", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.thinMaterial, in: Capsule())
                }
                Button {
                    showingCamera = true
                } label: {
                    Label("Shoot into \(collection.name)", systemImage: "camera.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraView { data, orientation in
                ingest(data: data, orientation: orientation)
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItems) { _, items in
            Task { await ingestPicked(items) }
        }
    }

    private func ingest(data: Data, orientation: Int) {
        let photo = Photo(orientation: orientation)
        photo.collection = collection
        do {
            try ImageStore.saveOriginalBytes(data, for: photo.id)
            context.insert(photo)
        } catch {
            print("Failed to save capture: \(error)")
        }
    }

    private func ingestPicked(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                ingest(data: data, orientation: 1)
            }
        }
        pickerItems = []
    }
}

struct PhotoThumb: View {
    let photo: Photo
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(.systemGray5)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .task(id: photo.id) {
            let cropped = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let img = ImageStore.loadImage(for: photo.id) else { return nil }
                return CropRenderer.render(image: img, normalizedRect: photo.cropRect)
            }.value
            self.image = cropped
        }
    }
}
