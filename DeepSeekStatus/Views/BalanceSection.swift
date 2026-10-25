import SwiftUI

/// 弹窗里的「账户余额」区块。
///
/// 卡片里有两个并列的服务商区块：DeepSeek 和 LithosAI。两家的排版完全一致
/// （名称行 + 贴右边缘的控件 + 金额行，见 `BalanceProviderBlock`），中间用一条淡线分开；
/// 卡片标题行只留「刷新」和最近一次刷新时间，两家共享。
///
/// - DeepSeek 的 API Key 入口挂在 DeepSeek 区块自己的名称行右侧（没 Key 时是「输入 API Key」，
///   有 Key 时是「API Key」），和 LithosAI 的开关处在同一条视觉边线上；
/// - 刷新失败（尤其是 Key 失效）时，除了报错文案还会一直给出「更换 API Key」的入口，
///   保证 Key 失效之后用户永远能换成新的。
struct BalanceSection: View {

    @ObservedObject var store: BalanceStore
    @ObservedObject var lithos: LithosBalanceStore

    /// 刷新时间的格式化：跟随界面语言，用本地时区（这是用户自己的操作时刻）。
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = PricingFormatter.displayLocale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: BalanceCardStyle.blockSpacing) {
            header

            BalanceProviderBlock(name: "DeepSeek") {
                keyAccessory
            } content: {
                deepSeekDetail
            }

            BalanceCardSeparator()

            LithosBalanceSection(store: lithos)
        }
        .padding(BalanceCardStyle.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BalanceCardStyle.cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    // MARK: - 标题行（余额 / 刷新时间 / 刷新）

    /// 标题行只放两件事：卡片叫什么，以及这份数据是什么时候拉的。
    /// 「更新于」和标题同色，只靠更小的字号往后退，读起来是「1:11 PM 更新过，现在可以再刷」。
    private var header: some View {
        HStack(spacing: 8) {
            Text(String(localized: "balance.title", defaultValue: "Account balance"))
                .font(BalanceCardStyle.titleFont)
                .foregroundStyle(WhaleTheme.labelTint)

            Spacer(minLength: 8)

            if store.isEditingKey {
                // 编辑中不摆刷新入口，避免和编辑器里的「保存 / 取消」混在一起。
                EmptyView()
            } else if store.hasKey || lithos.enabled {
                if let lastRefreshed = commonRefreshTime {
                    Text(refreshedLabel(lastRefreshed))
                        .font(BalanceCardStyle.metaFont)
                        .foregroundStyle(WhaleTheme.labelTint)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                refreshButton
            }
        }
    }

    private var refreshButton: some View {
        Button {
            store.refresh()
            if lithos.enabled { lithos.refresh() }
        } label: {
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
        .font(BalanceCardStyle.actionFont)
        .disabled(store.isRefreshing || (lithos.enabled && lithos.isRefreshing))
    }

    private var commonRefreshTime: Date? {
        guard store.hasKey else { return lithos.enabled ? lithos.lastRefreshed : nil }
        guard let deepSeekTime = store.lastRefreshed else { return nil }
        guard lithos.enabled else { return deepSeekTime }
        guard let lithosTime = lithos.lastRefreshed else { return nil }
        return min(deepSeekTime, lithosTime)
    }

    // MARK: - API Key 入口（DeepSeek 区块的名称行右侧）

    /// 和 LithosAI 的开关处在同一条视觉边线上：名称行右端就是这个服务商的控件。
    /// 刷新失败时不再放这里，因为失败文案下面已经有明文的「更换 API Key」。
    @ViewBuilder
    private var keyAccessory: some View {
        if store.isEditingKey {
            EmptyView()
        } else if !store.hasKey {
            keyLink(String(localized: "balance.enterKey", defaultValue: "Enter API Key"))
        } else if case .failed = store.state {
            EmptyView()
        } else {
            keyLink(String(localized: "balance.key.manage", defaultValue: "API Key"))
        }
    }

    private func keyLink(_ title: String) -> some View {
        Button { store.beginEditingKey() } label: {
            HStack(spacing: 3) {
                Image(systemName: "key")
                    .font(.system(size: 9.5, weight: .semibold))
                Text(title)
            }
        }
        .buttonStyle(.link)
        .font(BalanceCardStyle.actionFont)
        .help(String(localized: "balance.key.changeHelp",
                     defaultValue: "Change the saved API key"))
    }

    // MARK: - 内容

    @ViewBuilder
    private var deepSeekDetail: some View {
        if store.isEditingKey {
            keyEditor
        } else {
            switch store.state {
            case .noKey:
                Text(String(localized: "balance.noKey.hint",
                            defaultValue: "Add an API key to see your balance here."))
                    .font(BalanceCardStyle.messageFont)
                    .foregroundStyle(WhaleTheme.labelTint)
                    .fixedSize(horizontal: false, vertical: true)

            case .loading:
                HStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.55)
                        .frame(width: 10, height: 10)
                    Text(String(localized: "balance.loading", defaultValue: "Refreshing…"))
                        .font(BalanceCardStyle.messageFont)
                        .foregroundStyle(WhaleTheme.labelTint)
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
                    .font(BalanceCardStyle.messageFont)
                    .foregroundStyle(WhaleTheme.labelTint)
            } else {
                ForEach(balance.balanceInfos) { info in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: info.amount(info.totalBalance))
                            .font(BalanceCardStyle.amountFont)
                            .foregroundStyle(WhaleTheme.contentTint)
                            .monospacedDigit()
                        Text(verbatim: breakdown(info))
                            .font(BalanceCardStyle.captionFont)
                            .foregroundStyle(WhaleTheme.labelTint)
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
                .foregroundStyle(WhaleTheme.labelTint)
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
                .font(BalanceCardStyle.actionFont)
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
                .font(BalanceCardStyle.captionFont)
                .foregroundStyle(WhaleTheme.labelTint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.link)
            .font(BalanceCardStyle.actionFont)
    }

    /// 「更新于 14:32」。
    private func refreshedLabel(_ date: Date) -> String {
        String(format: String(localized: "balance.updated", defaultValue: "Updated %@"),
               Self.timeFormatter.string(from: date))
    }
}

#Preview("余额 · 已加载") {
    BalanceSection(store: .preview(), lithos: .preview())
        .padding(15)
        .frame(width: PopoverView.width)
}

#Preview("余额 · 两家都开启") {
    BalanceSection(store: .preview(), lithos: .preview(enabled: true, state: .loaded("$24.94")))
        .padding(15)
        .frame(width: PopoverView.width)
}

#Preview("余额 · 未填 Key") {
    BalanceSection(store: .preview(state: .noKey, hasKey: false, lastRefreshed: nil), lithos: .preview())
        .padding(15)
        .frame(width: PopoverView.width)
}

#Preview("余额 · Key 失效") {
    BalanceSection(store: .preview(state: .failed(.unauthorized)), lithos: .preview())
        .padding(15)
        .frame(width: PopoverView.width)
}
