import SwiftUI
import UIKit

private enum HomeTab: String {
    case today
    case album
}

struct HomeView: View {
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var journeyStore: LearningJourneyStore
    @AppStorage(AppSettings.Key.learningMode) private var modeRawValue = AppSettings.defaultLearningMode

    @State private var selectedTab: HomeTab = .today
    @State private var cameraPresented = false
    @State private var capturedImage: UIImage?
    @State private var recognitionImage: PresentedImage?
    @State private var presentedHistory: PresentedHistory?
    @State private var historyMessage: String?
    @State private var confirmMissionSwitch = false

    private var mode: LearningMode {
        LearningMode(rawValue: modeRawValue) ?? .selfExplore
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NotebookBackground()

                Group {
                    switch selectedTab {
                    case .today:
                        TodayDashboard(
                            mode: mode,
                            onModeChange: { modeRawValue = $0.rawValue },
                            onCamera: requestCamera,
                            onSwitchMission: switchMission,
                            onOpenHistory: openHistory
                        )
                    case .album:
                        WordAlbumDashboard(onOpen: openHistory)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottom) {
                ScrapbookTabBar(selectedTab: $selectedTab) {
                    requestCamera()
                }
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
        .alert("单词册", isPresented: Binding(
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
        cameraPresented = true
    }

    private func openHistory(_ record: HistoryRecord) {
        guard let image = historyStore.image(for: record) else {
            historyMessage = "这张本地照片已经丢失，可以删除后重新识别。"
            return
        }
        presentedHistory = PresentedHistory(record: record, image: image)
    }
}

private struct TodayDashboard: View {
    let mode: LearningMode
    let onModeChange: (LearningMode) -> Void
    let onCamera: () -> Void
    let onSwitchMission: () -> Void
    let onOpenHistory: (HistoryRecord) -> Void

    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var journeyStore: LearningJourneyStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header

                if mode == .parentChild {
                    missionHero
                } else {
                    exploreHero
                }

                recentSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 118)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
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

    @ViewBuilder
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("RECENT PAGES")
                        .font(.system(.caption2, design: .rounded, weight: .black))
                        .tracking(1.8)
                        .foregroundStyle(Color.coral)
                    Text("最近的单词")
                        .font(.scrapbookTitle)
                }
                Spacer()
                Text(historyStore.records.isEmpty ? "从一张照片开始" : "共 \(historyStore.records.count) 页")
                    .font(.scrapbookCaption)
                    .foregroundStyle(Color.ink.opacity(0.48))
            }

            if historyStore.records.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 24, weight: .bold))
                    Text("还没有照片单词卡。\n今天，从一个单词开始。")
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
                            RecentPhotoCard(
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

private struct WordAlbumDashboard: View {
    let onOpen: (HistoryRecord) -> Void

    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var journeyStore: LearningJourneyStore

    var body: some View {
        List {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MY WORD ALBUM")
                        .font(.system(.caption2, design: .rounded, weight: .black))
                        .tracking(2)
                        .foregroundStyle(Color.coral)
                    Text("我的单词册")
                        .font(.scrapbookHero)
                }
                Spacer()
                // NavigationLink {
                //     SettingsView()
                // } label: {
                //     Image(systemName: "slider.horizontal.3")
                //         .font(.system(size: 16, weight: .bold))
                //         .foregroundStyle(Color.ink)
                //         .frame(width: 44, height: 44)
                //         .background(Color.sun, in: Circle())
                // }
            }
            .listRowInsets(EdgeInsets(top: 18, leading: 20, bottom: 0, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden, edges: .all)

            stickerShelf
                .listRowInsets(EdgeInsets(top: 20, leading: 20, bottom: 14, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden, edges: .all)

            HStack {
                Text("照片单词卡")
                    .font(.scrapbookTitle)
                Spacer()
                Text("\(historyStore.records.count) 页")
                    .font(.scrapbookCaption)
                    .foregroundStyle(Color.ink.opacity(0.48))
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 0, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden, edges: .all)

            if historyStore.records.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 34, weight: .bold))
                    Text("还没有收藏的生活单词")
                        .font(.scrapbookBody)
                }
                .foregroundStyle(Color.ink.opacity(0.48))
                .frame(maxWidth: .infinity, minHeight: 170)
                .background(Color.paperLight.opacity(0.66), in: RoundedRectangle(cornerRadius: 24))
                .overlay { RoundedRectangle(cornerRadius: 24).stroke(Color.ink.opacity(0.08)) }
                .listRowInsets(EdgeInsets(top: 11, leading: 20, bottom: 11, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden, edges: .all)
            } else {
                ForEach(historyStore.records) { record in
                    HistoryRow(
                        record: record,
                        thumbnail: historyStore.thumbnail(for: record),
                        onOpen: { onOpen(record) }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            historyStore.delete(record)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden, edges: .all)
                }
            }

            Color.clear
                .frame(height: 118)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden, edges: .all)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .background {
            NotebookBackground()
        }
        .listRowSeparator(.hidden, edges: .all)
        .listRowBackground(Color.clear)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var stickerShelf: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("寻宝贴纸")
                    .font(.scrapbookTitle)
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
    }

}

private struct ScrapbookTabBar: View {
    @Binding var selectedTab: HomeTab
    let onCamera: () -> Void
    @State private var cameraTapLocked = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // 覆盖整个悬浮导航范围，阻止空白区域把点击穿透给下方照片卡。
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {}

            Color.clear
                .frame(height: 64)
                .pictureWordGlass(
                    tint: Color.paperLight.opacity(0.18),
                    in: RoundedRectangle(cornerRadius: 32, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .onTapGesture {}

            HStack(spacing: 0) {
                tabButton(.today, title: "今日", icon: "sun.max.fill")
                Spacer(minLength: 82)
                tabButton(.album, title: "单词册", icon: "book.closed.fill")
            }
            .padding(.horizontal, 18)
            .frame(height: 64)

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
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
        .frame(height: 88)
        .dynamicTypeSize(.large)
    }

    private func tabButton(_ tab: HomeTab, title: String, icon: String) -> some View {
        Button {
            guard selectedTab != tab else { return }
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                Text(title)
                    .font(.system(.caption2, design: .rounded, weight: .bold))
            }
            .foregroundStyle(selectedTab == tab ? Color.ink : Color.ink.opacity(0.38))
            .frame(width: 96, height: 54)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
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

private struct RecentPhotoCard: View {
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
        .accessibilityLabel("打开照片单词卡")
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
    }
}
