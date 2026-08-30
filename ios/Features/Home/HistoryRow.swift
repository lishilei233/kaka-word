import SwiftUI
import UIKit

struct DiscoveryCardRow: View {
    let record: HistoryRecord
    let image: UIImage?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { geometry in
                    Group {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Color.paperDeep.overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(Color.ink.opacity(0.32))
                            }
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(Color.ink.opacity(0.07), lineWidth: 1)
                    }
                }
                .aspectRatio(150.0 / 126.0, contentMode: .fit)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(wordSummary)
                        .font(.system(.headline, design: .serif, weight: .bold))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(Color.ink.opacity(0.28))
                }

                HStack(spacing: 8) {
                    Text("\(record.result.objects.count) WORDS")
                        .font(.system(.caption2, design: .rounded, weight: .black))
                        .tracking(1)
                        .foregroundStyle(Color.coral)

                    Text(record.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .foregroundStyle(Color.ink.opacity(0.52))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.paperDeep.opacity(0.42), in: Capsule())

                    Spacer(minLength: 0)

                    if let mode = record.mode {
                        Label(mode.title, systemImage: mode.icon)
                            .font(.system(.caption2, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.ink.opacity(0.58))
                            .lineLimit(1)
                    }
                }
                .frame(minHeight: 26)
            }
            .padding(10)
            .background(Color.paperLight, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.ink.opacity(0.06), lineWidth: 1)
            }
            .overlay(alignment: .topTrailing) {
                WashiTape(color: .sun, showsShadow: false)
                    .scaleEffect(0.58)
                    .offset(x: -24, y: -9)
                    .accessibilityHidden(true)
            }
            .shadow(color: Color.ink.opacity(0.11), radius: 0, x: 2, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .rotationEffect(.degrees(record.id.uuidString.hashValue.isMultiple(of: 2) ? -0.55 : 0.55))
        .accessibilityLabel("发现卡，包含 \(record.result.objects.count) 个单词，\(record.createdAt.formatted(date: .abbreviated, time: .omitted))")
        .accessibilityHint("打开完整发现卡")
    }

    private var wordSummary: String {
        let words = record.result.objects.map(\.english).prefix(3).joined(separator: " · ")
        return words.isEmpty ? "A NEW DISCOVERY" : words
    }
}
