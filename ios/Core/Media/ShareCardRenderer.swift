import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit
import Vision

enum ShareCardAspect: String, CaseIterable, Identifiable {
    case post
    case story

    var id: String { rawValue }
    var label: String { self == .post ? "小红书 3:4" : "竖屏 9:16" }
    var logicalSize: CGSize { self == .post ? CGSize(width: 540, height: 720) : CGSize(width: 540, height: 960) }
}

enum FacePrivacyService {
    static func prepare(_ image: UIImage) async -> (image: UIImage, faces: [CGRect]) {
        await Task.detached(priority: .userInitiated) {
            guard let normalized = ImageProcessor.normalizedImage(from: image),
                  let cgImage = normalized.cgImage else {
                return (image, [])
            }

            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
            try? handler.perform([request])
            let faces = (request.results ?? []).map(\.boundingBox)
            return (normalized, faces)
        }.value
    }

    static func blurFaces(in image: UIImage, normalizedRects: [CGRect]) async -> UIImage {
        guard !normalizedRects.isEmpty else { return image }
        return await Task.detached(priority: .userInitiated) {
            guard let cgImage = image.cgImage else { return image }
            let source = CIImage(cgImage: cgImage)
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = source
            filter.radius = 32

            let context = CIContext(options: [.useSoftwareRenderer: false])
            guard let output = filter.outputImage?.cropped(to: source.extent),
                  let blurredCG = context.createCGImage(output, from: source.extent) else {
                return image
            }
            let blurred = UIImage(cgImage: blurredCG)
            let size = image.size
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { renderContext in
                image.draw(in: CGRect(origin: .zero, size: size))
                for normalized in normalizedRects {
                    var rect = CGRect(
                        x: normalized.minX * size.width,
                        y: (1 - normalized.maxY) * size.height,
                        width: normalized.width * size.width,
                        height: normalized.height * size.height
                    )
                    rect = rect.insetBy(dx: -rect.width * 0.16, dy: -rect.height * 0.18)
                    renderContext.cgContext.saveGState()
                    UIBezierPath(roundedRect: rect, cornerRadius: min(rect.width, rect.height) * 0.42).addClip()
                    blurred.draw(in: CGRect(origin: .zero, size: size))
                    renderContext.cgContext.restoreGState()
                }
            }
        }.value
    }
}

@MainActor
enum ShareCardRenderer {
    static func render(
        image: UIImage,
        result: AnalyzeResult,
        aspect: ShareCardAspect,
        headline: String
    ) throws -> URL {
        let size = aspect.logicalSize
        let content = ShareCardCanvas(
            image: image,
            result: result,
            headline: headline,
            aspect: aspect
        )
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let renderedImage = renderer.uiImage,
              let data = ImageProcessor.jpegData(from: renderedImage, maxDimension: 2_000) else {
            throw ShareCardError.renderFailed
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("picture-word-\(UUID().uuidString).jpg")
        try data.write(to: url, options: .atomic)
        return url
    }
}

enum ShareCardError: LocalizedError {
    case renderFailed

    var errorDescription: String? { "分享卡生成失败，请稍后重试。" }
}

struct ShareCardCanvas: View {
    let image: UIImage
    let result: AnalyzeResult
    let headline: String
    let aspect: ShareCardAspect

    var body: some View {
        ZStack {
            Color.paper

            Canvas { context, size in
                for y in stride(from: 26.0, through: size.height, by: 26.0) {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(path, with: .color(Color.ink.opacity(0.045)), lineWidth: 1)
                }
            }

            VStack(alignment: .leading, spacing: aspect == .post ? 18 : 28) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("MY PICTURE WORDS")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .tracking(2.2)
                            .foregroundStyle(Color.coral)
                        Text(headline)
                            .font(.system(size: aspect == .post ? 30 : 36, weight: .bold, design: .serif))
                            .foregroundStyle(Color.ink)
                            .lineLimit(2)
                    }
                    Spacer()
                    StickerSeal(symbol: "sparkles", color: .coral)
                }

                AnnotatedImageView(image: image, objects: result.objects) { _ in }
                    .frame(height: aspect == .post ? 430 : 610)
                    .padding(10)
                    .background(Color.paperLight, in: RoundedRectangle(cornerRadius: 25))
                    .overlay(alignment: .top) { WashiTape(color: .sun).offset(y: -10) }
                    .rotationEffect(.degrees(-0.45))
                    .shadow(color: Color.ink.opacity(0.12), radius: 0, x: 3, y: 4)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(result.objects.map(\.english).prefix(5).joined(separator: "  ·  "))
                            .font(.system(size: 17, weight: .bold, design: .serif))
                            .foregroundStyle(Color.ink)
                            .lineLimit(2)
                        Text("\(result.objects.count) WORDS FOUND IN REAL LIFE")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .tracking(1.4)
                            .foregroundStyle(Color.ink.opacity(0.48))
                    }
                    Spacer()
                    Text("PICTURE\nWORD")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .tracking(1)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(Color.coral)
                }
            }
            .padding(30)
        }
        .dynamicTypeSize(.large)
    }
}
