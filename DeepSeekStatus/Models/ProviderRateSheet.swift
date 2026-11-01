import Foundation

/// 某一家服务商在一个模型上的一档价格，用于弹窗里的价目对比。
///
/// 倍数统一以 **DeepSeek 官方高峰价** 为 1×，也就是面板上 DeepSeek 卡里那个「×1.0」。
/// 各家的数字都用这把尺，才能直接比。
struct ProviderRate: Identifiable, Equatable {
    /// 档位名称，不翻译（服务商自己的叫法）。
    let name: String
    /// 相对 DeepSeek 官方高峰价的倍数，**固定不变**。
    let multiplier: Double
    /// 官方标称的单用户输出速度，只要数字部分（`"80+"`、`"250–1000"`，单位 tok/s）。
    /// 价目页没标速度的留空，界面上就只显示价格。
    let speed: String?

    init(name: String, multiplier: Double, speed: String? = nil) {
        self.name = name
        self.multiplier = multiplier
        self.speed = speed
    }

    var id: String { name }
}

/// 一家服务商在一个模型下的全部档位。
///
/// 同一家会同时卖好几个模型，每个模型又各有 Base / Fast / Ultra 里的一档或几档，
/// 所以价目按模型分组。不同模型的价格不能互相换算，只能各自对着同一把尺看。
///
/// `rates` 按 Base → Fast → Ultra 从低到高排列：界面默认只显示第一档（最低档）的价格，
/// 其余档位收在信息按钮后面。
struct ProviderRateGroup: Identifiable, Equatable {
    /// 模型名，不翻译。`nil` 表示这家只有一套价目、不需要分模型（DeepSeek 官方）。
    let model: String?
    let rates: [ProviderRate]

    var id: String { model ?? "" }
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
    /// 列出的价目，按模型分组。
    let groups: [ProviderRateGroup]
    let policy: Policy
    /// 是否是限时优惠价（要在界面上注明）。
    let isLimitedTimeOffer: Bool

    var id: String { name }

    /// 全部档位，分组拍平。只看「这一家卖哪些档」的地方（比如自检）用它。
    var rates: [ProviderRate] { groups.flatMap(\.rates) }

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
    /// LithosAI 各档同时在卖，永远返回 `false`，界面上也就不会给它加「now」。
    func isCharging(_ rate: ProviderRate, in period: PricePeriod) -> Bool {
        guard case .timeOfDay(let peak, let offPeak) = policy else { return false }
        return (period == .peak ? peak : offPeak).name == rate.name
    }

    /// DeepSeek 官方分时价。
    static let deepSeek = ProviderRateSheet(
        name: "DeepSeek",
        groups: [ProviderRateGroup(model: nil,
                                   rates: [ProviderRate(name: "Peak", multiplier: 1.0),
                                           ProviderRate(name: "Off-peak", multiplier: 0.5)])],
        policy: .timeOfDay(peak: ProviderRate(name: "Peak", multiplier: 1.0),
                           offPeak: ProviderRate(name: "Off-peak", multiplier: 0.5)),
        isLimitedTimeOffer: false
    )

    /// DeepSeek 官方 V4.1 Flash 的高峰输出价（美元 / 百万 tokens），也是所有倍数的那把尺。
    /// LithosAI 那个 DeepSeek V4.1 Flash 的 Base 档正好是它的一半，所以是 0.5×。
    static let referenceOutputPrice = 1.20

    /// 把 LithosAI 某个模型的输出价（美元 / 百万 tokens）折成倍数。
    private static func lithosMultiplier(output: Double) -> Double {
        output / referenceOutputPrice
    }

    /// LithosAI 在卖的各个模型，按它价目页的限时优惠价折算：
    /// 模型输出价 ÷ DeepSeek 高峰输出价 $1.20。
    ///
    /// 它不分峰谷，这些档位在一天里任何时刻都是同一个价，显示值也恒定不变。
    /// 只列已经开卖的模型——Qwen 3.8、Gemma 4、GPT OSS 还没定价，自有模型按需报价。
    /// 每个模型的档位也不齐：GLM-5.3 只有 Base，GLM-5.3-Flash 只有 Base 和 Ultra。
    static let lithos = ProviderRateSheet(
        name: "LithosAI",
        groups: [
            ProviderRateGroup(model: "Kimi K3", rates: [
                ProviderRate(name: "Base", multiplier: lithosMultiplier(output: 12), speed: "80+"),
                ProviderRate(name: "Fast", multiplier: lithosMultiplier(output: 20), speed: "180+"),
                ProviderRate(name: "Ultra", multiplier: lithosMultiplier(output: 28), speed: "250–1000"),
            ]),
            ProviderRateGroup(model: "DeepSeek V4.1 Flash", rates: [
                ProviderRate(name: "Base", multiplier: lithosMultiplier(output: 0.6), speed: "250+"),
                ProviderRate(name: "Fast", multiplier: lithosMultiplier(output: 1), speed: "350+"),
                ProviderRate(name: "Ultra", multiplier: lithosMultiplier(output: 1.4), speed: "450+"),
            ]),
            ProviderRateGroup(model: "GLM-5.3", rates: [
                ProviderRate(name: "Base", multiplier: lithosMultiplier(output: 3.3), speed: "200+"),
            ]),
            ProviderRateGroup(model: "GLM-5.3-Flash", rates: [
                ProviderRate(name: "Base", multiplier: lithosMultiplier(output: 0.5), speed: "250+"),
                ProviderRate(name: "Ultra", multiplier: lithosMultiplier(output: 1), speed: "450+"),
            ]),
        ],
        policy: .flat,
        isLimitedTimeOffer: true
    )

    static let all: [ProviderRateSheet] = [.deepSeek, .lithos]
}
