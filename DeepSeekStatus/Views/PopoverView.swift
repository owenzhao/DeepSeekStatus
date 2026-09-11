import SwiftUI

/// 菜单栏图标的弹窗面板。
struct PopoverView: View {
    /// 面板宽度。窗口定位和内容布局都用这个值。
    static let width: CGFloat = 320

    @ObservedObject var store: PricingStore
    var onQuit: () -> Void

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
            Text("预览中：正在显示「\(period.title)」的样子")
            Spacer(minLength: 0)
            Button("恢复实时") { store.previewPeriod = nil }
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
                Text("×\(String(format: "%.1f", period.priceMultiplier))")
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
                Text("当前单价")
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
                Text("距离「\(snapshot.nextPeriod.title)」还有")
                    .font(.system(size: 11.5, weight: .medium))
                Spacer()
                Text(PricingFormatter.duration(snapshot.secondsUntilTransition))
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            Text("\(PricingFormatter.transitionDescription(snapshot.nextTransition, relativeTo: snapshot.now)) 起转为\(snapshot.nextPeriod.title)")
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
            Text("时段规则")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            ruleRow(color: WhaleTheme.brandBlue,
                    title: "高峰",
                    detail: "周一至周五 09:00 – 12:00、14:00 – 18:00")
            ruleRow(color: Color.secondary.opacity(0.35),
                    title: "空闲",
                    detail: "其余时间（含周末全天）")

            WeekScheduleGrid(now: snapshot.now)

            Text(footnote)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func ruleRow(color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 9, height: 9)
                .padding(.top, 2)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, alignment: .leading)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var footnote: String {
        let beijing = "所有时间均为北京时间（UTC+8）。"
        let localOffset = TimeZone.current.secondsFromGMT()
        guard localOffset != DeepSeekPricing.timeZone.secondsFromGMT() else { return beijing }
        return beijing + "你本机时区为 \(TimeZone.current.identifier)。"
    }

    // MARK: - 选项

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle("在菜单栏显示倒计时", isOn: $store.showsCountdownInMenuBar)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 11.5))
                .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("开机自动启动", isOn: $store.launchAtLogin)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 11.5))
                .frame(maxWidth: .infinity, alignment: .leading)

            if let message = store.launchAtLoginMessage {
                Text(message)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Text("预览")
                    .font(.system(size: 11.5))
                Spacer()
                Picker("预览", selection: $store.previewPeriod) {
                    Text("自动").tag(nil as PricePeriod?)
                    Text("高峰").tag(PricePeriod.peak as PricePeriod?)
                    Text("空闲").tag(PricePeriod.offPeak as PricePeriod?)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 170)
            }
        }
    }

    // MARK: - 页脚

    private var footerSection: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("DeepSeek Status 1.0")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("退出") { onQuit() }
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
