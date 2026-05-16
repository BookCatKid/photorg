import SwiftUI
import SwiftData
import Photos

struct PhotoDetailView: View {
    @Bindable var photo: Photo
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var fullImage: UIImage?
    @State private var editing = false
    @State private var showShare = false
    @State private var shareItems: [Any] = []
    @State private var showingCountPicker = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let img = fullImage {
                if editing {
                    CropEditor(image: img, rect: bindingRect(for: img))
                } else {
                    Image(uiImage: CropRenderer.render(image: img, normalizedRect: photo.cropRect))
                        .resizable()
                        .scaledToFit()
                }
            } else {
                ProgressView().tint(.white)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if photo.count > 1 {
                    Button {
                        showingCountPicker = true
                    } label: {
                        Text("\(photo.count)")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.accentColor, in: Capsule())
                    }
                } else {
                    Button {
                        showingCountPicker = true
                    } label: {
                        Image(systemName: "number")
                            .foregroundStyle(.white)
                    }
                }
            }
            ToolbarItem(placement: .principal) {
                if editing {
                    Button("Done") { editing = false }.bold().foregroundStyle(.white)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    if editing {
                        if photo.cropRect != nil {
                            Button("Reset") {
                                photo.cropRect = nil
                            }
                            .foregroundStyle(.white)
                        }
                    } else {
                        Button {
                            editing = true
                        } label: {
                            Image(systemName: "crop")
                                .foregroundStyle(.white)
                        }
                        Menu {
                            Button("Export cropped", systemImage: "square.and.arrow.up") { exportCropped() }
                            Button("Export original", systemImage: "square.and.arrow.up.on.square") { exportOriginal() }
                            if photo.cropRect != nil {
                                Button("Reset crop", systemImage: "arrow.uturn.backward") {
                                    photo.cropRect = nil
                                }
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) { deletePhoto() }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .task(id: photo.id) {
            self.fullImage = await Task.detached { ImageStore.loadImage(for: photo.id) }.value
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareItems)
        }
        .sheet(isPresented: $showingCountPicker) {
            CountPickerSheet(photo: photo)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bindingRect(for img: UIImage) -> Binding<CGRect> {
        Binding(
            get: {
                if let existing = photo.cropRect {
                    return existing
                }
                return CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)
            },
            set: { newValue in
                let full = CGRect(x: 0, y: 0, width: 1, height: 1)
                if newValue == full || (newValue.origin == CGPoint.zero && newValue.size == CGSize(width: 0.9, height: 0.9)) {
                    photo.cropRect = nil
                } else {
                    photo.cropRect = newValue
                }
            }
        )
    }

    private func exportCropped() {
        guard let img = fullImage else { return }
        let rendered = CropRenderer.render(image: img, normalizedRect: photo.cropRect)
        shareItems = [rendered]
        showShare = true
    }

    private func exportOriginal() {
        let url = ImageStore.url(for: photo.id)
        shareItems = [url]
        showShare = true
    }

    private func deletePhoto() {
        ImageStore.delete(photo.id)
        context.delete(photo)
        dismiss()
    }
}

struct CountPickerSheet: View {
    @Bindable var photo: Photo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Stepper("Count: \(photo.count)", value: $photo.count, in: 1...99)
            }
            .navigationTitle("Item Count")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(200)])
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}