import SwiftUI

@main
struct PictureWordApp: App {
    // 历史记录跟随 App 生命周期持有，确保所有页面共享同一份内存索引和本地文件。
    @StateObject private var historyStore = HistoryStore()
    @StateObject private var journeyStore = LearningJourneyStore()
    @StateObject private var wordLearningStore = WordLearningStore()
    @StateObject private var membershipStore = MembershipStore()
    @AppStorage(AppSettings.Key.didCompleteOnboarding) private var didCompleteOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if didCompleteOnboarding {
                    HomeView()
                } else {
                    ModeSelectionView {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            didCompleteOnboarding = true
                        }
                    }
                }
            }
            .environmentObject(historyStore)
            .environmentObject(journeyStore)
            .environmentObject(wordLearningStore)
            .environmentObject(membershipStore)
            .task {
                wordLearningStore.synchronize(with: historyStore.records)
                await membershipStore.prepare()
            }
            .onChange(of: historyStore.records) { _, records in
                wordLearningStore.synchronize(with: records)
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await membershipStore.refreshCurrentEntitlements() }
            }
            // Picture Word uses a paper-first visual system; keep system UI in light appearance.
            .preferredColorScheme(.light)
        }
    }
}
