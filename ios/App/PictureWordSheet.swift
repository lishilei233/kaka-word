import SwiftUI

/// Shared paper-style content scaffold for sheets.
///
/// Sheet presentation height remains a responsibility of the presenting view;
/// this component only standardizes the content surface and scrolling behavior.
struct PictureWordSheet<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background(Color.paper)
    }
}

/// Standard heading hierarchy for content sheets.
struct PictureWordSheetHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    let eyebrowColor: Color
    let foreground: Color
    private let trailing: Trailing

    init(
        eyebrow: String,
        title: String,
        eyebrowColor: Color = .coral,
        foreground: Color = .ink,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.eyebrowColor = eyebrowColor
        self.foreground = foreground
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(eyebrowColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(title)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(foreground)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 0)
            trailing
        }
    }
}

extension PictureWordSheetHeader where Trailing == EmptyView {
    init(
        eyebrow: String,
        title: String,
        eyebrowColor: Color = .coral,
        foreground: Color = .ink
    ) {
        self.init(
            eyebrow: eyebrow,
            title: title,
            eyebrowColor: eyebrowColor,
            foreground: foreground
        ) {
            EmptyView()
        }
    }
}

extension View {
    /// Applies the shared presentation treatment for Picture Word sheets.
    func pictureWordSheetPresentation(
        detents: Set<PresentationDetent> = [.medium],
        showsDragIndicator: Bool = true
    ) -> some View {
        presentationDetents(detents)
            .presentationDragIndicator(showsDragIndicator ? .visible : .hidden)
            .presentationBackground(Color.paper)
    }
}
