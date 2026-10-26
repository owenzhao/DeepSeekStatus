import SwiftUI

/// 弹窗里的「账户」区：按服务商切成两张卡，每张卡里放这一家自己的**全部**信息。
///
/// 两家的规则本来就不一样——DeepSeek 用 API Key、按时段计费；LithosAI 要网页登录、
/// 一天一个价——混在一张卡里就会互相干扰。所以这里一人一张卡：
///
/// - DeepSeek 卡：时段（Peak / Off-peak）、倍数、费率条、距下次切换的倒计时，接着是余额；
/// - LithosAI 卡：开关、余额、三档报价。
///
/// 时段和倍数以前散在面板顶部，和余额隔着半屏，现在都归到 DeepSeek 卡里；动画（水族箱）
/// 仍在最上面，两家共用。
///
/// 卡片标题行只留「账户」和共享的刷新时间；DeepSeek 的卡片总有（没 Key 时提示去填），
/// LithosAI 的卡片会整个消失，只要开关是关着的——关掉之后连卡片都不该出现在界面上。
struct AccountSection: View {

    @ObservedObject var store: BalanceStore
    @ObservedObject var lithos: LithosBalanceStore

    /// 当前时段的完整快照：时段、倍数、费率、切换倒计时都从这里取。
    let snapshot: PricingSnapshot
    /// 当前时段。
    let period: PricePeriod

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

            ProviderCard(name: "DeepSeek") {
                keyAccessory
            } content: {
                deepSeekStatus
                Divider().overlay(Color.primary.opacity(0.07))
                deepSeekDetail
            } rates: {
                EmptyView()
            }

            if showsLithos {
                ProviderCard(name: "LithosAI") {
                    lithosToggle
                } content: {
                    lithosDetail
                } rates: {
                    if lithos.hasSession {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(String(localized: "rates.rateLabel", defaultValue: "Rate"))
                                .font(BalanceCardStyle.metaFont)
                                .foregroundStyle(WhaleTheme.labelTint)
                            Text(String(localized: "rates.limitedTime.badge", defaultValue: "Limited time"))
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(WhaleTheme.peakAccent)
                                .fixedSize()
                                .padding(.horizontal, 3)
                                .padding(.vertical, 0.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(WhaleTheme.peakAccent.opacity(0.14))
                                )
                            Spacer(minLength: 0)
                        }
                        ProviderRateRows(period: period, sheet: .lithos, showsScaleNote: true)
                        Text(String(localized: "rates.limitedTime.note",
                                    defaultValue: "LithosAI’s prices are a limited-time offer and may change."))
                            .font(.system(size: 9))
                            .foregroundStyle(WhaleTheme.labelTint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - 标题行（账户 / 刷新时间 / 刷新）

    /// 标题行只放两件事：这块叫什么，以及这份数据是什么时候拉的。
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

    // MARK: - DeepSeek 卡

    /// DeepSeek 自己的计费状态：现在是什么时段、几倍价、多久之后切换。
    /// 这几行以前在面板顶部，和余额隔得很远；现在它们就是 DeepSeek 卡的第一段。
    private var deepSeekStatus: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(period.title)
                    .font(.system(size: 15, weight: .bold))
                Spacer(minLength: 6)
                Text(verbatim: "×\(String(format: "%.1f", period.priceMultiplier))")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(WhaleTheme.accent(for: period))
            }

            Text(statusDetail)
                .font(.system(size: 10.5))
                .foregroundStyle(WhaleTheme.labelTint)
                .fixedSize(horizontal: false, vertical: true)

            // 费率条：长度就是当前倍数，和上面那个「×0.5」是同一条尺。
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.16))
                    Capsule()
                        .fill(LinearGradient(colors: [WhaleTheme.accent(for: period).opacity(0.75),
                                                      WhaleTheme.accent(for: period)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geometry.size.width * period.priceMultiplier))
                }
            }
            .frame(height: 5)

            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 9.5))
                    .foregroundStyle(WhaleTheme.labelTint)
                Text(String(format: String(localized: "popover.countdown.detail",
                                          defaultValue: "Switches to %2$@ %1$@"),
                            PricingFormatter.transitionDescription(snapshot.nextTransition, relativeTo: snapshot.now),
                            snapshot.nextPeriod.title))
                    .font(.system(size: 9.5))
                    .foregroundStyle(WhaleTheme.labelTint)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Text(PricingFormatter.duration(snapshot.secondsUntilTransition))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(WhaleTheme.contentTint)
            }
        }
    }

    /// 当天为什么是这个价：节假日 / 周末 / 普通工作日各有说法。
    private var statusDetail: String {
        switch snapshot.dayInfo.kind {
        case .publicHoliday, .alternateWorkdayWeekend:
            snapshot.dayInfo.localizedDetail
        case .weekend, .regularWeekday:
            period.summary
        }
    }

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

    // MARK: - LithosAI 卡片

    /// 开关关掉就连卡片一起收起来，不留一张空壳。
    private var showsLithos: Bool { lithos.enabled }

    private var lithosToggle: some View {
        Toggle(isOn: Binding(get: { lithos.enabled }, set: { lithos.setEnabled($0) })) {
            // 名称已经在卡片标题里了，开关自己不带文案。
            Text(verbatim: "LithosAI")
        }
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.mini)
        .accessibilityLabel(Text(verbatim: "LithosAI"))
    }

    @ViewBuilder
    private var lithosDetail: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            lithosStateText
            Spacer(minLength: 0)
            lithosSessionButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var lithosStateText: some View {
        switch lithos.state {
        case .signedOut:
            Text(lithos.isSigningOut
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
    private var lithosSessionButton: some View {
        if lithos.hasSession {
            Button(String(localized: "lithos.balance.signOut", defaultValue: "Sign out")) {
                lithos.signOut()
            }
            .buttonStyle(.link)
            .font(BalanceCardStyle.actionFont)
        } else if !lithos.isRefreshing && !lithos.isSigningOut {
            Button(String(localized: "lithos.balance.signIn", defaultValue: "Sign in")) {
                lithos.signIn()
            }
            .buttonStyle(.link)
            .font(BalanceCardStyle.actionFont)
        }
    }

    // MARK: - DeepSeek 余额

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

#Preview("账户 · 已加载") {
    AccountSection(store: .preview(), lithos: .preview(), snapshot: .init(now: Date()), period: .peak)
        .padding(15)
        .frame(width: PopoverView.width)
}

#Preview("账户 · 两家都开启") {
    AccountSection(store: .preview(),
                   lithos: .preview(enabled: true, state: .loaded("$24.94")),
                   snapshot: .init(now: Date()),
                   period: .offPeak)
        .padding(15)
        .frame(width: PopoverView.width)
}

#Preview("账户 · 未填 Key") {
    AccountSection(store: .preview(state: .noKey, hasKey: false, lastRefreshed: nil),
                   lithos: .preview(),
                   snapshot: .init(now: Date()),
                   period: .peak)
        .padding(15)
        .frame(width: PopoverView.width)
}
