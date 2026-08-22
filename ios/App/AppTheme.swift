import SwiftUI

/// Picture Word 的语义色板。页面使用颜色角色，避免重复书写 RGB 数值。
extension Color {
    static let ink = Color(red: 0.141, green: 0.129, blue: 0.118)
    static let paper = Color(red: 0.965, green: 0.941, blue: 0.894)
    static let paperLight = Color(red: 1.0, green: 0.992, blue: 0.973)
    static let paperDeep = Color(red: 0.914, green: 0.871, blue: 0.792)
    static let sun = Color(red: 0.957, green: 0.788, blue: 0.365)
    static let coral = Color(red: 0.949, green: 0.427, blue: 0.380)
    static let mint = Color(red: 0.659, green: 0.776, blue: 0.624)
    static let sky = Color(red: 0.659, green: 0.784, blue: 0.871)
    static let pencil = Color(red: 0.427, green: 0.388, blue: 0.345)
}

extension Font {
    static let scrapbookHero = Font.system(.largeTitle, design: .serif, weight: .bold)
    static let scrapbookTitle = Font.system(.title2, design: .rounded, weight: .heavy)
    static let scrapbookBody = Font.system(.body, design: .rounded, weight: .medium)
    static let scrapbookCaption = Font.system(.caption, design: .rounded, weight: .bold)
}

struct NotebookBackground: View {
    var body: some View {
        ZStack {
            Color.paper
            Canvas { context, size in
                let lineColor = Color.pencil.opacity(0.055)
                for y in stride(from: 30.0, through: size.height, by: 28.0) {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(path, with: .color(lineColor), lineWidth: 1)
                }
                for x in stride(from: 18.0, through: size.width, by: 42.0) {
                    let dot = CGRect(x: x, y: 16, width: 1.4, height: 1.4)
                    context.fill(Path(ellipseIn: dot), with: .color(Color.ink.opacity(0.04)))
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct WashiTape: View {
    var color: Color = .sun

    var body: some View {
        Rectangle()
            .fill(color.opacity(0.78))
            .frame(width: 72, height: 20)
            .overlay {
                Rectangle().stroke(Color.white.opacity(0.28), lineWidth: 1)
            }
            .rotationEffect(.degrees(-4))
            .shadow(color: Color.ink.opacity(0.08), radius: 2, y: 1)
            .accessibilityHidden(true)
    }
}

struct StickerSeal: View {
    let symbol: String
    var color: Color = .coral

    var body: some View {
        ZStack {
            Circle().fill(Color.paperLight)
            Circle().stroke(color, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.ink)
        }
        .frame(width: 54, height: 54)
        .rotationEffect(.degrees(5))
        .shadow(color: Color.ink.opacity(0.1), radius: 5, y: 3)
    }
}

extension View {
    /// iOS 26 使用原生 Liquid Glass；更早系统使用材质、描边与高光维持同一层级。
    @ViewBuilder
    func pictureWordGlass<S: Shape>(
        tint: Color? = nil,
        interactive: Bool = false,
        in shape: S
    ) -> some View {
        if #available(iOS 26.0, *) {
            let glass = (tint.map { Glass.regular.tint($0) } ?? Glass.regular)
                .interactive(interactive)
            self.glassEffect(glass, in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .background((tint ?? .clear).opacity(0.28), in: shape)
                .overlay {
                    shape.stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.62), Color.white.opacity(0.12), Color.ink.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                }
                .shadow(color: Color.ink.opacity(0.16), radius: 18, y: 8)
        }
    }

    /// 自定义导航栏会让系统返回手势不可用；仅响应屏幕左缘的明确横向滑动，避免干扰页面滚动。
    func pictureWordBackSwipe(action: @escaping () -> Void) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 18, coordinateSpace: .global)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = abs(value.translation.height)
                    guard value.startLocation.x <= 28,
                          horizontal >= 72,
                          horizontal > vertical * 1.35 else { return }
                    action()
                }
        )
    }
}
