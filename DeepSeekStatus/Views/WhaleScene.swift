import CoreGraphics
import SwiftUI

/// 鲸鱼的动画绘制。
///
/// 高峰时段：小鲸鱼在水里游来游去 - 沿水平方向来回巡游，带上下浮沉、身体侧倾，
/// 尾部还会冒出一串气泡。
/// 空闲时段：小鲸鱼安静地睡觉 - 悬浮在原地轻轻呼吸，身体侧躺，头顶飘出「z z z」。
///
/// 所有动画都由 `TimelineView` 提供的绝对时间驱动，因此没有累积误差，
/// 也不会因为视图重建而跳帧。菜单栏和弹窗共用同一套绘制代码。
enum WhaleScene {

    /// 巡游一个来回需要的秒数。
    static let swimCycle: TimeInterval = 4.2

    /// 上下浮沉与身体侧倾的周期。
    static let bobPeriod: TimeInterval = 4.05

    /// 巡游时的身体侧倾幅度（度）。
    static let tiltDegrees: Double = 8

    /// 睡觉时身体侧躺的角度（度）。
    static let sleepTiltDegrees: Double = -7

    /// 睡觉时缓慢漂浮的周期。
    static let sleepFloatPeriod: TimeInterval = 7.4

    /// 睡觉时呼吸的周期。
    static let sleepBreathPeriod: TimeInterval = 6.0

    /// 菜单栏画布里鲸鱼两侧留出的空白。
    static let menuBarMargin: CGFloat = 2

    /// 菜单栏画布里鲸鱼身体的宽度：身体高度约占画布高度的 75%。
    static func menuBarWhaleWidth(forStageHeight height: CGFloat) -> CGFloat {
        height * DeepSeekWhale.aspectRatio * 0.75
    }

    /// 游泳时的重绘帧率。菜单栏里的小动画不需要跑满刷新率，
    /// 限制帧率可以显著降低长时间运行时的 CPU 占用。
    static let menuBarFrameRate: Double = 20

    /// 睡觉时动作更细微，帧率可以更低。
    static let sleepFrameRate: Double = 12

    // MARK: - 入口

    /// 根据时段绘制鲸鱼。
    static func draw(in context: inout GraphicsContext,
                     size: CGSize,
                     time: TimeInterval,
                     period: PricePeriod,
                     whaleWidth: CGFloat,
                     palette: WhalePalette,
                     showsBubbles: Bool = true,
                     showsSleepMarks: Bool = true) {
        guard size.width > 1, size.height > 1 else { return }
        WhaleRenderStats.frames &+= 1
        switch period {
        case .peak:
            drawSwimming(in: &context, size: size, time: time, whaleWidth: whaleWidth,
                         palette: palette, showsBubbles: showsBubbles)
        case .offPeak:
            drawSleeping(in: &context, size: size, time: time, whaleWidth: whaleWidth,
                         palette: palette, showsSleepMarks: showsSleepMarks)
        }
    }

    // MARK: - 高峰：游来游去

