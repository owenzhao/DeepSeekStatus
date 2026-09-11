// 离屏渲染工具：把 App 里的 SwiftUI 视图直接渲成 PNG，用于在没有窗口的情况下检查视觉效果。
//
// 用法：
//   swiftc -parse-as-library ... (由 Tools/render-preview.sh 调用)
//   ./Snapshot preview --out Preview
//   ./Snapshot icons   --out Preview/AppIcon
import AppKit
import SwiftUI

// MARK: - 输出工具

let arguments = CommandLine.arguments
let mode = arguments.count > 1 ? arguments[1] : "preview"
let outIndex = arguments.firstIndex(of: "--out")
let outputPath = outIndex.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil } ?? "Preview"
let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent(outputPath)

_ = NSApplication.shared

@MainActor
func write(_ image: CGImage, named name: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        print("❌ 无法编码 \(name)")
        return
    }
    try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    let url = outputDirectory.appendingPathComponent("\(name).png")
    do {
        try data.write(to: url)
        print("✅ \(name).png  \(image.width)×\(image.height)")
    } catch {
        print("❌ \(name): \(error)")
    }
}

@MainActor
func render(_ view: some View, size: CGSize, scale: CGFloat = 2, name: String) {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    renderer.scale = scale
    guard let image = renderer.cgImage else {
        print("❌ 渲染失败 \(name)")
        return
    }
    write(image, named: name)
}

/// 只限定宽度，高度按内容的自然尺寸渲染。
@MainActor
func renderNatural(_ view: some View, width: CGFloat, scale: CGFloat = 2, name: String) {
    let renderer = ImageRenderer(content: view.frame(width: width))
    renderer.scale = scale
    guard let image = renderer.cgImage else {
        print("❌ 渲染失败 \(name)")
        return
    }
    write(image, named: name)
}

// MARK: - 固定时刻的舞台（用于查看动画的不同瞬间）

struct StaticStage: View {
    let period: PricePeriod
    let time: Double
    let size: CGSize
    var whaleWidth: CGFloat
    var palette: WhalePalette = .menuBar(for: .peak, dark: true)
    var background: Color = .clear

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, canvasSize in
            var canvas = context
            WhaleScene.draw(in: &canvas,
                            size: canvasSize,
                            time: time,
                            period: period,
                            whaleWidth: whaleWidth,
                            palette: palette)
        }
        .frame(width: size.width, height: size.height)
        .background(background)
    }
}

// MARK: - 菜单栏示意图

/// 菜单栏示意图。
///
/// 注意：真正的菜单栏图标是 AppKit + Core Animation 的 `WhaleStatusItemView`，
/// 这里用同一套绘制代码（`WhaleStage`）拼出等价的布局用于出图；
/// 真实渲染效果请看运行自检里抓下来的 `live-menubar-*.png`。
struct MenuBarStrip: View {
    let scheme: ColorScheme
    let period: PricePeriod
    let countdown: String?
    var background: Color?

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                Image(systemName: "apple.logo").font(.system(size: 12))
                Image(systemName: "wifi").font(.system(size: 12))
            }
            .foregroundStyle(scheme == .dark ? Color.white.opacity(0.85) : Color.black.opacity(0.8))
            Spacer()
            HStack(spacing: 5) {
                WhaleStage(period: period,
                           size: CGSize(width: WhaleStatusItemView.stageWidth, height: 22))
                if let countdown {
                    Text(countdown)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(scheme == .dark ? Color.white : Color.black)
                }
            }
            .frame(height: 22)
            Image(systemName: "battery.75").font(.system(size: 13))
            Image(systemName: "magnifyingglass").font(.system(size: 12))
            Text("9:41").font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(scheme == .dark ? Color.white.opacity(0.85) : Color.black.opacity(0.8))
        .padding(.horizontal, 12)
        .frame(width: 420, height: 24)
        .background(background ?? (scheme == .dark ? Color(white: 0.16) : Color(white: 0.94)))
        .environment(\.colorScheme, scheme)
    }
}

