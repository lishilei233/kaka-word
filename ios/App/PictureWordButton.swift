import SwiftUI

/// The default call-to-action used on notebook-style pages.
struct PictureWordButton: View {
    enum Style {
        case primary
        case secondary
        case destructive

        fileprivate var foreground: Color {
            Color.ink
        }

        fileprivate var background: Color {
            switch self {
            case .primary:
                return Color.sun
            case .secondary:
                return Color.paperLight.opacity(0.94)
            case .destructive:
                return Color.coral.opacity(0.92)
            }
        }

        fileprivate var border: Color {
            switch self {
            case .primary, .destructive:
                return Color.ink.opacity(0.14)
            case .secondary:
                return Color.ink.opacity(0.12)
            }
        }

        fileprivate var shadow: Color {
            switch self {
            case .primary, .destructive:
                return Color.ink.opacity(0.2)
            case .secondary:
                return Color.pencil.opacity(0.16)
            }
        }
    }

    enum Size {
        case large
        case compact

        fileprivate var minimumHeight: CGFloat {
            switch self {
            case .large: return 54
            case .compact: return 44
            }
        }

        fileprivate var horizontalPadding: CGFloat {
            switch self {
            case .large: return 20
            case .compact: return 16
            }
        }

        fileprivate var expandsHorizontally: Bool {
            self == .large
        }

        fileprivate var shape: AnyShape {
            switch self {
            case .large:
                return AnyShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            case .compact:
                return AnyShape(Capsule())
            }
        }

        fileprivate var font: Font {
            switch self {
            case .large:
                return .system(.headline, design: .rounded, weight: .heavy)
            case .compact:
                return .system(.subheadline, design: .rounded, weight: .bold)
            }
        }
    }

    let title: String
    let systemImage: String?
    let style: Style
    let size: Size
    let isLoading: Bool
    let iconOnly: Bool
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String? = nil,
        style: Style = .primary,
        size: Size = .large,
        isLoading: Bool = false,
        iconOnly: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.size = size
        self.isLoading = isLoading
        self.iconOnly = iconOnly
        self.action = action
    }

    init(
        systemImage: String,
        accessibilityLabel: String,
        style: Style = .primary,
        size: Size = .large,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.init(
            accessibilityLabel,
            systemImage: systemImage,
            style: style,
            size: size,
            isLoading: isLoading,
            iconOnly: true,
            action: action
        )
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                buttonLabel
                    .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                        .tint(style.foreground)
                }
            }
            .font(iconOnly ? .system(size: 18, weight: .bold) : size.font)
            .lineLimit(1)
            .minimumScaleFactor(iconOnly ? 1 : 0.72)
            .frame(maxWidth: iconOnly ? nil : (size.expandsHorizontally ? .infinity : nil))
            .frame(
                width: iconOnly ? size.minimumHeight : nil,
                height: iconOnly ? size.minimumHeight : nil,
                alignment: .center
            )
            .frame(minHeight: iconOnly ? nil : size.minimumHeight)
            .padding(.horizontal, iconOnly ? 0 : size.horizontalPadding)
            .contentShape(size.shape)
        }
        .buttonStyle(PictureWordButtonPressStyle(style: style, size: size))
        .disabled(isLoading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isLoading ? "\(title)，正在处理" : title)
    }

    @ViewBuilder
    private var buttonLabel: some View {
        if iconOnly, let systemImage {
            Image(systemName: systemImage)
        } else if let systemImage {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }
}

private struct PictureWordButtonPressStyle: ButtonStyle {
    let style: PictureWordButton.Style
    let size: PictureWordButton.Size

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed && isEnabled

        configuration.label
            .foregroundStyle(style.foreground)
            .background {
                size.shape
                    .fill(style.background)
                    .shadow(
                        color: isEnabled ? style.shadow : .clear,
                        radius: 0,
                        x: isPressed ? 1 : 3,
                        y: isPressed ? 1 : 4
                    )
            }
            .overlay {
                size.shape.stroke(style.border, lineWidth: 1)
            }
            .offset(x: isPressed ? 2 : 0, y: isPressed ? 3 : 0)
            .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.985 : 1))
            .opacity(isEnabled ? 1 : 0.45)
            .animation(
                reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.72),
                value: isPressed
            )
    }
}

private struct PictureWordButtonPreview: View {
    var body: some View {
        ZStack {
            NotebookBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("BUTTON NOTES")
                        .font(.system(.caption2, design: .monospaced, weight: .black))
                        .tracking(1.8)
                        .foregroundStyle(Color.coral)

                    Text("手账按钮")
                        .font(.scrapbookTitle)

                    PictureWordButton("拍下今天的一页", systemImage: "camera.fill") {}

                    PictureWordButton(
                        "稍后再说",
                        systemImage: "bookmark",
                        style: .secondary
                    ) {}

                    PictureWordButton(
                        "删除这一页",
                        systemImage: "trash",
                        style: .destructive
                    ) {}

                    HStack(spacing: 12) {
                        PictureWordButton(
                            "收藏",
                            systemImage: "heart",
                            style: .secondary,
                            size: .compact
                        ) {}

                        PictureWordButton(
                            "重试",
                            systemImage: "arrow.clockwise",
                            size: .compact
                        ) {}
                    }

                    PictureWordButton(
                        "更新单词",
                        systemImage: "sparkles",
                        isLoading: true
                    ) {}

                    PictureWordButton("暂不可用", style: .secondary) {}
                        .disabled(true)
                }
                .padding(24)
            }
        }
    }
}

struct PictureWordButton_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PictureWordButtonPreview()
                .frame(width: 320, height: 720)
                .previewDisplayName("320pt")

            PictureWordButtonPreview()
                .frame(width: 320, height: 900)
                .environment(\.sizeCategory, .accessibilityExtraExtraLarge)
                .previewDisplayName("Large Type")
        }
    }
}
