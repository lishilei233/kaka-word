import SwiftUI
import UIKit

private enum HomeTab: String {
    case home
    case words
}

struct HomeView: View {
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var journeyStore: LearningJourneyStore
    @EnvironmentObject private var membership: MembershipStore
    @AppStorage(AppSettings.Key.learningMode) private var modeRawValue = AppSettings.defaultLearningMode

    @State private var selectedTab: HomeTab = .home
    @State private var discoveryAlbumPresented = false
    @State private var cameraPresented = false
    @State private var capturedImage: UIImage?
    @State private var recognitionImage: PresentedImage?
    @State private var presentedHistory: PresentedHistory?
    @State private var historyMessage: String?
    @State private var confirmMissionSwitch = false
    @State private var paywallPresented = false

    private var mode: LearningMode {
        LearningMode(rawValue: modeRawValue) ?? .selfExplore
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NotebookBackground()

                Group {
                    switch selectedTab {
                    case .home:
                        HomeDashboard(
                            mode: mode,
                            onModeChange: { modeRawValue = $0.rawValue },
                            onCamera: requestCamera,
                            onSwitchMission: switchMission,
                            onOpenHistory: openHistory,
                            onOpenAlbum: { discoveryAlbumPresented = true }
                        )
                    case .words:
                        MyWordsDashboard()
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottom) {
                ScrapbookTabBar(selectedTab: $selectedTab) {
                    requestCamera()
                }
            }
            .navigationDestination(isPresented: $discoveryAlbumPresented) {
                DiscoveryAlbumView(onOpen: openHistory)
            }
        }
        .fullScreenCover(isPresented: $cameraPresented, onDismiss: presentCapturedImage) {
            CameraView { image in
                capturedImage = image
                cameraPresented = false
            } onCancel: {
                cameraPresented = false
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $recognitionImage) { item in
            RecognitionFlowView(image: item.image)
                .environmentObject(historyStore)
                .environmentObject(journeyStore)
        }
        .fullScreenCover(item: $presentedHistory) { item in
            ResultView(image: item.image, result: item.record.result, recordID: item.record.id)
        }
        .sheet(isPresented: $paywallPresented) {
            PaywallView {
                cameraPresented = true
            }
            .environmentObject(membership)
        }
        .onAppear { journeyStore.refreshForTodayIfNeeded() }
        .confirmationDialog(
            "换一个今日任务？",
            isPresented: $confirmMissionSwitch,
            titleVisibility: .visible
        ) {
            Button("换个任务", role: .destructive) { journeyStore.switchToNextMission() }
            Button("继续现在的任务", role: .cancel) {}
        } message: {
            Text("今天已经找到的单词会清空，获得过的贴纸不会删除。")
        }
        .alert("发现相册", isPresented: Binding(
            get: { historyMessage != nil },
            set: { if !$0 { historyMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(historyMessage ?? "")
        }
    }

    private func switchMission() {
        if journeyStore.completedCount > 0 {
            confirmMissionSwitch = true
        } else {
            journeyStore.switchToNextMission()
        }
    }

    private func presentCapturedImage() {
        guard let image = capturedImage else { return }
        recognitionImage = PresentedImage(image: image)
        capturedImage = nil
    }

    private func requestCamera() {
        if membership.canStartRecognition {
            cameraPresented = true
        } else {
            paywallPresented = true
        }
    }

    private func openHistory(_ record: HistoryRecord) {
        guard let image = historyStore.image(for: record) else {
            historyMessage = "这张本地照片已经丢失，可以删除后重新识别。"
            return
        }
        presentedHistory = PresentedHistory(record: record, image: image)
    }
}

private struct HomeDashboard: View {
    let mode: LearningMode
    let onModeChange: (LearningMode) -> Void
    let onCamera: () -> Void
    let onSwitchMission: () -> Void
    let onOpenHistory: (HistoryRecord) -> Void
    let onOpenAlbum: () -> Void

    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var journeyStore: LearningJourneyStore
    @EnvironmentObject private var wordLearningStore: WordLearningStore
    @State private var practicePresented = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header

                if mode == .parentChild {
                    missionHero
                    stickerShelf
                } else {
                    exploreHero
                }

                reviewCard
                recentSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 118)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .fullScreenCover(isPresented: $practicePresented) {
            ListeningPracticeView()
        }
    }

    private var reviewCard: some View {
        Button {
            practicePresented = true
        } label: {
            HStack(spacing: 16) {
                StickerSeal(
                    symbol: wordLearningStore.learningEntries.isEmpty ? "checkmark" : "ear.fill",
                    color: wordLearningStore.learningEntries.isEmpty ? .mint : .sun,
                    showsShadow: false
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text("LISTEN & FIND")
                        .font(.system(.caption2, design: .rounded, weight: .black))
                        .tracking(1.5)
                        .foregroundStyle(Color.coral)
                    Text("听音找词")
                        .font(.system(.headline, design: .rounded, weight: .heavy))
                    Text(wordLearningStore.learningEntries.isEmpty
                         ? "学习中的单词都会了，去发现新的吧。"
                         : "还有 \(wordLearningStore.learningEntries.count) 个学习中的词")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.ink.opacity(0.56))
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .black))
            }
            .foregroundStyle(Color.ink)
            .padding(18)
            .background(Color.paperLight.opacity(0.88), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.ink.opacity(0.08))
            }
        }
        .buttonStyle(.plain)
        .disabled(wordLearningStore.learningEntries.isEmpty)
        .opacity(wordLearningStore.learningEntries.isEmpty ? 0.62 : 1)
        .padding(.top, 24)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("KAKAWORD")
                    .font(.system(.caption2, design: .rounded, weight: .black))
                    .tracking(2.2)
                    .foregroundStyle(Color.coral)
                Text(Date.now.formatted(.dateTime.month().day().weekday(.wide)))
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.ink.opacity(0.5))
            }
            Spacer()

            Menu {
                ForEach(LearningMode.allCases) { option in
                    Button {
                        onModeChange(option)
                    } label: {
                        Label(option.title, systemImage: option.icon)
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: mode.icon)
                    Text(mode.title)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Color.paperLight, in: Capsule())
                .overlay { Capsule().stroke(Color.ink.opacity(0.1)) }
            }

            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 44, height: 44)
                    .background(Color.sun, in: Circle())
            }
            .accessibilityLabel("设置")
        }
    }

    private var exploreHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("今天想认识\n什么？")
                        .font(.scrapbookHero)
                        .foregroundStyle(Color.ink)
                        .lineSpacing(-3)
                    Text("把镜头对准生活，收下一页只属于你的英语手账。")
                        .font(.scrapbookBody)
                        .foregroundStyle(Color.ink.opacity(0.66))
                        .lineSpacing(4)
                }
                Spacer(minLength: 6)
                StickerSeal(symbol: "sparkles", color: .coral)
                    .padding(.top, 4)
            }

            PictureWordButton(
                "拍下今天的一页",
                systemImage: "camera.fill",
                action: onCamera
            )
        }
        .padding(24)
        .background(Color.sky, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(alignment: .top) { WashiTape(color: .sun).offset(y: -10) }
        .rotationEffect(.degrees(-0.6))
        .shadow(color: Color.ink.opacity(0.11), radius: 0, x: 3, y: 4)
        .padding(.top, 28)
    }

    private var missionHero: some View {
        let mission = journeyStore.currentMission
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                StickerSeal(symbol: mission.symbol, color: journeyStore.isComplete ? .mint : .coral)
                VStack(alignment: .leading, spacing: 5) {
                    Text(journeyStore.isComplete ? "TODAY · DONE" : "TODAY'S TREASURE")
                        .font(.system(.caption2, design: .rounded, weight: .black))
                        .tracking(1.6)
                        .foregroundStyle(Color.coral)
                    Text(mission.title)
                        .font(.scrapbookTitle)
                    Text(mission.prompt)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.ink.opacity(0.72))
                }
                Spacer(minLength: 0)
                Text("\(journeyStore.completedCount)/\(mission.targetCount)")
                    .font(.system(.title2, design: .serif, weight: .bold))
                    .foregroundStyle(Color.ink)
            }

            MissionProgressDots(count: journeyStore.completedCount, target: mission.targetCount)

            Text(mission.parentTip)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(Color.ink.opacity(0.62))
                .lineSpacing(3)

            HStack(spacing: 10) {
                PictureWordButton(
                    journeyStore.isComplete ? "再去发现" : "开始寻宝",
                    systemImage: "camera.fill",
                    action: onCamera
                )

                Button(action: onSwitchMission) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.ink)
                        .frame(width: 54, height: 54)
                        .background(Color.paperLight.opacity(0.76), in: RoundedRectangle(cornerRadius: 18))
                }
                .accessibilityLabel("换一个今日任务")
            }
        }
        .padding(22)
        .background(Color.mint, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(alignment: .topTrailing) {
            WashiTape(color: .coral)
                .rotationEffect(.degrees(5))
                .offset(x: -24, y: -9)
        }
        .rotationEffect(.degrees(0.45))
        .shadow(color: Color.ink.opacity(0.11), radius: 0, x: 3, y: 4)
        .padding(.top, 28)
    }

    private var stickerShelf: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("TREASURE STICKERS")
                        .font(.system(.caption2, design: .rounded, weight: .black))
                        .tracking(1.6)
                        .foregroundStyle(Color.coral)
                    Text("寻宝贴纸")
                        .font(.scrapbookTitle)
                }
                Spacer()
                Text("\(journeyStore.stickers.count) 枚")
                    .font(.scrapbookCaption)
                    .foregroundStyle(Color.ink.opacity(0.48))
            }

            if journeyStore.stickers.isEmpty {
                Text("完成亲子寻宝任务后，第一枚贴纸会出现在这里。")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(Color.ink.opacity(0.56))
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.mint.opacity(0.48), in: RoundedRectangle(cornerRadius: 20))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(journeyStore.stickers) { sticker in
                            VStack(spacing: 7) {
                                StickerSeal(symbol: sticker.symbol, color: .coral)
                                Text(sticker.title)
                                    .font(.system(.caption2, design: .rounded, weight: .bold))
                                    .lineLimit(1)
                            }
                            .frame(width: 86)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.top, 26)
    }

    @ViewBuilder
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("RECENT FINDS")
                        .font(.system(.caption2, design: .rounded, weight: .black))
                        .tracking(1.8)
                        .foregroundStyle(Color.coral)
                    Text("最近发现")
                        .font(.scrapbookTitle)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    // Text(historyStore.records.isEmpty ? "从一张照片开始" : "共 \(historyStore.records.count) 张")
                    //     .font(.scrapbookCaption)
                    //     .foregroundStyle(Color.ink.opacity(0.48))
                    Button("查看全部", action: onOpenAlbum)
                        .font(.system(.caption, design: .rounded, weight: .black))
                        .foregroundStyle(Color.coral)
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                        .accessibilityHint("打开发现相册")
                }
            }

            if historyStore.records.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 24, weight: .bold))
                    Text("还没有发现卡。\n从一张照片开始探索。")
                        .font(.scrapbookBody)
                        .lineSpacing(3)
                }
                .foregroundStyle(Color.ink.opacity(0.62))
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.paperLight.opacity(0.72), in: RoundedRectangle(cornerRadius: 22))
                .overlay { RoundedRectangle(cornerRadius: 22).stroke(Color.ink.opacity(0.08)) }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(historyStore.records.prefix(6)) { record in
                            DiscoveryCardCompact(
                                record: record,
                                thumbnail: historyStore.thumbnail(for: record),
                                onOpen: { onOpenHistory(record) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .contentMargins(.horizontal, 2, for: .scrollContent)
            }
        }
        .padding(.top, 30)
    }
}

