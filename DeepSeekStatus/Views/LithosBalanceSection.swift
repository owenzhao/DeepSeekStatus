import SwiftUI

/// 卡片里的 LithosAI 区块：名称行右侧是开关，开着的状态下把金额和「登录 / 退出」放在下面一行。
struct LithosBalanceSection: View {
    @ObservedObject var store: LithosBalanceStore

    var body: some View {
        BalanceProviderBlock(name: "LithosAI") {
            Toggle(isOn: Binding(get: { store.enabled }, set: { store.setEnabled($0) })) {
                // 名称已经在区块标题里了，开关自己不带文案，避免同一行出现两次 LithosAI。
                Text(verbatim: "LithosAI")
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .accessibilityLabel(Text(verbatim: "LithosAI"))
        } content: {
            if store.enabled {
                detailRow
            }
        }
    }

    private var detailRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            stateText
            Spacer(minLength: 0)
            sessionButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var stateText: some View {
        switch store.state {
        case .signedOut:
            Text(store.isSigningOut
                 ? String(localized: "lithos.balance.signingOut", defaultValue: "Signing out…")
                 : String(localized: "lithos.balance.signInHint", defaultValue: "Sign in to see your balance."))
                .font(BalanceCardStyle.messageFont)
                .foregroundStyle(WhaleTheme.labelTint)
        case .loading:
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.55)
                    .frame(width: 10, height: 10)
                Text(String(localized: "lithos.balance.loading", defaultValue: "Checking balance…"))
                    .font(BalanceCardStyle.messageFont)
                    .foregroundStyle(WhaleTheme.labelTint)
            }
        case .loaded(let amount):
            Text(verbatim: amount)
                .font(BalanceCardStyle.amountFont)
                .foregroundStyle(WhaleTheme.contentTint)
                .monospacedDigit()
        case .failed(let message):
            Text(message)
                .font(BalanceCardStyle.messageFont)
                .foregroundStyle(WhaleTheme.labelTint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var sessionButton: some View {
        if store.hasSession {
            Button(String(localized: "lithos.balance.signOut", defaultValue: "Sign out")) {
                store.signOut()
            }
            .buttonStyle(.link)
            .font(BalanceCardStyle.actionFont)
        } else if !store.isRefreshing && !store.isSigningOut {
            Button(String(localized: "lithos.balance.signIn", defaultValue: "Sign in")) {
                store.signIn()
            }
            .buttonStyle(.link)
            .font(BalanceCardStyle.actionFont)
        }
    }
}

#Preview("LithosAI · 已登录") {
    LithosBalanceSection(store: .preview(enabled: true, state: .loaded("$24.94")))
        .padding(15)
        .frame(width: PopoverView.width)
}
