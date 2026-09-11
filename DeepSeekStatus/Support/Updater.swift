import Foundation
import Sparkle

/// Sparkle 自动更新的薄封装。
///
/// 应用是「只有菜单栏图标」的 agent（`LSUIElement`），没有 MainMenu.xib，
/// 所以按 Sparkle 文档的 programmatic setup 自己建 `SPUStandardUpdaterController`。
/// `SUFeedURL` / `SUPublicEDKey` / `SUEnableAutomaticChecks` 见 `Config/Info.plist`。
///
/// 注意：界面层刻意只暴露 `Binding<Bool>` 和回调（见 `PopoverView`），
/// 不直接依赖 Sparkle —— 离屏渲染工具用 `swiftc` 编译时不会链接 Sparkle。
@MainActor
final class Updater {

    /// Sparkle 即将弹出自己的窗口（更新提示 / 错误弹窗）时回调。
    ///
    /// 我们的面板是 `NSWindow.Level.statusBar`（数值 25），而 Sparkle 的窗口是普通层级，
    /// 从面板里点「立即检查」时更新窗口会被面板整个盖住 —— 所以这里要先把面板收起来。
    var willShowModalUI: @MainActor () -> Void = {}

    /// 是否在后台自动检查更新。默认值来自 Info.plist 的 `SUEnableAutomaticChecks`。
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    /// 更新器是否可用（Info.plist 没配好或启动失败时为 false）。
    /// 检查进行中也会变成 false，正好可以用来禁用菜单项。
    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    private let controller: SPUStandardUpdaterController
    /// `SPUUpdater` 的两个 delegate 属性都是弱引用，所以这里得自己持有。
    private let delegate: SparkleDelegate

    init() {
        let environment = ProcessInfo.processInfo.environment
        let diagnostics = environment["DEEPSEEK_STATUS_DIAGNOSTICS"] == "1"
            || environment["DEEPSEEK_STATUS_CHECK_UPDATES"] == "1"

        let delegate = SparkleDelegate(diagnostics: diagnostics)
        self.delegate = delegate
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: delegate,
                                                  userDriverDelegate: delegate)

        // Sparkle 只在主线程回调这两个 delegate 方法。
        delegate.onWillShowModalUI = { [weak self] in
            MainActor.assumeIsolated { self?.willShowModalUI() }
        }
    }

    /// 手动检查更新（右键菜单 / 面板里的按钮）。
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

/// Sparkle 的委托：转发「即将显示窗口」的通知，并在自检模式下把检查结果打到控制台。
///
/// 有了这些日志，「旧版本能否发现新版本」不用靠肉眼看弹窗，命令行里就能断言。
private final class SparkleDelegate: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {

    let diagnostics: Bool
    /// 即将显示 Sparkle 自己的窗口；由 `Updater` 转发。
    var onWillShowModalUI: (() -> Void)?

    init(diagnostics: Bool) {
        self.diagnostics = diagnostics
        super.init()
    }

    private func log(_ message: String) {
        guard diagnostics else { return }
        print("[诊断] \(message)")
    }

    // MARK: - 即将显示自己的窗口（面板会盖住它，需要先收起）

    func standardUserDriverWillShowModalAlert() {
        log("Sparkle 即将显示弹窗，先收起面板")
        onWillShowModalUI?()
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                  forUpdate update: SUAppcastItem,
                                                  state: SPUUserUpdateState) {
        log("Sparkle 即将显示更新窗口，先收起面板")
        onWillShowModalUI?()
    }

    // MARK: - 自检日志

    /// appcast 拉取并解析成功 —— 「更新源可达」的确定性信号。
    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        let versions = appcast.items.map(\.displayVersionString).joined(separator: ", ")
        log("Sparkle 已加载 appcast：共 \(appcast.items.count) 条 [\(versions)]")
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        log("Sparkle 找到更新：\(item.displayVersionString)（build \(item.versionString)）")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        log("Sparkle 未找到更新（当前已是最新）")
    }

    /// 一轮检查的收尾，成功或失败都会走到这里。
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error {
            log("Sparkle 检查失败：\(error.localizedDescription)")
        } else {
            log("Sparkle 检查完成（无错误）")
        }
    }
}
