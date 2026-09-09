import SwiftUI
import UIKit

private struct WordDetailContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct WordDetailSheet: View {
    let object: LearningObject
    var objects: [LearningObject]
    var imageProvider: ((LearningObject) -> UIImage?)?
    var onUpdate: ((LearningObject) -> String?)?
    var onDelete: ((LearningObject) -> String?)?
    var onManualCorrection: ((LearningObject, LearningObject) -> Void)?
    var onEditingChanged: ((Bool) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var membership: MembershipStore
    @EnvironmentObject private var wordLearningStore: WordLearningStore
    @StateObject private var speech = SpeechService()
    @AppStorage(AppSettings.Key.englishSpeechEnabled) private var speechEnabled = AppSettings.defaultEnglishSpeechEnabled
    @AppStorage(AppSettings.Key.automaticWordSpeechEnabled) private var automaticWordSpeechEnabled = AppSettings.defaultAutomaticWordSpeechEnabled
    @AppStorage(AppSettings.Key.speechRate) private var speechRate = AppSettings.defaultSpeechRate
    @AppStorage(AppSettings.Key.didShowWordDetailSwipeHint) private var didShowSwipeHint = false
    @State private var displayedObject: LearningObject
    @State private var autoPlayTracker = WordDetailAutoPlayTracker()
    @State private var editingTerm = ""
    @State private var isEditing = false
    @State private var isResolving = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var showPaywall = false
    @State private var imageCache: [String: UIImage]
    @State private var unavailableImageIDs: Set<String> = []
    @State private var preferredSheetHeight: CGFloat = 420
    @State private var sheetDetent: PresentationDetent = .height(420)
    @State private var showsSwipeHint = false

    init(
        object: LearningObject,
        objects: [LearningObject] = [],
        imageProvider: ((LearningObject) -> UIImage?)? = nil,
        onUpdate: ((LearningObject) -> String?)? = nil,
        onDelete: ((LearningObject) -> String?)? = nil,
        onManualCorrection: ((LearningObject, LearningObject) -> Void)? = nil,
        onEditingChanged: ((Bool) -> Void)? = nil
    ) {
        self.object = object
        self.objects = objects.isEmpty ? [object] : objects
        self.imageProvider = imageProvider
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self.onManualCorrection = onManualCorrection
        self.onEditingChanged = onEditingChanged
        _displayedObject = State(initialValue: object)
        _imageCache = State(initialValue: imageProvider?(object).map { [object.id: $0] } ?? [:])
    }

    var body: some View {
        TabView(selection: selectedObjectID) {
            ForEach(objects) { object in
                wordPage(for: object)
                    .tag(object.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color.paper)
        .overlay(alignment: .bottom) {
            if showsSwipeHint {
                Label("左右滑动切换单词", systemImage: "arrow.left.and.right")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.ink.opacity(0.72))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.paperLight, in: Capsule())
                    .overlay {
                        Capsule().stroke(Color.ink.opacity(0.08), lineWidth: 1)
                    }
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .accessibilityHint(objects.count > 1 ? "左右滑动切换单词" : "")
        .onPreferenceChange(WordDetailContentHeightKey.self, perform: updatePreferredHeight)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isEditing {
                HStack(spacing: 12) {
                    PictureWordButton(
                        learningState == .learning ? "我会了" : "放回学习中",
                        systemImage: learningState == .learning ? "checkmark.circle.fill" : "arrow.uturn.backward.circle",
                        style: learningState == .learning ? .primary : .secondary,
                        isLoading: isResolving,
                        action: toggleLearningState
                    )
                    .disabled(isResolving)
                    .frame(maxWidth: .infinity)

                    if onDelete != nil {
                        PictureWordButton(
                            systemImage: "trash",
                            accessibilityLabel: "删除单词",
                            style: .destructive,
                            size: .large,
                            isLoading: isResolving,
                            action: { showDeleteConfirmation = true }
                        )
                        .disabled(isResolving)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 0)
                .background(Color.paper)
            }
        }
        .alert("删除这个单词？", isPresented: $showDeleteConfirmation) {
            Button("删除", role: .destructive, action: deleteObject)
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会从当前照片卡片中移除这个单词，不会删除整条历史记录。")
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(onPurchaseCompleted: startEditing)
                .environmentObject(membership)
        }
        .onAppear {
            playWordAutomaticallyIfNeeded(for: displayedObject)
            preloadImages(around: displayedObject.id)
        }
        .task {
            await presentSwipeHintIfNeeded()
        }
        .onDisappear {
            speech.stop()
            autoPlayTracker.reset()
        }
        .onChange(of: object) { _, updatedObject in
            displayedObject = updatedObject
            if !isEditing { editingTerm = updatedObject.english }
            if !isEditing {
                playWordAutomaticallyIfNeeded(for: updatedObject)
            }
        }
        .presentationDetents([.height(preferredSheetHeight), .large], selection: $sheetDetent)
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.paper)
    }

    @MainActor
    private func presentSwipeHintIfNeeded() async {
        guard objects.count > 1, !didShowSwipeHint else { return }
        try? await Task.sleep(for: .milliseconds(550))
        guard !Task.isCancelled else { return }
        didShowSwipeHint = true
        withAnimation(.easeOut(duration: 0.2)) {
            showsSwipeHint = true
        }
        try? await Task.sleep(for: .milliseconds(2_800))
        guard !Task.isCancelled else { return }
        withAnimation(.easeIn(duration: 0.2)) {
            showsSwipeHint = false
        }
    }

    private var selectedObjectID: Binding<String> {
        Binding(
            get: { displayedObject.id },
            set: { id in
                guard !isEditing,
                      let selectedObject = objects.first(where: { $0.id == id }),
                      selectedObject.id != displayedObject.id else { return }
                displayedObject = selectedObject
                errorMessage = nil
                playWordAutomaticallyIfNeeded(for: displayedObject)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    preloadImages(around: selectedObject.id)
                }
            }
        )
    }

    private func wordPage(for object: LearningObject) -> some View {
        PictureWordSheet {
            VStack(alignment: .leading, spacing: 18) {
                header(for: object)

                if object.id == displayedObject.id, let errorMessage {
                    Text(errorMessage)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.coral)
                }

                Text(object.chinese)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ink.opacity(0.82))

                if let image = imageCache[object.id] {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 112, height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.ink.opacity(0.08), lineWidth: 1)
                        }
                        .accessibilityLabel("\(object.english) 的物体图片")
                }