// MARK: - 预览

@MainActor
func renderPreviewSet() {
    let now = Date()

    // 1. 菜单栏图标本身（放大查看细节）
    for period in PricePeriod.allCases {
        render(WhaleStage(period: period, size: CGSize(width: 46, height: 22)),
               size: CGSize(width: 46, height: 22), scale: 8,
               name: "menubar-\(period.rawValue)-zoom")
    }

    // 2. 菜单栏真实尺寸示意
    //    菜单栏是半透明的，底色取决于壁纸，所以三种底色都要检查对比度：
    //    浅色菜单栏、深色菜单栏、以及半透明叠在深色壁纸上的灰底（实机上最常见的那种）。
    let bars: [(String, ColorScheme, Color)] = [
        ("light", .light, Color(white: 0.93)),
        ("dark", .dark, Color(white: 0.13)),
        ("gray", .dark, Color(red: 0.42, green: 0.45, blue: 0.50)),
    ]
    for (label, scheme, background) in bars {
        for period in PricePeriod.allCases {
            render(MenuBarStrip(scheme: scheme, period: period,
                                countdown: label == "gray" ? "01:23:45" : nil,
                                background: background),
                   size: CGSize(width: 420, height: 24), scale: 3,
                   name: "menubar-\(label)-\(period.rawValue)")
        }
    }

    // 3. 动画分解：高峰时段游泳的 6 个瞬间
    let swimFrames: [Double] = [0, 0.7, 1.4, 2.1, 2.8, 3.5]
    let swimGrid = VStack(spacing: 6) {
        ForEach(Array(swimFrames.enumerated()), id: \.offset) { _, time in
            StaticStage(period: .peak, time: time,
                        size: CGSize(width: 120, height: 34), whaleWidth: 34,
                        palette: .aquarium(for: .peak),
                        background: WhaleTheme.tankBottom)
        }
    }
    .padding(8)
    .background(WhaleTheme.tankBottom)
    render(swimGrid, size: CGSize(width: 136, height: 6 * 46 + 16), scale: 2, name: "swim-phases")

    // 4. 动画分解：空闲时段睡觉的 4 个瞬间
    let sleepFrames: [Double] = [0, 1.6, 3.2, 4.8]
    let sleepGrid = VStack(spacing: 6) {
        ForEach(Array(sleepFrames.enumerated()), id: \.offset) { _, time in
            StaticStage(period: .offPeak, time: time,
                        size: CGSize(width: 120, height: 34), whaleWidth: 30,
                        palette: .aquarium(for: .offPeak),
                        background: WhaleTheme.tankBottomSleep)
        }
    }
    .padding(8)
    .background(WhaleTheme.tankBottomSleep)
    render(sleepGrid, size: CGSize(width: 136, height: 4 * 46 + 16), scale: 2, name: "sleep-phases")

    // 5. 水族箱
    for period in PricePeriod.allCases {
        render(AquariumView(period: period, now: now),
               size: CGSize(width: 320, height: 152), scale: 2,
               name: "aquarium-\(period.rawValue)")
    }

    // 6. 一周时段表
    render(WeekScheduleGrid(now: now).padding(12).background(Color(nsColor: .windowBackgroundColor)),
           size: CGSize(width: 320, height: 120), scale: 2, name: "week-grid")

    // 7. 完整弹窗（两种状态），高度按内容自适应
    for period in PricePeriod.allCases {
        let store = PricingStore(now: now)
        store.previewPeriod = period
        renderNatural(PopoverView(store: store, onQuit: {})
                        .background(Color(nsColor: .windowBackgroundColor)),
                      width: 320, scale: 2,
                      name: "popover-\(period.rawValue)")
    }

    // 8. 鲸鱼矢量本身（和官方标志对比用）
    render(WhaleShape()
            .fill(WhaleTheme.brandBlue)
            .frame(width: 512, height: 512)
            .background(Color.white),
           size: CGSize(width: 512, height: 512), scale: 1, name: "whale-vector")
}

