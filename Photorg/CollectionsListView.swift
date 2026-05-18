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
    @State private var collectionToPickCover: PhotoCollection?
    @AppStorage("quickCollectionID") private var quickCollectionID: String = ""
    @State private var showingQuickPicker = false
    @State private var showingQuickCamera = false

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
                                        collectionToPickCover = collection
                                    } label: {
                                        Label("Choose Cover", systemImage: "photo")
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
            .safeAreaInset(edge: .bottom) {
                VStack {
                    Button {
                        if collections.first(where: { $0.id.uuidString == quickCollectionID }) != nil {
                            showingQuickCamera = true
                        } else {
                            showingQuickPicker = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: "camera.badge.bolt")
                            Text("Quick Photo")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                    }
                    .contextMenu {
                        Button("Change Quick Collection") { showingQuickPicker = true }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(
                    LinearGradient(colors: [.black, .clear], startPoint: .bottom, endPoint: .top)
                        .ignoresSafeArea()
                )
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
            .sheet(item: $collectionToPickCover) { c in
                CoverPickerSheet(collection: c)
            }
            .sheet(isPresented: $showingQuickPicker) {
                QuickCollectionPickerSheet(collections: collections, selectedID: $quickCollectionID)
            }
            .fullScreenCover(isPresented: $showingQuickCamera) {
                QuickCameraModeView(collections: collections, selectedID: $quickCollectionID) { data, orientation, collection in
                    ingest(data: data, orientation: orientation, into: collection)
                }
                .ignoresSafeArea()
            }
        }
    }

    private func ingest(data: Data, orientation: Int, into collection: PhotoCollection) {
        let photo = Photo(orientation: orientation)
        photo.collection = collection
        if collection.coverPhotoID == nil {
            collection.coverPhotoID = photo.id
        }
        do {
            try ImageStore.saveCapture(data, for: photo.id)
            context.insert(photo)
        } catch {
            print("Failed to save capture: \(error)")
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
                if let img = ImageStore.loadImage(for: photo.id),
                   let data = img.jpegData(compressionQuality: 0.9) {
                    let filename = String(format: "%03d_%@.jpg", index + 1, photo.id.uuidString)
                    try? data.write(to: tempDir.appendingPathComponent(filename))
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

struct QuickCameraModeView: View {
    private static let minSwipeDistanceForCollectionSwitch: CGFloat = 30
    private static let horizontalSwipeDominanceRatio: CGFloat = 1.0

    let collections: [PhotoCollection]
    @Binding var selectedID: String
    let onCapture: (Data, Int, PhotoCollection) -> Void

    @State private var currentIndex: Int = 0

    private var activeCollection: PhotoCollection? {
        guard collections.indices.contains(currentIndex) else { return nil }
        return collections[currentIndex]
    }

    var body: some View {
        ZStack(alignment: .top) {
            CameraView { data, orientation in
                if let activeCollection {
                    onCapture(data, orientation, activeCollection)
                }
            }
            .gesture(
                DragGesture(minimumDistance: Self.minSwipeDistanceForCollectionSwitch)
                    .onEnded { value in
                        guard abs(value.translation.width) > (abs(value.translation.height) * Self.horizontalSwipeDominanceRatio) else { return }
                        if value.translation.width < 0 {
                            goToNextCollection()
                        } else if value.translation.width > 0 {
                            goToPreviousCollection()
                        }
                    }
            )

            if let activeCollection {
                VStack(spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(collections.indices, id: \.self) { index in
                                let collection = collections[index]
                                Button {
                                    selectCollection(at: index)
                                } label: {
                                    VStack(spacing: 3) {
                                        ZStack {
                                            Circle()
                                                .fill(index == currentIndex ? Color.accentColor : Color.black.opacity(0.55))
                                                .frame(width: 34, height: 34)
                                            Text(collectionIconText(for: collection))
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                            if index == currentIndex {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundStyle(.white)
                                                    .offset(x: 11, y: -11)
                                            }
                                        }
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white.opacity(index == currentIndex ? 0.95 : 0.25), lineWidth: index == currentIndex ? 2 : 1)
                                        )
                                        .scaleEffect(index == currentIndex ? 1.08 : 1.0)
                                        Text(collection.name)
                                            .font(.caption2.weight(index == currentIndex ? .semibold : .regular))
                                            .foregroundStyle(.white.opacity(index == currentIndex ? 1.0 : 0.85))
                                            .lineLimit(1)
                                            .frame(maxWidth: 56)
                                    }
                                }
                                .accessibilityLabel(collection.name)
                                .accessibilityHint(index == currentIndex ? "Current collection" : "Switch to this collection")
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 8) {
                        Button {
                            goToPreviousCollection()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(.black.opacity(0.5), in: Circle())
                        }
                        Menu {
                            ForEach(collections.indices, id: \.self) { index in
                                let collection = collections[index]
                                Button {
                                    selectCollection(at: index)
                                } label: {
                                    if index == currentIndex {
                                        Label(collection.name, systemImage: "checkmark")
                                    } else {
                                        Text(collection.name)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(activeCollection.name)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.bold))
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.5), in: Capsule())
                        }
                        Button {
                            goToNextCollection()
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(.black.opacity(0.5), in: Circle())
                        }
                    }
                    .foregroundStyle(.white)
                }
                .padding(.top, 72)
            }
        }
        .onAppear {
            syncSelectionFromID()
        }
        .onChange(of: selectedID) { _, _ in
            syncSelectionFromID()
        }
    }

    private func syncSelectionFromID() {
        guard !collections.isEmpty else { return }
        if let index = collections.firstIndex(where: { $0.id.uuidString == selectedID }) {
            currentIndex = index
        } else {
            currentIndex = 0
            selectedID = collections[0].id.uuidString
        }
    }

    private func goToNextCollection() {
        guard !collections.isEmpty else { return }
        selectCollection(at: (currentIndex + 1) % collections.count)
    }

    private func goToPreviousCollection() {
        guard !collections.isEmpty else { return }
        selectCollection(at: (currentIndex - 1 + collections.count) % collections.count)
    }

    private func selectCollection(at index: Int) {
        guard collections.indices.contains(index) else { return }
        currentIndex = index
        selectedID = collections[currentIndex].id.uuidString
    }

    private func collectionIconText(for collection: PhotoCollection) -> String {
        let initial = collection.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)
        return initial.isEmpty ? "?" : String(initial).uppercased()
    }
}

struct CollectionCard: View {
    @Bindable var collection: PhotoCollection
    @State private var coverImage: UIImage?
    @State private var showingCoverPicker = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 4) {
                Image(systemName: "number")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("\(collection.itemCount)")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 32)

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .glassEffect(.regular)
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

            VStack(alignment: .leading, spacing: 6) {
                Text(collection.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(spacing: 12) {
                    Label("\(collection.photoCount)", systemImage: "photo")
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
        .contentShape(.rect(cornerRadius: 16))
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
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
        if let cover = collection.coverPhoto {
            let coverID = cover.id
            let task = Task.detached(priority: .userInitiated) { () -> UIImage? in
                ImageStore.loadImage(for: coverID)
            }
            coverImage = await task.value
        } else {
            coverImage = nil
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
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .task(id: photo.id) {
            let photoID = photo.id
            let task = Task.detached(priority: .userInitiated) { () -> UIImage? in
                ImageStore.loadImage(for: photoID)
            }
            image = await task.value
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
struct QuickCollectionPickerSheet: View {
    let collections: [PhotoCollection]
    @Binding var selectedID: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(collections) { collection in
                    Button {
                        selectedID = collection.id.uuidString
                        dismiss()
                    } label: {
                        HStack {
                            Text(collection.name)
                            Spacer()
                            if collection.id.uuidString == selectedID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Select Quick Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