    static func drawSwimming(in context: inout GraphicsContext,
                             size: CGSize,
                             time: TimeInterval,
                             whaleWidth: CGFloat,
                             palette: WhalePalette,
                             showsBubbles: Bool) {
        let margin: CGFloat = 2
        let bodyWidth = min(whaleWidth, max(4, size.width - margin * 2))
        let bodyHeight = DeepSeekWhale.height(forWidth: bodyWidth)

        // 0 → 1 → 0 的往返进度，端点处用余弦缓动，转身更自然。
        let u = (time / swimCycle).truncatingRemainder(dividingBy: 1)
        let triangle = u < 0.5 ? u * 2 : (1 - u) * 2
        let eased = 0.5 - 0.5 * cos(triangle * .pi)
        let facingLeft = u >= 0.5

        let travel = max(0, size.width - bodyWidth - margin * 2)
        let x = margin + travel * eased

        // 上下浮沉 + 身体侧倾，两者频率相同但相位不同，看起来像真的在游。
        let verticalRoom = max(0, size.height - bodyHeight)
        let bob = sin(time * 1.55) * verticalRoom * 0.26
        let y = verticalRoom / 2 + bob
        let tilt = sin(time * 1.55 + 0.75) * 8

        let transform = whaleTransform(x: x, y: y,
                                       width: bodyWidth, height: bodyHeight,
                                       tiltDegrees: tilt, mirrored: facingLeft)
        fillWhale(in: &context, palette: palette, size: CGSize(width: bodyWidth, height: bodyHeight), transform: transform)

        guard showsBubbles else { return }
        drawBubbles(in: &context, size: size, time: time,
                    bodyOrigin: CGPoint(x: x, y: y),
                    bodySize: CGSize(width: bodyWidth, height: bodyHeight),
                    facingLeft: facingLeft, palette: palette)
    }

    /// 尾部气泡：从鲸鱼身后升起，一边上升一边淡出。
    private static func drawBubbles(in context: inout GraphicsContext,
                                    size: CGSize,
                                    time: TimeInterval,
                                    bodyOrigin: CGPoint,
                                    bodySize: CGSize,
                                    facingLeft: Bool,
                                    palette: WhalePalette) {
        let unit = bodySize.width / 20
        let tailX = facingLeft ? bodyOrigin.x + bodySize.width * 0.92 : bodyOrigin.x + bodySize.width * 0.08
        let direction: CGFloat = facingLeft ? 1 : -1

        for index in 0..<3 {
            let offset = Double(index) * 0.34
            let progress = ((time * 0.42) + offset).truncatingRemainder(dividingBy: 1)
            let radius = (0.75 + Double(index) * 0.4) * unit
            let point = CGPoint(
                x: tailX + direction * (2.5 + progress * 7) * unit,
                y: bodyOrigin.y + bodySize.height * 0.72 - progress * (bodySize.height + 7 * unit)
            )
            guard point.y > -4 else { continue }
            var bubbleContext = context
            bubbleContext.opacity = (1 - progress) * 0.55
            let rect = CGRect(x: point.x - radius, y: point.y - radius,
                              width: radius * 2, height: radius * 2)
            bubbleContext.fill(Path(ellipseIn: rect), with: .color(palette.bubble))
        }
    }

    // MARK: - 空闲：安静地睡觉

    static func drawSleeping(in context: inout GraphicsContext,
                             size: CGSize,
                             time: TimeInterval,
                             whaleWidth: CGFloat,
                             palette: WhalePalette,
                             showsSleepMarks: Bool) {
        let margin: CGFloat = 2
        let bodyWidth = min(whaleWidth, max(4, size.width - margin * 2))
        let bodyHeight = DeepSeekWhale.height(forWidth: bodyWidth)

        // 轻微呼吸 + 慢慢上下漂浮。
        let breath = 1 + sin(time * 1.05) * 0.022
        let renderedWidth = bodyWidth * breath
        let renderedHeight = bodyHeight * breath
        let verticalRoom = max(0, size.height - renderedHeight)

        // 睡觉的鲸鱼停在画面中间（略微偏左，给右边升起的「z」留出空间）。
        let x = (size.width - renderedWidth) / 2 - size.width * 0.04
        let y = verticalRoom / 2 + sin(time * 0.85) * verticalRoom * 0.14
        let tilt = -7 + sin(time * 0.6) * 1.6

        let transform = whaleTransform(x: x, y: y,
                                       width: renderedWidth, height: renderedHeight,
                                       tiltDegrees: tilt, mirrored: false)
        fillWhale(in: &context, palette: palette, size: CGSize(width: renderedWidth, height: renderedHeight), transform: transform)

        guard showsSleepMarks else { return }
        drawSleepMarks(in: &context, time: time,
                       origin: CGPoint(x: x, y: y),
                       bodySize: CGSize(width: renderedWidth, height: renderedHeight),
                       palette: palette)
    }

