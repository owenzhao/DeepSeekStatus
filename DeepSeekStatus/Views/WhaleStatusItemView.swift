import AppKit
import QuartzCore

/// 菜单栏图标视图。
///
/// 这里刻意**不用 SwiftUI**：在 `NSStatusItem` 里用 `TimelineView` + `Canvas` 每帧重绘，
/// 实测每次更新要花掉约 9ms（常驻约 11% CPU），瓶颈在 SwiftUI 的更新管线而不是绘制本身。
/// 改用 Core Animation 之后，动画由 WindowServer 侧的渲染进程驱动，
/// 应用本身只在状态切换时做一次工作，常驻 CPU 接近 0。
///
/// 动画参数与 SwiftUI 版（`WhaleScene`）保持一致，两处共用 `WhaleScene` 里的常量。
@MainActor
final class WhaleStatusItemView: NSView {

    // MARK: - 配置

    /// 菜单栏里鲸鱼画布的宽度。
    static let stageWidth: CGFloat = 46

    /// 菜单栏图标是否播放动画。
    ///
    /// 按目前的需求先做成静态图标；置为 `true` 即可恢复游泳 / 睡觉动画。
    static var animates = false

    private(set) var period: PricePeriod = .offPeak

    /// 菜单栏当前是不是深色（深色菜单栏上的系统图标是白色的）。
    private var isDarkMenuBar: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    // MARK: - 图层

    /// 整体位置（巡游 / 漂浮）。
    private let whaleContainer = CALayer()
    /// 身体侧倾旋转。
    private let tiltLayer = CALayer()
    /// 朝向镜像（游泳到右端后转身）。
    private let mirrorLayer = CALayer()
    /// 鲸鱼身体。
    private let whaleLayer = CAShapeLayer()
    private var bubbleLayers: [CAShapeLayer] = []
    private var sleepMarkLayers: [CAShapeLayer] = []
    private let countdownLabel = NSTextField(labelWithString: "")

    /// 记住上一次的配置，避免每秒重复重建动画。
    private var appliedCountdown: String?
    private var laidOutSize: CGSize = .zero

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    /// 让点击落到 `NSStatusItem` 的按钮上，而不是被这个视图吃掉。
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// 与 Core Graphics 一致：原点在左上角，y 向下。
    override var isFlipped: Bool { true }

    private func setup() {
        wantsLayer = true
        layer?.isGeometryFlipped = true
        layer?.masksToBounds = false

        whaleContainer.anchorPoint = .zero
        whaleContainer.masksToBounds = false

        tiltLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        tiltLayer.masksToBounds = false

        mirrorLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        mirrorLayer.masksToBounds = false

        whaleLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        whaleLayer.fillColor = NSColor.systemBlue.cgColor

        mirrorLayer.addSublayer(whaleLayer)
        tiltLayer.addSublayer(mirrorLayer)
        whaleContainer.addSublayer(tiltLayer)
        layer?.addSublayer(whaleContainer)

        countdownLabel.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        countdownLabel.textColor = .labelColor
        countdownLabel.alignment = .left
        countdownLabel.maximumNumberOfLines = 1
        addSubview(countdownLabel)
    }

    // MARK: - 对外接口

    /// 更新时段与倒计时文本。只有时段变化时才会重建动画。
    func update(period newPeriod: PricePeriod, countdown: String?) {
        let periodChanged = newPeriod != period
        period = newPeriod

        if appliedCountdown != countdown {
            appliedCountdown = countdown
            countdownLabel.stringValue = countdown ?? ""
            countdownLabel.isHidden = countdown == nil
        }

        if periodChanged || laidOutSize != bounds.size {
            rebuildAnimations()
        }
    }

    override func layout() {
        super.layout()
        if laidOutSize != bounds.size {
            rebuildAnimations()
        }
    }

    // MARK: - 自检

    /// 当前呈现层（presentation layer）的位置。
    ///
    /// Core Animation 的动画跑在渲染进程里，图层的 model 值并不会逐帧变化，
    /// 截图对比看不出动画是否在跑；取 `presentation()` 的值才能确认。
    var presentationPosition: CGPoint? {
        whaleContainer.presentation()?.position
    }

    /// 当前呈现层的旋转角度（弧度）。
    var presentationRotation: CGFloat? {
        let transform = tiltLayer.presentation()?.transform
        guard let transform else { return nil }
        return atan2(transform.m12, transform.m11)
    }

    // MARK: - 构建

