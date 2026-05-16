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
            ToolbarItem(placement: .topBarTrailing) {
                if editing {
                    Button("Done") { editing = false }.bold()
                } else {
                    Menu {
                        Button("Crop", systemImage: "crop") { editing = true }
                        if photo.cropRect != nil {
                            Button("Reset crop", systemImage: "arrow.uturn.backward") {
                                photo.cropRect = nil
                            }
                        }
                        Button("Export cropped", systemImage: "square.and.arrow.up") { exportCropped() }
                        Button("Export original", systemImage: "square.and.arrow.up.on.square") { exportOriginal() }
                        Button("Delete", systemImage: "trash", role: .destructive) { deletePhoto() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
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
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Binding that defaults to the full image when no crop is set yet.
    private func bindingRect(for img: UIImage) -> Binding<CGRect> {
        Binding(
            get: { photo.cropRect ?? CGRect(x: 0, y: 0, width: 1, height: 1) },
            set: { photo.cropRect = ($0 == CGRect(x: 0, y: 0, width: 1, height: 1)) ? nil : $0 }
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

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
