import SwiftUI
import SwiftData

@main
struct PictureWordApp: App {
    @StateObject private var data = AppDataBootstrap()
    @StateObject private var membershipStore = MembershipStore()
    @StateObject private var appVersionCoordinator = AppVersionCoordinator()
    @AppStorage(AppSettings.Key.didCompleteOnboarding) private var didCompleteOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppVersionPresentationHost(coordinator: appVersionCoordinator) {
                if data.isPreparing {
                    DataMigrationProgressView()
                } else if let migrationError = data.migrationError {
                    DataMigrationFailureView(message: migrationError) { data.retryMigration() }
                } else {
                    if didCompleteOnboarding {
                        HomeView()
                    } else {
                        ModeSelectionView {
                            appVersionCoordinator.markFreshInstallOnboardingCompleted()
                            withAnimation(.easeInOut(duration: 0.3)) {
                                didCompleteOnboarding = true
                            }
                        }
                    }
                }
            }
            .environmentObject(data.historyStore)
            .environmentObject(data.journeyStore)
            .environmentObject(data.wordLearningStore)
            .environmentObject(membershipStore)
            .task {
                data.prepareIfNeeded()
                await membershipStore.prepare()
            }
            .task(id: didCompleteOnboarding) {
                guard didCompleteOnboarding else { return }
                await appVersionCoordinator.checkAfterOnboarding()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await membershipStore.refreshAfterForegroundActivation() }
            }
            // Picture Word uses a paper-first visual system; keep system UI in light appearance.
            .preferredColorScheme(.light)
        }
    }
}

@MainActor
private final class AppDataBootstrap: ObservableObject {
    let container: ModelContainer
    let historyStore: HistoryStore
    let journeyStore: LearningJourneyStore
    let wordLearningStore: WordLearningStore
    @Published private(set) var isPreparing = true
    @Published private(set) var migrationError: String?
    private let migration: LegacyJSONMigration

    init() {
        do {
            container = try PersistenceController.makeContainer()
        } catch {
            fatalError("Unable to create the app database: \(error)")
        }
        migration = LegacyJSONMigration(container: container)
        historyStore = HistoryStore(container: container)
        journeyStore = LearningJourneyStore(container: container)
        wordLearningStore = WordLearningStore(container: container)
        historyStore.onHistoryChanged = { [weak wordLearningStore] in wordLearningStore?.reload() }
    }

    func prepareIfNeeded() {
        guard isPreparing else { return }
        do {
            try migration.runIfNeeded()
            historyStore.reload()
            journeyStore.reload()
            wordLearningStore.reload()
            migrationError = nil
        } catch {
            migrationError = error.localizedDescription
        }
        isPreparing = false
    }

    func retryMigration() {
        isPreparing = true
        prepareIfNeeded()
    }
}

private struct DataMigrationProgressView: View {
    var body: some View {
        NotebookBackground()
            .overlay {
                VStack(spacing: 16) {
                    ProgressView().tint(Color.coral)
                    Text("正在升级本地数据…")
                        .font(.scrapbookBody)
                        .foregroundStyle(Color.ink.opacity(0.68))
                }
                .accessibilityElement(children: .combine)
            }
    }
}

private struct DataMigrationFailureView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        NotebookBackground()
            .overlay {
                VStack(spacing: 18) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(Color.coral)
                    Text("数据升级未完成").font(.scrapbookTitle)
                    Text(message)
                        .font(.scrapbookBody)
                        .foregroundStyle(Color.ink.opacity(0.68))
                        .multilineTextAlignment(.center)
                    PictureWordButton("重新尝试", action: retry)
                }
                .padding(28)
                .background(Color.paperLight, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .padding(24)
            }
    }
}

private struct AppVersionPresentationHost<Content: View>: View {
    @ObservedObject var coordinator: AppVersionCoordinator
    @Environment(\.openURL) private var openURL
    @ViewBuilder let content: Content

    var body: some View {
        content
            .sheet(item: $coordinator.requiredUpgrade) { prompt in
                RequiredUpgradeView(prompt: prompt) {
                    openStore(for: prompt)
                }
                .interactiveDismissDisabled(true)
                .pictureWordSheetPresentation(detents: [.medium], showsDragIndicator: false)
            }
            .sheet(item: $coordinator.releaseNotes) { presentation in
                ReleaseNotesView(presentation: presentation)
                    .pictureWordSheetPresentation(detents: [.medium, .large])
            }
            .alert(item: $coordinator.suggestedUpgrade) { prompt in
                Alert(
                    title: Text(prompt.title),
                    message: Text(prompt.message),
                    primaryButton: .default(Text("立即更新")) { openStore(for: prompt) },
                    secondaryButton: .cancel(Text("以后再说"))
                )
            }
            .alert("暂时无法打开 App Store", isPresented: $coordinator.storeOpenErrorPresented) {
                Button("重新尝试") {
                    if let prompt = coordinator.failedStorePrompt { openStore(for: prompt) }
                }
                Button("暂时使用", role: .cancel) {}
            } message: {
                Text("请稍后重试，或直接前往 App Store 搜索“咔咔单词”。你可以暂时继续使用当前版本。")
            }
    }

    private func openStore(for prompt: UpgradePrompt) {
        openURL(prompt.appStoreURL) { accepted in
            guard !accepted else { return }
            Task { @MainActor in coordinator.handleStoreOpenFailure(for: prompt) }
        }
    }
}

private struct RequiredUpgradeView: View {
    let prompt: UpgradePrompt
    let openStore: () -> Void

    var body: some View {
        PictureWordSheet {
            VStack(alignment: .leading, spacing: 22) {
                PictureWordSheetHeader(
                    eyebrow: "UPDATE REQUIRED · \(prompt.targetVersion)",
                    title: prompt.title
                )

                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.coral.opacity(0.12))
                    Image(systemName: "arrow.down.app.fill")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(Color.coral)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 112)
                .overlay(alignment: .topTrailing) {
                    WashiTape(color: .sun)
                        .offset(x: -18, y: -9)
                }
                .accessibilityHidden(true)

                Text(prompt.message)
                    .font(.scrapbookBody)
                    .foregroundStyle(Color.ink.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)

                PictureWordButton("前往 App Store", systemImage: "arrow.up.right.square", action: openStore)
            }
        }
    }
}

private struct ReleaseNotesView: View {
    let presentation: ReleaseNotesPresentation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PictureWordSheet {
            VStack(alignment: .leading, spacing: 22) {
                PictureWordSheetHeader(
                    eyebrow: "WHAT'S NEW · \(presentation.version)",
                    title: presentation.notes.title
                )

                if !presentation.notes.summary.isEmpty {
                    Text(presentation.notes.summary)
                        .font(.scrapbookBody)
                        .foregroundStyle(Color.ink.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 12) {
                    ForEach(Array(presentation.notes.items.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .top, spacing: 14) {
                            Text(String(format: "%02d", index + 1))
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundStyle(Color.coral)
                                .frame(width: 28, height: 28)
                                .background(Color.sun.opacity(0.42), in: Circle())

                            Text(item)
                                .font(.system(.body, design: .rounded, weight: .semibold))
                                .foregroundStyle(Color.ink.opacity(0.82))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .background(Color.paperLight, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.ink.opacity(0.08), lineWidth: 1)
                        }
                    }
                }

                PictureWordButton("开始体验", systemImage: "sparkles") { dismiss() }
            }
        }
    }
}
