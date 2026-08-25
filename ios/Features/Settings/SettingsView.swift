import SwiftUI

/// MVP 设置全部保存在本机，不依赖账号或网络服务。
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyStore: HistoryStore
    @AppStorage(AppSettings.Key.englishSpeechEnabled) private var speechEnabled = AppSettings.defaultEnglishSpeechEnabled
    @AppStorage(AppSettings.Key.speechRate) private var speechRate = AppSettings.defaultSpeechRate
    @AppStorage(AppSettings.Key.maxObjects) private var maxObjects = AppSettings.defaultMaxObjects
    @AppStorage(AppSettings.Key.captionStyle) private var captionStyleRawValue = AppSettings.defaultCaptionStyle
    @AppStorage(AppSettings.Key.learningMode) private var modeRawValue = AppSettings.defaultLearningMode
    @State private var confirmClearHistory = false

    var body: some View {
        ZStack {
            NotebookBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    experienceSection
                    recognitionSection
                    speechSection
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
        .confirmationDialog("清空全部历史记录？", isPresented: $confirmClearHistory, titleVisibility: .visible) {
            Button("清空全部", role: .destructive) { historyStore.deleteAll() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所有本地照片和识别结果都会被删除，且无法恢复。")
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
        SettingsCard(index: "00", title: "玩法") {
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
        SettingsCard(index: "01", title: "识别") {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SettingsLabel(icon: "viewfinder", title: "每次识别单词")
                    Spacer()
                    Text("最多 \(maxObjects) 个")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.ink.opacity(0.62))
                }
                Stepper("", value: $maxObjects, in: 3...8)
                    .labelsHidden()
                    .tint(Color.ink)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Divider().overlay(Color.ink.opacity(0.12))

                VStack(alignment: .leading, spacing: 10) {
                    SettingsLabel(icon: "text.quote", title: "图片英文描述")
                    Picker("图片描述风格", selection: $captionStyleRawValue) {
                        ForEach(CaptionStyle.allCases) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("只影响之后新识别的照片，历史内容不会重新生成。")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.ink.opacity(0.52))
                }
            }
        }
    }

    private var speechSection: some View {
        SettingsCard(index: "02", title: "发音") {
            VStack(spacing: 18) {
                // Toggle(isOn: $speechEnabled) {
                //     SettingsLabel(icon: "speaker.wave.2.fill", title: "英文发音")
                // }
                // .tint(Color.coral)

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
        SettingsCard(index: "03", title: "本地数据") {
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
                        Text("\(historyStore.records.count)")
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
        SettingsCard(index: "04", title: "关于") {
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

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
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

private enum LegalDocument {
    case privacy
    case terms

    var key: ContentKey {
        switch self {
        case .privacy: return .privacy
        case .terms: return .terms
        }
    }
}

private struct LegalDocumentView: View {
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
                .environmentObject(HistoryStore())
        }
    }
}
