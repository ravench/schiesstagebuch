import SwiftUI

struct PhotoGrid: View {
    @Binding var photos: [Data]
    var editable = true
    @State private var preview: Int?

    var body: some View {
        if !photos.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                ForEach(photos.indices, id: \.self) { i in
                    if let img = UIImage(data: photos[i]) {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(minWidth: 0, maxWidth: .infinity).frame(height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                            .onTapGesture { preview = i }
                            .overlay(alignment: .topTrailing) {
                                if editable {
                                    Button { photos.remove(at: i) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .buttonStyle(.plain).padding(4)
                                }
                            }
                    }
                }
            }
            .padding(.vertical, 4)
            .fullScreenCover(item: Binding(get: { preview.map(IdentifiedIndex.init) },
                                           set: { preview = $0?.id })) { idx in
                PhotoViewer(photos: photos, start: idx.id)
            }
        }
    }
}

private struct IdentifiedIndex: Identifiable { let id: Int }

struct PhotoViewer: View {
    let photos: [Data]
    @State var start: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TabView(selection: $start) {
                ForEach(photos.indices, id: \.self) { i in
                    if let img = UIImage(data: photos[i]) {
                        Image(uiImage: img).resizable().scaledToFit().tag(i)
                    }
                }
            }
            .tabViewStyle(.page)
            .background(.black)
            .toolbar { Button("Fertig") { dismiss() } }
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