private struct MyWordsDashboard: View {
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var wordLearningStore: WordLearningStore
    @State private var selectedState: WordLearningState = .learning
    @State private var searchText = ""
    @State private var selectedWord: WordEntry?

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 12) {
                pageHeader

                wordControls
                    .padding(.top, 12)

                wordListHeader
                    .padding(.top, 8)

                if filteredWords.isEmpty {
                    wordEmptyState
                } else {
                    ForEach(filteredWords) { entry in
                        WordLearningRow(
                            entry: entry,
                            state: selectedState,
                            image: wordImage(for: entry),
                            onOpen: { selectedWord = entry }
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 124)
        }
        .background { NotebookBackground() }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sheet(item: $selectedWord) { entry in
            WordDetailSheet(object: entry.object)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.paper)
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("MY WORDS")
                    .font(.system(.caption2, design: .rounded, weight: .black))
                    .tracking(2)
                    .foregroundStyle(Color.coral)
                Text("我的单词")
                    .font(.scrapbookHero)
                Text("把生活里遇见的单词，一张张收进学习手账。")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(Color.ink.opacity(0.54))
                    .lineSpacing(3)
            }

            Spacer(minLength: 0)

            StickerSeal(
                symbol: selectedState == .learning ? "pencil.and.scribble" : "checkmark",
                color: selectedState == .learning ? .sun : .mint,
                showsShadow: false
            )
            .rotationEffect(.degrees(selectedState == .learning ? 4 : -4))
            .padding(.top, 2)
            .accessibilityHidden(true)
        }
    }

    private var sourceWords: [WordEntry] {
        selectedState == .learning ? wordLearningStore.learningEntries : wordLearningStore.masteredEntries
    }

    private var filteredWords: [WordEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return sourceWords }
        return sourceWords.filter {
            $0.object.english.lowercased().contains(query) || $0.object.chinese.contains(query)
        }
    }

    private var wordCounts: [WordLearningState: Int] {
        [
            .learning: wordLearningStore.learningEntries.count,
            .mastered: wordLearningStore.masteredEntries.count
        ]
    }

    private var wordControls: some View {
        VStack(spacing: 12) {
            ScrapbookWordStateTabs(selection: $selectedState, counts: wordCounts)
            ScrapbookSearchField(text: $searchText)
        }
    }

    private var wordListHeader: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(selectedState == .learning ? Color.sun : Color.mint)
                .frame(width: 24, height: 6)

            Text(selectedState == .learning ? "正在熟悉" : "成长印记")
                .font(.system(.caption, design: .rounded, weight: .black))
                .tracking(0.8)
                .foregroundStyle(Color.ink.opacity(0.62))

            Spacer(minLength: 0)

            Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                 ? "\(sourceWords.count) 个单词"
                 : "找到 \(filteredWords.count) 个")
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .foregroundStyle(Color.ink.opacity(0.42))
        }
        .padding(.horizontal, 4)
    }

    private var wordEmptyState: some View {
        VStack(spacing: 12) {
            StickerSeal(
                symbol: searchText.isEmpty
                    ? (selectedState == .learning ? "sparkles" : "checkmark")
                    : "magnifyingglass",
                color: selectedState == .learning ? .sun : .mint,
                showsShadow: false
            )

            Text(searchText.isEmpty
                 ? (selectedState == .learning ? "等待新的发现" : "还没有成长印记")
                 : "没有找到匹配的单词")
                .font(.scrapbookTitle)

            Text(searchText.isEmpty
                 ? (selectedState == .learning ? "拍照后，新单词会自动来到这里。" : "把学会的单词标记为“已会”，它会留在这里。")
                 : "换一个英文或中文关键词试试看。")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .multilineTextAlignment(.center)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Label("清除搜索", systemImage: "xmark")
                        .font(.system(.caption, design: .rounded, weight: .black))
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 40)
                        .background(Color.sun.opacity(0.82), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(Color.ink.opacity(0.58))
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 210)
        .background(Color.paperLight.opacity(0.76), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .top) {
            WashiTape(color: selectedState == .learning ? .sun : .mint, showsShadow: false)
                .scaleEffect(0.72)
                .offset(y: -9)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.ink.opacity(0.07), lineWidth: 1)
        }
        .shadow(color: Color.ink.opacity(0.08), radius: 0, x: 2, y: 3)
    }

    private func wordImage(for entry: WordEntry) -> UIImage? {
        WordImageCropper.image(for: entry, historyStore: historyStore)
    }

}

