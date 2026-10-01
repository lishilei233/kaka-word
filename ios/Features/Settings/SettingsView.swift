import AVFoundation
import SwiftUI

/// MVP 设置全部保存在本机，不依赖账号或网络服务。
struct SettingsView: View {
    var onPresentationEnded: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var membership: MembershipStore
    @EnvironmentObject private var notifications: LocalNotificationCoordinator
    @StateObject private var speech = SpeechService()
    @AppStorage(AppSettings.Key.englishSpeechEnabled) private var speechEnabled = AppSettings.defaultEnglishSpeechEnabled
    @AppStorage(AppSettings.Key.automaticWordSpeechEnabled) private var automaticWordSpeechEnabled = AppSettings.defaultAutomaticWordSpeechEnabled
    @AppStorage(AppSettings.Key.speechRate) private var speechRate = AppSettings.defaultSpeechRate
    @AppStorage(AppSettings.Key.englishVoiceIdentifier) private var voiceIdentifier = AppSettings.defaultEnglishVoiceIdentifier
    @AppStorage(AppSettings.Key.maxObjects) private var maxObjects = AppSettings.defaultMaxObjects
    @AppStorage(AppSettings.Key.learningMode) private var modeRawValue = AppSettings.defaultLearningMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var membershipAppeared = false
    @State private var membershipSuccess = false
    @State private var pendingMembershipSuccess = false
    @State private var membershipDetailsPresented = false
    @State private var confirmClearHistory = false
    @State private var paywallPresented = false
    @State private var voicePickerPresented = false

    var body: some View {
        ZStack {
            NotebookBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    membershipSection
                    experienceSection
                    recognitionSection
                    speechSection
                    NotificationSettingsSection(notifications: notifications)
                    storageSection
                    informationSection
                    versionFooter
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            header
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(InteractivePopGestureEnabler())
        .task {
            await membership.refreshForSettingsPresentation()
        }
        .onAppear {
            speech.refreshAvailableVoices()
            reconcileVoiceSelection()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: AVSpeechSynthesizer.availableVoicesDidChangeNotification
        )) { _ in
            speech.refreshAvailableVoices()
            reconcileVoiceSelection()
        }
        .onDisappear {
            speech.stop()
        }
        .confirmationDialog("清空全部历史记录？", isPresented: $confirmClearHistory, titleVisibility: .visible) {
            Button("清空全部", role: .destructive) { historyStore.deleteAll() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所有本地照片和识别结果都会被删除，且无法恢复。")
        }
        .sheet(isPresented: $paywallPresented, onDismiss: {
            onPresentationEnded()
            if pendingMembershipSuccess {
                pendingMembershipSuccess = false
                showMembershipSuccess()
            }
        }) {
            PaywallView(onPurchaseCompleted: { pendingMembershipSuccess = true })
                .environmentObject(membership)
        }
        .sheet(isPresented: $voicePickerPresented, onDismiss: {
            speech.stop()
            onPresentationEnded()
        }) {
            voiceSelectionSheet
                .pictureWordSheetPresentation(detents: [.medium, .large])
        }
        .alert("会员", isPresented: Binding(
            get: { !paywallPresented && !membershipDetailsPresented && membership.message != nil },
            set: { isPresented in
                guard !isPresented else { return }
                // Avoid publishing synchronously from SwiftUI's alert transaction.
                Task { @MainActor in
                    await Task.yield()
                    membership.dismissMessage()
                }
            }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(membership.message ?? "")
        }
    }

    private var membershipSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            MembershipSummaryCard(
                entitlement: membership.entitlement,
                state: membershipDisplayState,
                showSuccess: membershipSuccess
            )
            if membershipDisplayState != .loaded {
                if membershipDisplayState == .initialLoading || membershipDisplayState == .idle {
                    ProgressView().accessibilityLabel("正在读取会员状态")
                } else if membershipDisplayState != .failedWithoutCachedValue {
                    membershipRefreshStatus
                }
                if membershipDisplayState.isFailure {
                    Button("重新读取会员状态", action: refreshMembershipStatus)
                        .disabled(membership.isPurchasing)
                }
            }
            MembershipTicketDivider()
            if membership.isMember {
                MembershipPassEntry { membershipDetailsPresented = true }
            } else if membership.entitlement != nil && membershipDisplayState != .failedWithoutCachedValue {
                PictureWordButton("查看会员方案", systemImage: "sparkles") {
                    paywallPresented = true
                }
                .disabled(membership.isPurchasing)
            }
            #if DEBUG
            Button("申请沙盒退款") {
                Task { await membership.requestRefundForDebug() }
            }
            .font(.caption)
            .foregroundStyle(Color.coral)
            .disabled(membership.isPurchasing)
            #endif
        }
        .font(.system(.subheadline, design: .rounded, weight: .semibold))
        .foregroundStyle(Color.ink)
        .padding(20)
        .background(Color.paperLight, in: RoundedRectangle(cornerRadius: 28))
        .overlay { RoundedRectangle(cornerRadius: 28).stroke(Color.ink.opacity(0.08)) }
        .shadow(color: Color.ink.opacity(0.05), radius: 8, y: 3)
        .padding(.bottom, membership.isMember ? 0 : 44)
        .overlay(alignment: .bottom) {
            if !membership.isMember { MembershipRestoreButton(onRestored: showMembershipSuccess) }
        }
        .opacity(membershipAppeared ? 1 : 0)
        .offset(y: membershipAppeared || reduceMotion ? 0 : 6)
        .onAppear {
            guard !membershipAppeared else { return }
            withAnimation(.easeOut(duration: 0.25)) { membershipAppeared = true }
        }
        .navigationDestination(isPresented: $membershipDetailsPresented) {
            MembershipDetailsView(onRestored: showMembershipSuccess)
        }
    }