    private func rebuildAnimations() {
        laidOutSize = bounds.size
        let size = bounds.size
        guard size.width > 1, size.height > 1 else { return }

        // 清空旧动画与旧图层。
        whaleContainer.removeAllAnimations()
        tiltLayer.removeAllAnimations()
        mirrorLayer.removeAllAnimations()
        whaleLayer.removeAllAnimations()
        bubbleLayers.forEach { $0.removeFromSuperlayer() }
        bubbleLayers.removeAll()
        sleepMarkLayers.forEach { $0.removeFromSuperlayer() }
        sleepMarkLayers.removeAll()

        layoutCountdown()

        let stageHeight = size.height
        let bodyWidth = WhaleScene.menuBarWhaleWidth(forStageHeight: stageHeight)
        let bodyHeight = DeepSeekWhale.height(forWidth: bodyWidth)
        let margin: CGFloat = 2
        let verticalRoom = max(0, stageHeight - bodyHeight)

        whaleContainer.bounds = CGRect(x: 0, y: 0, width: bodyWidth, height: bodyHeight)

        let whalePath = DeepSeekWhale.cachedPath(fitting: CGRect(x: 0, y: 0, width: bodyWidth, height: bodyHeight))
        whaleLayer.bounds = CGRect(x: 0, y: 0, width: bodyWidth, height: bodyHeight)
        whaleLayer.position = CGPoint(x: bodyWidth / 2, y: bodyHeight / 2)
        whaleLayer.path = whalePath.cgPath
        tiltLayer.bounds = whaleContainer.bounds
        tiltLayer.position = CGPoint(x: bodyWidth / 2, y: bodyHeight / 2)
        mirrorLayer.bounds = whaleContainer.bounds
        mirrorLayer.position = CGPoint(x: bodyWidth / 2, y: bodyHeight / 2)

        switch period {
        case .peak:
            buildSwimming(stageHeight: stageHeight, bodyWidth: bodyWidth, bodyHeight: bodyHeight,
                          margin: margin, verticalRoom: verticalRoom)
        case .offPeak:
            buildSleeping(stageHeight: stageHeight, bodyWidth: bodyWidth, bodyHeight: bodyHeight,
                          verticalRoom: verticalRoom)
        }
    }

    private func layoutCountdown() {
        guard !countdownLabel.isHidden else { return }
        let textWidth = min(countdownLabel.intrinsicContentSize.width,
                            max(0, bounds.width - Self.stageWidth - 6))
        let height = ceil(countdownLabel.intrinsicContentSize.height)
        countdownLabel.frame = NSRect(x: Self.stageWidth + 5,
                                      y: (bounds.height - height) / 2,
                                      width: max(0, textWidth),
                                      height: height)
    }

    /// 统一的颜色设置。
    private func applyColors(_ palette: WhalePalette) {
        let color = palette.fillColors[palette.fillColors.count / 2]
        whaleLayer.fillColor = NSColor(color).cgColor
    }

    // MARK: - 高峰：游来游去

    private func buildSwimming(stageHeight: CGFloat,
                               bodyWidth: CGFloat,
                               bodyHeight: CGFloat,
                               margin: CGFloat,
                               verticalRoom: CGFloat) {
        let palette = WhalePalette.menuBar(for: .peak, dark: isDarkMenuBar)
        applyColors(palette)
        mirrorLayer.transform = CATransform3DIdentity

        let travel = max(0, bounds.width - bodyWidth - margin * 2)
        let leftX = margin
        let rightX = margin + travel
        let baseY = (stageHeight - bodyHeight) / 2
        let bobAmplitude = verticalRoom * 0.26

        // 静态图标：鲸鱼停在画布中间，带一点仰角，气泡固定漂在尾后。
        guard Self.animates else {
            whaleContainer.position = CGPoint(x: margin + travel / 2, y: baseY)
            tiltLayer.transform = CATransform3DMakeRotation(-WhaleScene.tiltDegrees * .pi / 180, 0, 0, 1)
            buildBubbles(bodyWidth: bodyWidth, bodyHeight: bodyHeight,
                         palette: palette, static: true)
            return
        }

        whaleContainer.position = CGPoint(x: leftX, y: baseY)

        // 左右巡游：余弦缓动，两端自然减速转身。
        let move = CAKeyframeAnimation(keyPath: "position.x")
        move.values = [leftX, rightX, leftX]
        move.keyTimes = [0, 0.5, 1]
        move.timingFunctions = [.init(name: .easeInEaseOut), .init(name: .easeInEaseOut)]
        move.duration = WhaleScene.swimCycle
        move.repeatCount = .infinity
        whaleContainer.add(move, forKey: "swim.x")

        // 上下浮沉。
        let bob = CAKeyframeAnimation(keyPath: "position.y")
        bob.values = [baseY, baseY - bobAmplitude, baseY, baseY + bobAmplitude, baseY]
        bob.keyTimes = [0, 0.25, 0.5, 0.75, 1]
        bob.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
        bob.duration = WhaleScene.bobPeriod
        bob.repeatCount = .infinity
        whaleContainer.add(bob, forKey: "swim.y")

        // 身体侧倾。
        let tilt = CAKeyframeAnimation(keyPath: "transform.rotation")
        let tiltRadians = WhaleScene.tiltDegrees * .pi / 180
        tilt.values = [-tiltRadians, tiltRadians, -tiltRadians]
        tilt.keyTimes = [0, 0.5, 1]
        tilt.timingFunctions = [.init(name: .easeInEaseOut), .init(name: .easeInEaseOut)]
        tilt.duration = WhaleScene.bobPeriod
        tilt.repeatCount = .infinity
        tiltLayer.add(tilt, forKey: "swim.tilt")

        // 到端点时转身（水平镜像）。
        let flip = CAKeyframeAnimation(keyPath: "transform")
        let facingRight = NSValue(caTransform3D: CATransform3DIdentity)
        let facingLeft = NSValue(caTransform3D: CATransform3DMakeScale(-1, 1, 1))
        flip.values = [facingRight, facingRight, facingLeft, facingLeft]
        flip.keyTimes = [0, 0.4999, 0.5, 1]
        flip.calculationMode = .discrete
        flip.duration = WhaleScene.swimCycle
        flip.repeatCount = .infinity
        mirrorLayer.add(flip, forKey: "swim.facing")

        buildBubbles(bodyWidth: bodyWidth, bodyHeight: bodyHeight, palette: palette)
    }

