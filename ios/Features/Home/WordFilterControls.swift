import SwiftUI

/// Handwritten-style state switcher for vocabulary collections.
struct ScrapbookWordStateTabs: View {
    @Binding var selection: WordLearningState
    let counts: [WordLearningState: Int]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionHighlight

    var body: some View {
        HStack(spacing: 6) {
            ForEach(WordLearningState.allCases) { state in
                Button {
                    guard selection != state else { return }
                    withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82)) {
                        selection = state
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: icon(for: state))
                            .font(.system(size: 13, weight: .black))

                        Text(state.title)
                            .font(.system(.subheadline, design: .rounded, weight: .heavy))

                        Text("\(counts[state, default: 0])")
                            .font(.system(.caption, design: .monospaced, weight: .black))
                            .foregroundStyle(isSelected(state) ? Color.ink.opacity(0.62) : Color.ink.opacity(0.42))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                isSelected(state) ? Color.paperLight.opacity(0.68) : Color.paperDeep.opacity(0.28),
                                in: Capsule()
                            )
                    }
                    .foregroundStyle(isSelected(state) ? Color.ink : Color.ink.opacity(0.48))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background {
                        if isSelected(state) {
                            Capsule()
                                .fill(accent(for: state).opacity(0.82))
                                .matchedGeometryEffect(
                                    id: "word-state-selection",
                                    in: selectionHighlight
                                )
                        }
                    }
                    .overlay {
                        Capsule()
                            .stroke(
                                isSelected(state) ? Color.ink.opacity(0.08) : Color.clear,
                                lineWidth: 1
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected(state) ? .isSelected : [])
                .accessibilityLabel("\(state.title)，\(counts[state, default: 0]) 个单词")
            }
        }
        .padding(5)
        .background(Color.paperDeep.opacity(0.34), in: Capsule())
        .overlay {
            Capsule().stroke(Color.ink.opacity(0.06), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("单词状态")
    }

    private func isSelected(_ state: WordLearningState) -> Bool {
        selection == state
    }

    private func accent(for state: WordLearningState) -> Color {
        switch state {
        case .learning: return .sun
        case .mastered: return .mint
        }
    }

    private func icon(for state: WordLearningState) -> String {
        switch state {
        case .learning: return "pencil"
        case .mastered: return "checkmark.seal.fill"
        }
    }
}

/// Paper-like search field shared by vocabulary screens.
struct ScrapbookSearchField: View {
    @Binding var text: String
    @Binding private var externallyFocused: Bool
    let placeholder: String
    let onFocusChange: (Bool) -> Void
    @FocusState private var fieldFocused: Bool

    init(
        text: Binding<String>,
        placeholder: String = "搜索英文或中文",
        isFocused: Binding<Bool> = .constant(false),
        onFocusChange: @escaping (Bool) -> Void = { _ in }
    ) {
        _text = text
        _externallyFocused = isFocused
        self.placeholder = placeholder
        self.onFocusChange = onFocusChange
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.coral)
                .frame(width: 24)

            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .focused($fieldFocused)
                .onSubmit {
                    fieldFocused = false
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.ink.opacity(0.32))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(Color.paperLight.opacity(0.92), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.ink.opacity(0.09), lineWidth: 1)
        }
        .shadow(color: Color.ink.opacity(0.06), radius: 0, x: 2, y: 2)
        .accessibilityElement(children: .contain)
        .onChange(of: fieldFocused) { _, focused in
            if externallyFocused != focused {
                externallyFocused = focused
            }
            onFocusChange(focused)
        }
        .onChange(of: externallyFocused) { _, focused in
            if fieldFocused != focused {
                fieldFocused = focused
            }
        }
        .onDisappear {
            if fieldFocused || externallyFocused {
                fieldFocused = false
                externallyFocused = false
                onFocusChange(false)
            }
        }
    }
}
