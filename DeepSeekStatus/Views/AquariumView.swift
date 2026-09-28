import SwiftUI

/// 弹窗顶部的水族箱：鲸鱼在里面游来游去，或者安静地睡觉。
///
/// 氛围元素（气泡 / 星星）和鲸鱼合并到同一块 `Canvas`、同一个 `TimelineView` 里。
/// 它们原本各挂一个计时器（20fps + 30fps），两个计时器互不同步，等于每秒要做 50 次
/// 画布绘制和 50 次布局；合并之后只剩 20 次，动作也天然同步。
struct AquariumView: View {
    let period: PricePeriod
    let now: Date
    /// 水族箱是否真的在屏幕上。
    ///
    /// 面板收起走的是 `orderOut`，窗口连同整棵视图树都还活着。而 `TimelineView` 一旦开始计时，
    /// 把窗口移出屏幕并不会让它停下 —— 实测收起后 Canvas 仍然全速重绘、常驻 CPU 约 12%，
    /// 比打开面板时还费电。所以收起时直接把 `TimelineView` 从视图树里摘掉：
    /// 没有订阅者的 timeline 不会触发任何重绘。
    var isVisible: Bool = true
    var height: CGFloat = 134
    var whaleWidth: CGFloat = 100
    /// 重绘帧率。20fps 和菜单栏图标一致，肉眼已经看不出跳帧。
    var frameRate: Double = 20
    /// 固定时刻（离屏快照用；`nil` 表示播放动画）。
    var fixedTime: TimeInterval?

    var body: some View {
        ZStack {
            background
            if isVisible {
                animation
            }
            overlay
        }
        .frame(height: height)
        .clipped()
    }

    // MARK: - 动画

    @ViewBuilder
    private var animation: some View {
        if let fixedTime {
            canvas(at: fixedTime)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / frameRate)) { timeline in
                canvas(at: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func canvas(at time: TimeInterval) -> some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            var canvas = context
            // 画布可能比水族箱大一点（`.clipped()` 之前），裁掉越界部分。
            canvas.clip(to: Path(CGRect(origin: .zero, size: size)))
            drawDecorations(in: &canvas, size: size, time: time)
            WhaleScene.draw(in: &canvas,
                            size: size,
                            time: time,
                            period: period,
                            whaleWidth: whaleWidth,
                            palette: .aquarium(for: period))
        }
        .allowsHitTesting(false)
    }

    // MARK: - 氛围元素

    /// 高峰时是上升的气泡，空闲时是星星和月亮。
    private func drawDecorations(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        guard size.width > 10, size.height > 10 else { return }
        switch period {
        case .peak:
            drawBubbles(in: &context, size: size, time: time)
        case .offPeak:
            drawNight(in: &context, size: size, time: time)
        }
    }

    /// 高峰：缓慢上升的小气泡。
    private func drawBubbles(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        for index in 0..<9 {
            let seedX = Self.pseudoRandom(index, 1)
            let seedSpeed = 0.045 + Self.pseudoRandom(index, 2) * 0.05
            let radius = 1.2 + Self.pseudoRandom(index, 3) * 2.4
            let progress = ((time * seedSpeed) + Self.pseudoRandom(index, 4)).truncatingRemainder(dividingBy: 1)
            let x = size.width * (0.05 + seedX * 0.9) + sin(time * 0.8 + Double(index)) * 3
            let y = size.height + 6 - progress * (size.height + 16)
            var bubble = context
            bubble.opacity = sin(progress * .pi) * 0.4
            bubble.stroke(Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                                 width: radius * 2, height: radius * 2)),
                          with: .color(.white.opacity(0.7)), lineWidth: 0.8)
        }
    }

    /// 空闲：星星 + 一弯月亮。
    private func drawNight(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        for index in 0..<26 {
            let x = size.width * Self.pseudoRandom(index, 11)
            let y = size.height * 0.78 * Self.pseudoRandom(index, 12)
            let radius = 0.5 + Self.pseudoRandom(index, 13) * 0.9
            let twinkle = 0.35 + 0.45 * (0.5 + 0.5 * sin(time * (0.7 + Self.pseudoRandom(index, 14)) + Double(index)))
            var star = context
            star.opacity = twinkle
            star.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                             width: radius * 2, height: radius * 2)),
                      with: .color(.white))
        }

        // 月亮：用两个圆做差集得到月牙（放在右上角文字的下方，避免重叠）。
        let moonRadius: CGFloat = 13
        let moonCenter = CGPoint(x: size.width - 52, y: 52)
        var moon = Path()
        moon.addEllipse(in: CGRect(x: moonCenter.x - moonRadius, y: moonCenter.y - moonRadius,
                                   width: moonRadius * 2, height: moonRadius * 2))
        moon.addEllipse(in: CGRect(x: moonCenter.x - moonRadius + 6.5, y: moonCenter.y - moonRadius - 3.5,
                                   width: moonRadius * 2, height: moonRadius * 2))
        var moonContext = context
        moonContext.opacity = 0.85
        moonContext.fill(moon, with: .color(Color(red: 0.90, green: 0.93, blue: 1.0)),
                         style: FillStyle(eoFill: true))
    }

    /// 固定的伪随机数，保证每帧的星星/气泡位置一致。
    private static func pseudoRandom(_ index: Int, _ salt: Double) -> Double {
        let value = sin(Double(index) * 12.9898 + salt * 78.233) * 43758.5453
        return value - value.rounded(.down)
    }

    // MARK: - 背景

    private var background: some View {
        ZStack {
            LinearGradient(colors: period == .peak
                           ? [WhaleTheme.tankTop, WhaleTheme.tankBottom]
                           : [WhaleTheme.tankTopSleep, WhaleTheme.tankBottomSleep],
                           startPoint: .top, endPoint: .bottom)
            // 水面透下来的光。
            RadialGradient(colors: [Color.white.opacity(period == .peak ? 0.16 : 0.07), .clear],
                           center: UnitPoint(x: 0.5, y: -0.1),
                           startRadius: 4, endRadius: 190)
        }
    }

    // MARK: - 信息浮层

    private var overlay: some View {
        VStack {
            HStack(alignment: .top) {
                Spacer()
                Text(String(localized: "aquarium.beijingTime", defaultValue: "Beijing time"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            HStack {
                statusBadge
                Spacer()
            }
        }
        .padding(12)
    }

    private var statusBadge: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(WhaleTheme.accent(for: period))
                .frame(width: 7, height: 7)
                .shadow(color: WhaleTheme.accent(for: period).opacity(0.9), radius: 3)
            Text(period.title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
            Text(PricingFormatter.preciseTime(now))
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
    }
}

#Preview("水族箱 · 高峰") {
    AquariumView(period: .peak, now: Date())
        .frame(width: 320)
}

#Preview("水族箱 · 空闲") {
    AquariumView(period: .offPeak, now: Date())
        .frame(width: 320)
}
