import AppKit
import SwiftUI

/// 菜单栏图标的弹窗面板。
struct PopoverView: View {
    /// 面板宽度。窗口定位和内容布局都用这个值。
    static let width: CGFloat = 320

    @ObservedObject var store: PricingStore
    var onQuit: () -> Void
    /// 自动检查更新开关 + 手动检查回调。
    /// 刻意用 `Binding` / 闭包而不是直接引用 Sparkle，离屏渲染工具才能不链接 Sparkle 编译这些视图。
    var automaticallyChecksForUpdates: Binding<Bool> = .constant(false)
    var onCheckForUpdates: () -> Void = {}

    private var period: PricePeriod { store.period }
    private var snapshot: PricingSnapshot { store.snapshot }

    var body: some View {
        VStack(spacing: 0) {
            AquariumView(period: period, now: snapshot.now)
            if store.isPreviewing {
                previewBanner
            }
            VStack(alignment: .leading, spacing: 10) {
                headerSection
                priceSection
                countdownSection
                Divider()
                scheduleSection
                Divider()
                optionsSection
                footerSection
            }
            .padding(15)
        }
        .frame(width: Self.width)
    }

    // MARK: - 预览提示

    private var previewBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "eye")
            Text(String(format: String(localized: "popover.preview.banner",
                                      defaultValue: "Previewing: showing “%@”"),
                        period.title))
            Spacer(minLength: 0)
            Button(String(localized: "popover.preview.resume", defaultValue: "Resume live")) {
                store.previewPeriod = nil
            }
            .buttonStyle(.link)
            .font(.system(size: 10.5, weight: .semibold))
        }
        .font(.system(size: 10.5))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(WhaleTheme.accent(for: period).opacity(0.16))
    }

    // MARK: - 状态

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(period.title)
                    .font(.system(size: 19, weight: .bold))
                Spacer()
                Text(verbatim: "×\(String(format: "%.1f", period.priceMultiplier))")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(WhaleTheme.accent(for: period))
            }
            Text(period.summary)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var priceSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(String(localized: "popover.currentRate", defaultValue: "Current rate"))
                    .font(.system(size: 11.5, weight: .medium))
                Spacer()
                Text(period.priceText)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(WhaleTheme.accent(for: period))
            }
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
            .frame(height: 6)
        }
    }

    private var countdownSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(String(format: String(localized: "popover.countdown.title",
                                          defaultValue: "Time until “%@”"),
                            snapshot.nextPeriod.title))
                    .font(.system(size: 11.5, weight: .medium))
                Spacer()
                Text(PricingFormatter.duration(snapshot.secondsUntilTransition))
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            Text(String(format: String(localized: "popover.countdown.detail",
                                      defaultValue: "Switches to %2$@ %1$@"),
                        PricingFormatter.transitionDescription(snapshot.nextTransition, relativeTo: snapshot.now),
                        snapshot.nextPeriod.title))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            // 当前时段的进度：自定义细条比 ProgressView 更紧凑。
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.14))
                    Capsule()
                        .fill(WhaleTheme.accent(for: period).opacity(0.85))
                        .frame(width: max(3, geometry.size.width * snapshot.intervalProgress))
                }
            }
            .frame(height: 3)
        }
    }

    // MARK: - 规则

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "popover.schedule.title", defaultValue: "Schedule rules"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            ruleRow(color: WhaleTheme.brandBlue,
                    title: PricePeriod.peak.shortTitle,
                    detail: String(localized: "popover.schedule.peak.detail",
                                   defaultValue: "Mon–Fri 09:00 – 12:00, 14:00 – 18:00"))
            ruleRow(color: Color.secondary.opacity(0.35),
                    title: PricePeriod.offPeak.shortTitle,
                    detail: String(localized: "popover.schedule.offPeak.detail",
                                   defaultValue: "All other times (including weekends)"))

            WeekScheduleGrid(now: snapshot.now)

            Text(footnote)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 规则标签列的宽度。
    ///
    /// 标签随语言变化（英文 "Off-peak" 比中文「空闲」宽得多），固定一个宽度会在某一种语言下
    /// 要么换行、要么把右侧说明挤到换行，所以这里按当前语言实测最宽的那个标签取列宽。
    private static let ruleLabelWidth: CGFloat = {
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let widest = [PricePeriod.peak.shortTitle, PricePeriod.offPeak.shortTitle]
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 26
        return ceil(widest) + 4
    }()

    private func ruleRow(color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 9, height: 9)
                .padding(.top, 2)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: Self.ruleLabelWidth, alignment: .leading)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var footnote: String {
        let beijing = String(localized: "popover.footnote.beijing",
                             defaultValue: "All times are Beijing time (UTC+8).")
        let localOffset = TimeZone.current.secondsFromGMT()
        guard localOffset != DeepSeekPricing.timeZone.secondsFromGMT() else { return beijing }
        // 英文的这句带前导空格（接在上一句后面），中文不带；所以空格写进译文里。
        return beijing + String(format: String(localized: "popover.footnote.localZone",
                                              defaultValue: " Your local time zone is %@."),
                                TimeZone.current.identifier)
    }

    // MARK: - 选项

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            settingToggle(String(localized: "popover.option.countdown",
                                  defaultValue: "Show countdown in menu bar"),
                          isOn: $store.showsCountdownInMenuBar)

            settingToggle(String(localized: "popover.option.launchAtLogin", defaultValue: "Launch at login"),
                          isOn: $store.launchAtLogin)

            if let message = store.launchAtLoginMessage {
                Text(message)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Text(String(localized: "popover.preview.label", defaultValue: "Preview"))
                    .font(.system(size: 11.5))
                Spacer()
                Picker(String(localized: "popover.preview.label", defaultValue: "Preview"),
                       selection: $store.previewPeriod) {
                    Text(String(localized: "popover.preview.auto", defaultValue: "Auto"))
                        .tag(nil as PricePeriod?)
                    Text(PricePeriod.peak.shortTitle).tag(PricePeriod.peak as PricePeriod?)
                    Text(PricePeriod.offPeak.shortTitle).tag(PricePeriod.offPeak as PricePeriod?)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 170)
            }

            settingToggle(String(localized: "popover.option.autoUpdate",
                                 defaultValue: "Auto-check for updates"),
                          isOn: automaticallyChecksForUpdates)

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Button(String(localized: "popover.update.checkNow", defaultValue: "Check Now")) {
                    onCheckForUpdates()
                }
                .buttonStyle(.link)
                .font(.system(size: 10.5, weight: .semibold))
            }
        }
    }

    /// 所有开关统一成一行：文案占满左侧、开关固定贴右边缘。
    /// 直接写 `Toggle` 时它只有内容宽度，开关会跟着文案长短左右跳，三行就对不齐了。
    private func settingToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 11.5))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
    }

    // MARK: - 页脚

    /// 「DeepSeek Status <版本号>」。版本号直接读 bundle（`MARKETING_VERSION`），
    /// 避免升级版本后页脚忘记同步。名字不翻译。
    private static let versionText: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.1"
        return "DeepSeek Status \(version)"
    }()

    private var footerSection: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(Self.versionText)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
            Spacer()
            Button(String(localized: "popover.quit", defaultValue: "Quit")) { onQuit() }
                .buttonStyle(.link)
                .font(.system(size: 11, weight: .medium))
        }
    }
}

#Preview("弹窗 · 高峰") {
    PopoverView(store: PricingStore(now: Date()), onQuit: {})
}

#Preview("弹窗 · 空闲") {
    let store = PricingStore(now: Date())
    store.previewPeriod = .offPeak
    return PopoverView(store: store, onQuit: {})
}
