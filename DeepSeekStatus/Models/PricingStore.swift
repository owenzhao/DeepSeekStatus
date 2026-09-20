import Foundation
import SwiftUI

/// 全局状态：当前时段快照 + 用户偏好。
///
/// 每秒刷新一次（使用 `.common` run loop 模式，菜单弹出时也不会停），
/// 并且会在系统时钟变化、跨天、唤醒等时刻立刻重新计算。
@MainActor
final class PricingStore: ObservableObject {

    /// Apple 中国大陆节假日订阅解析出的计费日历。
    @Published private(set) var holidaySchedule: HolidaySchedule

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
        static let holidayETag = "holidayScheduleETag"
        static let holidayLastChecked = "holidayScheduleLastChecked"
    }

    static let holidayRefreshInterval: TimeInterval = 24 * 60 * 60
    static let holidayCalendarURL = URL(string: "https://calendars.icloud.com/holidays/cn_zh.ics")!

    private let defaults: UserDefaults
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var isRefreshingHolidaySchedule = false

    init(defaults: UserDefaults = .standard,
         now: Date = Date(),
         holidaySchedule suppliedSchedule: HolidaySchedule? = nil) {
        self.defaults = defaults
        let schedule = suppliedSchedule ?? Self.loadCachedSchedule() ?? .bundled
        self.holidaySchedule = schedule
        self.snapshot = PricingSnapshot(now: now, schedule: schedule)
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
        refreshHolidayScheduleIfNeeded()
    }

    /// 立即按当前时间重新计算。
    func refresh() {
        let next = PricingSnapshot(now: Date(), schedule: holidaySchedule)
        if next != snapshot {
            snapshot = next
        }
    }

    /// Apple 的节假日安排每天最多检查一次。失败时继续使用当前有效数据。
    func refreshHolidayScheduleIfNeeded() {
        guard !isRefreshingHolidaySchedule else { return }
        if let lastChecked = defaults.object(forKey: Keys.holidayLastChecked) as? Date,
           Date().timeIntervalSince(lastChecked) < Self.holidayRefreshInterval {
            return
        }
        isRefreshingHolidaySchedule = true
        Task { await refreshHolidaySchedule() }
    }

    private func refreshHolidaySchedule() async {
        var request = URLRequest(url: Self.holidayCalendarURL)
        request.timeoutInterval = 20
        if let etag = defaults.string(forKey: Keys.holidayETag) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        defer { isRefreshingHolidaySchedule = false }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            if http.statusCode == 304 {
                defaults.set(Date(), forKey: Keys.holidayLastChecked)
                return
            }
            guard http.statusCode == 200 else { return }

            let parsed = try HolidaySchedule.parseICS(data)
            // 临时返回旧数据或不完整数据时，不倒退已经覆盖的年份。
            if let currentYear = holidaySchedule.newestCoveredYear,
               let receivedYear = parsed.newestCoveredYear,
               receivedYear < currentYear {
                return
            }

            try Self.saveCachedSchedule(parsed)
            holidaySchedule = parsed
            if let etag = http.value(forHTTPHeaderField: "ETag") {
                defaults.set(etag, forKey: Keys.holidayETag)
            }
            defaults.set(Date(), forKey: Keys.holidayLastChecked)
            refresh()
        } catch {
            // 网络、解析或落盘失败都保留已经生效的数据；下次启动/唤醒后仍会重试。
        }
    }

    private static var holidayCacheURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.parussoft.DeepSeekStatus", isDirectory: true)
            .appendingPathComponent("holiday-schedule.json")
    }

    private static func loadCachedSchedule() -> HolidaySchedule? {
        guard let url = holidayCacheURL,
              let data = try? Data(contentsOf: url),
              let schedule = try? JSONDecoder().decode(HolidaySchedule.self, from: data),
              schedule.newestCoveredYear != nil else { return nil }
        return schedule
    }

    private static func saveCachedSchedule(_ schedule: HolidaySchedule) throws {
        guard let url = holidayCacheURL else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(schedule)
        try data.write(to: url, options: .atomic)
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
                MainActor.assumeIsolated {
                    self?.refresh()
                    self?.refreshHolidayScheduleIfNeeded()
                }
            }
            observers.append(token)
        }
        // 从睡眠中唤醒后立刻刷新。
        let wakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
                self?.refreshHolidayScheduleIfNeeded()
            }
        }
        observers.append(wakeToken)
    }

    private func applyLaunchAtLogin() {
        do {
            try LaunchAtLogin.set(enabled: launchAtLogin)
            launchAtLoginMessage = LaunchAtLogin.needsApproval
                ? String(localized: "launchAtLogin.needsApproval",
                         defaultValue: "Allow it in System Settings › General › Login Items.")
                : nil
        } catch {
            launchAtLoginMessage = String(format: String(localized: "launchAtLogin.failed",
                                                         defaultValue: "Couldn’t change the setting: %@"),
                                          error.localizedDescription)
            // 回滚开关状态。
            let actual = LaunchAtLogin.isEnabled
            if actual != launchAtLogin {
                launchAtLogin = actual
            }
        }
    }
}
