import SwiftUI

/// 弹窗里的「账户余额」区块。
///
/// - 没保存 Key 时，右上角按钮是「输入 API Key」；
/// - 有 Key 时是「刷新」，按钮后面紧跟着最近一次刷新时间，再往后是「更换 API Key」；
/// - 刷新失败（尤其是 Key 失效）时，除了报错文案还会一直给出「更换 API Key」的入口，
///   保证 Key 失效之后用户永远能换成新的。
struct BalanceSection: View {

    @ObservedObject var store: BalanceStore

    /// 刷新时间的格式化：跟随界面语言，用本地时区（这是用户自己的操作时刻）。
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = PricingFormatter.displayLocale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    // MARK: - 标题行（余额 / 刷新按钮 / 刷新时间 / 更换 Key）

    private var header: some View {
        HStack(spacing: 6) {
            Text(String(localized: "balance.title", defaultValue: "Account balance"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 6)

            if store.isEditingKey {
                // 编辑中不摆刷新 / 更换入口，避免和编辑器里的「保存 / 取消」混在一起。
                EmptyView()
            } else if store.hasKey {
                refreshButton
                if let lastRefreshed = store.lastRefreshed {
                    Text(refreshedLabel(lastRefreshed))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                changeKeyButton
            } else {
                enterKeyButton
            }
        }
    }

    private var refreshButton: some View {
        Button { store.refresh() } label: {
            HStack(spacing: 3) {
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.55)
                        .frame(width: 9, height: 9)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9.5, weight: .semibold))
                }
                Text(String(localized: "balance.refresh", defaultValue: "Refresh"))
            }
        }
        .buttonStyle(.link)
        .font(.system(size: 10.5, weight: .semibold))
        .disabled(store.isRefreshing)
    }

    private var enterKeyButton: some View {
        Button { store.beginEditingKey() } label: {
            HStack(spacing: 3) {
                Image(systemName: "key")
                    .font(.system(size: 9.5, weight: .semibold))
                Text(String(localized: "balance.enterKey", defaultValue: "Enter API Key"))
            }
        }
        .buttonStyle(.link)
        .font(.system(size: 10.5, weight: .semibold))
    }

    private var changeKeyButton: some View {
        Button { store.beginEditingKey() } label: {
            Image(systemName: "key")
                .font(.system(size: 9.5, weight: .semibold))
        }
        .buttonStyle(.link)
        .help(String(localized: "balance.key.changeHelp",
                     defaultValue: "Change the saved API key"))
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if store.isEditingKey {
            keyEditor
        } else {
            switch store.state {
            case .noKey:
                Text(String(localized: "balance.noKey.hint",
                            defaultValue: "Add an API key to see your balance here."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

            case .loading:
                HStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.55)
                        .frame(width: 10, height: 10)
                    Text(String(localized: "balance.loading", defaultValue: "Refreshing…"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

            case .loaded(let balance):
                balanceRows(balance)

            case .failed(let error):
                failureRows(error)
            }
        }
    }

    // MARK: - 余额

    @ViewBuilder
    private func balanceRows(_ balance: DeepSeekBalance) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if balance.balanceInfos.isEmpty {
                Text(String(localized: "balance.empty", defaultValue: "No balance information."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(balance.balanceInfos) { info in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: info.amount(info.totalBalance))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(verbatim: breakdown(info))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            if !balance.isAvailable {
                warningRow(String(localized: "balance.unavailable",
                                  defaultValue: "Not enough balance — API calls are paused."))
            }
        }
    }

    /// 「赠送 ¥10.00 · 充值 ¥100.00」。
    private func breakdown(_ info: DeepSeekBalance.BalanceInfo) -> String {
        let granted = String(format: String(localized: "balance.granted", defaultValue: "Granted %@"),
                             info.amount(info.grantedBalance))
        let toppedUp = String(format: String(localized: "balance.toppedUp", defaultValue: "Topped up %@"),
                              info.amount(info.toppedUpBalance))
        return "\(granted) · \(toppedUp)"
    }

    // MARK: - 失败

    @ViewBuilder
    private func failureRows(_ error: BalanceError) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            warningRow(error.errorDescription ?? "")

            HStack(spacing: 10) {
                // Key 本身有问题时，把「更换」放在前面：重试大概率还是同样的结果。
                if error.suggestsReplacingKey {
                    changeKeyLink
                    retryLink
                } else {
                    retryLink
                    changeKeyLink
                }
            }
        }
    }

    private var retryLink: some View {
        linkButton(String(localized: "balance.retry", defaultValue: "Retry")) {
            store.refresh()
        }
    }

    private var changeKeyLink: some View {
        linkButton(String(localized: "balance.key.change", defaultValue: "Change API Key")) {
            store.beginEditingKey()
        }
    }

    // MARK: - API Key 编辑器

    private var keyEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            SecureField(String(localized: "balance.key.placeholder", defaultValue: "sk-…"),
                        text: $store.keyDraft)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .controlSize(.small)
                .onSubmit { store.saveKey() }

            Text(String(localized: "balance.key.hint",
                        defaultValue: "Create a key at platform.deepseek.com. It is stored in your Keychain."))
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let keyError = store.keyError {
                Text(keyError)
                    .font(.system(size: 9.5))
                    .foregroundStyle(WhaleTheme.peakAccent)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                if store.hasKey {
                    linkButton(String(localized: "balance.key.remove", defaultValue: "Remove")) {
                        store.removeKey()
                    }
                }
                Spacer(minLength: 0)
                linkButton(String(localized: "balance.key.cancel", defaultValue: "Cancel")) {
                    store.cancelEditingKey()
                }
                Button(String(localized: "balance.key.save", defaultValue: "Save")) {
                    store.saveKey()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .font(.system(size: 10.5, weight: .semibold))
            }
        }
    }

    // MARK: - 小工具

    private func warningRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 9.5))
                .foregroundStyle(WhaleTheme.peakAccent)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.link)
            .font(.system(size: 10.5, weight: .semibold))
    }

    /// 「更新于 14:32」。
    private func refreshedLabel(_ date: Date) -> String {
        String(format: String(localized: "balance.updated", defaultValue: "Updated %@"),
               Self.timeFormatter.string(from: date))
    }
}

#Preview("余额 · 已加载") {
    BalanceSection(store: .preview())
        .padding(15)
        .frame(width: PopoverView.width)
}

#Preview("余额 · 未填 Key") {
    BalanceSection(store: .preview(state: .noKey, hasKey: false, lastRefreshed: nil))
        .padding(15)
        .frame(width: PopoverView.width)
}

#Preview("余额 · Key 失效") {
    BalanceSection(store: .preview(state: .failed(.unauthorized)))
        .padding(15)
        .frame(width: PopoverView.width)
}
