import SwiftUI
import UIKit

struct HistoryRow: View {
    let record: HistoryRecord
    let thumbnail: UIImage?
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 13) {
                    Group {
                        if let thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Color.paperDeep.overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(Color.ink.opacity(0.32))
                            }
                        }
                    }
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.result.objects.map(\.english).prefix(3).joined(separator: " · "))
                            .font(.system(.headline, design: .serif, weight: .bold))
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                        Text("\(record.result.objects.count) 个单词 · \(record.createdAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(Color.ink.opacity(0.48))
                        if record.mode == .parentChild {
                            Label("亲子寻宝", systemImage: "figure.2.and.child.holdinghands")
                                .font(.system(.caption2, design: .rounded, weight: .bold))
                                .foregroundStyle(Color.coral)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.coral)
                    .frame(width: 44, height: 44)
                    .background(Color.coral.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除这张单词卡")
        }
        .padding(10)
        .background(Color.paperLight.opacity(0.9), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(Color.ink.opacity(0.07)) }
    }
}
