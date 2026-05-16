import SwiftUI
import SwiftData
import PhotosUI

enum PhotoSortOption: String, CaseIterable {
    case newestFirst = "Newest First"
    case oldestFirst = "Oldest First"
    case highestCount = "Highest Count"
    case lowestCount = "Lowest Count"
}

struct CollectionDetailView: View {
    @Bindable var collection: PhotoCollection
    @Environment(\.modelContext) private var context

    @State private var showingCamera = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var sortOption: PhotoSortOption = .newestFirst
    @State private var isSelecting = false
    @State private var selectedPhotos: Set<Photo> = []

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    private var sortedPhotos: [Photo] {
        let photos = collection.photos
        switch sortOption {
        case .newestFirst:
            return photos.sorted { $0.capturedAt > $1.capturedAt }
        case .oldestFirst:
            return photos.sorted { $0.capturedAt < $1.capturedAt }
        case .highestCount:
            return photos.sorted { $0.count > $1.count }
        case .lowestCount:
            return photos.sorted { $0.count < $1.count }
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(sortedPhotos) { photo in
                        if isSelecting {
                            Button {
                                if selectedPhotos.contains(photo) {
                                    selectedPhotos.remove(photo)
                                } else {
                                    selectedPhotos.insert(photo)
                                }
                            } label: {
                                PhotoThumb(photo: photo)
                                    .frame(height: 110)
                                    .clipped()
                                    .overlay(SelectionOverlay(isSelected: selectedPhotos.contains(photo)))
                            }
                        } else {
                            NavigationLink(value: photo) {
                                PhotoThumb(photo: photo)
                                    .frame(height: 110)
                                    .clipped()
                            }
                        }
                    }
                }
                .padding(2)
            }
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Photo.self) { p in
            PhotoDetailView(photo: p)
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                VStack {
                    Button(role: .destructive) {
                        deleteSelectedPhotos()
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Selected (\(selectedPhotos.count))")
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.red, in: Capsule())
                        .foregroundStyle(.white)
                    }
                    .disabled(selectedPhotos.isEmpty)
                    .opacity(selectedPhotos.isEmpty ? 0.5 : 1)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            } else {
                VStack(spacing: 10) {
                    PhotosPicker(selection: $pickerItems, matching: .images, photoLibrary: .shared()) {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                            Text("Import")
                        }
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    Button {
                        showingCamera = true
                    } label: {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("Shoot")
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        isSelecting.toggle()
                        if !isSelecting {
                            selectedPhotos.removeAll()
                        }
                    } label: {
                        Text(isSelecting ? "Cancel" : "Select")
                    }
                    .foregroundStyle(.white)
                    
                    if !isSelecting {
                        Menu {
                            Picker("Sort By", selection: $sortOption) {
                                ForEach(PhotoSortOption.allCases, id: \.self) { option in
                                    Text(option.rawValue).tag(option)
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .onAppear {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.8)
            UINavigationBar.appearance().standardAppearance = appearance
        }
    }

    private func ingest(data: Data, orientation: Int) {
        let photo = Photo(orientation: orientation)
        photo.collection = collection
        if collection.coverPhotoID == nil {
            collection.coverPhotoID = photo.id
        }
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

    private func deleteSelectedPhotos() {
        for photo in selectedPhotos {
            ImageStore.delete(photo.id)
            context.delete(photo)
        }
        selectedPhotos.removeAll()
        isSelecting = false
    }
}

struct SelectionOverlay: View {
    let isSelected: Bool
    var body: some View {
        ZStack {
            if isSelected {
                Color.black.opacity(0.3)
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white, Color.accentColor)
            } else {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "circle")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .padding(6)
                    }
                    Spacer()
                }
            }
        }
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
            if photo.count > 1 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("\(photo.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.6), in: Capsule())
                            .padding(4)
                    }
                }
            }
        }
        .task(id: photo.id) {
            let photoID = photo.id
            let rect = photo.cropRect
            let task = Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let img = ImageStore.loadImage(for: photoID) else { return nil }
                return CropRenderer.render(image: img, normalizedRect: rect)
            }
            self.image = await task.value
        }
    }
}