    private func showMembershipSuccess() {
        membership.dismissMessage()
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.35)) {
            membershipSuccess = true
        }
    }

    private var header: some View {
        PictureWordPageHeader(
            eyebrow: "SETTINGS",
            title: "设置",
            foreground: Color.ink,
            eyebrowColor: Color.coral,
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
                Text("SET")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .frame(width: 50, height: 50)
            }
        }
    }

    private var experienceSection: some View {
        SettingsCard(index: "01", title: "玩法") {
            VStack(alignment: .leading, spacing: 12) {
                Text("选择首页更适合谁使用，拍照识词和单词册会始终保留。")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(Color.ink.opacity(0.56))
                Picker("学习模式", selection: $modeRawValue) {
                    ForEach(LearningMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var recognitionSection: some View {
        SettingsCard(index: "02", title: "识别") {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SettingsLabel(icon: "viewfinder", title: "每次识别单词")
                    Spacer()
                    Text("最多 \(maxObjects) 个")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.ink.opacity(0.62))
                }
                Stepper("", value: $maxObjects, in: 3...10)
                    .labelsHidden()
                    .tint(Color.ink)
                    .frame(maxWidth: .infinity, alignment: .trailing)

            }
        }
    }

    private var speechSection: some View {
        SettingsCard(index: "03", title: "发音") {
            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 9) {
                    Toggle(isOn: $automaticWordSpeechEnabled) {
                        SettingsLabel(icon: "speaker.wave.2.fill", title: "自动播放单词音频")
                    }
                    .tint(Color.coral)
                    .accessibilityLabel("打开单词详情时自动播放单词音频")
                    .accessibilityHint("进入单词详情时自动朗读当前英文单词；关闭后仍可手动播放")

                    Text("进入单词详情时自动朗读当前单词，关闭后仍可点击英文单词手动播放。")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.ink.opacity(0.52))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().overlay(Color.ink.opacity(0.12))

                VStack(alignment: .leading, spacing: 10) {
                    SettingsLabel(icon: "waveform", title: "英语音色")
                    Button {
                        speech.refreshAvailableVoices()
                        reconcileVoiceSelection()
                        voicePickerPresented = true
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(currentVoiceTitle)
                                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                                    .foregroundStyle(Color.ink)
                                Text(currentVoiceDetail)
                                    .font(.system(.caption, design: .rounded, weight: .medium))
                                    .foregroundStyle(Color.ink.opacity(0.52))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.ink.opacity(0.38))
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 54)
                        .background(Color.paperLight.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.ink.opacity(0.08), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("选择英语音色，当前为\(currentVoiceTitle)")
                    .accessibilityHint("打开精选英语音色列表")
                }

                Divider().overlay(Color.ink.opacity(0.12))

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("发音语速")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Spacer()
                        Text(speechRateLabel)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.ink.opacity(0.52))
                    }
                    Slider(value: $speechRate, in: 0.35...0.55, step: 0.01)
                        .tint(Color.coral)
                        .disabled(!speechEnabled)
                        .opacity(speechEnabled ? 1 : 0.35)
                }
            }
        }
    }

    private var storageSection: some View {
        SettingsCard(index: "04", title: "本地数据") {
            VStack(alignment: .leading, spacing: 16) {
                Label {
                    Text("识别照片和历史记录仅保存在当前设备。服务器只转发识别请求，不保存照片。")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .lineSpacing(3)
                } icon: {
                    Image(systemName: "iphone.gen3")
                        .foregroundStyle(Color.ink)
                }

                Button(role: .destructive) { confirmClearHistory = true } label: {
                    HStack {
                        Text("清空全部历史记录")
                        Spacer()
                        Text("\(historyStore.totalRecordCount)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(historyStore.records.isEmpty ? Color.ink.opacity(0.28) : Color.coral)
                    .padding(.vertical, 2)
                }
                .disabled(historyStore.records.isEmpty)
            }
        }
    }

    private var informationSection: some View {
        SettingsCard(index: "05", title: "关于") {
            VStack(spacing: 0) {
                NavigationLink {
                    LegalDocumentView(document: .privacy)
                } label: {
                    SettingsLinkRow(title: "隐私政策")
                }
                Divider().overlay(Color.ink.opacity(0.12))
                NavigationLink {
                    LegalDocumentView(document: .terms)
                } label: {
                    SettingsLinkRow(title: "服务条款")
                }
                Divider().overlay(Color.ink.opacity(0.12))
                NavigationLink {
                    AboutView()
                } label: {
                    SettingsLinkRow(title: "关于咔咔单词")
                }
            }
        }
    }

    private var versionFooter: some View {
        Text("KAKAWORD · VERSION \(appVersion)")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(Color.ink.opacity(0.3))
            .padding(.top, 4)
    }

    private var speechRateLabel: String {
        switch speechRate {
        case ..<0.41: return "SLOW"
        case 0.48...: return "FAST"
        default: return "NORMAL"
        }
    }

    private var availableEnglishVoices: [SpeechVoiceDescriptor] {
        speech.availableEnglishVoices
    }

    private var currentVoice: SpeechVoiceDescriptor? {
        availableEnglishVoices.first(where: { $0.identifier == voiceIdentifier })
    }

    private var currentVoiceTitle: String {
        currentVoice?.name ?? "系统默认"
    }

    private var currentVoiceDetail: String {
        guard let currentVoice else { return "自动选择合适的英语音色" }
        return "\(currentVoice.accentTitle) · \(currentVoice.quality.title)"
    }

    private var voiceSelectionSheet: some View {
        PictureWordSheet {
            VStack(alignment: .leading, spacing: 18) {
                PictureWordSheetHeader(eyebrow: "ENGLISH VOICE", title: "选择英语音色") {
                    Button("完成") {
                        speech.stop()
                        voicePickerPresented = false
                    }
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(Color.sun, in: Capsule())
                    .buttonStyle(.plain)
                    .accessibilityHint("关闭音色选择")
                }

                Text("点击一行选择音色，点击右侧播放按钮试听。选择后会应用到所有单词和例句。")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(Color.ink.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 8) {
                    voiceChoiceRow(
                        title: "系统默认",
                        detail: "自动选择合适的英语音色",
                        identifier: AppSettings.defaultEnglishVoiceIdentifier
                    )
                    ForEach(availableEnglishVoices) { voice in
                        voiceChoiceRow(
                            title: voice.name,
                            detail: "\(voice.accentTitle) · \(voice.quality.title)",
                            identifier: voice.identifier
                        )
                    }
                }

                if availableEnglishVoices.isEmpty {
                    Text("当前设备没有可供选择的常规美式或英式音色，仍可使用系统默认语音。")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.coral)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("精选当前设备上的 3 个美式和 2 个英式常规音色；数量不足时会自动补位。")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.ink.opacity(0.52))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func reconcileVoiceSelection() {
        guard speech.isVoiceAvailable(identifier: voiceIdentifier) else {
            speech.stop()
            voiceIdentifier = AppSettings.defaultEnglishVoiceIdentifier
            return
        }
    }

    private func voiceChoiceRow(title: String, detail: String, identifier: String) -> some View {
        let isSelected = voiceIdentifier == identifier
        return HStack(spacing: 8) {
            Button {
                speech.stop()
                voiceIdentifier = identifier
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(isSelected ? Color.coral : Color.ink.opacity(0.28))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.ink)
                        Text(detail)
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(Color.ink.opacity(0.52))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title)，\(detail)")
            .accessibilityValue(isSelected ? "已选择" : "未选择")
            .accessibilityHint("选择此音色")

            Button {
                speech.speak(
                    "Hello! Welcome to Kakaword.",
                    rate: speechRate,
                    voiceIdentifier: identifier
                )
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 44, height: 44)
                    .background(Color.sun.opacity(0.82), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("试听\(title)")
            .accessibilityHint("播放固定英文示例句")
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .background(Color.paperLight.opacity(isSelected ? 1 : 0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? Color.coral.opacity(0.55) : Color.ink.opacity(0.08), lineWidth: 1)
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    private var membershipDisplayState: MembershipSettingsDisplayState {
        MembershipSettingsDisplayState.resolve(
            loadState: membership.entitlementLoadState,
            isRefreshing: membership.isRefreshingEntitlements
        )
    }

    private func refreshMembershipStatus() {
        Task {
            await membership.refreshCurrentEntitlements(source: .settings)
        }
    }

    @ViewBuilder
    private var membershipRefreshStatus: some View {
        let state = membershipDisplayState
        HStack(spacing: 6) {
            if state.isLoading {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: state.statusSymbol)
                    .font(.system(.caption2, weight: .bold))
            }
            Text(state.statusText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(.caption2, design: .rounded, weight: .semibold))
        .foregroundStyle(state.isFailure ? Color.coral : Color.ink.opacity(0.5))
        .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
    }
}

private struct SettingsCard<Content: View>: View {
    let index: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(index)
                    .font(.system(size: 17, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.coral)
                Text(title.uppercased())
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(Color.ink.opacity(0.48))
            }
            .tracking(1.1)
            content
        }
        .foregroundStyle(Color.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.paperLight.opacity(0.92), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24).stroke(Color.ink.opacity(0.07)) }
    }
}

private struct SettingsLabel: View {
    let icon: String
    let title: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(size: 15, weight: .heavy, design: .rounded))
    }
}

private struct SettingsLinkRow: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(Color.ink.opacity(0.38))
        }
        .foregroundStyle(Color.ink)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

