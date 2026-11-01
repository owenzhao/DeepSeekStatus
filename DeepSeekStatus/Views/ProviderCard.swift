import AppKit
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

/// 价格行：一家服务商一个模型一行，只写最低档的价和它标称的速度。
///
/// 每行：模型名 + 右对齐的倍数 + 官方承诺的输出速度。一个模型卖好几档，其余档位放在
/// 鼠标悬停时冒出的泡泡里（每档各自的倍数和速度），不占版面——四个模型九档价全铺开的话，
/// 最该看的「这家最便宜多少钱」反而要翻半天才找得到。
///
/// 之前试过点信息按钮就地展开：展开后档位行要缩进，倍数那一列和收起时的行首对不齐，
/// 一开一合数字会左右跳一格。悬停泡泡不参与布局，这张表也就永远保持同一套对齐。
///
/// 倍数一律以 **DeepSeek 官方高峰价 = ×1** 为固定尺，不随时段换算：
/// LithosAI 的限时优惠价本身就按这把尺定（DeepSeek V4.1 Flash 的 Base = DeepSeek 谷价 0.5×），
/// 它不分峰谷，所以这些行任何时刻都是同一组数字。
struct ProviderRateRows: View {
    let period: PricePeriod
    let sheet: ProviderRateSheet
    /// 是否要附一行说明这把尺。LithosAI 的报价容易和自己余额的币种混看，需要解释一次。
    var showsScaleNote = false
    /// 价目块最下面的那行说明（LithosAI 的限时优惠提醒）。
    ///
    /// 它必须待在这块里面：块外的文字是后面绘制的兄弟，会把悬停泡泡盖住。
    var notice: String?
    /// 离屏快照用：直接指定哪个模型冒泡泡。界面上永远是 `nil`，由鼠标悬停决定。
    var previewHoveredModel: String?

    /// 鼠标正停在哪个模型上（按模型名记）。
    @State private var hoveredModel: String? = nil

    init(period: PricePeriod,
         sheet: ProviderRateSheet,
         showsScaleNote: Bool = false,
         notice: String? = nil,
         previewHoveredModel: String? = nil) {
        self.period = period
        self.sheet = sheet
        self.showsScaleNote = showsScaleNote
        self.notice = notice
        self.previewHoveredModel = previewHoveredModel
    }

    /// 卖多个模型时才拆成「模型 + 最低档」的行；DeepSeek 只有一套价目，一行就是当前时段的价。
    private var showsModelNames: Bool {
        sheet.groups.contains { $0.model != nil }
    }

    /// 鼠标停在哪个模型上（离屏快照时可以强行指定）。
    private var activeHover: String? { previewHoveredModel ?? hoveredModel }

    /// 这个模型现在要不要冒泡泡。只有一档的模型没什么可展开的，悬停也不冒。
    private func showsBubble(_ group: ProviderRateGroup) -> Bool {
        group.rates.count > 1 && activeHover == group.id
    }

    /// 泡泡现在盖住的行：都在悬停行的下面。这些行直接隐掉，否则泡泡的底边会把某一行的
    /// 字从中间切开，看着像串字。行本身还在原处，鼠标照样能移过去换一个模型看。
    private func isCovered(_ index: Int) -> Bool {
        guard let hovered = activeHover,
              let hoveredIndex = sheet.groups.firstIndex(where: { $0.id == hovered }),
              showsBubble(sheet.groups[hoveredIndex]) else { return false }
        return index > hoveredIndex
    }

    /// 有没有泡泡正开着（两块说明文字在泡泡面前让位）。
    private var isBubbleVisible: Bool {
        sheet.groups.contains { showsBubble($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(sheet.groups.enumerated()), id: \.element.id) { index, group in
                if showsModelNames {
                    groupRow(group, index: index)
                        .opacity(isCovered(index) ? 0 : 1)
                } else {
                    ForEach(group.rates) { rate in
                        row(rate)
                    }
                }
            }
            if showsScaleNote {
                Text(String(localized: "rates.comparison.footnote",
                            defaultValue: "×1 = DeepSeek’s peak output price. The same all day."))
                    .font(.system(size: 9))
                    .foregroundStyle(WhaleTheme.labelTint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 1)
                    .opacity(isBubbleVisible ? 0 : 1)
            }
            if let notice {
                Text(verbatim: notice)
                    .font(.system(size: 9))
                    .foregroundStyle(WhaleTheme.labelTint)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(isBubbleVisible ? 0 : 1)
            }
        }
        // 给泡泡留出最后一行底下的空间：它一律往下挂，最后一行（GLM-5.3-Flash）的泡泡
        // 正好会顶到这段说明下面。没有这点余量，泡泡就会顶出卡片，被下面的「时段规则」压住。
        // 代价是这一块高 8pt，换来的是一进一出位置固定、任何时候都不会互相压字。
        .padding(.bottom, 8)
        .coordinateSpace(name: Self.rowSpace)
        // 泡泡挂在这整块的最外层，而不是挂在被悬停的那一行里。
        // 挂在行里的话，它和行是同级的，后面几行和脚注会盖在它上面——实测两者会互相透出来。
        // 放这里它是最后一个绘制的内容，永远在最上层。
        // `alignment: .topLeading` 是关键：overlay 默认按中心对齐，那样 offset 就不是从左上角算的，
        // 泡泡会莫名其妙地往下偏一行多。左上对齐之后，行 frame 的 minX/minY 可以直接当偏移量用。
        .overlayPreferenceValue(RowFrames.self, alignment: .topLeading) { frames in
            GeometryReader { proxy in
                if let hovered = activeHover,
                   let frame = frames[hovered],
                   let group = sheet.groups.first(where: { $0.id == hovered }),
                   showsBubble(group) {
                    // 一律往下挂：泡泡永远在它自己那一行的下面，模型名就还看得见。
                    // 曾经按空间够不够决定往上还是往下翻，结果同样的操作一会儿朝上一会儿朝下，
                    // 而且往上翻的那几行会把标题挡住。
                    tierBubble(group)
                        .frame(width: frame.width)
                        .offset(x: frame.minX, y: frame.maxY + 2)
                }
            }
        }
    }

