import SwiftUI

/// Shared separated-capsule navigation header used by secondary pages.
struct PictureWordPageHeader<Leading: View, Trailing: View>: View {
    let eyebrow: String
    let title: String
    let foreground: Color
    let eyebrowColor: Color
    let tint: Color
    private let leading: Leading
    private let trailing: Trailing

    init(
        eyebrow: String,
        title: String,
        foreground: Color,
        eyebrowColor: Color,
        tint: Color,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.foreground = foreground
        self.eyebrowColor = eyebrowColor
        self.tint = tint
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        ZStack {
            HStack(spacing: 6) {
                leading
                Spacer(minLength: 0)
                trailing
            }

            PictureWordHeaderCapsule(
                tint: tint,
                foreground: foreground
            ) {
                VStack(spacing: 2) {
                    Text(eyebrow)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .tracking(1.8)
                        .foregroundStyle(eyebrowColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(title)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                }
                .padding(.horizontal, 18)
                .frame(minWidth: 126, maxWidth: 220, minHeight: 50)
            }
            .padding(.horizontal, 56)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }
}

/// A single independent glass capsule. It can contain either a button or a passive badge.
struct PictureWordHeaderCapsule<Content: View>: View {
    let tint: Color
    let foreground: Color
    var interactive = false
    private let content: Content

    init(
        tint: Color,
        foreground: Color,
        interactive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.foreground = foreground
        self.interactive = interactive
        self.content = content()
    }

    var body: some View {
        content
            .frame(minWidth: 50, minHeight: 50)
            .foregroundStyle(foreground)
            .pictureWordGlass(
                tint: tint,
                interactive: interactive,
                in: Capsule()
            )
    }
}