enum LegalDocument {
    case privacy
    case terms

    var key: ContentKey {
        switch self {
        case .privacy: return .privacy
        case .terms: return .terms
        }
    }
}

struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        ContentDocumentView(key: document.key)
    }
}

private struct AboutView: View {
    var body: some View {
        ContentDocumentView(key: .about)
    }
}

private struct ContentDocumentView: View {
    let key: ContentKey
    private let provider: any ContentProviding
    @Environment(\.dismiss) private var dismiss
    @State private var document: ContentDocument

    init(key: ContentKey, provider: any ContentProviding = APIClient()) {
        self.key = key
        self.provider = provider
        _document = State(initialValue: .fallback(for: key))
    }

    var body: some View {
        ZStack {
            NotebookBackground()
            VStack(spacing: 0) {
                EditorialBackHeader(title: document.title, code: document.code, dismiss: dismiss.callAsFunction)
                if key == .about {
                    aboutContent
                } else {
                    legalContent
                }
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .pictureWordBackSwipe { dismiss() }
        .task {
            await refresh()
        }
    }

    private var legalContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                if !document.summary.isEmpty {
                    Text(document.summary)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.ink.opacity(0.82))
                        .lineSpacing(7)
                }
                ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                    ContentSectionView(section: section)
                }
                metadataFooter
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.paperLight, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(20)
        }
    }

    private var aboutContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Text(document.summary)
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .lineSpacing(-4)

                ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                    ContentSectionView(section: section, showsHeading: false)
                }

                metadataFooter
            }
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.sun, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .padding(20)
        }
    }

    private var metadataFooter: some View {
        Text("VERSION \(document.version) · \(document.updatedDate)")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(Color.ink.opacity(0.34))
            .padding(.top, 4)
    }

    private func refresh() async {
        guard let remoteDocument = try? await provider.fetchContent(for: key) else { return }
        document = remoteDocument
    }
}

