import Foundation
import SwiftUI

/// 账户余额的状态与刷新策略。
///
/// - 启动时读一次钥匙串，有 Key 就立刻刷新一次；
/// - 之后每隔 `refreshInterval` 自动刷新；
/// - 系统唤醒、或数据已经过期时 App 回到前台，也会顺手刷新一次。
///
/// API Key 的读写只有这里经手，界面层拿到的永远只是「有没有 Key」和状态文本。
@MainActor
final class BalanceStore: ObservableObject {

    /// 界面要展示的状态。
    enum State: Equatable {
        /// 还没有保存 API Key。
        case noKey
        /// 正在刷新（还没有可展示的数据）。
        case loading
        /// 拿到了余额。
        case loaded(DeepSeekBalance)
        /// 刷新失败。
        case failed(BalanceError)
    }

    /// 自动刷新间隔。
    static let refreshInterval: TimeInterval = 5 * 60

    @Published private(set) var state: State = .noKey

    /// 是否已经保存过 API Key。决定右上角按钮是「刷新」还是「输入 API Key」。
    @Published private(set) var hasKey = false

    /// 最近一次刷新**成功**的时刻；刷新失败时保留上一次成功的时间。
    @Published private(set) var lastRefreshed: Date?

    /// 是否有请求在飞（用于禁用按钮、显示转圈）。
    @Published private(set) var isRefreshing = false

    /// 是否展开「输入 / 更换 API Key」编辑器。
    @Published var isEditingKey = false

    /// 编辑器里的输入内容。
    @Published var keyDraft = ""

    /// 保存 Key 失败时的提示。
    @Published private(set) var keyError: String?

    private let client: DeepSeekBalanceClient
    private let now: () -> Date
    /// 当前生效的 Key。缓存在内存里，避免每次刷新都去读钥匙串。
    private var apiKey: String?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    /// 每次发起刷新都自增，用来判断回来的响应是不是「最新那次」。
    private var refreshToken = 0

    init(client: DeepSeekBalanceClient = DeepSeekBalanceClient(),
         now: @escaping () -> Date = Date.init) {
        self.client = client
        self.now = now
    }

    /// 预览 / 离屏渲染专用：不读钥匙串、不联网，直接摆出一个状态。
    static func preview(state: State = .loaded(.sample),
                        hasKey: Bool = true,
                        lastRefreshed: Date? = Date()) -> BalanceStore {
        let store = BalanceStore()
        store.state = state
        store.hasKey = hasKey
        store.lastRefreshed = lastRefreshed
        return store
    }

    deinit {
        timer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    // MARK: - 生命周期

    /// 读取钥匙串、立刻刷新一次，并开始定时刷新。重复调用是安全的。
    func start() {
        guard timer == nil else { return }
        reloadKey()

        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // `.common` 模式保证菜单/弹窗跟踪期间计时器照常触发。
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        installObservers()
    }

    /// 重新从钥匙串读 Key，并立刻刷新一次。
    private func reloadKey() {
        apiKey = APIKeyStore.load()
        hasKey = apiKey != nil
        state = hasKey ? .loading : .noKey
        if hasKey { refresh() }
    }

    // MARK: - 刷新

    /// 手动 / 定时刷新。没有 Key、或者已经有一次请求在飞时直接跳过。
    func refresh() {
        startRefresh(force: false)
    }

    /// 数据已经过期时才刷新（面板打开、App 回到前台、从睡眠唤醒时调用）。
    func refreshIfNeeded() {
        guard hasKey, !isRefreshing else { return }
        guard let lastRefreshed else {
            refresh()
            return
        }
        if now().timeIntervalSince(lastRefreshed) >= Self.refreshInterval {
            refresh()
        }
    }

    /// `force` 为 true 时会作废正在飞的那次请求（换了 Key 必须立刻用新 Key 验证）。
    private func startRefresh(force: Bool) {
        guard hasKey, apiKey != nil else {
            state = .noKey
            return
        }
        guard force || !isRefreshing else { return }

        isRefreshing = true
        // 已经有余额时保留旧数据，避免刷新期间数字闪一下。
        if case .loaded = state {} else { state = .loading }

        refreshToken += 1
        let token = refreshToken
        Task { await performRefresh(token: token) }
    }

    private func performRefresh(token: Int) async {
        guard let apiKey else {
            if token == refreshToken {
                isRefreshing = false
                state = .noKey
            }
            return
        }

        let result: Result<DeepSeekBalance, BalanceError>
        do {
            result = .success(try await client.fetchBalance(apiKey: apiKey))
        } catch let error as BalanceError {
            result = .failure(error)
        } catch {
            result = .failure(.network(error.localizedDescription))
        }

        // 请求期间换过 Key（或又发起了新的刷新）：这次结果已经过时，直接丢掉，
        // 否则旧 Key 的失败/成功会把刚保存的新 Key 的状态覆盖掉。
        guard token == refreshToken else { return }

        isRefreshing = false
        switch result {
        case .success(let balance):
            state = .loaded(balance)
            lastRefreshed = now()
        case .failure(let error):
            state = .failed(error)
        }
    }

    private func installObservers() {
        guard observers.isEmpty else { return }

        let token = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIfNeeded() }
        }
        observers.append(token)

        // 从睡眠中唤醒后，余额很可能已经变了。
        let wakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIfNeeded() }
        }
        observers.append(wakeToken)
    }

    // MARK: - API Key

    /// 展开编辑器，并预填当前 Key（方便在原 Key 上改）。
    func beginEditingKey() {
        keyDraft = apiKey ?? ""
        keyError = nil
        isEditingKey = true
    }

    /// 放弃这次编辑。
    func cancelEditingKey() {
        isEditingKey = false
        keyDraft = ""
        keyError = nil
    }

    /// 保存编辑器里的 Key，并立刻用它验证一次。
    ///
    /// 只有先写进钥匙串成功、才把内存里的 Key 换掉，避免出现「界面显示已换、实际没换」。
    func saveKey() {
        let trimmed = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        switch APIKeyStore.save(trimmed) {
        case .failure(let error):
            keyError = error.errorDescription
        case .success:
            apiKey = trimmed
            hasKey = true
            isEditingKey = false
            keyDraft = ""
            keyError = nil
            // 换了 Key 必须立刻用新 Key 验证，并作废可能还在飞的那次旧请求。
            startRefresh(force: true)
        }
    }

    /// 删除已保存的 Key（彻底换一个 Key 时使用）。
    func removeKey() {
        APIKeyStore.delete()
        apiKey = nil
        hasKey = false
        isEditingKey = false
        keyDraft = ""
        keyError = nil
        state = .noKey
        lastRefreshed = nil
        // 作废还在飞的请求，别让它把结果写到「已经没有 Key」的状态上。
        refreshToken += 1
        isRefreshing = false
    }
}
