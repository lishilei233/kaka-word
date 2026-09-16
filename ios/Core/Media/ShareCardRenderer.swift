import SwiftUI
import UIKit

@MainActor
enum DecoratedPhotoRenderer {
    static let logicalWidth: CGFloat = 540

    static func logicalSize(for image: UIImage) -> CGSize {
        let imageRatio = image.size.width / max(image.size.height, 1)
        let height = logicalWidth / imageRatio
        return CGSize(width: logicalWidth, height: ceil(height * 2) / 2)
    }

    static func render(
        image: UIImage,
        result: AnalyzeResult,
        revealsAnnotations: Bool = true
    ) throws -> UIImage {
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
        ZStack {
            // Keep the exported bitmap opaque. Transparent PNG margins are shown
            // as black by several share destinations and image viewers.
            Color.paperLight

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
        }
        .dynamicTypeSize(.large)
    }
}
