import SwiftUI
import UIKit

@MainActor
enum DecoratedPhotoRenderer {
    static let logicalWidth: CGFloat = 540

    static func logicalSize(for image: UIImage, sceneWordCount: Int = 0) -> CGSize {
        let imageRatio = image.size.width / max(image.size.height, 1)
        let rows = sceneWordCount == 0 ? 0 : Int(ceil(Double(sceneWordCount) / 3.0))
        let height = logicalWidth / imageRatio + CGFloat(rows * 54) + (rows > 0 ? 42 : 0)
        return CGSize(width: logicalWidth, height: ceil(height * 2) / 2)
    }

    static func render(
        image: UIImage,
        result: AnalyzeResult,
        revealsAnnotations: Bool = true
    ) throws -> UIImage {
        let logicalSize = logicalSize(for: image, sceneWordCount: result.sceneWords.count)
        let content = ShareableDecoratedPhoto(
            image: image,
            result: result,
            revealsAnnotations: revealsAnnotations
        )
        .frame(width: logicalSize.width, height: logicalSize.height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let renderedImage = renderer.uiImage,
              let renderedCGImage = renderedImage.cgImage,
              renderedCGImage.width == Int(logicalSize.width * renderer.scale),
              renderedCGImage.height == Int(logicalSize.height * renderer.scale) else {
            throw DecoratedPhotoShareError.renderFailed
        }
        return renderedImage
    }
}

enum DecoratedPhotoShareError: LocalizedError {
    case renderFailed

    var errorDescription: String? { "分享图片生成失败，请稍后重试。" }
}

private struct ShareableDecoratedPhoto: View {
    let image: UIImage
    let result: AnalyzeResult
    let revealsAnnotations: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Keep the exported bitmap opaque. Transparent PNG margins are shown
            // as black by several share destinations and image viewers.
            AnnotatedPhotoCard(
                image: image,
                objects: result.objects,
                revealsAnnotations: revealsAnnotations,
                showsShadow: false,
                usesOriginalAspectRatio: true,
                supportsZoom: false
            ) { _ in }
            .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
            .frame(maxWidth: .infinity)

            if !result.sceneWords.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SCENE WORDS")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(Color.coral)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(result.sceneWords) { word in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(word.english)
                                    .font(.system(size: 14, weight: .bold, design: .serif))
                                    .lineLimit(1)
                                Text("\(word.kind.title) · \(word.chinese)")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.ink.opacity(0.58))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                            .padding(.horizontal, 9)
                            .background((word.kind == .action ? Color.sun : Color.sky).opacity(0.24), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(14)
                .background(Color.paperLight)
            }
        }
        .background(Color.paperLight)
        .dynamicTypeSize(.large)
    }
}
