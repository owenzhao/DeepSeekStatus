import Foundation
import SwiftUI

/// 全局状态：当前时段快照 + 用户偏好。
///
/// 每秒刷新一次（使用 `.common` run loop 模式，菜单弹出时也不会停），
/// 并且会在系统时钟变化、跨天、唤醒等时刻立刻重新计算。
@MainActor
final class PricingStore: ObservableObject {

    /// 当前时刻的时段快照。
    @Published private(set) var snapshot: PricingSnapshot

    /// 预览模式：强制显示某个时段的样子，方便随时查看两种动画。`nil` 表示跟随真实时间。
    @Published var previewPeriod: PricePeriod?

    /// 是否在菜单栏的鲸鱼旁显示倒计时。
    @Published var showsCountdownInMenuBar: Bool {
        didSet {
            guard oldValue != showsCountdownInMenuBar else { return }
            defaults.set(showsCountdownInMenuBar, forKey: Keys.showsCountdown)
        }
    }

    /// 是否开机自动启动。
    @Published var launchAtLogin: Bool {
        didSet {
            guard oldValue != launchAtLogin else { return }
            applyLaunchAtLogin()
        }
    }

    /// 开机启动设置失败时的提示。
    @Published private(set) var launchAtLoginMessage: String?

    /// 用于界面展示的时段（可能是预览值）。
    var period: PricePeriod {
        previewPeriod ?? snapshot.period
    }

    var isPreviewing: Bool {
        previewPeriod != nil
    }

    private enum Keys {
        static let showsCountdown = "showsCountdownInMenuBar"
    }

    private let defaults: UserDefaults
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard, now: Date = Date()) {
        self.defaults = defaults
        self.snapshot = PricingSnapshot(now: now)
        self.showsCountdownInMenuBar = defaults.bool(forKey: Keys.showsCountdown)
        self.launchAtLogin = LaunchAtLogin.isEnabled
    }

    deinit {
        timer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    /// 开始定时刷新。重复调用是安全的。
    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        // `.common` 模式保证菜单/弹窗跟踪期间计时器照常触发。
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        installObservers()
        refresh()
    }

    /// 立即按当前时间重新计算。
    func refresh() {
        let next = PricingSnapshot(now: Date())
        if next != snapshot {
            snapshot = next
        }
    }

    private func installObservers() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .NSSystemClockDidChange,
            .NSCalendarDayChanged,
            NSApplication.didBecomeActiveNotification,
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            observers.append(token)
        }
        // 从睡眠中唤醒后立刻刷新。
        let wakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        observers.append(wakeToken)
    }

    private func applyLaunchAtLogin() {
        do {
            try LaunchAtLogin.set(enabled: launchAtLogin)
            launchAtLoginMessage = LaunchAtLogin.needsApproval ? "需要在「系统设置 › 通用 › 登录项」中允许。" : nil
        } catch {
            launchAtLoginMessage = "设置失败：\(error.localizedDescription)"
            // 回滚开关状态。
            let actual = LaunchAtLogin.isEnabled
            if actual != launchAtLogin {
                launchAtLogin = actual
            }
        }
    }
}
