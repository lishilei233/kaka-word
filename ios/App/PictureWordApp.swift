import SwiftUI

@main
struct PictureWordApp: App {
    // 历史记录跟随 App 生命周期持有，确保所有页面共享同一份内存索引和本地文件。
    @StateObject private var historyStore = HistoryStore()
    @StateObject private var journeyStore = LearningJourneyStore()
    @AppStorage(AppSettings.Key.didCompleteOnboarding) private var didCompleteOnboarding = false

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
        }
    }
}
