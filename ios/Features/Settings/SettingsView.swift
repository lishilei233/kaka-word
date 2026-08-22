import SwiftUI

/// MVP 设置全部保存在本机，不依赖账号或网络服务。
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyStore: HistoryStore
    @AppStorage(AppSettings.Key.englishSpeechEnabled) private var speechEnabled = AppSettings.defaultEnglishSpeechEnabled
    @AppStorage(AppSettings.Key.speechRate) private var speechRate = AppSettings.defaultSpeechRate
    @AppStorage(AppSettings.Key.maxObjects) private var maxObjects = AppSettings.defaultMaxObjects
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
            VStack(spacing: 12) {
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
                    SettingsLinkRow(title: "关于 Picture Word")
                }
            }
        }
    }

    private var versionFooter: some View {
        Text("PICTURE WORD · VERSION \(appVersion)")
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

    var title: String { self == .privacy ? "隐私政策" : "服务条款" }
    var code: String { self == .privacy ? "PRIVACY" : "TERMS" }
    var text: String {
        switch self {
        case .privacy:
            return "Picture Word 会将你主动拍摄或选择的照片发送给 AI 服务进行即时识别。照片不会写入应用服务器、对象存储或业务数据库。识别完成后，照片、任务进度与贴纸仅保存在当前设备。生成分享卡时，人脸检测和模糊处理也只在本机完成，导出图片不会包含拍摄位置和时间元数据。"
        case .terms:
            return "Picture Word 提供基于 AI 的图片识别与语言学习辅助。AI 返回的物体名称、位置、音标和例句可能存在错误，仅供学习参考。请勿上传包含敏感个人信息、违法内容或你无权处理的照片。"
        }
    }
}

private struct LegalDocumentView: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            NotebookBackground()
            VStack(spacing: 0) {
                EditorialBackHeader(title: document.title, code: document.code, dismiss: dismiss.callAsFunction)
                ScrollView {
                    Text(document.text)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.ink.opacity(0.8))
                        .lineSpacing(7)
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.paperLight, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .padding(20)
                }
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .pictureWordBackSwipe { dismiss() }
    }
}

private struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            NotebookBackground()
            VStack(spacing: 0) {
                EditorialBackHeader(title: "关于", code: "ABOUT", dismiss: dismiss.callAsFunction)
                VStack(alignment: .leading, spacing: 18) {
                    Text("看见，\n就会说。")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundStyle(Color.ink)
                        .lineSpacing(-4)
                    Text("Picture Word 用 AI 找到照片中值得学习的物体，把英文单词贴回真实世界。")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.ink.opacity(0.68))
                        .lineSpacing(5)
                }
                .padding(26)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.sun, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .padding(20)
                Spacer()
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .pictureWordBackSwipe { dismiss() }
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
