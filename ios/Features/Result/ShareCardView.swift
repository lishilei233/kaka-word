import SwiftUI
import UIKit

struct ShareCardView: View {
    let image: UIImage
    let result: AnalyzeResult
    let headline: String

    @Environment(\.dismiss) private var dismiss
    @State private var normalizedImage: UIImage
    @State private var previewImage: UIImage
    @State private var faceRects: [CGRect] = []
    @State private var blurFaces = true
    @State private var isDetecting = true
    @State private var isRendering = false
    @State private var shareItem: ShareFile?
    @State private var errorMessage: String?

    init(image: UIImage, result: AnalyzeResult, headline: String? = nil) {
        self.image = image
        self.result = result
        self.headline = headline ?? result.caption ?? "把生活读成英语"
        _normalizedImage = State(initialValue: image)
        _previewImage = State(initialValue: image)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NotebookBackground()
                VStack(spacing: 0) {
                    PictureWordPageHeader(
                        eyebrow: "SHARE CARD",
                        title: "分享学习卡",
                        foreground: Color.ink,
                        eyebrowColor: Color.coral,
                        tint: Color.paperLight.opacity(0.52)
                    ) {
                        PictureWordHeaderCapsule(
                            tint: Color.paperLight.opacity(0.52),
                            foreground: Color.ink,
                            interactive: true
                        ) {
                            Button("取消") { dismiss() }
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .frame(width: 50, height: 50)
                                .buttonStyle(.plain)
                        }
                    } trailing: {
                        Color.clear.frame(width: 50, height: 50)
                    }

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            preview
                            privacyCard
                            shareButton
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)
                    }
                }
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .task { await preparePrivacyPreview() }
        .onChange(of: blurFaces) { _, _ in
            Task { await updatePreviewImage() }
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
        }
        .alert("无法生成分享卡", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var preview: some View {
        ShareCardCanvas(
            image: previewImage,
            result: result,
            headline: headline
        )
        .aspectRatio(ShareCardRenderer.logicalSize, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.ink.opacity(0.16), radius: 16, y: 8)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var privacyCard: some View {
        if isDetecting {
            HStack(spacing: 12) {
                ProgressView().tint(Color.ink)
                Text("正在本机检查照片中的人物…")
            }
            .font(.system(.subheadline, design: .rounded, weight: .medium))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.sky.opacity(0.55), in: RoundedRectangle(cornerRadius: 18))
        } else if !faceRects.isEmpty {
            Toggle(isOn: $blurFaces) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("默认模糊人物面部", systemImage: "eye.slash.fill")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                    Text("检测完全在本机完成；分享前请再次确认预览。")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.ink.opacity(0.56))
                }
            }
            .tint(Color.coral)
            .padding(16)
            .background(Color.sun.opacity(0.52), in: RoundedRectangle(cornerRadius: 18))
        } else {
            Label("没有检测到人物面部，卡片也不会写入姓名、地点或拍摄时间。", systemImage: "checkmark.shield.fill")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(Color.ink.opacity(0.62))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.mint.opacity(0.52), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var shareButton: some View {
        Button(action: createShareFile) {
            HStack(spacing: 9) {
                if isRendering { ProgressView().tint(Color.paperLight) }
                Image(systemName: "square.and.arrow.up")
                Text(isRendering ? "正在生成…" : "保存或分享")
            }
            .font(.system(.headline, design: .rounded, weight: .heavy))
            .foregroundStyle(Color.paperLight)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Color.ink, in: RoundedRectangle(cornerRadius: 19))
        }
        .disabled(isRendering || isDetecting)
        .opacity(isDetecting ? 0.52 : 1)
    }

    private func preparePrivacyPreview() async {
        isDetecting = true
        let prepared = await FacePrivacyService.prepare(image)
        normalizedImage = prepared.image
        faceRects = prepared.faces
        blurFaces = !prepared.faces.isEmpty
        await updatePreviewImage()
        isDetecting = false
    }

    private func updatePreviewImage() async {
        if blurFaces, !faceRects.isEmpty {
            previewImage = await FacePrivacyService.blurFaces(in: normalizedImage, normalizedRects: faceRects)
        } else {
            previewImage = normalizedImage
        }
    }

    private func createShareFile() {
        isRendering = true
        do {
            let url = try ShareCardRenderer.render(
                image: previewImage,
                result: result,
                headline: headline
            )
            shareItem = ShareFile(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
        isRendering = false
    }
}

private struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
