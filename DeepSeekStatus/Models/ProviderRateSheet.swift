import Foundation

/// 某一家服务商的一档价格，用于弹窗里的价目对比。
///
/// 倍数统一以 **DeepSeek 官方高峰价** 为 1×，也就是面板上 DeepSeek 卡里那个「×1.0」。
/// 两家的数字都用这把尺，才能直接比。
struct ProviderRate: Identifiable, Equatable {
    /// 档位名称，不翻译（服务商自己的叫法）。
    let name: String
    /// 相对 DeepSeek 官方高峰价的倍数，**固定不变**。
    let multiplier: Double

    var id: String { name }
}

/// 一家服务商的价目。
struct ProviderRateSheet: Identifiable, Equatable {
    enum Policy: Equatable {
        /// 分时计价：价格由当前时段决定（DeepSeek 官方：高峰 1×、空闲 0.5×）。
        case timeOfDay(peak: ProviderRate, offPeak: ProviderRate)
        /// 不分时段，任何时候都是同一个价（LithosAI）。
        case flat
    }

    /// 服务商名称，不翻译。
    let name: String
    /// 列出的档位。
    let rates: [ProviderRate]
    let policy: Policy
    /// 是否是限时优惠价（要在界面上注明）。
    let isLimitedTimeOffer: Bool

    var id: String { name }

    /// 是否随时段变价。这是两家唯一的行为差异，界面上靠它决定要不要给档位标「now」。
    var variesWithTimeOfDay: Bool {
        switch policy {
        case .timeOfDay: true
        case .flat: false
        }
    }

    /// 这一档的显示倍数——就是它自己，**不乘也不除当前时段**。
    ///
    /// 曾经这里除以了 `period.priceMultiplier`，结果谷价时把 LithosAI 整体抬了一倍
    /// （Base 从 0.5× 变成 1×）。LithosAI 的限时优惠价本来就是按 DeepSeek 的峰谷标价
    /// 定好的固定倍数，不分峰谷，所以任何时候都原样显示。
    func displayedMultiplier(of rate: ProviderRate) -> Double {
        rate.multiplier
    }

    /// 当前时段是否正在收这一档的价。
    ///
    /// 只对分时计价的服务商有意义：DeepSeek 的 Peak / Off-peak 里只有一条在生效。
    /// LithosAI 三档同时在卖，永远返回 `false`，界面上也就不会给它加「now」。
    func isCharging(_ rate: ProviderRate, in period: PricePeriod) -> Bool {
        guard case .timeOfDay(let peak, let offPeak) = policy else { return false }
        return (period == .peak ? peak : offPeak).name == rate.name
    }

    /// DeepSeek 官方分时价。
    static let deepSeek = ProviderRateSheet(
        name: "DeepSeek",
        rates: [ProviderRate(name: "Peak", multiplier: 1.0),
                ProviderRate(name: "Off-peak", multiplier: 0.5)],
        policy: .timeOfDay(peak: ProviderRate(name: "Peak", multiplier: 1.0),
                           offPeak: ProviderRate(name: "Off-peak", multiplier: 0.5)),
        isLimitedTimeOffer: false
    )

    /// LithosAI 的三档，按它现在的限时优惠价折算：
    /// Base 档等于 DeepSeek 官方谷价（0.5×），Fast、Ultra 分别是 Base 的 1⅔ 倍和 2⅓ 倍。
    ///
    /// 它不分峰谷，这三档在一天里任何时刻都是同一个价，显示值也恒为
    /// Base ×0.50、Fast ×0.83、Ultra ×1.17。
    static let lithos = ProviderRateSheet(
        name: "LithosAI",
        rates: [ProviderRate(name: "Base", multiplier: 0.5),
                ProviderRate(name: "Fast", multiplier: 0.5 * 10 / 6),    // 1⅔ × Base
                ProviderRate(name: "Ultra", multiplier: 0.5 * 14 / 6)],  // 2⅓ × Base
        policy: .flat,
        isLimitedTimeOffer: true
    )

    static let all: [ProviderRateSheet] = [.deepSeek, .lithos]
}
