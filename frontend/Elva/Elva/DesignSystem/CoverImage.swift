import SwiftUI

/// Обложка фиксированной высоты, которая не влияет на ширину разметки.
///
/// Прямой `AsyncImage { $0.resizable().scaledToFill() }.frame(height:).clipped()`
/// выглядит правильно, но ломает вёрстку: `scaledToFill` расширяет вид под размер
/// картинки, а `clipped()` обрезает только рисование, разметку — нет. Контейнер
/// становится шире экрана, и весь текст под обложкой уезжает за край.
///
/// Здесь картинка живёт в `overlay` поверх прямоугольника заданного размера:
/// прямоугольник задаёт геометрию, картинка на неё повлиять не может.
struct CoverImage: View {
    let url: String?
    var category: String?
    var height: CGFloat = 150

    var body: some View {
        Rectangle()
            .fill(Theme.secondaryBg)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay {
                if let url, let u = URL(string: url) {
                    AsyncImage(url: u) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            CategoryCover(category: category)
                        default:
                            CategoryCover(category: category)
                        }
                    }
                } else {
                    CategoryCover(category: category)
                }
            }
            .clipped()
            // Обложка декоративна: озвучивать её нечем, содержание — в тексте рядом.
            .accessibilityHidden(true)
    }
}