    /// 尾后的气泡。
    private func buildBubbles(bodyWidth: CGFloat, bodyHeight: CGFloat,
                              palette: WhalePalette, static isStatic: Bool = false) {
        let unit = bodyWidth / 20
        let tailX = bodyWidth * 0.95
        let startY = bodyHeight * 0.72
        let riseDistance = bodyHeight + 7 * unit

        for index in 0..<3 {
            let radius = (0.75 + Double(index) * 0.4) * unit
            let bubble = CAShapeLayer()
            bubble.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
            bubble.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            bubble.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2),
                                 transform: nil)
            bubble.fillColor = NSColor(palette.bubble).cgColor
            mirrorLayer.addSublayer(bubble)
            bubbleLayers.append(bubble)

            if isStatic {
                // 静态图标：三颗大小不一的气泡斜着排在尾后。
                bubble.position = CGPoint(x: tailX + (2.5 + Double(index) * 4) * unit,
                                          y: startY - (0.35 + Double(index) * 0.28) * riseDistance)
                bubble.opacity = Float(0.45 - Double(index) * 0.1)
                continue
            }

            bubble.position = CGPoint(x: tailX, y: startY)
            bubble.opacity = 0

            let duration = 2.4
            let offset = Double(index) * 0.8

            let rise = CAKeyframeAnimation(keyPath: "position.y")
            rise.values = [startY, startY - riseDistance]
            rise.keyTimes = [0, 1]
            rise.timingFunctions = [.init(name: .linear)]