    /// 头顶飘出的「z」：从鲸鱼右侧上方升起，避免和尾巴叠在一起。
    ///
    /// 这里用路径描边画「z」而不是用 `Text`：菜单栏每秒要重绘十几次，
    /// 每帧做一次文字排版完全没有必要，路径要便宜得多，效果也更统一。
    private static func drawSleepMarks(in context: inout GraphicsContext,
                                       time: TimeInterval,
                                       origin: CGPoint,
                                       bodySize: CGSize,
                                       palette: WhalePalette) {
        let markSize = max(3.5, bodySize.width * 0.15)
        let start = CGPoint(x: origin.x + bodySize.width * 1.06,
                            y: origin.y + bodySize.height * 0.30)

        for index in 0..<3 {
            let progress = ((time * 0.30) + Double(index) / 3).truncatingRemainder(dividingBy: 1)
            let point = CGPoint(
                x: start.x + CGFloat(progress) * bodySize.width * 0.24,
                y: start.y - CGFloat(progress) * bodySize.height * 0.60
            )
            let size = markSize * (1 + CGFloat(progress) * 0.30)

            var markContext = context
            markContext.opacity = sin(progress * .pi) * 0.9
            markContext.stroke(zMarkPath(at: point, size: size),
                               with: .color(palette.sleepMark),
                               style: StrokeStyle(lineWidth: size * 0.20,
                                                  lineCap: .round,
                                                  lineJoin: .round))
        }
    }

    /// 一个「z」字形：上横、斜线、下横。菜单栏的 Core Animation 版本也用它。
    static func zMarkPath(at center: CGPoint, size: CGFloat) -> Path {
        let halfWidth = size * 0.5
        let halfHeight = size * 0.5
        var path = Path()
        path.move(to: CGPoint(x: center.x - halfWidth, y: center.y - halfHeight))
        path.addLine(to: CGPoint(x: center.x + halfWidth, y: center.y - halfHeight))
        path.addLine(to: CGPoint(x: center.x - halfWidth, y: center.y + halfHeight))
        path.addLine(to: CGPoint(x: center.x + halfWidth, y: center.y + halfHeight))
        return path
    }

    // MARK: - 公共几何

    /// 把 0×0 处的鲸鱼路径搬到目标位置，并做旋转 / 镜像。
    private static func whaleTransform(x: CGFloat,
                                       y: CGFloat,
                                       width: CGFloat,
                                       height: CGFloat,
                                       tiltDegrees: Double,
                                       mirrored: Bool) -> CGAffineTransform {
        let center = CGPoint(x: width / 2, y: height / 2)
        return CGAffineTransform(translationX: -center.x, y: -center.y)
            .concatenating(CGAffineTransform(rotationAngle: CGFloat(tiltDegrees * .pi / 180)))
            .concatenating(CGAffineTransform(scaleX: mirrored ? -1 : 1, y: 1))
            .concatenating(CGAffineTransform(translationX: x + center.x, y: y + center.y))
    }

    private static func fillWhale(in context: inout GraphicsContext,
                                  palette: WhalePalette,
                                  size: CGSize,
                                  transform: CGAffineTransform) {
        let path = DeepSeekWhale.cachedPath(fitting: CGRect(origin: .zero, size: size))
        var whaleContext = context
        whaleContext.transform = transform
        if palette.isFlat {
            whaleContext.fill(path, with: .color(palette.fillColors[0]))
        } else {
            whaleContext.fill(path, with: .linearGradient(
                Gradient(colors: palette.fillColors),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: size.width * 0.35, y: size.height)
            ))
        }
    }
}

/// 渲染计数，仅用于开发自检（例如测量菜单栏动画的真实帧率）。
/// 只在主线程访问。
enum WhaleRenderStats {
    static var frames: UInt64 = 0
}
