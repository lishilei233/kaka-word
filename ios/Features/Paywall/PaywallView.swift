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
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var membership: MembershipStore
    @State private var selectedProductId = MembershipStore.annualProductId
    @State private var canPresentMembershipAlert = false
    @State private var awaitingOutcome: MembershipActionOutcome?
    @State private var completed = false

    var body: some View {
        NavigationStack {
            ZStack {
                NotebookBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        hero
                        benefits
                        if membership.isMember {
                            membershipStatusCard
                        } else {
                            plans
                            purchaseButton
                            if let awaitingOutcome {
                                Text(awaitingOutcome == .pending
                                     ? "购买正在等待批准，批准后会员会自动生效。"
                                     : "正在确认会员权益，请勿重复购买。可稍后恢复购买或重新读取状态。")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.ink.opacity(0.65))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if (!membership.hasFreshEntitlement || awaitingOutcome != nil) && !membership.isPurchasing {
                                Button("重新读取会员状态") {
                                    Task { await membership.refreshCurrentEntitlements(source: .manual) }
                                }
                                .disabled(membership.isRefreshingEntitlements)
                            }
                        }
                        footer
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Text("MEMBERSHIP")
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                        .foregroundStyle(Color.ink.opacity(0.5))
                    Spacer()
                    closeButton
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Color.paper)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.light)
        .task {
            // Wait until the sheet's hosting controller is in the window hierarchy
            // before presenting an alert triggered by startup or StoreKit work.
            await Task.yield()
            canPresentMembershipAlert = true
            membership.recordMetric("paywall_exposure")
            async let products: Void = membership.prepareProducts(force: true)
            async let planConfig: Void = membership.preparePlanConfig()
            await products
            await planConfig
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
        .onChange(of: membership.products.map(\.id)) { _, ids in
            selectedProductId = MembershipPlanSelection.resolve(selected: selectedProductId, available: ids)
        }
        .onChange(of: membership.hasFreshEntitlement && membership.isMember) { _, confirmed in
            if confirmed && awaitingOutcome != nil { finishPurchase() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, !membership.isPurchasing else { return }
            Task { await membership.prepareProducts(force: true) }
        }
    }

    private var hero: some View {
        VStack(spacing: 16) {
            MembershipCameraArtwork(size: 100)

            Text(membership.isMember ? "继续发现生活里的英语" : "把生活变成英语单词册")
                .font(.system(.title2, design: .rounded, weight: .black))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.ink)
                .lineSpacing(4)
                .minimumScaleFactor(0.78)

            HStack(spacing: 9) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.sun)
                Text(membership.isMember ? "会员权益一览" : "更多拍照探索，也能完善你的单词")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.ink.opacity(0.72))
                    .multilineTextAlignment(.center)
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.sun)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var benefits: some View {
        VStack(spacing: 12) {
            MembershipBenefitCard(symbol: "camera", title: "拍下生活里的好奇", detail: quotaBenefitText, tint: .sun)
            if !membership.isMember || membership.entitlement?.vocabularyCorrectionEnabled == true {
                MembershipBenefitCard(symbol: "character.book.closed", title: "完善你的单词卡", detail: "AI 智能优化，完善音标、释义与例句。")
            }
            Text("回顾、发音、分享与听音练习，免费版也可使用。")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(Color.ink.opacity(0.6))
        }
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(Color.ink)
                .frame(width: 48, height: 48)
                .background(Color.paperLight.opacity(0.92), in: Circle())
                .overlay { Circle().stroke(Color.white.opacity(0.9), lineWidth: 1) }
                .shadow(color: Color.ink.opacity(0.1), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("关闭会员购买页面")
    }

    private var quotaBenefitText: String {
        if let value = membership.entitlement, value.isMember {
            return value.hasUnlimitedQuota ? "拍照识词不限次数" : "每个订阅月 \(value.limit) 次拍照识别"
        }
        guard let config = membership.planConfig else { return "每月享有完整拍照识词额度" }
        return config.paywallBenefitText
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
                        title: membership.annualIntroductoryOffer == nil ? "年会员" : "新人年会员",
                        badge: membership.annualIntroductoryOffer == nil ? annualBadge(for: annual) : "推荐",
                        detail: membership.annualIntroductoryOffer?.detail ?? annualMonthlyEquivalent(annual)
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
            isLoading: membership.isPurchasing && !membership.isRestoring
        ) {
            guard let product = selectedProduct else { return }
            Task {
                let outcome = await membership.purchase(product)
                if outcome == .active {
                    finishPurchase()
                } else if outcome == .pending || outcome == .awaitingSync {
                    awaitingOutcome = outcome
                }
            }
        }
        .disabled(selectedProduct == nil || !membership.canPurchase || awaitingOutcome != nil)
    }

    private var purchaseButtonTitle: String {
        if membership.isRestoring { return selectedIntroductoryOffer?.purchaseTitle ?? "开通咔咔会员" }
        if awaitingOutcome != nil { return "等待会员权益确认" }
        switch membership.purchasePhase {
        case .preflight:
            return "正在确认会员状态…"
        case .waitingForApple:
            return "正在连接 App Store…"
        case .syncingEntitlement:
            return "正在同步会员权益…"
        case nil:
            if membership.isPurchasing { return "正在连接 App Store…" }
            return selectedIntroductoryOffer?.purchaseTitle ?? "开通咔咔会员"
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
            Text("拍照识词不限次数")
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

    private func finishPurchase() {
        guard !completed else { return }
        completed = true
        membership.dismissMessage()
        onPurchaseCompleted?()
        dismiss()
    }

    private var quotaRenewalDisclosure: String {
        // Active subscribers use their actual entitlement; prospective subscribers use the plan configuration.
        let unlimited = membership.isMember
            ? membership.entitlement?.hasUnlimitedQuota
            : membership.planConfig?.unlimited
        return unlimited == false ? "额度按订阅日逐月重置，不结转。" : ""
    }

    private var footer: some View {
        VStack(spacing: 13) {
            if !membership.isMember {
                Button {
                    Task {
                        if await membership.restorePurchases() == .active {
                            finishPurchase()
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
                .disabled(membership.isPurchasing || membership.isRefreshingEntitlements)
            }

            Text("订阅由 Apple 管理，可在 App Store 中修改或取消。")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(Color.ink.opacity(0.65))
                .multilineTextAlignment(.center)

            if !membership.isMember, let product = selectedProduct {
                Text(selectedIntroductoryOffer?.renewalDisclosure
                     ?? "\(product.displayPrice)/\(product.id == MembershipStore.annualProductId ? "年" : "月")，自动续订，可在 App Store 取消。")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.ink.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("付款将由 Apple 账户确认。新人优惠资格由 App Store 判定，同一订阅组每人只能享受一次介绍性优惠。订阅会自动续期，除非在当前周期结束前至少 24 小时关闭自动续订。" + quotaRenewalDisclosure)
                .font(.system(.caption2, design: .rounded, weight: .medium))
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

    private func planCard(_ product: Product, title: String, badge: String?, detail: String) -> some View {
        let offer = product.id == MembershipStore.annualProductId ? membership.annualIntroductoryOffer : nil
        return MembershipPlanCard(
            title: title,
            badge: badge,
            priceText: offer?.priceText ?? "\(product.displayPrice)/\(product.id == MembershipStore.annualProductId ? "年" : "月")",
            detail: detail,
            selected: selectedProduct?.id == product.id
        ) {
            selectedProductId = product.id
            membership.recordMetric("plan_selection", productId: product.id)
        }
        .disabled(membership.isPurchasing || awaitingOutcome != nil)
    }

    private var selectedProduct: Product? {
        let id = MembershipPlanSelection.resolve(selected: selectedProductId, available: membership.products.map(\.id))
        return membership.products.first { $0.id == id }
    }

    private var selectedIntroductoryOffer: AnnualIntroductoryOffer? {
        selectedProduct?.id == MembershipStore.annualProductId ? membership.annualIntroductoryOffer : nil
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

struct MembershipPlanCard: View {
    let title: String
    let badge: String?
    let priceText: String
    let detail: String
    let selected: Bool
    let onSelect: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .stroke(selected ? Color.coral : Color.paperDeep, lineWidth: 2)
                        .frame(width: 25, height: 25)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(Color.coral)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.7).combined(with: .opacity))
                    }
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
                    layout {
                        Text(title)
                            .font(.system(.headline, design: .rounded, weight: .heavy))
                            .fixedSize(horizontal: false, vertical: true)
                        if let badge {
                            Text(badge)
                                .font(.system(.caption2, design: .rounded, weight: .black))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.sun, in: Capsule())
                        }
                        if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    }
                    Text(priceText)
                        .font(.system(.title2, design: .rounded, weight: .black))
                        .foregroundStyle(selected ? Color.coral : Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.ink.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 17)
            .background(Color.paperLight.opacity(selected ? 0.98 : 0.62), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(selected ? Color.coral : Color.paperDeep.opacity(0.78), lineWidth: selected ? 2 : 1)
            }
            .shadow(color: selected ? Color.coral.opacity(0.08) : .clear, radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(priceText)，\(detail)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .animation(.easeInOut(duration: reduceMotion ? 0.1 : 0.2), value: selected)
    }
}

enum MembershipPlanSelection {
    static func resolve(selected: String, available: [String]) -> String {
        if available.contains(selected) { return selected }
        if available.contains(MembershipStore.annualProductId) { return MembershipStore.annualProductId }
        if available.contains(MembershipStore.monthlyProductId) { return MembershipStore.monthlyProductId }
        return MembershipStore.annualProductId
    }
}