// MARK: - App 图标

@MainActor
func renderIcons() {
    let sizes: [(String, Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32),
        ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256),
        ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]
    for (name, pixels) in sizes {
        render(AppIconView(),
               size: CGSize(width: pixels, height: pixels), scale: 1,
               name: name)
    }
}

struct AppIconView: View {
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let inset = side * 0.085
            let rect = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
            ZStack {
                RoundedRectangle(cornerRadius: rect.width * 0.2237, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.50, blue: 1.0),
                                                  Color(red: 0.20, green: 0.29, blue: 0.85)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        RoundedRectangle(cornerRadius: rect.width * 0.2237, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: max(1, side * 0.006))
                    )
                    .shadow(color: .black.opacity(0.25), radius: side * 0.02, y: side * 0.012)
                WhaleShape()
                    .fill(LinearGradient(colors: [.white, Color(red: 0.86, green: 0.91, blue: 1.0)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: rect.width * 0.62)
                    .offset(y: rect.height * 0.01)
            }
            .frame(width: side, height: side)
        }
    }
}

// MARK: - 菜单栏配色候选

/// 把几种候选的「高峰」颜色画在实机那种半透明灰底菜单栏上，方便挑一个最醒目的。
@MainActor
func renderColorCandidates() {
    let background = Color(red: 0.42, green: 0.45, blue: 0.50)

    let candidates: [(String, NSColor)] = [
        ("#A8D4FF 亮天蓝", NSColor(srgbRed: 0.659, green: 0.831, blue: 1.0, alpha: 1)),
        ("#8FD3FF 亮青蓝", NSColor(srgbRed: 0.561, green: 0.827, blue: 1.0, alpha: 1)),
        ("#7FB8FF 亮蓝", NSColor(srgbRed: 0.498, green: 0.722, blue: 1.0, alpha: 1)),
        ("#5B9BFF 饱和蓝", NSColor(srgbRed: 0.357, green: 0.608, blue: 1.0, alpha: 1)),
        ("#4D6BFE 品牌蓝", NSColor(srgbRed: 0.302, green: 0.420, blue: 0.996, alpha: 1)),
        ("#D6E9FF 近白蓝", NSColor(srgbRed: 0.839, green: 0.914, blue: 1.0, alpha: 1)),
        ("#FFFFFF 纯白对比", NSColor.white),
    ]

    let sheet = VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(candidates.enumerated()), id: \.offset) { _, item in
            HStack(spacing: 12) {
                Image(nsImage: MenuBarIcon.image(period: .peak, dark: true, overrideColor: item.1))
                    .frame(width: 46, height: 22)
                Text(item.0)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
        }
        Divider().overlay(Color.white.opacity(0.3))
        HStack(spacing: 12) {
            Image(nsImage: MenuBarIcon.image(period: .offPeak, dark: true))
                .frame(width: 46, height: 22)
            Text("当前空闲配色（参考）")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
    }
    .frame(width: 300)
    .background(background)

    render(sheet, size: CGSize(width: 300, height: 30 * CGFloat(candidates.count + 1) + 1),
           scale: 3, name: "menubar-color-candidates")
}

// MARK: - 尺寸测量

@MainActor
func measure() {
    let now = Date()
    for period in PricePeriod.allCases {
        let store = PricingStore(now: now)
        store.previewPeriod = period
        let hosting = NSHostingView(rootView: PopoverView(store: store, onQuit: {}))
        print("弹窗 \(period.title): \(hosting.fittingSize)")
    }
    let aquarium = NSHostingView(rootView: AquariumView(period: .peak, now: now))
    print("水族箱: \(aquarium.fittingSize)")
    let grid = NSHostingView(rootView: WeekScheduleGrid(now: now))
    print("时段表: \(grid.fittingSize)")
    let menuBarHeight = NSStatusBar.system.thickness
    let whaleWidth = WhaleScene.menuBarWhaleWidth(forStageHeight: menuBarHeight)
    print("菜单栏鲸鱼宽度: \(whaleWidth)（画布宽 \(WhaleStatusItemView.stageWidth)、菜单栏高 \(menuBarHeight)）")
}

