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

    /// Manual recognition ranges are exact; automatic crops retain their familiar breathing room.
    static func objectCropRect(for object: LearningObject) -> CGRect? {
        guard object.kind == .noun else { return nil }
        let manual = object.recognitionBoxOverride.flatMap { RecognitionRangeGeometry.isValid($0) ? $0 : nil }
        let box = manual ?? object.box
        let padding = manual == nil ? 0.08 : 0
        guard [box.x, box.y, box.width, box.height].allSatisfy({ $0.isFinite }),
              box.width > 0, box.height > 0 else { return nil }
        let rect = CGRect(x: box.x - box.width * padding, y: box.y - box.height * padding,
                          width: box.width * (1 + 2 * padding), height: box.height * (1 + 2 * padding))
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        return rect.isNull || rect.isEmpty ? nil : rect
    }

    static func objectCrop(from image: UIImage, object: LearningObject?) -> UIImage {
        let normalized = normalizedImage(from: image, maxDimension: 1200) ?? image
        guard let object, let rect = objectCropRect(for: object), let source = normalized.cgImage else { return normalized }
        let pixels = CGRect(x: rect.minX * CGFloat(source.width), y: rect.minY * CGFloat(source.height),
                            width: rect.width * CGFloat(source.width), height: rect.height * CGFloat(source.height))
            .integral.intersection(CGRect(x: 0, y: 0, width: source.width, height: source.height))
        guard !pixels.isEmpty, let cropped = source.cropping(to: pixels) else { return normalized }
        return UIImage(cgImage: cropped)
    }

    /// 修正图片方向、限制内存与网络开销，并统一编码为 JPEG。
    static func jpegData(from image: UIImage, maxDimension: CGFloat = 1280) -> Data? {
        guard let rendered = normalizedImage(from: image, maxDimension: maxDimension) else { return nil }
        return rendered.jpegData(compressionQuality: 0.82)
    }

}