private struct ContentSectionView: View {
    let section: ContentSection
    var showsHeading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsHeading && !section.heading.isEmpty {
                Text(section.heading)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(Color.ink)
            }
            ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.ink.opacity(0.76))
                    .lineSpacing(6)
            }
            ForEach(Array(section.bullets.enumerated()), id: \.offset) { _, bullet in
                Text("• \(bullet)")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.ink.opacity(0.76))
                    .lineSpacing(5)
            }
        }
    }
}

private struct EditorialBackHeader: View {
    let title: String
    let code: String
    let dismiss: () -> Void

    var body: some View {
        PictureWordPageHeader(
            eyebrow: code,
            title: title,
            foreground: Color.ink,
            eyebrowColor: Color.coral,
            tint: Color.paperLight.opacity(0.52)
        ) {
            PictureWordHeaderCapsule(
                tint: Color.paperLight.opacity(0.52),
                foreground: Color.ink,
                interactive: true
            ) {
                Button(action: dismiss) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .black))
                        .frame(width: 50, height: 50)
                }
                .accessibilityLabel("返回")
                .buttonStyle(.plain)
            }
        } trailing: {
            Color.clear.frame(width: 50, height: 50)
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SettingsView()
            .environmentObject(LocalNotificationCoordinator.shared)
                .environmentObject(HistoryStore())
        }
    }
}

