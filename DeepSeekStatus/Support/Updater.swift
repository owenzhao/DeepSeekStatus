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

    /// 是否在后台自动检查更新。默认值来自 Info.plist 的 `SUEnableAutomaticChecks`。
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    /// 更新器是否可用（Info.plist 没配好或启动失败时为 false）。
    /// 检查进行中也会变成 false，正好可以用来禁用菜单项。
    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    private let controller: SPUStandardUpdaterController
    /// `SPUUpdater.updaterDelegate` 是弱引用，所以这里得自己持有。
    private let diagnosticsDelegate: DiagnosticsDelegate?

    init() {
        let environment = ProcessInfo.processInfo.environment
        let wantsDiagnostics = environment["DEEPSEEK_STATUS_DIAGNOSTICS"] == "1"
            || environment["DEEPSEEK_STATUS_CHECK_UPDATES"] == "1"
        let delegate: DiagnosticsDelegate? = wantsDiagnostics ? DiagnosticsDelegate() : nil
        diagnosticsDelegate = delegate
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: delegate,
                                                  userDriverDelegate: nil)
    }

    /// 手动检查更新（右键菜单里那一项）。
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

/// 自检代理：把 Sparkle 的判断打到控制台。
///
/// 有了它，「旧版本能否发现新版本」不用靠肉眼看弹窗，命令行里就能断言。
private final class DiagnosticsDelegate: NSObject, SPUUpdaterDelegate {

    /// appcast 拉取并解析成功 —— 「更新源可达」的确定性信号。
    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        let versions = appcast.items.map(\.displayVersionString).joined(separator: ", ")
        print("[诊断] Sparkle 已加载 appcast：共 \(appcast.items.count) 条 [\(versions)]")
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        print("[诊断] Sparkle 找到更新：\(item.displayVersionString)（build \(item.versionString)）")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        print("[诊断] Sparkle 未找到更新（当前已是最新）")
    }

    /// 一轮检查的收尾，成功或失败都会走到这里。
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error {
            print("[诊断] Sparkle 检查失败：\(error.localizedDescription)")
        } else {
            print("[诊断] Sparkle 检查完成（无错误）")
        }
    }
}