private struct DiscoveryAlbumView: View {
    let onOpen: (HistoryRecord) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyStore: HistoryStore

    var body: some View {
        ZStack {
            NotebookBackground()

            List {
                if historyStore.records.isEmpty {
                    emptyState
                        .listRowInsets(EdgeInsets(top: 24, leading: 20, bottom: 12, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden, edges: .all)
                } else {
                    ForEach(historyStore.records) { record in
                        DiscoveryCardRow(
                            record: record,
                            image: historyStore.image(for: record),
                            onOpen: { onOpen(record) }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                historyStore.delete(record)
                            } label: {
                                Label("删除发现卡", systemImage: "trash")
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden, edges: .all)
                    }
                }

                Color.clear
                    .frame(height: 24)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden, edges: .all)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            header
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(InteractivePopGestureEnabler())
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var header: some View {
        PictureWordPageHeader(
            eyebrow: "DISCOVERY ALBUM",
            title: "发现相册",
            foreground: .ink,
            eyebrowColor: .coral,
            tint: Color.paperLight.opacity(0.52)
        ) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(Color.ink)
                    .frame(width: 50, height: 50)
                    .contentShape(Capsule())
                    .pictureWordGlass(
                        tint: Color.paperLight.opacity(0.52),
                        interactive: true,
                        in: Capsule()
                    )
            }
            .accessibilityLabel("返回")
            .buttonStyle(.plain)
        } trailing: {
            PictureWordHeaderCapsule(
                tint: Color.sun,
                foreground: Color.ink
            ) {
                Text("\(historyStore.records.count) 张")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .frame(width: 50, height: 50)
            }
            .accessibilityLabel("共 \(historyStore.records.count) 张发现卡")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 36, weight: .bold))
            Text("还没有发现卡")
                .font(.scrapbookTitle)
            Text("拍下一张照片后，它会作为完整的发现卡保存在这里。")
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(Color.ink.opacity(0.54))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Color.ink.opacity(0.58))
        .padding(26)
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(Color.paperLight.opacity(0.72), in: RoundedRectangle(cornerRadius: 26))
        .overlay { RoundedRectangle(cornerRadius: 26).stroke(Color.ink.opacity(0.08)) }
    }
}

