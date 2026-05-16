import SwiftUI
import SwiftData

struct CollectionsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PhotoCollection.createdAt, order: .reverse) private var collections: [PhotoCollection]
    @State private var showingNew = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                if collections.isEmpty {
                    ContentUnavailableView(
                        "No collections yet",
                        systemImage: "rectangle.stack.badge.plus",
                        description: Text("Tap + to start a collection like “White Teslas”, then shoot straight into it.")
                    )
                }
                ForEach(collections) { c in
                    NavigationLink(value: c) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(c.name).font(.headline)
                                Text("\(c.photos.count) photo\(c.photos.count == 1 ? "" : "s")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
                .onDelete(perform: delete)
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
        }
    }

    private func delete(_ offsets: IndexSet) {
        for i in offsets {
            let c = collections[i]
            for p in c.photos { ImageStore.delete(p.id) }
            context.delete(c)
        }
    }
}
