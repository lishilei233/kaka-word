import SwiftUI
import UIKit

/// 绘制等比例适配的图片及 `AnnotationLayoutEngine` 计算结果；本视图不负责布局决策。
struct AnnotatedImageView: View {
    let image: UIImage
    let objects: [LearningObject]
    var revealsAnnotations = true
    let onSelect: (LearningObject) -> Void

    var body: some View {
        GeometryReader { proxy in
            let imageFrame = fittedImageFrame(in: proxy.size)
            let layout = AnnotationLayoutEngine(objects: objects).layout(in: imageFrame)

            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: imageFrame.width, height: imageFrame.height)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .position(x: imageFrame.midX, y: imageFrame.midY)

                Canvas { context, _ in
                    for route in layout.routes {
                        drawLeaderLine(route, in: &context)
                    }
                }
                .allowsHitTesting(false)
                .opacity(revealsAnnotations ? 1 : 0)
                .animation(.easeOut(duration: 0.28), value: revealsAnnotations)

                ForEach(Array(layout.placements.enumerated()), id: \.element.id) { index, placement in
                    Button { onSelect(placement.object) } label: {
                        Text(placement.object.english)
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.66)
                            .allowsTightening(true)
                            .padding(.horizontal, 10)
                            .frame(width: placement.labelWidth, height: placement.labelHeight)
                            .background(Color.sun, in: Capsule())
                            .overlay {
                                Capsule().stroke(Color.ink.opacity(0.18), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .position(placement.labelCenter)
                    .scaleEffect(revealsAnnotations ? 1 : 0.72)
                    .opacity(revealsAnnotations ? 1 : 0)
                    .animation(
                        .spring(response: 0.42, dampingFraction: 0.72)
                            .delay(Double(index) * 0.075),
                        value: revealsAnnotations
                    )
                }
            }
        }
    }

    private func drawLeaderLine(_ route: AnnotationRoute, in context: inout GraphicsContext) {
        var path = Path()
        path.move(to: route.start)
        path.addQuadCurve(to: route.target, control: route.control)
        context.stroke(
            path,
            with: .color(Color.ink.opacity(0.78)),
            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
        )
        context.stroke(
            path,
            with: .color(Color.sun),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )

        let outerDot = CGRect(x: route.target.x - 5, y: route.target.y - 5, width: 10, height: 10)
        let innerDot = CGRect(x: route.target.x - 3, y: route.target.y - 3, width: 6, height: 6)
        context.fill(Path(ellipseIn: outerDot), with: .color(Color.ink.opacity(0.82)))
        context.fill(Path(ellipseIn: innerDot), with: .color(Color.sun))
    }

    private func fittedImageFrame(in container: CGSize) -> CGRect {
        let imageRatio = image.size.width / image.size.height
        let containerRatio = container.width / max(container.height, 1)
        let size: CGSize
        if imageRatio > containerRatio {
            size = CGSize(width: container.width, height: container.width / imageRatio)
        } else {
            size = CGSize(width: container.height * imageRatio, height: container.height)
        }
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}