/// Shared by settings and membership details so cached and unknown states use the same language.
struct MembershipSummaryCard: View {
    let entitlement: EntitlementSummary?
    let state: MembershipSettingsDisplayState
    var showSuccess = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var displayedRemaining: Int?

    private var visibleEntitlement: EntitlementSummary? {
        state == .failedWithoutCachedValue || state == .initialLoading || state == .idle ? nil : entitlement
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            let headerLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 8))
            headerLayout {
                Text("KAKA PASS")
                    .font(.system(.caption2, design: .monospaced, weight: .black))
                    .tracking(2)
                    .foregroundStyle(Color.ink.opacity(0.5))
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                if let value = visibleEntitlement {
                    Label(value.isMember ? "已开通" : "体验中", systemImage: value.isMember ? "checkmark.seal" : "sparkles")
                        .font(.system(.caption2, design: .rounded, weight: .black))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(value.isMember ? Color.mint.opacity(0.35) : Color.sun.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
                        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Color.ink.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [2, 2])) }
                        .rotationEffect(.degrees(reduceMotion ? 0 : -5))
                        .id(showSuccess)
                        .transition(reduceMotion ? .opacity : .offset(y: -8).combined(with: .scale(scale: 1.12)).combined(with: .opacity))
                }
            }
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            layout {
                VStack(alignment: .leading, spacing: 5) {
                    if let value = visibleEntitlement {
                        Text(value.isMember ? value.membershipDisplayName : "从生活里发现英语")
                            .font(.system(.headline, design: .rounded, weight: .heavy))
                            .fixedSize(horizontal: false, vertical: true)
                        if value.hasUnlimitedQuota {
                            Image(systemName: "infinity")
                                .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 58 : 48, weight: .medium))
                                .foregroundStyle(Color.ink)
                                .padding(.vertical, 5)
                                .accessibilityHidden(true)
                            Text("随心拍，慢慢发现")
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                        } else {
                            Text(value.isMember ? "本期还可识别" : "体验还可识别")
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .foregroundStyle(Color.ink.opacity(0.6))
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text("\(max(0, displayedRemaining ?? value.remaining))")
                                    .font(.system(.largeTitle, design: .serif, weight: .black))
                                    .contentTransition(reduceMotion ? .identity : .numericText())
                                Text("次").font(.system(.caption, design: .rounded, weight: .bold))
                            }
                        }
                    } else {
                        Text("你的生活探索通行证")
                            .font(.system(.headline, design: .rounded, weight: .heavy))
                        Text(state.isFailure ? "会员状态暂时无法确认" : "正在读取会员状态…")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(Color.ink.opacity(0.6))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                MembershipCameraArtwork(size: dynamicTypeSize.isAccessibilitySize ? 78 : 94)
            }
            if let value = visibleEntitlement {
                if value.hasUnlimitedQuota {
                    Text("拍照识词不限次数")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.ink.opacity(0.6))
                } else {
                    GeometryReader { geometry in
                        let fraction = value.limit > 0 ? min(1, max(0, Double(value.remaining) / Double(value.limit))) : 0
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.ink.opacity(0.07))
                            Capsule().fill(value.isMember ? Color.mint : Color.sun)
                                .frame(width: geometry.size.width * fraction)
                        }
                    }
                    .frame(height: 5)
                    .accessibilityHidden(true)
                    Text(value.isMember ? "本期共 \(value.limit) 次" : "免费体验共 \(value.limit) 次")
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.ink.opacity(0.55))
                    if value.isMember, let reset = value.resetDate {
                        Text("\(reset.formatted(date: .abbreviated, time: .omitted)) 额度更新")
                            .font(.system(.caption2, design: .rounded, weight: .medium))
                            .foregroundStyle(Color.ink.opacity(0.55))
                    }
                    if value.remaining <= 0 {
                        Text(value.isMember ? "等待额度更新时，仍可回看照片、听音练习。" : "体验额度已用完，已保存的照片和单词仍可回顾。")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(Color.ink.opacity(0.6))
                    }
                }
            }
        }
        .foregroundStyle(Color.ink)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .onChange(of: visibleEntitlement?.remaining) { oldValue, newValue in
            withAnimation(oldValue != nil && newValue != nil && !reduceMotion ? .easeInOut(duration: 0.25) : nil) {
                displayedRemaining = newValue
            }
        }
    }
}