            let drift = CAKeyframeAnimation(keyPath: "position.x")
            drift.values = [tailX, tailX + 3 * unit, tailX + 7 * unit]
            drift.keyTimes = [0, 0.5, 1]

            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 0.55, 0.55, 0]
            fade.keyTimes = [0, 0.25, 0.6, 1]

            let group = CAAnimationGroup()
            group.animations = [rise, drift, fade]
            group.duration = duration
            group.repeatCount = .infinity
            group.timeOffset = offset
            bubble.add(group, forKey: "bubble")
        }
    }

    // MARK: - 空闲：安静地睡觉

    private func buildSleeping(stageHeight: CGFloat,
                               bodyWidth: CGFloat,
                               bodyHeight: CGFloat,
                               verticalRoom: CGFloat) {
        let palette = WhalePalette.menuBar(for: .offPeak, dark: isDarkMenuBar)
        applyColors(palette)

        let baseY = (stageHeight - bodyHeight) / 2
        let x = (bounds.width - bodyWidth) / 2 - bounds.width * 0.04
        whaleContainer.position = CGPoint(x: x, y: baseY)

        // 静态图标：保持侧躺姿势，三个「z」固定飘在头顶。
        guard Self.animates else {
            tiltLayer.transform = CATransform3DMakeRotation(WhaleScene.sleepTiltDegrees * .pi / 180, 0, 0, 1)
            buildSleepMarks(bodyWidth: bodyWidth, bodyHeight: bodyHeight,
                            palette: palette, static: true)
            return
        }

        // 缓慢上下漂浮。
        let float = CAKeyframeAnimation(keyPath: "position.y")
        let amplitude = verticalRoom * 0.14
        float.values = [baseY, baseY + amplitude, baseY, baseY - amplitude, baseY]
        float.keyTimes = [0, 0.25, 0.5, 0.75, 1]
        float.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
        float.duration = WhaleScene.sleepFloatPeriod
        float.repeatCount = .infinity
        whaleContainer.add(float, forKey: "sleep.float")

        // 侧躺 + 轻微晃动。
        let tiltRadians = WhaleScene.sleepTiltDegrees * .pi / 180
        tiltLayer.transform = CATransform3DMakeRotation(tiltRadians, 0, 0, 1)
        let wobble = CAKeyframeAnimation(keyPath: "transform.rotation")
        wobble.values = [tiltRadians - 0.028, tiltRadians + 0.028, tiltRadians - 0.028]
        wobble.keyTimes = [0, 0.5, 1]
        wobble.timingFunctions = [.init(name: .easeInEaseOut), .init(name: .easeInEaseOut)]
        wobble.duration = WhaleScene.sleepBreathPeriod
        wobble.repeatCount = .infinity
        tiltLayer.add(wobble, forKey: "sleep.tilt")

        // 呼吸。
        let breath = CAKeyframeAnimation(keyPath: "transform")
        let normal = NSValue(caTransform3D: CATransform3DIdentity)
        let inhale = NSValue(caTransform3D: CATransform3DMakeScale(1.022, 1.022, 1))
        breath.values = [normal, inhale, normal]
        breath.keyTimes = [0, 0.5, 1]
        breath.timingFunctions = [.init(name: .easeInEaseOut), .init(name: .easeInEaseOut)]
        breath.duration = WhaleScene.sleepBreathPeriod
        breath.repeatCount = .infinity
        mirrorLayer.add(breath, forKey: "sleep.breath")

        buildSleepMarks(bodyWidth: bodyWidth, bodyHeight: bodyHeight, palette: palette)
    }

    /// 头顶升起的「z」。
    private func buildSleepMarks(bodyWidth: CGFloat, bodyHeight: CGFloat,
                                 palette: WhalePalette, static isStatic: Bool = false) {
        let markSize = max(3.5, bodyWidth * 0.15)
        let start = CGPoint(x: bodyWidth * 1.06, y: bodyHeight * 0.30)

        for index in 0..<3 {
            let mark = CAShapeLayer()
            mark.bounds = CGRect(x: 0, y: 0, width: markSize * 2, height: markSize * 2)
            mark.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            mark.position = start
            mark.path = WhaleScene.zMarkPath(at: CGPoint(x: markSize, y: markSize), size: markSize).cgPath
            mark.fillColor = nil
            mark.strokeColor = NSColor(palette.sleepMark).cgColor
            mark.lineWidth = markSize * 0.20
            mark.lineCap = .round
            mark.lineJoin = .round
            mark.opacity = 0
            whaleContainer.addSublayer(mark)
            sleepMarkLayers.append(mark)

            let riseX = bodyWidth * 0.24
            let riseY = bodyHeight * 0.60

            if isStatic {
                // 静态图标：三个「z」由小到大排成一条斜线，全部可见。
                mark.position = CGPoint(x: start.x + riseX * Double(index) / 3,
                                        y: start.y - riseY * Double(index) / 3)
                mark.opacity = Float(0.55 + Double(index) * 0.18)
                mark.transform = CATransform3DMakeScale(1 + 0.15 * CGFloat(index), 1 + 0.15 * CGFloat(index), 1)
                continue
            }

            let duration = 3.33
            let offset = Double(index) * duration / 3

            let move = CAKeyframeAnimation(keyPath: "position")
            move.values = [NSValue(point: start),
                           NSValue(point: CGPoint(x: start.x + riseX, y: start.y - riseY))]
            move.keyTimes = [0, 1]

            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 0.9, 0.9, 0]
            fade.keyTimes = [0, 0.25, 0.6, 1]

            let grow = CAKeyframeAnimation(keyPath: "transform")
            grow.values = [NSValue(caTransform3D: CATransform3DMakeScale(1, 1, 1)),
                           NSValue(caTransform3D: CATransform3DMakeScale(1.3, 1.3, 1))]
            grow.keyTimes = [0, 1]

            let group = CAAnimationGroup()
            group.animations = [move, fade, grow]
            group.duration = duration
            group.repeatCount = .infinity
            group.timeOffset = offset
            mark.add(group, forKey: "sleep.mark")
        }
    }

    // MARK: - 外观变化

    /// 菜单栏在浅色 / 深色之间切换时，重新取色。
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        rebuildAnimations()
    }
}
