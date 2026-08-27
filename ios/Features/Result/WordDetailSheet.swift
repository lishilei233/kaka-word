import SwiftUI

struct WordDetailSheet: View {
    let object: LearningObject
    var onUpdate: ((LearningObject) -> String?)?
    var onDelete: ((LearningObject) -> String?)?
    var onEditingChanged: ((Bool) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechService()
    @AppStorage(AppSettings.Key.englishSpeechEnabled) private var speechEnabled = AppSettings.defaultEnglishSpeechEnabled
    @AppStorage(AppSettings.Key.speechRate) private var speechRate = AppSettings.defaultSpeechRate
    @State private var displayedObject: LearningObject
    @State private var editingTerm = ""
    @State private var isEditing = false
    @State private var isResolving = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    @FocusState private var termIsFocused: Bool

    init(
        object: LearningObject,
        onUpdate: ((LearningObject) -> String?)? = nil,
        onDelete: ((LearningObject) -> String?)? = nil,
        onEditingChanged: ((Bool) -> Void)? = nil
    ) {
        self.object = object
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self.onEditingChanged = onEditingChanged
        _displayedObject = State(initialValue: object)
    }

    var body: some View {
        PictureWordSheet {
            VStack(alignment: .leading, spacing: 18) {
                header

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.coral)
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
                    Button {
                        speech.speak(displayedObject.example, rate: speechRate)
                    } label: {
                        Text(displayedObject.example)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.ink)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .disabled(!speechEnabled)
                    .accessibilityLabel("朗读例句")
                    .accessibilityHint(speechEnabled ? "点击播放英文例句" : "请先在设置中开启英文发音")
                    if let exampleChinese = displayedObject.exampleChinese, !exampleChinese.isEmpty {
                        Text(exampleChinese)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.ink.opacity(0.56))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isEditing, onDelete != nil {
                PictureWordButton(
                    "删除单词",
                    systemImage: "trash",
                    style: .destructive,
                    isLoading: isResolving,
                    action: { showDeleteConfirmation = true }
                )
                .disabled(isResolving)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .background(Color.paper)
            }
        }
        .alert("删除这个单词？", isPresented: $showDeleteConfirmation) {
            Button("删除", role: .destructive, action: deleteObject)
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会从当前照片卡片中移除这个单词，不会删除整条历史记录。")
        }
        .task(id: isEditing) {
            guard isEditing else { return }
            do {
                try await Task.sleep(for: .milliseconds(260))
            } catch {
                return
            }
            guard !Task.isCancelled, isEditing else { return }
            termIsFocused = true
        }
        .onChange(of: object) { _, updatedObject in
            displayedObject = updatedObject
            if !isEditing { editingTerm = updatedObject.english }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            if isEditing {
                TextField("中文或英文单词", text: $editingTerm)
                    .focused($termIsFocused)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    .background(Color.paperLight, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(Color.ink.opacity(0.1), lineWidth: 1)
                    }
                    .onSubmit(resolveVocabulary)

                HStack(spacing: 8) {
                    Button(action: cancelEditing) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.ink.opacity(0.7))
                            .frame(width: 34, height: 34)
                            .background(Color.ink.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isResolving)
                    .accessibilityLabel("取消修改")

                    Button(action: resolveVocabulary) {
                        Group {
                            if isResolving {
                                ProgressView()
                                    .tint(Color.ink)
                            } else {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .black))
                            }
                        }
                        .foregroundStyle(Color.ink)
                        .frame(width: 34, height: 34)
                        .background(Color.sun, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isResolving || submittedTerm.isEmpty || submittedTerm.count > 60)
                    .accessibilityLabel("保存修改")
                }
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 9) {
                        Button {
                            speech.speak(displayedObject.english, rate: speechRate)
                        } label: {
                            Text(displayedObject.english)
                                .font(.system(size: 36, weight: .black, design: .rounded))
                                .foregroundStyle(Color.ink)
                        }
                        .buttonStyle(.plain)
                        .disabled(!speechEnabled)
                        .accessibilityLabel("朗读 \(displayedObject.english)")
                        .accessibilityHint(speechEnabled ? "点击播放英文单词" : "请先在设置中开启英文发音")
                    }
                    Text(displayedObject.ipa)
                        .font(.system(size: 17, weight: .medium, design: .serif))
                        .foregroundStyle(Color.ink.opacity(0.52))
                }

                Spacer()

                if onUpdate != nil {
                    Button(action: startEditing) {
                        Image(systemName: "pencil")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(Color.ink)
                            .frame(width: 52, height: 52)
                            .background(speechEnabled ? Color.sun : Color.ink.opacity(0.12), in: Circle())
                    }
                    .accessibilityLabel("修改 \(displayedObject.english)")
                }
            }
        }
    }

    private var submittedTerm: String {
        editingTerm.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func startEditing() {
        editingTerm = displayedObject.english
        errorMessage = nil
        onEditingChanged?(true)
        isEditing = true
    }

    private func cancelEditing() {
        guard !isResolving else { return }
        termIsFocused = false
        editingTerm = displayedObject.english
        errorMessage = nil
        isEditing = false
        onEditingChanged?(false)
    }

    private func resolveVocabulary() {
        guard !submittedTerm.isEmpty, submittedTerm.count <= 60, !isResolving else { return }
        isResolving = true
        errorMessage = nil
        Task {
            do {
                let details = try await APIClient().resolveVocabulary(term: submittedTerm)
                let updated = displayedObject.replacingVocabulary(with: details)
                if let persistenceError = onUpdate?(updated) {
                    errorMessage = persistenceError
                } else {
                    displayedObject = updated
                    termIsFocused = false
                    isEditing = false
                    onEditingChanged?(false)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isResolving = false
        }
    }

    private func deleteObject() {
        guard let onDelete else { return }
        if let persistenceError = onDelete(displayedObject) {
            errorMessage = persistenceError
        } else {
            dismiss()
        }
    }
}