struct MembershipCameraArtwork: View {
    var size: CGFloat = 100

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.sky.opacity(0.4))
                .frame(width: size * 0.88, height: size)
                .rotationEffect(.degrees(12))
                .offset(x: 7, y: 2)
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.paperLight)
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.ink.opacity(0.12)) }
                .shadow(color: Color.ink.opacity(0.1), radius: 3, y: 3)
                .rotationEffect(.degrees(-8))
            Image("PaywallHeroCamera")
                .resizable()
                .scaledToFit()
                .padding(7)
                .rotationEffect(.degrees(-8))
            Rectangle()
                .fill(Color.sun.opacity(0.5))
                .frame(width: size * 0.45, height: 15)
                .rotationEffect(.degrees(-14))
                .offset(y: -size * 0.49)
        }
        .frame(width: size, height: size)
        .padding(8)
        .accessibilityHidden(true)
    }
}

struct MembershipPassEntry: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text("查看会员权益")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .frame(width: 32, height: 32)
                    .background(Color.sun.opacity(0.45), in: Circle())
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color.ink)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct MembershipTicketDivider: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.ink.opacity(0.14))
                .mask {
                    HStack(spacing: 5) {
                        ForEach(0..<90, id: \.self) { _ in Rectangle().frame(width: 4) }
                    }
                }
                .frame(height: 1)
            HStack {
                Circle().fill(Color.paper).frame(width: 16, height: 16).offset(x: -8)
                Spacer()
                Circle().fill(Color.paper).frame(width: 16, height: 16).offset(x: 8)
            }
        }
        .frame(height: 16)
        .padding(.horizontal, -20)
        .accessibilityHidden(true)
    }
}

struct MembershipBenefitCard: View {
    let symbol: String
    let title: String
    let detail: String
    var tint: Color = .mint
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        layout {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.4))
                    .rotationEffect(.degrees(-7))
                Image(systemName: symbol)
                    .font(.system(size: 25, weight: .medium))
            }
            .frame(width: 54, height: 58)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(.headline, design: .rounded, weight: .bold))
                Text(detail)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(Color.ink.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Color.ink)
        .fixedSize(horizontal: false, vertical: true)
        .padding(18)
        .background(Color.paperLight, in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(Color.ink.opacity(0.07)) }
        .accessibilityElement(children: .combine)
    }
}

