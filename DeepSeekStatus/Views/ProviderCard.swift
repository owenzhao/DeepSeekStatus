import SwiftUI

/// 一个服务商的一张卡片：名称行 + 它自己的余额（或 Key / 登录状态）+ 它自己的价格。
///
/// 之前余额归一张卡、价格归面板顶部，两家的信息是交错的：看到 LithosAI 的 ¥/$ 数字，
/// 要抬头去上面找它的档位；看到 DeepSeek 的价，又不知道它现在收了多少钱。
/// 现在按服务商切块——一张卡就是一家，看谁的信息都不用跳。
///
/// 卡片本身只负责排版和底色，里外的具体内容都由调用方给：
/// - `accessory`：名称行右端贴边的控件（DeepSeek 是 API Key，LithosAI 是开关）；
/// - `content`：名称行下面的余额 / 状态；
/// - `rates`：价格行，没有就整块不出现（比如 LithosAI 关掉或未登录时）。
struct ProviderCard<Accessory: View, Content: View, Rates: View>: View {
    let name: String
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content
    @ViewBuilder var rates: () -> Rates

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(verbatim: name)
                    .font(BalanceCardStyle.nameFont)
                    .foregroundStyle(WhaleTheme.contentTint)
                Spacer(minLength: 6)
                accessory()
            }

            content()
            rates()
        }
        .padding(BalanceCardStyle.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BalanceCardStyle.cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

/// 价格行最多三行（LithosAI 的 Base / Fast / Ultra）。
///
/// 每行：档位名 + 右对齐的倍数。DeepSeek 只有一行（当前时段的价），
/// 倍数一律以 **DeepSeek 官方高峰价 = ×1** 为固定尺，不随时段换算：
/// LithosAI 的限时优惠价本身就按这把尺定（Base = DeepSeek 谷价 0.5×），
/// 它不分峰谷，所以这三行任何时刻都是同一组数字。
struct ProviderRateRows: View {
    let period: PricePeriod
    let sheet: ProviderRateSheet
    /// 是否要附一行说明这把尺。LithosAI 的报价容易和自己余额的币种混看，需要解释一次。
    var showsScaleNote = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(sheet.rates) { rate in
                row(rate)
            }
            if showsScaleNote {
                Text(String(localized: "rates.comparison.footnote",
                            defaultValue: "×1 = DeepSeek peak price. Limited-time prices, the same all day."))
                    .font(.system(size: 9))
                    .foregroundStyle(WhaleTheme.labelTint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 1)
            }
        }
    }

    private func row(_ rate: ProviderRate) -> some View {
        let current = sheet.isCharging(rate, in: period)
        return HStack(spacing: 5) {
            // DeepSeek 只有一个时段在收钱，所以档名旁边直接标出「now」；
            // LithosAI 三档同时在卖，档名自己就够了。
            HStack(spacing: 4) {
                Text(verbatim: rate.name)
                    .font(.system(size: 10.5, weight: current ? .semibold : .regular))
                    .foregroundStyle(current ? WhaleTheme.contentTint : WhaleTheme.labelTint)
                if current {
                    Text(String(localized: "rates.now", defaultValue: "now"))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WhaleTheme.accent(for: period))
                }
            }

            Spacer(minLength: 4)

            Text(verbatim: PricingFormatter.multiplier(sheet.displayedMultiplier(of: rate)))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(current ? WhaleTheme.accent(for: period) : WhaleTheme.contentTint)
                .help(String(localized: "rates.help.reference",
                             defaultValue: "Relative to DeepSeek’s peak price"))
        }
    }
}
