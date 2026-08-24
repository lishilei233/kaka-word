import SwiftUI

struct WordDetailSheet: View {
    let object: LearningObject
    var onUpdate: ((LearningObject) -> String?)?

    @StateObject private var speech = SpeechService()
    @AppStorage(AppSettings.Key.englishSpeechEnabled) private var speechEnabled = AppSettings.defaultEnglishSpeechEnabled
    @AppStorage(AppSettings.Key.speechRate) private var speechRate = AppSettings.defaultSpeechRate
    @State private var displayedObject: LearningObject
    @State private var showEditor = false

    init(object: LearningObject, onUpdate: ((LearningObject) -> String?)? = nil) {
        self.object = object
        self.onUpdate = onUpdate
        _displayedObject = State(initialValue: object)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 9) {
                        Text(displayedObject.english)
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .foregroundStyle(Color.ink)
                        if onUpdate != nil {
                            Button {
                                showEditor = true
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 14, weight: .black))
                                    .foregroundStyle(Color.ink)
                                    .frame(width: 32, height: 32)
                                    .background(Color.mint.opacity(0.62), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("修改 \(displayedObject.english)")
                        }
                    }
                    Text(displayedObject.ipa)
                        .font(.system(size: 17, weight: .medium, design: .serif))
                        .foregroundStyle(Color.ink.opacity(0.52))
                }
                Spacer()
                Button { speech.speak(displayedObject.english, rate: speechRate) } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Color.ink)
                        .frame(width: 52, height: 52)
                        .background(speechEnabled ? Color.sun : Color.ink.opacity(0.12), in: Circle())
                }
                .disabled(!speechEnabled)
                .accessibilityHint(speechEnabled ? "朗读英文单词" : "请先在设置中开启英文发音")
            }
            Text(displayedObject.chinese)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ink.opacity(0.82))
            Divider()
            VStack(alignment: .leading, spacing: 7) {
                Text("例句")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(Color.coral)
                Text(displayedObject.example)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.ink)
            }
            Spacer()
        }
        .padding(24)
        .background(Color.paper)
        .sheet(isPresented: $showEditor) {
            VocabularyEditSheet(object: displayedObject) { updatedObject in
                if let error = onUpdate?(updatedObject) {
                    return error
                }
                displayedObject = updatedObject
                return nil
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: object) { _, updatedObject in
            displayedObject = updatedObject
        }
    }
}

private struct VocabularyEditSheet: View {
    let object: LearningObject
    let onCommit: (LearningObject) -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var term: String
    @State private var isResolving = false
    @State private var errorMessage: String?
    @FocusState private var termIsFocused: Bool

    init(object: LearningObject, onCommit: @escaping (LearningObject) -> String?) {
        self.object = object
        self.onCommit = onCommit
        _term = State(initialValue: object.english)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("EDIT WORD")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(Color.coral)
                    Text("修改识别结果")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(Color.ink)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.ink.opacity(0.62))
                    .disabled(isResolving)
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("输入正确的中文或英文物体名称")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.ink.opacity(0.62))
                TextField("例如：窗户 / window", text: $term)
                    .focused($termIsFocused)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .padding(16)
                    .background(Color.paperLight, in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.ink.opacity(0.1), lineWidth: 1)
                    }
                    .onSubmit(resolveVocabulary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.coral)
            }

            Button(action: resolveVocabulary) {
                HStack(spacing: 8) {
                    if isResolving { ProgressView().tint(Color.paperLight) }
                    Text(isResolving ? "正在生成学习信息…" : "更新单词")
                }
                .font(.system(.headline, design: .rounded, weight: .heavy))
                .foregroundStyle(Color.paperLight)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Color.ink, in: RoundedRectangle(cornerRadius: 17))
            }
            .buttonStyle(.plain)
            .disabled(isResolving || submittedTerm.isEmpty || submittedTerm.count > 60)
            .opacity(submittedTerm.isEmpty || submittedTerm.count > 60 ? 0.45 : 1)

            Spacer(minLength: 0)
        }
        .padding(24)
        .background(Color.paper)
        .task {
            try? await Task.sleep(for: .milliseconds(180))
            termIsFocused = true
        }
    }

    private var submittedTerm: String {
        term.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveVocabulary() {
        guard !submittedTerm.isEmpty, submittedTerm.count <= 60, !isResolving else { return }
        isResolving = true
        errorMessage = nil
        Task {
            do {
                let details = try await APIClient().resolveVocabulary(term: submittedTerm)
                let updated = object.replacingVocabulary(with: details)
                if let persistenceError = onCommit(updated) {
                    errorMessage = persistenceError
                } else {
                    dismiss()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isResolving = false
        }
    }
}