private struct ScrapbookTabBar: View {
    @Binding var selectedTab: HomeTab
    let onCamera: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cameraTapLocked = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // 覆盖整个悬浮导航范围，阻止空白区域把点击穿透给下方照片卡。
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {}

            Color.clear
                .frame(height: 66)
                .pictureWordGlass(
                    tint: Color.paperLight.opacity(0.3),
                    in: RoundedRectangle(cornerRadius: 33, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 33, style: .continuous))
                .onTapGesture {}

            HStack(spacing: 0) {
                tabButton(.home, title: "Home", icon: "house.fill")
                Spacer(minLength: 78)
                tabButton(.words, title: "Learn", icon: "book.closed.fill")
            }
            .padding(.horizontal, 9)
            .frame(height: 66)

            Button(action: openCamera) {
                ZStack {
                    Circle()
                        .fill(Color.paperLight)
                    Circle()
                        .stroke(
                            Color.coral,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [5, 4])
                        )
                        .padding(5)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(Color.ink)
                    Circle()
                        .fill(Color.sun)
                        .frame(width: 8, height: 8)
                        .offset(x: 10, y: -2)
                }
                .frame(width: 68, height: 68)
                .contentShape(Circle())
                .rotationEffect(.degrees(-3))
                .shadow(color: Color.ink.opacity(0.2), radius: 0, x: 3, y: 4)
            }
            .buttonStyle(ScrapbookCameraButtonStyle())
            .disabled(cameraTapLocked)
            .offset(y: -6)
            .zIndex(2)
            .accessibilityLabel("拍照识别")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .frame(height: 92)
        .dynamicTypeSize(.large)
    }

    private func tabButton(_ tab: HomeTab, title: String, icon: String) -> some View {
        Button {
            guard selectedTab != tab else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: selectedTab == tab ? icon : inactiveIcon(for: tab))
                    .font(.system(size: 17, weight: .black))
                Text(title)
                    .font(.system(.caption2, design: .rounded, weight: .black))
            }
            .foregroundStyle(selectedTab == tab ? Color.ink : Color.ink.opacity(0.38))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(selectedTab == tab ? selectedTint(for: tab).opacity(0.76) : Color.clear, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(selectedTab == tab ? Color.ink.opacity(0.07) : Color.clear, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
        .accessibilityLabel(title)
    }

    private func selectedTint(for tab: HomeTab) -> Color {
        tab == .home ? .sky : .sun
    }

    private func inactiveIcon(for tab: HomeTab) -> String {
        tab == .home ? "house" : "book.closed"
    }

    private func openCamera() {
        guard !cameraTapLocked else { return }
        cameraTapLocked = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onCamera()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            cameraTapLocked = false
        }
    }
}

