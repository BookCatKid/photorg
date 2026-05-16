import SwiftUI
import SwiftData
import Photos

struct PhotoDetailView: View {
    @Bindable var photo: Photo
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var fullImage: UIImage?
    @State private var showShare = false
    @State private var shareItems: [Any] = []
    @State private var showingCountPicker = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let img = fullImage {
                ZoomableScrollView {
                    Image(uiImage: img)
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
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Export", systemImage: "square.and.arrow.up") { exportPhoto() }
                    Button("Delete", systemImage: "trash", role: .destructive) { deletePhoto() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.white)
                }
            }
        }
        .task(id: photo.id) {
            let photoID = photo.id
            self.fullImage = await Task.detached { ImageStore.loadImage(for: photoID) }.value
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareItems)
        }
        .sheet(isPresented: $showingCountPicker) {
            CountPickerSheet(photo: photo)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func exportPhoto() {
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