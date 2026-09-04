import Foundation
import StoreKit
import SwiftUI

struct SubscriptionDiscountCalculator {
    /// Returns the whole-number percentage saved by paying annually instead of
    /// paying the monthly price for twelve months. A nil result means the two
    /// prices are not safe to compare or there is no real discount.
    static func savingsPercent(
        monthlyPrice: Decimal,
        annualPrice: Decimal,
        monthlyCurrencyCode: String?,
        annualCurrencyCode: String?
    ) -> Int? {
        guard monthlyPrice > 0,
              annualPrice > 0,
              let monthlyCurrencyCode,
              let annualCurrencyCode,
              !monthlyCurrencyCode.isEmpty,
              monthlyCurrencyCode == annualCurrencyCode else {
            return nil
        }

        let twelveMonths = monthlyPrice * Decimal(12)
        guard annualPrice < twelveMonths else { return nil }

        let savings = (twelveMonths - annualPrice) / twelveMonths * Decimal(100)
        let rounded = NSDecimalNumber(decimal: savings).rounding(
            accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain,
                scale: 0,
                raiseOnExactness: false,
                raiseOnOverflow: true,
                raiseOnUnderflow: true,
                raiseOnDivideByZero: true
            )
        ).intValue
        guard (1...99).contains(rounded) else { return nil }
        return rounded
    }
}