private struct ScrapbookCameraButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.94 : 1))
            .opacity(configuration.isPressed ? 0.76 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.68),
                value: configuration.isPressed
            )
    }
}

private struct MissionProgressDots: View {
    let count: Int
    let target: Int

    var body: some View {
        HStack(spacing: 9) {
            ForEach(0..<target, id: \.self) { index in
                Capsule()
                    .fill(index < count ? Color.ink : Color.paperLight.opacity(0.62))
                    .frame(maxWidth: .infinity)
                    .frame(height: 10)
                    .overlay { Capsule().stroke(Color.ink.opacity(0.12)) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日任务已完成 \(count) 个，共 \(target) 个")
    }
}

private struct DiscoveryCardCompact: View {
    let record: HistoryRecord
    let thumbnail: UIImage?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 9) {
                Group {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.paperDeep.overlay { Image(systemName: "photo") }
                    }
                }
                .frame(width: 150, height: 126)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))

                Text(record.result.objects.map(\.english).prefix(2).joined(separator: " · "))
                    .font(.system(.subheadline, design: .serif, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Text("\(record.result.objects.count) WORDS")
                    .font(.system(.caption2, design: .rounded, weight: .black))
                    .tracking(1)
                    .foregroundStyle(Color.coral)
            }
            .padding(10)
            .background(Color.paperLight, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: Color.ink.opacity(0.11), radius: 0, x: 2, y: 3)
        }
        .buttonStyle(.plain)
        .rotationEffect(.degrees(record.id.uuidString.hashValue.isMultiple(of: 2) ? -1 : 1))
        .accessibilityLabel("打开包含 \(record.result.objects.count) 个单词的发现卡")
    }
}

private struct PresentedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct PresentedHistory: Identifiable {
    var id: UUID { record.id }
    let record: HistoryRecord
    let image: UIImage
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
            .environmentObject(HistoryStore())
            .environmentObject(LearningJourneyStore())
            .environmentObject(WordLearningStore())
            .environmentObject(MembershipStore())
    }
}
