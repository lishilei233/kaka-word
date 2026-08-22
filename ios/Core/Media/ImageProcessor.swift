import UIKit

enum ImageProcessor {
    static func normalizedImage(from image: UIImage, maxDimension: CGFloat = 1800) -> UIImage? {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(sourceSize.width, sourceSize.height))
        let targetSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    /// 修正图片方向、限制内存与网络开销，并统一编码为 JPEG。
    static func jpegData(from image: UIImage, maxDimension: CGFloat = 1280) -> Data? {
        guard let rendered = normalizedImage(from: image, maxDimension: maxDimension) else { return nil }
        return rendered.jpegData(compressionQuality: 0.82)
    }
}