struct MembershipRestoreButton: View {
    var onRestored: () -> Void
    @EnvironmentObject private var membership: MembershipStore

    var body: some View {
        Button {
            Task {
                if await membership.restorePurchases() == .active {
                    membership.dismissMessage()
                    onRestored()
                }
            }
        } label: {
            HStack(spacing: 8) {
                if membership.isRestoring { ProgressView().controlSize(.small) }
                Text(membership.isRestoring ? "正在恢复购买…" : "恢复购买")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .font(.system(.subheadline, design: .rounded, weight: .semibold))
        .foregroundStyle(Color.ink.opacity(0.65))
        .disabled(membership.isPurchasing || membership.isRefreshingEntitlements)
    }
}

struct MembershipDetailsView: View {
    var onRestored: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var membership: MembershipStore
    @State private var restored = false

    private var displayState: MembershipSettingsDisplayState {
        .resolve(loadState: membership.entitlementLoadState, isRefreshing: membership.isRefreshingEntitlements)
    }

    var body: some View {
        ZStack {
            NotebookBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(spacing: 14) {
                        MembershipSummaryCard(entitlement: membership.entitlement, state: displayState, showSuccess: restored)
                        MembershipTicketDivider()
                        Text("生活探索通行证")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.ink.opacity(0.5))
                    }
                    .padding(20)
                    .background(Color.paperLight, in: RoundedRectangle(cornerRadius: 26))
                    .overlay { RoundedRectangle(cornerRadius: 26).stroke(Color.ink.opacity(0.08)) }
                    if displayState != .loaded {
                        Text(displayState.statusText)
                            .foregroundStyle(Color.ink.opacity(0.6))
                        if displayState.isFailure {
                            Button("重新读取") {
                                Task { await membership.refreshCurrentEntitlements(source: .settings) }
                            }
                            .disabled(membership.isPurchasing)
                        }
                    }
                    if let value = membership.entitlement, displayState != .failedWithoutCachedValue {
                        if value.isMember {
                            MembershipBenefitCard(symbol: "camera", title: "拍下生活里的好奇", detail: value.hasUnlimitedQuota ? "拍照识词不限次数，随心发现身边的英语。" : "每个订阅月 \(value.limit) 次拍照识词。", tint: .sun)
                            if value.vocabularyCorrectionEnabled {
                                MembershipBenefitCard(symbol: "character.book.closed", title: "完善你的单词卡", detail: "AI 单词纠错与补充，让音标、释义和例句更完整。")
                            }

                        }
                        MembershipBenefitCard(symbol: "photo.on.rectangle", title: "发现值得留下", detail: "回顾、发音、分享和听音练习，免费版也可使用。", tint: .sky)
                    }
                    Divider()
                    if let value = membership.entitlement, value.isMember, displayState != .failedWithoutCachedValue {
                            if let expiration = value.expirationDate {
                                Label("会员有效期至 \(expiration.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar")
                            }
                            if !value.hasUnlimitedQuota {
                                Text("识别额度按订阅日逐月更新，不结转。额度更新日期与会员有效期不同。")
                            }
                    }
                    Text("订阅由 Apple 管理，可在 App Store 中修改或取消。")
                        .foregroundStyle(Color.ink.opacity(0.65))
                    MembershipRestoreButton {
                        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.35)) { restored = true }
                        onRestored()
                    }
                }
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(Color.ink)
                .padding(20)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PictureWordPageHeader(eyebrow: "MEMBERSHIP", title: "会员权益", foreground: .ink, eyebrowColor: .coral, tint: Color.paperLight.opacity(0.52)) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 50, height: 50)
                        .pictureWordGlass(tint: Color.paperLight, interactive: true, in: Capsule())
                }
                .accessibilityLabel("返回")
            } trailing: {
                Color.clear.frame(width: 50, height: 50).accessibilityHidden(true)
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(InteractivePopGestureEnabler())
        .alert("会员", isPresented: Binding(
            get: { membership.message != nil },
            set: { if !$0 { Task { @MainActor in membership.dismissMessage() } } }
        )) {
            Button("知道了", role: .cancel) { membership.dismissMessage() }
        } message: { Text(membership.message ?? "") }
    }
}
