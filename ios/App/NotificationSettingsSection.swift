import SwiftUI
import UserNotifications

struct NotificationSettingsSection: View {
    @ObservedObject var notifications: LocalNotificationCoordinator
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("提醒").font(.scrapbookTitle)
            Toggle(isOn: enabledBinding(.learning)) {
                Text("学习提醒").font(.scrapbookBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("有可练习单词时提醒，当天完成一轮听音练习后不再提醒。")
                .font(.footnote).foregroundStyle(Color.ink.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            if notifications.preferences.learning {
                VStack(alignment: .leading, spacing: 8) {
                    Text("提醒时间").font(.scrapbookBody)
                    DatePicker("提醒时间", selection: Binding(get: { notifications.learningTime }, set: {
                        notifications.setLearningTime($0)
                    }), displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                }
                Text("每次打开会安排未来 7 天的提醒，长期未打开后自动停止。")
                    .font(.footnote).foregroundStyle(Color.ink.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Toggle(isOn: enabledBinding(.membership)) {
                Text("会员开通提醒").font(.scrapbookBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("免费体验次数用完后，次日中午提醒一次，了解会员方案。")
                .font(.footnote).foregroundStyle(Color.ink.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            if notifications.authorization == .denied {
                Text("系统通知未开启。你的提醒选择已保留，可前往系统设置允许通知。")
                    .font(.footnote).foregroundStyle(Color.ink.opacity(0.65))
                PictureWordButton("前往系统设置", style: .secondary, size: .compact) {
                    guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
                    openURL(url)
                }
            } else if notifications.authorization == .notDetermined {
                Text("开启提醒时会申请系统通知权限。")
                    .font(.footnote).foregroundStyle(Color.ink.opacity(0.65))
            }
            if let error = notifications.errorMessage {
                Text(error).font(.footnote).foregroundStyle(Color.coral)
                PictureWordButton("重试", style: .secondary, size: .compact) {
                    Task { await notifications.retry() }
                }
            }
        }
        .tint(Color.mint)
        .foregroundStyle(Color.ink)
        .padding(20)
        .background(Color.paperLight, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.ink.opacity(0.08)))
        .task { notifications.requestReconcile() }
    }

    private func enabledBinding(_ destination: ReminderDestination) -> Binding<Bool> {
        Binding(get: {
            destination == .learning ? notifications.preferences.learning : notifications.preferences.membership
        }, set: { value in
            Task { await notifications.setEnabled(value, for: destination) }
        })
    }
}