struct PaywallView: View {
    var onPurchaseCompleted: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var membership: MembershipStore
    @State private var selectedProductId = MembershipStore.annualProductId
    @State private var canPresentMembershipAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                NotebookBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        hero
                        benefits
                        if membership.isMember {
                            membershipStatusCard
                            manageSubscriptionButton
                        } else {
                            plans
                            purchaseButton
                        }
                        footer
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 34)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(Color.ink)
                            .frame(width: 42, height: 42)
                            .background(Color.paperLight.opacity(0.9), in: Circle())
                    }
                    .accessibilityLabel("关闭")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.light)
        .task {
            // Wait until the sheet's hosting controller is in the window hierarchy
            // before presenting an alert triggered by startup or StoreKit work.
            await Task.yield()
            canPresentMembershipAlert = true
            membership.recordMetric("paywall_exposure")
            await membership.prepareProducts()
        }
        .alert("会员", isPresented: Binding(
            get: { canPresentMembershipAlert && membership.message != nil },
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
        .onDisappear { canPresentMembershipAlert = false }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            StickerSeal(symbol: "sparkles", color: .coral)
            Text("把生活继续变成\n孩子的英语单词册")
                .font(.system(size: 30, weight: .black, design: .serif))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.ink)
                .lineSpacing(2)
            Text("会员额度以服务端实时显示为准")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Color.ink.opacity(0.58))
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 13) {
            benefit("camera.viewfinder", "每个额度月享有完整拍照识词额度")
            benefit("pencil.and.outline", "AI 修改单词并补全音标、释义和例句")
            benefit("books.vertical.fill", "历史、发音、分享和亲子寻宝持续保留")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mint.opacity(0.62), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 25).stroke(Color.ink.opacity(0.07)) }
    }

    @ViewBuilder
    private var plans: some View {
        if membership.isLoading {
            VStack(spacing: 12) {
                ProgressView().tint(Color.ink)
                Text("正在从 App Store 获取价格…")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.ink.opacity(0.55))
            }
            .frame(maxWidth: .infinity, minHeight: 150)
        } else if membership.products.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: membership.productLoadFailed ? "exclamationmark.triangle" : "bag.badge.questionmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.coral)
                Text(membership.productLoadFailed ? "暂时没有获取到订阅商品" : "正在从 App Store 获取价格…")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.ink.opacity(0.55))
                if membership.productLoadFailed {
                    Button("重试") {
                        Task { await membership.retryProducts() }
                    }
                    .font(.system(.subheadline, design: .rounded, weight: .heavy))
                    .foregroundStyle(Color.ink)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150)
        } else {
            VStack(spacing: 12) {
                if let annual = membership.annualProduct {
                    planCard(
                        annual,
                        title: "年会员",
                        badge: annualBadge(for: annual),
                        detail: annualMonthlyEquivalent(annual)
                    )
                }
                if let monthly = membership.monthlyProduct {
                    planCard(monthly, title: "月会员", badge: nil, detail: "按月自动续订")
                }
            }
        }
    }

    private var purchaseButton: some View {
        PictureWordButton(
            purchaseButtonTitle,
            systemImage: "sparkles",
            isLoading: membership.isPurchasing
        ) {
            guard let product = selectedProduct else { return }
            Task {
                if await membership.purchase(product) == .active {
                    onPurchaseCompleted?()
                    dismiss()
                }
            }
        }
        .disabled(selectedProduct == nil || !membership.canPurchase)
    }

    private var purchaseButtonTitle: String {
        if membership.isRestoring { return "正在恢复购买…" }
        switch membership.purchasePhase {
        case .preflight:
            return "正在确认会员状态…"
        case .waitingForApple:
            return "正在连接 App Store…"
        case .syncingEntitlement:
            return "正在同步会员权益…"
        case nil:
            return membership.isPurchasing ? "正在连接 App Store…" : "开通咔咔会员"
        }
    }

    private var quotaExhaustedCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "hourglass")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.coral)
            Text("本期识别额度已用完")
                .font(.system(.headline, design: .rounded, weight: .heavy))
                .foregroundStyle(Color.ink)
            if let reset = membership.entitlement?.resetDate {
                Text("额度将在 \(reset.formatted(date: .abbreviated, time: .omitted)) 重置，当前会员权益仍然有效。")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.ink.opacity(0.58))
                    .multilineTextAlignment(.center)
            } else {
                Text("当前会员权益仍然有效，额度将在下个额度月自动重置。")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.ink.opacity(0.58))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.paperLight.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(Color.ink.opacity(0.08)) }
    }

    @ViewBuilder
    private var membershipStatusCard: some View {
        switch membership.membershipPaywallState {
        case .syncing:
            membershipSyncingCard
        case .active(let remaining, let limit):
            activeMembershipCard(remaining: remaining, limit: limit)
        case .unlimited:
            unlimitedMembershipCard
        case .exhausted:
            quotaExhaustedCard
        case .unavailable:
            membershipUnavailableCard
        }
    }

    private var membershipSyncingCard: some View {
        VStack(spacing: 10) {
            ProgressView().tint(Color.ink)
            Text("正在同步会员权益…")
                .font(.system(.headline, design: .rounded, weight: .heavy))
                .foregroundStyle(Color.ink)
            Text("同步完成后将显示本期剩余额度。")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.ink.opacity(0.58))
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.paperLight.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(Color.ink.opacity(0.08)) }
    }

    private func activeMembershipCard(remaining: Int, limit: Int) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.mint)
            Text("咔咔会员已开通")
                .font(.system(.headline, design: .rounded, weight: .heavy))
                .foregroundStyle(Color.ink)
            Text("本期剩余 \(remaining)/\(limit) 次识别")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Color.ink.opacity(0.7))
            if let reset = membership.entitlement?.resetDate {
                Text("额度将在 \(reset.formatted(date: .abbreviated, time: .omitted)) 重置。")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.ink.opacity(0.58))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.paperLight.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(Color.ink.opacity(0.08)) }
    }

    private var unlimitedMembershipCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "infinity.circle.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.mint)
            Text("咔咔会员已开通")
                .font(.system(.headline, design: .rounded, weight: .heavy))
                .foregroundStyle(Color.ink)
            Text("本期识别额度：无限")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Color.ink.opacity(0.7))
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.paperLight.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(Color.ink.opacity(0.08)) }
    }

    private var membershipUnavailableCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.coral)
            Text("会员状态暂时无法确认")
                .font(.system(.headline, design: .rounded, weight: .heavy))
                .foregroundStyle(Color.ink)
            Text("已保留会员状态，暂不判断本期额度。")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.ink.opacity(0.58))
                .multilineTextAlignment(.center)
            Button("重新读取") {
                Task { await membership.refreshCurrentEntitlements(source: .manual) }
            }
            .font(.system(.subheadline, design: .rounded, weight: .heavy))
            .foregroundStyle(Color.ink)
            .disabled(membership.isRefreshingEntitlements)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.paperLight.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(Color.ink.opacity(0.08)) }
    }

    private var manageSubscriptionButton: some View {
        PictureWordButton("管理订阅", systemImage: "gearshape") {
            Task { await membership.showManageSubscriptions() }
        }
        .disabled(membership.isPurchasing)
    }

    private var footer: some View {
        VStack(spacing: 13) {
            if !membership.isMember {
                Button {
                    Task {
                        if await membership.restorePurchases() == .active {
                            onPurchaseCompleted?()
                            dismiss()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if membership.isRestoring {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(membership.isRestoring ? "正在恢复购买…" : "恢复购买")
                    }
                }
                .font(.system(.subheadline, design: .rounded, weight: .heavy))
                .foregroundStyle(Color.ink)
                .disabled(membership.isPurchasing)
            }

            Text("付款将由 Apple 账户确认。订阅会自动续期，除非在当前周期结束前至少 24 小时关闭自动续订。额度按订阅日逐月重置，不结转。")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color.ink.opacity(0.48))
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            HStack(spacing: 18) {
                NavigationLink("服务条款") { LegalDocumentView(document: .terms) }
                NavigationLink("隐私政策") { LegalDocumentView(document: .privacy) }
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(Color.ink.opacity(0.7))
        }
    }

    private func benefit(_ symbol: String, _ title: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .foregroundStyle(Color.ink)
    }

    private func planCard(_ product: Product, title: String, badge: String?, detail: String) -> some View {
        let selected = selectedProductId == product.id
        return Button {
            selectedProductId = product.id
            membership.recordMetric("plan_selection", productId: product.id)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(selected ? Color.coral : Color.ink.opacity(0.28))
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(.headline, design: .rounded, weight: .heavy))
                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.sun, in: Capsule())
                        }
                    }
                    Text(detail)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.ink.opacity(0.52))
                }
                Spacer()
                Text("\(product.displayPrice)/\(product.id == MembershipStore.annualProductId ? "年" : "月")")
                    .font(.system(.title3, design: .rounded, weight: .black))
                    .foregroundStyle(Color.ink)
            }
            .padding(18)
            .background(selected ? Color.paperLight : Color.paperLight.opacity(0.68), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(selected ? Color.coral : Color.ink.opacity(0.08), lineWidth: selected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var selectedProduct: Product? {
        membership.products.first { $0.id == selectedProductId }
    }

    private func annualMonthlyEquivalent(_ product: Product) -> String {
        let monthly = product.price / Decimal(12)
        return "约 \(monthly.formatted(product.priceFormatStyle))/月，按年自动续订"
    }

    private func annualBadge(for annualProduct: Product) -> String {
        guard let monthlyProduct = membership.monthlyProduct,
              let savings = SubscriptionDiscountCalculator.savingsPercent(
                  monthlyPrice: monthlyProduct.price,
                  annualPrice: annualProduct.price,
                  monthlyCurrencyCode: monthlyProduct.priceFormatStyle.currencyCode,
                  annualCurrencyCode: annualProduct.priceFormatStyle.currencyCode
              ) else {
            return "推荐"
        }
        return "推荐 · 省 \(savings)%"
    }
}