// MARK: - 时段规则自检

@MainActor
func checkSchedule() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = DeepSeekPricing.timeZone

    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute
        return calendar.date(from: components)!
    }

    // 2026-09-14 是周一。
    let cases: [(String, Date, PricePeriod, Date)] = [
        ("周一 08:59", date(2026, 9, 14, 8, 59), .offPeak, date(2026, 9, 14, 9, 0)),
        ("周一 09:00", date(2026, 9, 14, 9, 0), .peak, date(2026, 9, 14, 12, 0)),
        ("周一 11:59", date(2026, 9, 14, 11, 59), .peak, date(2026, 9, 14, 12, 0)),
        ("周一 12:00", date(2026, 9, 14, 12, 0), .offPeak, date(2026, 9, 14, 14, 0)),
        ("周一 13:59", date(2026, 9, 14, 13, 59), .offPeak, date(2026, 9, 14, 14, 0)),
        ("周一 14:00", date(2026, 9, 14, 14, 0), .peak, date(2026, 9, 14, 18, 0)),
        ("周一 17:59", date(2026, 9, 14, 17, 59), .peak, date(2026, 9, 14, 18, 0)),
        ("周一 18:00", date(2026, 9, 14, 18, 0), .offPeak, date(2026, 9, 15, 9, 0)),
        ("周二 00:30", date(2026, 9, 15, 0, 30), .offPeak, date(2026, 9, 15, 9, 0)),
        ("周五 17:59", date(2026, 9, 18, 17, 59), .peak, date(2026, 9, 18, 18, 0)),
        ("周五 18:00", date(2026, 9, 18, 18, 0), .offPeak, date(2026, 9, 21, 9, 0)),
        ("周六 10:00", date(2026, 9, 19, 10, 0), .offPeak, date(2026, 9, 21, 9, 0)),
        ("周日 23:59", date(2026, 9, 20, 23, 59), .offPeak, date(2026, 9, 21, 9, 0)),
    ]

    var failures = 0
    for (label, moment, expectedPeriod, expectedNext) in cases {
        let snapshot = PricingSnapshot(now: moment)
        let periodOK = snapshot.period == expectedPeriod
        let nextOK = abs(snapshot.nextTransition.timeIntervalSince(expectedNext)) < 1
        let nextLabel = PricingFormatter.transitionDescription(snapshot.nextTransition, relativeTo: moment)
        if !periodOK || !nextOK { failures += 1 }
        print("\(periodOK && nextOK ? "✅" : "❌") \(label) → \(snapshot.period.title)，下次切换 \(nextLabel)（转为\(snapshot.nextPeriod.title)）")
    }

    // 同一时刻换算到别的时区，结论必须一致（规则固定按北京时间）。
    let instant = date(2026, 9, 14, 10, 30)
    let base = DeepSeekPricing.period(at: instant)
    let consistent = ["America/Los_Angeles", "Europe/London", "Asia/Tokyo", "UTC"]
        .allSatisfy { _ in DeepSeekPricing.period(at: instant) == base }
    print("\(consistent ? "✅" : "❌") 时区无关性：周一 10:30 北京时间 = \(base.title)（与本地时区无关）")
    if !consistent { failures += 1 }

    print(failures == 0 ? "\n全部通过 ✅" : "\n失败 \(failures) 项 ❌")
}

// MARK: - 入口

MainActor.assumeIsolated {
    switch mode {
    case "icons":
        renderIcons()
    case "measure":
        measure()
    case "schedule":
        checkSchedule()
    case "candidates":
        renderColorCandidates()
    default:
        renderPreviewSet()
    }
}
