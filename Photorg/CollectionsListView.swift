import SwiftUI
import SwiftData
import PhotosUI

struct CollectionsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PhotoCollection.createdAt, order: .reverse) private var collections: [PhotoCollection]
    @State private var showingNew = false
    @State private var newName = ""
    @State private var showingDeleteConfirm = false
    @State private var collectionToDelete: PhotoCollection?
    @State private var showingExportProgress = false
    @State private var exportProgress: Double = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if collections.isEmpty {
                    ContentUnavailableView(
                        "No collections yet",
                        systemImage: "rectangle.stack.badge.plus",
                        description: Text("Tap + to start a collection like \"White Teslas\", then shoot straight into it.")
                    )
                    .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(collections) { collection in
                                NavigationLink(value: collection) {
                                    CollectionCard(collection: collection)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .contextMenu {
                                    Button {
                                        collectionToDelete = collection
                                        showingDeleteConfirm = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button {
                                        collection.coverPhotoID = nil
                                    } label: {
                                        Label("Remove Cover", systemImage: "photo")
                                    }
                                    Button {
                                        exportCollectionAsZip(collection)
                                    } label: {
                                        Label("Export All as ZIP", systemImage: "square.and.arrow.up")
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Collections")
            .navigationDestination(for: PhotoCollection.self) { c in
                CollectionDetailView(collection: c)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNew = true } label: { Image(systemName: "plus") }
                }
            }
            .alert("New collection", isPresented: $showingNew) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { newName = "" }
                Button("Create") {
                    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    context.insert(PhotoCollection(name: trimmed))
                    newName = ""
                }
            }
            .alert("Delete Collection?", isPresented: $showingDeleteConfirm) {
                Button("Cancel", role: .cancel) { collectionToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let c = collectionToDelete {
                        deleteCollection(c)
                    }
                    collectionToDelete = nil
                }
            } message: {
                if let c = collectionToDelete {
                    Text("This will permanently delete \"\(c.name)\" and all \(c.photoCount) photos.")
                }
            }
            .sheet(isPresented: $showingExportProgress) {
                ExportProgressSheet(progress: $exportProgress)
            }
        }
    }

    private func deleteCollection(_ c: PhotoCollection) {
        for p in c.photos { ImageStore.delete(p.id) }
        context.delete(c)
    }

    private func exportCollectionAsZip(_ collection: PhotoCollection) {
        showingExportProgress = true
        exportProgress = 0

        Task {
            let fileManager = FileManager.default
            let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let sortedPhotos = collection.photos.sorted { $0.capturedAt < $1.capturedAt }
            for (index, photo) in sortedPhotos.enumerated() {
                if let img = ImageStore.loadImage(for: photo.id) {
                    let rendered = CropRenderer.render(image: img, normalizedRect: photo.cropRect)
                    let filename = String(format: "%03d_%@.jpg", index + 1, photo.id.uuidString)
                    if let data = rendered.jpegData(compressionQuality: 0.9) {
                        try? data.write(to: tempDir.appendingPathComponent(filename))
                    }
                }
                await MainActor.run {
                    exportProgress = Double(index + 1) / Double(sortedPhotos.count)
                }
            }

            let zipURL = fileManager.temporaryDirectory.appendingPathComponent("\(collection.name).zip")
            try? fileManager.removeItem(at: zipURL)

            let coordinator = NSFileCoordinator()
            var error: NSError?
            coordinator.coordinate(readingItemAt: tempDir, options: .forUploading, error: &error) { url in
                try? fileManager.moveItem(at: url, to: zipURL)
            }

            await MainActor.run {
                showingExportProgress = false
                let activityVC = UIActivityViewController(activityItems: [zipURL], applicationActivities: nil)
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootVC = windowScene.windows.first?.rootViewController {
                    rootVC.present(activityVC, animated: true)
                }
            }

            try? fileManager.removeItem(at: tempDir)
        }
    }
}

struct CollectionCard: View {
    @Bindable var collection: PhotoCollection
    @State private var coverImage: UIImage?
    @State private var showingCoverPicker = false

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentColor.opacity(0.1))
                    )
                if let image = coverImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Image(systemName: "photo.stack")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, height: 80)
            .onTapGesture(count: 2) {
                showingCoverPicker = true
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(collection.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(spacing: 12) {
                    Label("\(collection.photoCount)", systemImage: "photo")
                    Label("\(collection.itemCount)", systemImage: "number")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let earliest = collection.earliestPhoto {
                    Text(dateRangeString)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .sheet(isPresented: $showingCoverPicker) {
            CoverPickerSheet(collection: collection)
        }
        .task(id: collection.coverPhotoID) {
            await loadCover()
        }
    }

    private var dateRangeString: String {
        guard let earliest = collection.earliestPhoto,
              let latest = collection.latestPhoto else { return "" }
        let formatter = DateFormatter()
        if Calendar.current.isDate(earliest, equalTo: latest, toGranularity: .day) {
            formatter.dateStyle = .medium
            return formatter.string(from: earliest)
        } else {
            formatter.dateFormat = "MMM d"
            return "\(formatter.string(from: earliest)) - \(formatter.string(from: latest))"
        }
    }

    private func loadCover() async {
        guard let cover = collection.coverPhoto else {
            coverImage = nil
            return
        }
        if let img = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let img = ImageStore.loadImage(for: cover.id) else { return nil }
            return CropRenderer.render(image: img, normalizedRect: cover.cropRect)
        }.value {
            coverImage = img
        }
    }
}

struct CoverPickerSheet: View {
    @Bindable var collection: PhotoCollection
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                    ForEach(collection.photos.sorted(by: { $0.capturedAt < $1.capturedAt })) { photo in
                        Button {
                            collection.coverPhotoID = photo.id
                            dismiss()
                        } label: {
                            CoverThumb(photo: photo, isSelected: photo.id == collection.coverPhotoID)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Choose Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct CoverThumb: View {
    let photo: Photo
    let isSelected: Bool
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray5))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 3)
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white)
                    .font(.title2)
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipped()
        .task(id: photo.id) {
            if let img = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let img = ImageStore.loadImage(for: photo.id) else { return nil }
                return CropRenderer.render(image: img, normalizedRect: photo.cropRect)
            }.value {
                image = img
            }
        }
    }
}

struct ExportProgressSheet: View {
    @Binding var progress: Double

    var body: some View {
        VStack(spacing: 20) {
            ProgressView(value: progress)
                .scaleEffect(x: 1, y: 2)
            Text("Exporting... \(Int(progress * 100))%")
                .font(.headline)
        }
        .padding(40)
    }
}