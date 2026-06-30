import SwiftUI

/// Полноэкранный просмотр фото: листание свайпом + пинч-зум.
struct FullScreenPhotoView: View {
    let images: [String]
    @State private var index: Int
    @Environment(\.dismiss) private var dismiss

    init(images: [String], start: Int = 0) {
        self.images = images
        _index = State(initialValue: min(max(start, 0), max(images.count - 1, 0)))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(images.enumerated()), id: \.offset) { i, url in
                    ZoomableImage(urlString: url).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .automatic : .never))
            .ignoresSafeArea()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline).foregroundStyle(.white)
                    .padding(12).background(.black.opacity(0.5)).clipShape(Circle())
            }
            .padding()
        }
    }
}

private struct ZoomableImage: View {
    let urlString: String
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        if let url = URL(string: urlString) {
            AsyncImage(url: url) { img in
                img.resizable().scaledToFit()
            } placeholder: {
                ProgressView().tint(.white)
            }
            .scaleEffect(scale * pinch)
            .gesture(
                MagnificationGesture()
                    .updating($pinch) { value, state, _ in state = value }
                    .onEnded { value in
                        scale = min(max(scale * value, 1), 4)
                    }
            )
            .onTapGesture(count: 2) {
                 withAnimation { scale = scale > 1 ? 1 : 2 }
            }
        }
    }
}
