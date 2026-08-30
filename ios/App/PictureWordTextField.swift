import SwiftUI

/// Shared notebook-style single-line input used by vocabulary editing flows.
struct PictureWordTextField: View {
    @Binding private var text: String

    private let placeholder: String
    private let submitLabel: SubmitLabel
    private let autoFocus: Bool
    private let isLoading: Bool
    private let onSubmit: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool

    init(
        _ placeholder: String,
        text: Binding<String>,
        submitLabel: SubmitLabel = .done,
        autoFocus: Bool = false,
        isLoading: Bool = false,
        onSubmit: @escaping () -> Void = {}
    ) {
        self.placeholder = placeholder
        _text = text
        self.submitLabel = submitLabel
        self.autoFocus = autoFocus
        self.isLoading = isLoading
        self.onSubmit = onSubmit
    }

    var body: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $text)
                .focused($isFocused)
                .submitLabel(submitLabel)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.body, design: .rounded, weight: .bold))
                .foregroundStyle(Color.ink)
                .onSubmit(onSubmit)

            if isLoading {
                ProgressView()
                    .tint(Color.ink)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(Color.paperLight.opacity(0.94), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.ink.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: Color.pencil.opacity(0.16), radius: 0, x: 3, y: 4)
        .opacity(isEnabled ? 1 : 0.62)
        .accessibilityValue(isLoading ? "正在处理" : text)
        .task(id: autoFocus) {
            guard autoFocus else { return }
            do {
                try await Task.sleep(for: .milliseconds(220))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            isFocused = true
        }
    }
}
