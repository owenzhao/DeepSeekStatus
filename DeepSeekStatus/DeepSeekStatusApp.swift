import AppKit
import Combine
import SwiftUI

/// 菜单栏应用的入口。
///
/// 这是一个「只有菜单栏图标」的 agent 应用（`LSUIElement = YES`，Dock 里不出现）。
/// 菜单栏图标用 `NSStatusItem.button.image` 渲染成静态位图（自定义视图会让
/// `NSStatusItem` 每帧重做快照，CPU 会飙到 20% 以上，见 `MenuBarIcon`）；
/// 点图标弹出的详细面板是一个自己定位的 `NSPanel`（见 `StatusPanel`）。
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }

    private let store = PricingStore()
    /// 自动更新（Sparkle）。
    private let updater = Updater()
    private var statusItem: NSStatusItem?
    private var panel: StatusPanel?
    /// 点击面板外部 / 按 Esc 时关闭面板的事件监听。
    private var dismissMonitors: [Any] = []
    private var cancellables = Set<AnyCancellable>()
    /// 上一次渲染到菜单栏的内容，用来避免每秒无意义的重复设置。
    private var renderedKey: String?

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store.start()
        applyLaunchOverrides()
        configureStatusItem()
        // Sparkle 弹出任何自己的窗口前，先把面板收起来 —— 否则普通层级的更新窗口
        // 会被 .statusBar 层级的面板整个盖住（见 Updater.willShowModalUI）。
        updater.willShowModalUI = { [weak self] in self?.hidePanel() }
        observeStore()
        renderMenuBar()
        runDiagnosticsIfRequested()
        runUpdateCheckIfRequested()
    }

    /// 开发用：`DEEPSEEK_STATUS_CHECK_UPDATES=1` 启动后立刻手动检查一次更新，
    /// 配合 `Updater` 里的自检代理，可以在命令行里直接看到「能否发现新版本」。
    private func runUpdateCheckIfRequested() {
        guard ProcessInfo.processInfo.environment["DEEPSEEK_STATUS_CHECK_UPDATES"] == "1" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
            print("[诊断] 手动触发一次更新检查，更新源=\(Bundle.main.infoDictionary?["SUFeedURL"] as? String ?? "（未配置）")")
            updater.checkForUpdates()
        }
    }

    /// 启动参数覆盖，方便截图和排查：
    /// `DEEPSEEK_STATUS_PREVIEW=peak|offPeak` 会强制显示某个时段的样子。
    private func applyLaunchOverrides() {
        switch ProcessInfo.processInfo.environment["DEEPSEEK_STATUS_PREVIEW"]?.lowercased() {
        case "peak": store.previewPeriod = .peak
        case "offpeak": store.previewPeriod = .offPeak
        default: break
        }
    }

    /// 开发用自检：以 `DEEPSEEK_STATUS_DIAGNOSTICS=1` 启动时会打印状态栏的实际几何信息，
    /// 便于在没有屏幕录制权限的环境里确认菜单栏图标确实挂上去了。
    private func runDiagnosticsIfRequested() {
        guard ProcessInfo.processInfo.environment["DEEPSEEK_STATUS_DIAGNOSTICS"] == "1" else { return }

        if let item = statusItem, let button = item.button {
            print("[诊断] 状态栏按钮 frame=\(button.frame) 可见=\(!button.isHidden) 长度=\(item.length) 子视图数=\(button.subviews.count)")
            print("[诊断] 图标尺寸=\(button.image.map { "\($0.size)" } ?? "无") 标题=\(button.title.isEmpty ? "（空）" : button.title)")
        } else {
            print("[诊断] ❌ 状态栏按钮创建失败")
        }
        print("[诊断] 当前时段=\(store.period.title) 北京时间=\(PricingFormatter.preciseTime(store.snapshot.now))")
        print("[诊断] 距下次切换=\(PricingFormatter.duration(store.snapshot.secondsUntilTransition)) → \(store.snapshot.nextPeriod.title)")
        print("[诊断] 更新器可用=\(updater.canCheckForUpdates) 自动检查=\(updater.automaticallyChecksForUpdates)")

        // 弹出面板，等布局完成后再检查窗口与内容尺寸。
        // 状态栏窗口要等系统摆好位置（几十毫秒），所以稍等一下再弹，
        // 这样这里量到的位置和用户真的去点图标时是一致的。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
            if let button = statusItem?.button {
                togglePanel(button)
                print("[诊断] 调用 show 之后 面板可见=\(panel?.isVisible ?? false) 应用激活=\(NSApp.isActive)")
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [self] in
            print("[诊断] 0.8 秒后 更新器可用=\(updater.canCheckForUpdates)")
            if let button = statusItem?.button {
                print("[诊断] 布局后按钮 frame=\(button.frame) 窗口=\(button.window.map { "\($0.frame)" } ?? "无")")
                if let window = button.window {
                    let screenRect = window.convertToScreen(button.convert(button.bounds, to: nil))
                    print("[诊断] 菜单栏屏幕坐标=\(screenRect)")
                }
            }
            print("[诊断] 0.8 秒后 面板可见=\(panel?.isVisible ?? false) 应用激活=\(NSApp.isActive)")
            if let panel {
                print("[诊断] 面板窗口=\(panel.frame) 层级=\(panel.level.rawValue) 内容尺寸=\(panel.contentView?.frame.size ?? .zero)")
                if let screen = panel.screen ?? NSScreen.main {
                    let visible = screen.visibleFrame
                    print("[诊断] 屏幕可见区域=\(visible) 面板是否完全在可见区域内="
                          + "\(visible.contains(panel.frame))")
                }
            } else {
                print("[诊断] ❌ 面板未创建")
            }
            if let contentView = panel?.contentView {
                let data = capture(contentView, named: "live-panel-\(store.period.rawValue)")
                print("[诊断] 面板截图 字节数=\(data?.count ?? 0) 内容尺寸=\(contentView.bounds.size)")
            }
        }

        // 抓一张菜单栏图标的实际渲染效果。
        var firstFrame: Data?
        var frameBaseline: UInt64 = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
            firstFrame = captureStatusItem(named: "live-menubar-1")
            frameBaseline = WhaleRenderStats.frames
            print("[诊断] 菜单栏图标第 1 帧 字节数=\(firstFrame?.count ?? 0)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [self] in
            let secondFrame = captureStatusItem(named: "live-menubar-2")
            print("[诊断] 菜单栏图标第 2 帧 字节数=\(secondFrame?.count ?? 0) 两帧相同=\(firstFrame == secondFrame)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            let drawn = WhaleRenderStats.frames - frameBaseline
            print("[诊断] 最近 2 秒 SwiftUI 画布重绘 \(drawn) 帧 ≈ \(Double(drawn) / 2.0) fps（只剩弹窗水族箱）")
        }

        // 触发更新检查时要留出网络往返时间，别把还在检查的进程提前杀掉。
        let lifetime: TimeInterval = ProcessInfo.processInfo.environment["DEEPSEEK_STATUS_CHECK_UPDATES"] == "1"
            ? 25 : 3.6
        DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) {
            NSApp.terminate(nil)
        }
    }

    /// 把菜单栏图标视图渲染成 PNG。`cacheDisplay` 走的是视图自己的绘制路径，
    /// 不需要屏幕录制权限。设置 `DEEPSEEK_STATUS_CAPTURE=<目录>` 可以把图片存下来。
    private func captureStatusItem(named name: String) -> Data? {
        guard let button = statusItem?.button else { return nil }
        return capture(button, named: name)
    }

    /// 把一个视图渲染成 PNG。`cacheDisplay` 不需要屏幕录制权限。
    private func capture(_ view: NSView, named name: String) -> Data? {
        guard view.bounds.width > 0, view.bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        if let directory = ProcessInfo.processInfo.environment["DEEPSEEK_STATUS_CAPTURE"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? data.write(to: url)
        }
        return data
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - 菜单栏图标

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: MenuBarIcon.size.width)
        guard let button = item.button else {
            statusItem = item
            return
        }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleNone
        button.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        button.appearsDisabled = false

        // 菜单栏明暗变化的处理放在 renderMenuBar 里：它每秒都会跑一次，
        // 而缓存 key 里带着明暗状态，所以最多 1 秒就会换上正确配色。
        // （这里不用 KVO：给按钮设图片会再次触发外观变更通知，容易变成死循环。）

        statusItem = item
    }

    /// 每秒（或状态变化时）刷新菜单栏内容。
    ///
    /// 图标是 `NSImage`：不用自定义视图，`NSStatusItem` 就不需要持续做视图快照，
    /// 常驻 CPU 会低很多。
    private func renderMenuBar() {
        guard let item = statusItem, let button = item.button else { return }

        let countdown = store.showsCountdownInMenuBar
            ? PricingFormatter.compactCountdown(store.snapshot.secondsUntilTransition)
            : nil
        let dark = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let key = "\(store.period.rawValue)|\(countdown ?? "")|\(dark)"
        guard key != renderedKey else { return }
        renderedKey = key

        button.image = MenuBarIcon.image(period: store.period, dark: dark)
        button.title = countdown ?? ""

        var width = MenuBarIcon.size.width
        if let countdown {
            width += 4 + Self.textWidth(countdown)
        }
        width = max(width, MenuBarIcon.size.width)
        if item.length != width {
            item.length = width
        }
    }

    /// 量出倒计时文字在菜单栏里的宽度（使用等宽数字，宽度稳定）。
    private static func textWidth(_ text: String) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel(sender)
        }
    }

    // MARK: - 弹出面板

    private func togglePanel(_ sender: NSStatusBarButton) {
        if panel?.isVisible == true {
            hidePanel()
            return
        }
        store.refresh()
        refreshMenuBarNow()
        showPanel(relativeTo: sender)
    }

    /// 显示面板。
    ///
    /// 窗口位置完全由我们自己算（`panelOrigin`），而不是交给 `NSPopover` 去猜，
    /// 所以不会再出现「弹窗被顶到屏幕外面、只剩半截」的情况。
    private func showPanel(relativeTo sender: NSStatusBarButton) {
        guard let screen = sender.window?.screen ?? NSScreen.main else { return }

        let margin: CGFloat = 8
        let available = screen.visibleFrame.height - margin * 2

        // 先按内容自然高度量一次，屏幕放不下时再退化成可滚动。
        //
        // 注意：这里必须直接建 `NSHostingView` 来量尺寸。
        // `NSHostingController.view` 在第一次布局之前 `fittingSize` 是 0，
        // 用它算出来的窗口高度会是 0，面板就整个消失了。
        let makeContent: (CGFloat?) -> StatusPanelContent = { limit in
            StatusPanelContent(store: self.store,
                               onQuit: { NSApp.terminate(nil) },
                               maxHeight: limit,
                               automaticallyChecksForUpdates: self.autoCheckBinding,
                               onCheckForUpdates: { self.checkForUpdates() })
        }
        let contentView = NSHostingView(rootView: makeContent(nil))
        contentView.frame = NSRect(x: 0, y: 0, width: PopoverView.width, height: 100)
        var size = CGSize(width: PopoverView.width, height: ceil(contentView.fittingSize.height))
        if size.height > available {
            contentView.rootView = makeContent(available)
            size.height = available
        }
        size.height = max(size.height, 120)

        let panel = self.panel ?? StatusPanel()
        self.panel = panel
        panel.contentView = contentView
        panel.setContentSize(size)
        panel.setFrameOrigin(panelOrigin(for: size, button: sender, screen: screen))

        // 激活放在最前面：accessory 应用未激活时，键盘焦点不会给到面板。
        NSApp.activate(ignoringOtherApps: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }
        installPanelDismissMonitors()

        // `NSHostingView` 会在挂进窗口后把窗口调成自己的实际高度（调整时顶边不动），
        // 所以下一轮 runloop 再按「最终尺寸」校正一次位置，保证面板始终贴在菜单栏下方。
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            let origin = self.panelOrigin(for: panel.frame.size, button: sender, screen: screen)
            if panel.frame.origin != origin {
                panel.setFrameOrigin(origin)
            }
            if ProcessInfo.processInfo.environment["DEEPSEEK_STATUS_DIAGNOSTICS"] == "1" {
                print("[诊断] 校正后 面板 frame=\(panel.frame) 内容=\(panel.contentView?.frame.size ?? .zero)")
            }
        }
    }

    private func hidePanel() {
        removePanelDismissMonitors()
        panel?.orderOut(nil)
    }

    /// 计算面板左上角应该落在哪里：居中贴在菜单栏图标下方，并夹在屏幕可见区域内。
    private func panelOrigin(for size: CGSize, button: NSStatusBarButton, screen: NSScreen) -> NSPoint {
        let visible = screen.visibleFrame
        let gap: CGFloat = 6

        let buttonRect = anchorRect(for: button, screen: screen)

        var x = buttonRect.midX - size.width / 2
        x = min(max(x, visible.minX + gap), max(visible.minX + gap, visible.maxX - size.width - gap))

        var y = buttonRect.minY - gap - size.height
        if y < visible.minY + gap {
            // 下方空间不够就翻到图标上方（正常菜单栏在顶部时不会走到）。
            y = buttonRect.maxY + gap
        }
        y = min(max(y, visible.minY + gap), max(visible.minY + gap, visible.maxY - size.height - gap))

        return NSPoint(x: x.rounded(), y: y.rounded())
    }

    /// 菜单栏图标在屏幕上的矩形。
    ///
    /// 应用刚启动的那一瞬间，状态栏窗口还没被系统摆好位置，此时 `convertToScreen`
    /// 会返回一个在屏幕外的矩形（实测是 y 为负数）。这种情况直接退化成
    /// 「贴在菜单栏右端」的兜底位置，避免面板被算到屏幕外面去。
    private func anchorRect(for button: NSStatusBarButton, screen: NSScreen) -> NSRect {
        if let window = button.window {
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            if rect.width > 0, rect.height > 0, screen.frame.contains(rect) {
                return rect
            }
        }
        // 兜底：菜单栏最右侧（状态栏图标通常就在那里）。
        return NSRect(x: screen.frame.maxX - 44, y: screen.visibleFrame.maxY, width: 1, height: 1)
    }

    /// 点击面板以外的地方或者按 Esc 就收起来（等价于原来 `NSPopover` 的 transient 行为）。
    private func installPanelDismissMonitors() {
        guard dismissMonitors.isEmpty else { return }

        // 全局监听收不到发给自己应用的事件，所以点菜单栏图标走的是按钮 action。
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
                                                          handler: { [weak self] _ in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            if !panel.frame.contains(NSEvent.mouseLocation) {
                self.hidePanel()
            }
        }) {
            dismissMonitors.append(global)
        }

        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return event }   // 53 = Esc
            self?.hidePanel()
            return nil
        }) {
            dismissMonitors.append(local)
        }
    }

    private func removePanelDismissMonitors() {
        dismissMonitors.forEach { NSEvent.removeMonitor($0) }
        dismissMonitors.removeAll()
    }

    // MARK: - 右键菜单

    private func showContextMenu() {
        hidePanel()
        let menu = NSMenu()

        let peak = NSMenuItem(title: String(localized: "menu.preview.peak",
                                            defaultValue: "Preview: Peak hours"),
                              action: #selector(previewPeak), keyEquivalent: "")
        peak.target = self
        peak.state = store.previewPeriod == .peak ? .on : .off
        menu.addItem(peak)

        let offPeak = NSMenuItem(title: String(localized: "menu.preview.offPeak",
                                               defaultValue: "Preview: Off-peak hours"),
                                 action: #selector(previewOffPeak), keyEquivalent: "")
        offPeak.target = self
        offPeak.state = store.previewPeriod == .offPeak ? .on : .off
        menu.addItem(offPeak)

        let live = NSMenuItem(title: String(localized: "menu.preview.live",
                                            defaultValue: "Follow current time"),
                              action: #selector(previewLive), keyEquivalent: "")
        live.target = self
        live.state = store.previewPeriod == nil ? .on : .off
        menu.addItem(live)

        menu.addItem(.separator())

        let countdown = NSMenuItem(title: String(localized: "menu.showCountdown",
                                                 defaultValue: "Show countdown in menu bar"),
                                   action: #selector(toggleCountdown), keyEquivalent: "")
        countdown.target = self
        countdown.state = store.showsCountdownInMenuBar ? .on : .off
        menu.addItem(countdown)

        menu.addItem(.separator())

        let updateItem = NSMenuItem(title: String(localized: "menu.checkForUpdates",
                                                  defaultValue: "Check for Updates…"),
                                    action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        updateItem.isEnabled = updater.canCheckForUpdates
        menu.addItem(updateItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: String(localized: "menu.quit",
                                            defaultValue: "Quit DeepSeek Status"),
                              action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // 标准做法：临时挂上 menu，performClick 后立刻摘掉，避免左键也弹出菜单。
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func previewPeak() { applyPreview(.peak) }
    @objc private func previewOffPeak() { applyPreview(.offPeak) }
    @objc private func previewLive() { applyPreview(nil) }

    private func applyPreview(_ period: PricePeriod?) {
        store.previewPeriod = period
        refreshMenuBarNow()
    }

    @objc private func toggleCountdown() {
        store.showsCountdownInMenuBar.toggle()
        refreshMenuBarNow()
    }

    @objc private func checkForUpdates() {
        // 面板是 .statusBar 层级，会盖住 Sparkle 的窗口，先收起来。
        hidePanel()
        updater.checkForUpdates()
    }

    /// 面板里的「自动检查更新」开关：界面只拿到一个 `Binding`，不直接依赖 Sparkle。
    private var autoCheckBinding: Binding<Bool> {
        Binding(get: { self.updater.automaticallyChecksForUpdates },
                set: { self.updater.automaticallyChecksForUpdates = $0 })
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - 状态同步

    private func observeStore() {
        store.objectWillChange
            .sink { [weak self] _ in
                // objectWillChange 在属性更新之前发出，推到下一个 runloop 再取新值。
                DispatchQueue.main.async { self?.refreshMenuBarNow() }
            }
            .store(in: &cancellables)
    }

    /// 按最新状态刷新菜单栏。`renderMenuBar` 内部会判断是否真的需要改动，
    /// 没有变化时什么都不做（避免让 `NSStatusItem` 重新做视图快照）。
    private func refreshMenuBarNow() {
        renderMenuBar()
    }
}

