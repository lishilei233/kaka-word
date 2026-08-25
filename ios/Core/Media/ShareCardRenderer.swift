import SwiftUI
import UIKit

@MainActor
enum DecoratedPhotoRenderer {
    static let logicalWidth: CGFloat = 540

    static func logicalSize(for image: UIImage) -> CGSize {
        let height = logicalWidth / DecoratedPhotoLayout.cardRatio(for: image)
        return CGSize(width: logicalWidth, height: ceil(height * 2) / 2)
    }

    static func render(
        image: UIImage,
        result: AnalyzeResult,
        revealsAnnotations: Bool = true
    ) throws -> URL {
        let logicalSize = logicalSize(for: image)
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
              renderedCGImage.height == Int(logicalSize.height * renderer.scale),
              let data = renderedImage.jpegData(compressionQuality: 0.95) else {
            throw DecoratedPhotoShareError.renderFailed
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("picture-word-\(UUID().uuidString).jpg")
        try data.write(to: url, options: .atomic)
        return url
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
        ZStack {
            // Keep the exported bitmap opaque. Transparent PNG margins are shown
            // as black by several share destinations and image viewers.
            Color.paperLight

            AnnotatedPhotoCard(
                image: image,
                objects: result.objects,
                revealsAnnotations: revealsAnnotations,
                showsShadow: false
            ) { _ in }
            .aspectRatio(DecoratedPhotoLayout.cardRatio(for: image), contentMode: .fit)
            .frame(maxWidth: .infinity)
        }
        .dynamicTypeSize(.large)
    }
}
