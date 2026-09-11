import SwiftUI

/// 一块透明画布，鲸鱼在里面游泳或睡觉。
///
/// 弹窗顶部的水族箱用它（以及离屏渲染工具）。菜单栏图标不用它 ——
/// 见 `WhaleStatusItemView`：在 `NSStatusItem` 里每帧重绘 SwiftUI 太贵，
/// 菜单栏那份是用 Core Animation 实现的。
struct WhaleStage: View {
    let period: PricePeriod
    /// 固定尺寸；传 `nil` 表示填满父视图给出的空间。
    var size: CGSize? = CGSize(width: 46, height: 22)
    /// 鲸鱼身体的宽度；`nil` 时按画布高度自动推算。
    var whaleWidth: CGFloat?
    /// 配色；`nil` 时使用适合菜单栏的一套。
    var palette: WhalePalette?
    var showsBubbles: Bool = true
    var showsSleepMarks: Bool = true
    /// 重绘帧率；`nil` 时按状态取默认值（游泳 20fps、睡觉 12fps）。
    var frameRate: Double?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // 用 `.periodic` 而不是 `.animation`：`.animation` 会按屏幕刷新率驱动（实测 60fps），
        // `.periodic` 才能真正把帧率压下来。
        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0),
                               by: 1.0 / (frameRate ?? Self.defaultFrameRate(for: period)))) { timeline in
            Canvas(opaque: false, rendersAsynchronously: false) { context, canvasSize in
                var canvas = context
                canvas.clip(to: Path(CGRect(origin: .zero, size: canvasSize)))
                WhaleScene.draw(
                    in: &canvas,
                    size: canvasSize,
                    time: timeline.date.timeIntervalSinceReferenceDate,
                    period: period,
                    whaleWidth: whaleWidth ?? Self.defaultWhaleWidth(for: canvasSize),
                    palette: palette ?? .menuBar(for: period, dark: colorScheme == .dark),
                    showsBubbles: showsBubbles,
                    showsSleepMarks: showsSleepMarks
                )
            }
        }
        .frame(width: size?.width, height: size?.height)
        .frame(maxWidth: size == nil ? .infinity : nil,
               maxHeight: size == nil ? .infinity : nil)
        .accessibilityLabel(period.title)
    }

    /// 默认帧率：游泳的动作幅度大，给 20fps；睡觉只有细微呼吸，12fps 就够。
    static func defaultFrameRate(for period: PricePeriod) -> Double {
        period == .peak ? WhaleScene.menuBarFrameRate : WhaleScene.sleepFrameRate
    }

    static func defaultWhaleWidth(for size: CGSize) -> CGFloat {
        WhaleScene.menuBarWhaleWidth(forStageHeight: size.height)
    }
}

#Preview("鲸鱼舞台") {
    VStack(spacing: 16) {
        WhaleStage(period: .peak, palette: .aquarium(for: .peak))
            .background(WhaleTheme.tankBottom)
        WhaleStage(period: .offPeak, palette: .aquarium(for: .offPeak))
            .background(WhaleTheme.tankBottomSleep)
    }
    .padding(20)
}