                Divider()

                VStack(alignment: .leading, spacing: 7) {
                    Text("例句")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(Color.coral)
                    Button {
                        speech.speak(object.example, rate: speechRate)
                    } label: {
                        Text(object.example)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.ink)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .disabled(!speechEnabled)
                    .accessibilityLabel("朗读例句")
                    .accessibilityHint(speechEnabled ? "点击播放英文例句" : "请先在设置中开启英文发音")
                    if let exampleChinese = object.exampleChinese, !exampleChinese.isEmpty {
                        Text(exampleChinese)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.ink.opacity(0.56))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: WordDetailContentHeightKey.self,
                        value: object.id == displayedObject.id ? proxy.size.height : 0
                    )
                }
            }
        }
    }

    private func updatePreferredHeight(_ contentHeight: CGFloat) {
        guard contentHeight > 0, !isEditing else { return }
        let height = min(max(contentHeight + 136, 320), 620)
        guard abs(height - preferredSheetHeight) > 1 else { return }
        preferredSheetHeight = height
        sheetDetent = .height(height)
    }

    private func preloadImages(around objectID: String) {
        guard let imageProvider,
              let index = objects.firstIndex(where: { $0.id == objectID }) else { return }
        for candidateIndex in [index - 1, index, index + 1] where objects.indices.contains(candidateIndex) {
            let candidate = objects[candidateIndex]
            guard imageCache[candidate.id] == nil,
                  !unavailableImageIDs.contains(candidate.id) else { continue }
            if let image = imageProvider(candidate) {
                imageCache[candidate.id] = image
            } else {
                unavailableImageIDs.insert(candidate.id)
            }
        }
    }

    @ViewBuilder
    private func header(for object: LearningObject) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if isEditing && object.id == displayedObject.id {
                PictureWordTextField(
                    "中文或英文单词",
                    text: $editingTerm,
                    autoFocus: true,
                    isLoading: isResolving,
                    onSubmit: resolveVocabulary
                )
                .disabled(isResolving)

                PictureWordButton(
                    systemImage: "xmark",
                    accessibilityLabel: "取消修改",
                    style: .secondary,
                    size: .large,
                    action: cancelEditing
                )
                .disabled(isResolving)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 9) {
                        Button {
                            speech.speak(object.english, rate: speechRate)
                        } label: {
                            Text(object.english)
                                .font(.system(size: 36, weight: .black, design: .rounded))
                                .foregroundStyle(Color.ink)
                        }
                        .buttonStyle(.plain)
                        .disabled(!speechEnabled)
                        .accessibilityLabel("朗读 \(object.english)")
                        .accessibilityHint(speechEnabled ? "点击播放英文单词" : "请先在设置中开启英文发音")
                    }
                    Text(object.ipa)
                        .font(.system(size: 17, weight: .medium, design: .serif))
                        .foregroundStyle(Color.ink.opacity(0.52))
                }

                Spacer()

                if onUpdate != nil {
                    PictureWordButton(
                        systemImage: "pencil",
                        accessibilityLabel: "修改 \(object.english)",
                        size: .large,
                        action: startEditing
                    )
                }
            }
        }
    }

    private var submittedTerm: String {
        editingTerm.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var learningState: WordLearningState {
        wordLearningStore.state(for: displayedObject.english)
    }

    private func playWordAutomaticallyIfNeeded(for object: LearningObject) {
        guard autoPlayTracker.shouldPlay(
            objectID: object.id,
            english: object.english,
            isEnabled: automaticWordSpeechEnabled && speechEnabled
        ) else { return }
        speech.speak(object.english, rate: speechRate)
    }

    private func toggleLearningState() {
        wordLearningStore.setState(
            learningState == .learning ? .mastered : .learning,
            for: displayedObject.english
        )
    }

    private func startEditing() {
        guard membership.isMember else {
            showPaywall = true
            return
        }
        editingTerm = displayedObject.english
        errorMessage = nil
        onEditingChanged?(true)
        isEditing = true
        sheetDetent = .large
    }

    private func cancelEditing() {
        guard !isResolving else { return }
        editingTerm = displayedObject.english
        errorMessage = nil
        isEditing = false
        onEditingChanged?(false)
        sheetDetent = .height(preferredSheetHeight)
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
                    onManualCorrection?(displayedObject, updated)
                    displayedObject = updated
                    isEditing = false
                    onEditingChanged?(false)
                    sheetDetent = .height(preferredSheetHeight)
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
