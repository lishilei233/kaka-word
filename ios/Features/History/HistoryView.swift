import SwiftUI
import UIKit

/// 完整历史列表。首页只承担最近记录预览，所有管理操作集中在这里完成。
struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyStore: HistoryStore
    @State private var presentedResult: HistoryResultItem?
    @State private var confirmClearHistory = false
    @State private var historyMessage: String?

    var body: some View {
        ZStack {
            Color.ink.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                content
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .pictureWordBackSwipe { dismiss() }
        .fullScreenCover(item: $presentedResult) { item in
            ResultView(image: item.image, result: item.record.result)
        }
        .confirmationDialog("清空全部历史记录？", isPresented: $confirmClearHistory, titleVisibility: .visible) {
            Button("清空全部", role: .destructive) { historyStore.deleteAll() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("本地保存的照片和识别结果都会被删除，且无法恢复。")
        }
        .alert("历史记录", isPresented: Binding(
            get: { historyMessage != nil },
            set: { if !$0 { historyMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(historyMessage ?? "")
        }
    }

    private var header: some View {
        PictureWordPageHeader(
            eyebrow: "HISTORY",
            title: "全部识别记录",
            foreground: .white,
            eyebrowColor: Color.sun,
            tint: Color.ink
        ) {
            PictureWordHeaderCapsule(
                tint: Color.ink,
                foreground: .white,
                interactive: true
            ) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .black))
                        .frame(width: 50, height: 50)
                }
                .accessibilityLabel("返回")
                .buttonStyle(.plain)
            }
        } trailing: {
            PictureWordHeaderCapsule(
                tint: Color.ink,
                foreground: historyStore.records.isEmpty ? .white.opacity(0.25) : Color.coral,
                interactive: true
            ) {
                Button { confirmClearHistory = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 50, height: 50)
                }
                .disabled(historyStore.records.isEmpty)
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if historyStore.records.isEmpty {
            VStack(spacing: 14) {
                Text("00")
                    .font(.system(size: 74, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.sun)
                Text("还没有识别记录")
                    .font(.system(size: 23, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("回到首页拍一张照片，认识身边的第一个单词。")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 42)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(historyStore.records) { record in
                        HistoryRow(
                            record: record,
                            thumbnail: historyStore.thumbnail(for: record),
                            onOpen: { open(record) },
                            onDelete: { historyStore.delete(record) }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
    }

    private func open(_ record: HistoryRecord) {
        guard let image = historyStore.image(for: record) else {
            historyMessage = "这条记录的本地图片已经丢失，可以删除后重新识别。"
            return
        }
        presentedResult = HistoryResultItem(record: record, image: image)
    }
}

private struct HistoryResultItem: Identifiable {
    var id: UUID { record.id }
    let record: HistoryRecord
    let image: UIImage
}

struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            HistoryView()
                .environmentObject(HistoryStore())
        }
    }
}
