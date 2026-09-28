import SwiftUI
import UIKit

struct WordDetailSheet: View {
    let object: LearningObject
    var objects: [LearningObject]
    var imageProvider: ((LearningObject, Int) -> UIImage?)?
    var photoProvider: ((LearningObject, Int) -> WordDetailPhoto?)?
    var onUpdate: ((LearningObject) -> String?)?
    var onDelete: ((LearningObject) -> String?)?
    var onManualCorrection: ((LearningObject, LearningObject) -> Void)?
    var onEditingChanged: ((Bool) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var membership: MembershipStore
    @EnvironmentObject private var wordLearningStore: WordLearningStore
    // Voice enumeration is only needed by Settings. Deferring it here keeps
    // system voice discovery out of the sheet's first presentation frame.
    @StateObject private var speech = SpeechService(refreshesVoicesOnInit: false)
    @AppStorage(AppSettings.Key.englishSpeechEnabled) private var speechEnabled = AppSettings.defaultEnglishSpeechEnabled
    @AppStorage(AppSettings.Key.automaticWordSpeechEnabled) private var automaticWordSpeechEnabled = AppSettings.defaultAutomaticWordSpeechEnabled
    @AppStorage(AppSettings.Key.speechRate) private var speechRate = AppSettings.defaultSpeechRate
    @AppStorage(AppSettings.Key.didShowWordDetailSwipeHint) private var didShowSwipeHint = false
    @State private var displayedObject: LearningObject
    @State private var selectedPageIndex: Int
    @State private var autoPlayTracker = WordDetailAutoPlayTracker()
    @State private var editingTerm = ""
    @State private var isEditing = false
    @State private var isResolving = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var showPaywall = false
    @State private var imageCache: [Int: UIImage]
    @State private var unavailableImageIndexes: Set<Int> = []
    @State private var sheetDetent: PresentationDetent = .large
    @State private var showsSwipeHint = false
    @State private var navigation = WordPhotoNavigationState()
    @State private var openedPhoto: PhotoDetailDestination?

    init(
        object: LearningObject,
        objects: [LearningObject] = [],
        imageProvider: ((LearningObject, Int) -> UIImage?)? = nil,
        photoProvider: ((LearningObject, Int) -> WordDetailPhoto?)? = nil,
        onUpdate: ((LearningObject) -> String?)? = nil,
        onDelete: ((LearningObject) -> String?)? = nil,
        onManualCorrection: ((LearningObject, LearningObject) -> Void)? = nil,
        onEditingChanged: ((Bool) -> Void)? = nil
    ) {
        self.object = object
        let resolvedObjects = objects.isEmpty ? [object] : objects
        let initialPageIndex = resolvedObjects.firstIndex(of: object)
            ?? resolvedObjects.firstIndex(where: { $0.id == object.id })
            ?? 0
        self.objects = resolvedObjects
        self.imageProvider = imageProvider
        self.photoProvider = photoProvider
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self.onManualCorrection = onManualCorrection
        self.onEditingChanged = onEditingChanged
        _displayedObject = State(initialValue: object)
        _selectedPageIndex = State(initialValue: initialPageIndex)
        // Cropping a camera photo can require decoding or normalizing the full
        // image. Keep that work out of the sheet's presentation transaction so
        // the first frame appears immediately after a capsule tap.
        _imageCache = State(initialValue: [:])
    }

    var body: some View {
        NavigationStack(path: navigationPath) {
            wordPages
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: WordPhotoRoute.self) { route in
                    photoDestination(route)
                }
        }
        .onDisappear { speech.stop() }
        .fullScreenCover(item: $openedPhoto) { destination in
            ResultView(image: destination.image, result: destination.record.result,
                       recordID: destination.record.id, usesNavigationBackButton: true)
        }
        .presentationDetents(WordPhotoNavigationState.detents, selection: $sheetDetent)
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.paper)
    }

    private var wordPages: some View {
        TabView(selection: selectedPage) {
            ForEach(Array(objects.enumerated()), id: \.offset) { index, object in
                wordPage(for: object, at: index)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color.paper)
        .overlay(alignment: .bottom) {
            if showsSwipeHint && navigation.path.isEmpty {
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
        .task(id: selectedPageIndex) {
            await loadImagesAfterPresentation(around: selectedPageIndex)
        }
        .task {
            await presentSwipeHintIfNeeded()
        }
        .onDisappear { speech.stop() }
        .onChange(of: object) { _, updatedObject in
            displayedObject = updatedObject
            selectedPageIndex = objects.firstIndex(of: updatedObject)
                ?? objects.firstIndex(where: { $0.id == updatedObject.id })
                ?? selectedPageIndex
            if !isEditing { editingTerm = updatedObject.english }
            if !isEditing {
                playWordAutomaticallyIfNeeded(for: updatedObject)
            }
        }
    }

    private var navigationPath: Binding<[WordPhotoRoute]> {
        Binding(get: { navigation.path }, set: { path in
            if !path.isEmpty {
                speech.stop()
                showsSwipeHint = false
            }
            sheetDetent = navigation.transition(to: path, currentDetent: sheetDetent)
        })
    }

    private func push(_ route: WordPhotoRoute) {
        guard !isEditing, navigation.path.last?.hasSameDestination(as: route) != true else { return }
        navigationPath.wrappedValue = navigation.path + [route]
    }

    @ViewBuilder
    private func photoDestination(_ route: WordPhotoRoute) -> some View {
        switch route.content {
        case .gallery(let photos, let word, let currentID):
            WordPhotoGallery(photos: photos, word: word, currentID: currentID, onNavigate: push)
        case .preview(let photo, let word, let isCurrent):
            WordPhotoPreview(photo: photo, word: word, isCurrent: isCurrent,
                             onOpenPhoto: { destination in
                                 guard openedPhoto == nil else { return }
                                 speech.stop()
                                 openedPhoto = destination
                             })
        }
    }

    @MainActor
    private func presentSwipeHintIfNeeded() async {
        guard navigation.path.isEmpty, objects.count > 1, !didShowSwipeHint else { return }
        try? await Task.sleep(for: .milliseconds(550))
        guard !Task.isCancelled, navigation.path.isEmpty else { return }
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

    private var selectedPage: Binding<Int> {
        Binding(
            get: { selectedPageIndex },
            set: { index in
                guard !isEditing,
                      objects.indices.contains(index),
                      index != selectedPageIndex else { return }
                let selectedObject = objects[index]
                selectedPageIndex = index
                displayedObject = selectedObject
                errorMessage = nil
                playWordAutomaticallyIfNeeded(for: displayedObject)
            }
        )
    }

    private func wordPage(for object: LearningObject, at index: Int) -> some View {
        GeometryReader { geometry in
            PictureWordSheet(scrolls: false) {
                VStack(alignment: .leading, spacing: 12) {
                    header(for: object, at: index)

                    if index == selectedPageIndex, let errorMessage {
                        Text(errorMessage)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color.coral)
                    }

                    HStack(spacing: 9) {
                        Text(object.chinese)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.ink.opacity(0.82))
                        Text("\(object.kind.title)词")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(Color.ink.opacity(0.66))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background((object.kind == .action ? Color.sun : object.kind == .state ? Color.sky : Color.mint).opacity(0.3), in: Capsule())
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
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.paperLight, in: RoundedRectangle(cornerRadius: 18))

                    if let photoProvider {
                        WordDetailPhotos(object: object, thumbnailHeight: min(90, max(44, (geometry.size.height - 360) / 2)), source: { photoProvider(object, index) }, onNavigate: push)
                            .id(object)
                    } else if imageProvider != nil {
                        WordPhotoImage(image: imageCache[index], unavailable: unavailableImageIndexes.contains(index), height: 200)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @MainActor
    private func loadImagesAfterPresentation(around index: Int) async {
        // Let SwiftUI commit the sheet's first frame before voice discovery or
        // image decoding. Neither operation is required to render the sheet.
        try? await Task.sleep(for: .milliseconds(80))
        guard !Task.isCancelled else { return }
        playWordAutomaticallyIfNeeded(for: displayedObject)
        preloadImage(at: index)

        // Adjacent pages are speculative. Delay them until the presentation
        // animation has settled so they cannot steal time from the tap response.
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        preloadImage(at: index - 1)
        preloadImage(at: index + 1)
    }

    private func preloadImage(at index: Int) {
        guard let imageProvider, objects.indices.contains(index),
              imageCache[index] == nil,
              !unavailableImageIndexes.contains(index) else { return }
        if let image = imageProvider(objects[index], index) {
            imageCache[index] = image
        } else {
            unavailableImageIndexes.insert(index)
        }
    }

    @ViewBuilder
    private func header(for object: LearningObject, at index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if isEditing && index == selectedPageIndex {
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
        guard navigation.path.isEmpty, autoPlayTracker.shouldPlay(
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
        sheetDetent = .large
    }

    private func resolveVocabulary() {
        guard !submittedTerm.isEmpty, submittedTerm.count <= 60, !isResolving else { return }
        isResolving = true
        errorMessage = nil
        Task {
            do {
                let details = try await APIClient().resolveVocabulary(term: submittedTerm, kind: displayedObject.kind)
                let updated = displayedObject.replacingVocabulary(with: details)
                if let persistenceError = onUpdate?(updated) {
                    errorMessage = persistenceError
                } else {
                    onManualCorrection?(displayedObject, updated)
                    displayedObject = updated
                    isEditing = false
                    onEditingChanged?(false)
                    sheetDetent = .large
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

/// A photo retains its source identity even when the displayed image is a crop.
struct WordDetailPhoto: Identifiable {
    var id: String { recordID?.uuidString ?? "current" }
    let recordID: UUID?
    let date: Date?
    let objects: [LearningObject]
    var imageSize: CGSize? = nil
    let load: () -> UIImage?

    @MainActor
    static func relatedOccurrences(for object: LearningObject, entries: [WordEntry], excluding recordID: UUID?) -> [[WordOccurrence]] {
        let key = WordLearningStore.normalizedKey(for: object.english)
        let occurrences = entries.first(where: { $0.id == key })?.occurrences.filter {
            $0.recordID != recordID && $0.object.kind == object.kind
        } ?? []
        return Dictionary(grouping: occurrences, by: \.recordID).values.sorted {
            let left = $0[0], right = $1[0]
            return left.encounteredAt == right.encounteredAt
                ? left.recordID.uuidString < right.recordID.uuidString
                : left.encounteredAt > right.encounteredAt
        }
    }

    static func rect(for box: ObjectBox, padding: Double = 0) -> CGRect? {
        guard box.x.isFinite, box.y.isFinite, box.width.isFinite, box.height.isFinite,
              box.width > 0, box.height > 0 else { return nil }
        let rect = CGRect(x: box.x - box.width * padding, y: box.y - box.height * padding,
                          width: box.width * (1 + padding * 2), height: box.height * (1 + padding * 2))
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        return rect.isNull || rect.isEmpty ? nil : rect
    }

    func thumbnail(from image: UIImage) -> UIImage {
        Self.thumbnail(from: image, object: objects.first)
    }

    static func thumbnail(from image: UIImage, object: LearningObject?) -> UIImage {
        let normalized = ImageProcessor.normalizedImage(from: image, maxDimension: 1200) ?? image
        guard let object, object.kind == .object,
              let rect = Self.rect(for: object.box, padding: 0.08), let cgImage = normalized.cgImage else { return normalized }
        let pixels = CGRect(x: rect.minX * CGFloat(cgImage.width), y: rect.minY * CGFloat(cgImage.height),
                            width: rect.width * CGFloat(cgImage.width), height: rect.height * CGFloat(cgImage.height)).integral
            .intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        guard let cropped = cgImage.cropping(to: pixels) else { return normalized }
        let result = UIImage(cgImage: cropped)
        return ImageProcessor.normalizedImage(from: result, maxDimension: 600) ?? result
    }
}

private struct WordPhotoImage: View {
    let image: UIImage?
    var unavailable = false
    let height: CGFloat

    var body: some View {
        ZStack {
            Color.paperDeep.opacity(0.45)
            if let image {
                Image(uiImage: image).resizable().scaledToFit().padding(8)
            } else if unavailable {
                Label("照片暂不可用", systemImage: "photo")
                    .font(.caption).foregroundStyle(Color.ink.opacity(0.5))
            } else {
                ProgressView().tint(Color.ink.opacity(0.4))
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct WordDetailPhotos: View {
    let object: LearningObject
    let thumbnailHeight: CGFloat
    let source: () -> WordDetailPhoto?
    let onNavigate: (WordPhotoRoute) -> Void
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var wordLearningStore: WordLearningStore
    // Metadata is available before decoding; the first frame reserves the final grid.
    private var current: WordDetailPhoto? {
        guard let resolved = source() else { return nil }
        let record = resolved.recordID.flatMap { historyStore.record(id: $0) }
        let matches = record?.result.allWords.filter {
            WordLearningStore.normalizedKey(for: $0.english) == WordLearningStore.normalizedKey(for: object.english)
                && $0.kind == object.kind
        } ?? []
        return WordDetailPhoto(recordID: resolved.recordID, date: resolved.date ?? record?.createdAt,
            objects: resolved.objects + matches.filter { match in !resolved.objects.contains(where: { $0.id == match.id }) },
            imageSize: resolved.imageSize, load: resolved.load)
    }

    private func related(excluding recordID: UUID?) -> [WordDetailPhoto] {
        WordDetailPhoto.relatedOccurrences(for: object, entries: wordLearningStore.entries, excluding: recordID)
            .compactMap { occurrences in
                guard let occurrence = occurrences.first,
                      let record = historyStore.record(id: occurrence.recordID) else { return nil }
                return WordDetailPhoto(recordID: record.id, date: record.createdAt,
                    objects: occurrences.map(\.object),
                    imageSize: CGSize(width: record.result.imageWidth, height: record.result.imageHeight),
                    load: { historyStore.image(for: record) })
            }
    }

    var body: some View {
        let current = current
        let photos = (current.map { [$0] } ?? []) + related(excluding: current?.recordID)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("照片里的 \(object.english)")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text("\(photos.count) 张").font(.caption.monospacedDigit())
            }
            .foregroundStyle(Color.ink.opacity(0.55))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 3), spacing: 12) {
                ForEach(Array(photos.prefix(6))) { photo in
                    WordPhotoTile(photo: photo, height: thumbnailHeight, isCurrent: photo.id == current?.id) {
                        onNavigate(WordPhotoRoute(content: .preview(photo, object.english, photo.id == current?.id)))
                    }
                }
                if photos.isEmpty {
                    WordPhotoImage(image: nil, unavailable: true, height: thumbnailHeight)
                }
            }
            if photos.count > 6 {
                Button { onNavigate(WordPhotoRoute(content: .gallery(photos, object.english, current?.id))) } label: {
                    HStack {
                        Text("查看全部 \(photos.count) 张")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .padding(.vertical, 10)
                }.buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.paperLight, in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(Color.ink.opacity(0.06), lineWidth: 1) }
        .foregroundStyle(Color.ink)

    }
}

private struct WordPhotoTile: View {
    let photo: WordDetailPhoto
    let height: CGFloat
    var isCurrent = false
    let action: () -> Void
    @State private var image: UIImage?
    @State private var loaded = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                WordPhotoImage(image: image, unavailable: loaded && image == nil, height: height)
                    .overlay {
                        if isCurrent {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.sun.opacity(0.85), lineWidth: 1.5)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if isCurrent {
                            Text("当前")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.ink)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Color.sun, in: Capsule())
                                .padding(5)
                        }
                    }
                if let date = photo.date {
                    Text(date, format: .dateTime.month().day())
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.ink.opacity(0.48))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(isCurrent ? "当前照片，" : "")查看\(photo.objects.first?.english ?? "单词")的原始照片")
        .task(id: photo.objects) {
            await Task.yield()
            guard !Task.isCancelled else { return }
            let original = photo.load()
            let object = photo.objects.first
            let thumbnail = await Task.detached(priority: .utility) {
                original.map { WordDetailPhoto.thumbnail(from: $0, object: object) }
            }.value
            guard !Task.isCancelled else { return }
            image = thumbnail
            loaded = true
        }
    }
}

private struct WordPhotoGallery: View {
    let photos: [WordDetailPhoto]
    let word: String
    let currentID: String?
    let onNavigate: (WordPhotoRoute) -> Void

    var body: some View {
        PictureWordSheet {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10, alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 10) {
                ForEach(photos) { photo in
                    WordPhotoTile(photo: photo, height: 150, isCurrent: photo.id == currentID) { onNavigate(WordPhotoRoute(content: .preview(photo, word, photo.id == currentID))) }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            WordPhotoNavigationHeader(eyebrow: "PHOTO MEMORIES", title: "照片里的 \(word)")
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(InteractivePopGestureEnabler())
    }
}

private struct WordPhotoPreview: View {
    let photo: WordDetailPhoto
    let word: String
    let isCurrent: Bool
    @EnvironmentObject private var historyStore: HistoryStore
    let onOpenPhoto: (PhotoDetailDestination) -> Void
    @State private var detailError: String?
    @State private var image: UIImage?
    @State private var loaded = false

    var body: some View {
        PictureWordSheet(scrolls: false) {
            VStack(alignment: .leading, spacing: 10) {
                if let date = photo.date {
                    Text(date, format: .dateTime.year().month().day())
                        .font(.caption).foregroundStyle(Color.ink.opacity(0.55))
                }
                WordPhotoViewportLayout(imageSize: photo.imageSize) {
                    ZStack {
                        Color.paperDeep.opacity(0.45)
                        if let image {
                            WordPhotoZoom(image: image, boxes: photo.objects.filter { $0.kind == .object }.compactMap { WordDetailPhoto.rect(for: $0.box) })
                                .accessibilityLabel("\(word) 原始照片，已标出对应物体")
                        } else if loaded {
                            Label("照片暂不可用", systemImage: "photo").foregroundStyle(Color.ink.opacity(0.5))
                        } else {
                            ProgressView()
                        }
                    }
                }
                .layoutPriority(-1)
                Text("双指缩放，查看照片细节")
                    .font(.caption).foregroundStyle(Color.ink.opacity(0.5))
                if !isCurrent, photo.recordID != nil {
                    PictureWordButton(
                        "打开这张照片",
                        systemImage: "photo.on.rectangle",
                        style: .secondary,
                        size: .compact,
                        action: openPhotoDetail
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
            }

        }
        .safeAreaInset(edge: .top, spacing: 0) {
            WordPhotoNavigationHeader(eyebrow: "PHOTO MEMORY", title: word)
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(InteractivePopGestureEnabler())
        .alert("无法打开照片详情", isPresented: Binding(
            get: { detailError != nil },
            set: { if !$0 { detailError = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(detailError ?? "")
        }
        .task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            let original = photo.load()
            let preview = await Task.detached(priority: .userInitiated) {
                original.flatMap { ImageProcessor.normalizedImage(from: $0, maxDimension: 1800) }
            }.value
            guard !Task.isCancelled else { return }
            image = preview
            loaded = true
        }
    }

    private func openPhotoDetail() {
        guard !isCurrent else { return }
        guard let recordID = photo.recordID,
              let record = historyStore.record(id: recordID) else {
            detailError = "这张照片的历史记录已不存在。"
            return
        }
        guard let original = historyStore.image(for: record) else {
            detailError = "暂时无法读取这张照片，请稍后重试。"
            return
        }
        onOpenPhoto(PhotoDetailDestination(record: record, image: original))
    }


}

private struct WordPhotoZoom: UIViewRepresentable {
    let image: UIImage
    let boxes: [CGRect]

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> ZoomCanvas {
        let view = ZoomCanvas()
        view.delegate = context.coordinator
        view.minimumZoomScale = 1
        view.maximumZoomScale = 5
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = false
        return view
    }
    func updateUIView(_ view: ZoomCanvas, context: Context) {
        view.photoView.image = image
        view.boxes = boxes
        view.setNeedsLayout()
    }
    final class Coordinator: NSObject, UIScrollViewDelegate {
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { (scrollView as? ZoomCanvas)?.photoView }
    }
    final class ZoomCanvas: UIScrollView {
        let photoView = UIImageView()
        var boxes: [CGRect] = []
        private let marks = CAShapeLayer()
        private var previousSize = CGSize.zero

        override init(frame: CGRect) {
            super.init(frame: frame)
            photoView.contentMode = .scaleAspectFit
            addSubview(photoView)
            photoView.layer.addSublayer(marks)
            marks.fillColor = UIColor.clear.cgColor
            marks.strokeColor = UIColor(Color.sun).cgColor
            marks.lineWidth = 3
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let image = photoView.image, bounds.width > 0, bounds.height > 0 else { return }
            if bounds.size != previousSize {
                previousSize = bounds.size
                setZoomScale(1, animated: false)
                photoView.frame = CGRect(origin: .zero, size: bounds.size)
                contentSize = bounds.size
            }
            let size = photoView.bounds.size
            let scale = min(size.width / image.size.width, size.height / image.size.height)
            let fitted = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2)
            let path = UIBezierPath()
            for box in boxes {
                path.append(UIBezierPath(roundedRect: CGRect(x: origin.x + box.minX * fitted.width,
                    y: origin.y + box.minY * fitted.height, width: box.width * fitted.width,
                    height: box.height * fitted.height), cornerRadius: 6))
            }
            marks.path = path.cgPath
        }
    }
}


private struct WordPhotoNavigationHeader: View {
    let eyebrow: String
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PictureWordPageHeader(eyebrow: eyebrow, title: title, foreground: .ink,
                             eyebrowColor: .coral, tint: Color.paperLight.opacity(0.52)) {
            Button { dismiss() } label: {
                PictureWordHeaderCapsule(tint: Color.paperLight.opacity(0.52), foreground: .ink, interactive: true) {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .black))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")
        } trailing: { EmptyView() }
        .background(Color.paper)
    }
}

struct PhotoDetailDestination: Identifiable {
    var id: UUID { record.id }
    let record: HistoryRecord
    let image: UIImage
}

struct WordPhotoRoute: Hashable {
    enum Content {
        case gallery([WordDetailPhoto], String, String?)
        case preview(WordDetailPhoto, String, Bool)
    }
    let id = UUID()
    let content: Content

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    func hasSameDestination(as other: Self) -> Bool {
        switch (content, other.content) {
        case let (.gallery(_, word, current), .gallery(_, otherWord, otherCurrent)):
            return word == otherWord && current == otherCurrent
        case let (.preview(photo, word, _), .preview(otherPhoto, otherWord, _)):
            return photo.id == otherPhoto.id && word == otherWord
        default:
            return false
        }
    }
}

/// Content loading never changes the sheet's height or the user's chosen detent.
struct WordPhotoNavigationState {
    static let detents: Set<PresentationDetent> = [.large]
    private(set) var path: [WordPhotoRoute] = []

    mutating func transition(to newPath: [WordPhotoRoute], currentDetent: PresentationDetent) -> PresentationDetent {
        path = newPath
        return currentDetent
    }
}

/// Computes the image viewport in the same layout pass, without geometry/state feedback.
struct WordPhotoViewportLayout: Layout {
    let imageSize: CGSize?

    static func height(for width: CGFloat, imageSize: CGSize?) -> CGFloat {
        let size = imageSize ?? CGSize(width: 4, height: 3)
        let valid = size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
        return min(max(width, 0) * (valid ? size.height / size.width : 0.75), 480)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        let idealHeight = Self.height(for: width, imageSize: imageSize)
        return CGSize(width: width, height: min(idealHeight, max(0, proposal.height ?? idealHeight)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        }
    }
}