    /// 行位置记录用的坐标空间名（只在这块视图内部用）。
    private static let rowSpace = "rates.rows"


    /// 一个模型的一行：名字 + 最低档的价和速度，悬停时在下面冒出全部档位的泡泡。
    private func groupRow(_ group: ProviderRateGroup, index: Int) -> some View {
        let bubble = showsBubble(group)
        return HStack(spacing: 5) {
            Text(verbatim: group.model ?? "")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WhaleTheme.contentTint)

            Spacer(minLength: 4)

            if let lowest = group.rates.first {
                multiplierLabel(lowest, current: false)
                speedLabel(lowest.speed)
            }

            // 小图标只提示「这里有更多档位」，真正的开关是悬停；只卖一档的模型留空占位，
            // 上面几行的倍数和速度才对得齐。
            if group.rates.count > 1 {
                Image(systemName: "info.circle")
                    .font(.system(size: 9.5))
                    .foregroundStyle(WhaleTheme.labelTint)
                    .frame(width: 12, height: 14)
            } else {
                Color.clear.frame(width: 12, height: 14)
            }
        }
        .padding(.top, index == 0 ? 0 : 3)
        // 行首左边多铺出去一点，悬停时的高亮才不是紧贴着文字。
        .padding(.horizontal, 3)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(bubble ? 0.06 : 0))
        )
        .background(
            HoverArea { inside in
                guard group.rates.count > 1 else { return }
                if inside {
                    hoveredModel = group.id
                } else if hoveredModel == group.id {
                    hoveredModel = nil
                }
            }
        )
        // 把自己的位置报给外层的 overlay，泡泡就挂在这一行的正下方。
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: RowFrames.self,
                    value: [group.id: proxy.frame(in: .named(Self.rowSpace))]
                )
            }
        )
    }

    /// 悬停泡泡：把这个模型的每一档摊开，价和速度并排。
    ///
    /// 宽度撑满整行、左右各留 3pt（和行自己的内边距一致），里面的档位行结构和卡片里完全一样，
    /// 所以泡泡里的倍数、速度和卡片那几列是同一个 x——悬停时数字不会跳。
    private func tierBubble(_ group: ProviderRateGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(group.rates) { rate in
                HStack(spacing: 5) {
                    row(rate)
                    // 补上和卡片行一样的图标位，倍数和速度才对得齐。
                    Color.clear.frame(width: 12, height: 14)
                }
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                // 深色模式下窗口底色和卡片底色几乎一样，泡泡的边界会糊掉；
                // 叠一层 6% 的前景色（深色模式下就是白），两种模式都能浮起来。
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )

        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.16))
        )
        .allowsHitTesting(false)
    }

    /// 一档的价格行：档位名 + 倍数 + 速度。
    private func row(_ rate: ProviderRate) -> some View {
        let current = sheet.isCharging(rate, in: period)
        return HStack(spacing: 5) {
            // DeepSeek 只有一个时段在收钱，所以档名旁边直接标出「now」；
            // LithosAI 各档同时在卖，档名自己就够了。
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

            multiplierLabel(rate, current: current)
            speedLabel(rate.speed)
        }
    }

    /// 右对齐的倍数。固定宽度，好让同一列的数字上下对齐。
    private func multiplierLabel(_ rate: ProviderRate, current: Bool) -> some View {
        Text(verbatim: PricingFormatter.multiplier(sheet.displayedMultiplier(of: rate)))
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(current ? WhaleTheme.accent(for: period) : WhaleTheme.contentTint)
            .frame(width: 46, alignment: .trailing)
            .help(String(localized: "rates.help.reference",
                         defaultValue: "Relative to DeepSeek’s peak price"))
    }

    /// 官方标称的单用户输出速度。没标速度的时候也占住位置，倍数才不会左右跳。
    private func speedLabel(_ speed: String?) -> some View {
        Text(verbatim: speed.map { "\($0) tok/s" } ?? "")
            .font(.system(size: 9))
            .monospacedDigit()
            .foregroundStyle(WhaleTheme.labelTint)
            // 76pt 刚好装得下最长的「250–1000 tok/s」（70.7pt）；再窄就会被截成 250–1000 to…
            .frame(width: 76, alignment: .leading)
            .help(String(localized: "rates.speed.help",
                         defaultValue: "Output speed the provider advertises per user"))
    }
}

/// 一行价目的鼠标进出检测。
///
/// 这个面板是 `.nonactivatingPanel`：点开它时 App 往往仍然不是活动应用，窗口也不一定是 key。
/// SwiftUI 的 `.onHover` 依赖活动窗口的跟踪区域，在这种面板里可能一声不吭，泡泡就永远不出现。
/// 所以这里自己挂一条 `.activeAlways` 的 `NSTrackingArea`——不管 App 在不在前台都照发进出事件。
private struct HoverArea: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSView { View(onChange: onChange) }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? View)?.onChange = onChange
    }

    final class View: NSView {
        var onChange: (Bool) -> Void

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(rect: .zero,
                                           options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self))
        }

        override func mouseEntered(with event: NSEvent) { onChange(true) }
        override func mouseExited(with event: NSEvent) { onChange(false) }

        /// 只盯着鼠标，不要抢这一行的点击。
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// 每个模型那一行在这块价目里的位置，泡泡靠它定位。
private struct RowFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
