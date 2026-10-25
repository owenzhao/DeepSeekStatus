import AppKit
import Foundation
import WebKit

/// LithosAI 控制台余额。登录状态只保存在 WebKit 的默认网站数据存储中。
@MainActor
final class LithosBalanceStore: NSObject, ObservableObject, WKNavigationDelegate, NSWindowDelegate, URLSessionTaskDelegate {
    enum State {
        case signedOut
        case loading
        case loaded(String)
        case failed(String)
    }

    private static let console = URL(string: "https://console.lithosai.cloud")!
    private static let enabledKey = "lithosBalanceEnabled"
    private static let refreshInterval: TimeInterval = 5 * 60

    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: enabledKey)
    @Published private(set) var state: State = .signedOut
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshed: Date?
    @Published private(set) var hasSession = false
    @Published private(set) var isSigningOut = false

    private var loginWindow: NSWindow?
    private var loginWebView: WKWebView?
    private var timer: Timer?
    private var requestID = 0
    private var shouldAutomaticallySignIn = true

    static func preview() -> LithosBalanceStore {
        let store = LithosBalanceStore()
        store.enabled = false
        return store
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        if enabled { refresh() }
    }

    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        UserDefaults.standard.set(value, forKey: Self.enabledKey)
        if value {
            shouldAutomaticallySignIn = true
            refresh()
        } else {
            requestID += 1
            isRefreshing = false
            state = .signedOut
            loginWindow?.close()
        }
    }

    func refreshIfNeeded() {
        guard enabled, !isRefreshing, !isSigningOut else { return }
        if let lastRefreshed, Date().timeIntervalSince(lastRefreshed) < Self.refreshInterval { return }
        refresh()
    }

    func refresh() {
        guard enabled, !isRefreshing, !isSigningOut else { return }
        isRefreshing = true
        if case .loaded = state {} else { state = .loading }
        requestID += 1
        let currentID = requestID
        Task {
            let result: Result<String, Error>
            do { result = .success(try await fetchBalance()) }
            catch { result = .failure(error) }
            guard currentID == requestID, enabled else { return }
            isRefreshing = false
            switch result {
            case .success(let amount):
                state = .loaded(amount)
                hasSession = true
                lastRefreshed = Date()
                shouldAutomaticallySignIn = true
            case .failure(let error as LithosError) where error == .signedOut:
                state = .signedOut
                hasSession = false
                if shouldAutomaticallySignIn { signIn() }
            case .failure(let error):
                state = .failed(error.localizedDescription)
            }
        }
    }

    func signIn() {
        guard enabled, !isSigningOut else { return }
        shouldAutomaticallySignIn = false
        if let loginWindow {
            loginWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = self
        let window = NSWindow(contentRect: NSRect(x: 160, y: 120, width: 950, height: 740),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = String(localized: "lithos.balance.signInWindow", defaultValue: "Sign in to LithosAI")
        window.contentView = webView
        window.delegate = self
        loginWebView = webView
        loginWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        webView.load(URLRequest(url: Self.console))
    }

    func signOut() {
        guard enabled, !isSigningOut else { return }
        isSigningOut = true
        shouldAutomaticallySignIn = false
        requestID += 1
        isRefreshing = false
        lastRefreshed = nil
        hasSession = false
        state = .signedOut
        loginWindow?.close()
        Task {
            let websiteData = WKWebsiteDataStore.default()
            await withCheckedContinuation { continuation in
                websiteData.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                       modifiedSince: .distantPast) { continuation.resume() }
            }
            isSigningOut = false
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === loginWebView, webView.url?.host == Self.console.host else { return }
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self, self.enabled, self.loginWebView === webView,
                  cookies.contains(where: { $0.domain == Self.console.host && $0.name == "__Host-console_session" }) else { return }
            self.loginWindow?.close()
            self.refresh()
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showLoginError(error, for: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showLoginError(error, for: webView)
    }

    private func showLoginError(_ error: Error, for webView: WKWebView) {
        guard webView === loginWebView, (error as NSError).code != NSURLErrorCancelled else { return }
        state = .failed(error.localizedDescription)
    }

    func windowWillClose(_ notification: Notification) {
        loginWebView?.navigationDelegate = nil
        // close() 尚在执行，等它返回后再释放窗口和 WebView。
        DispatchQueue.main.async { [weak self] in
            self?.loginWindow = nil
            self?.loginWebView = nil
        }
    }

    private func fetchBalance() async throws -> String {
        let cookies = await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        let own = cookies.filter {
            $0.domain == Self.console.host && $0.isSecure && $0.expiresDate.map { $0 > Date() } != false
        }
        guard let session = own.first(where: { $0.name == "__Host-console_session" }),
              let csrf = own.first(where: { $0.name == "__Host-console_csrf" }) else {
            throw LithosError.signedOut
        }
        hasSession = true
        // Cookie 值仅在内存中发回其原始控制台域；从不输出或另行保存。
        let cookieHeader = "\(session.name)=\(session.value); \(csrf.name)=\(csrf.value)"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        let client = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { client.finishTasksAndInvalidate() }

        func get(_ path: String, organizationID: String? = nil) async throws -> [String: Any] {
            var request = URLRequest(url: Self.console.appending(path: path))
            request.httpMethod = "GET"
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            request.setValue(csrf.value, forHTTPHeaderField: "X-Console-Csrf")
            if let organizationID { request.setValue(organizationID, forHTTPHeaderField: "X-Organization-Id") }
            let (data, response) = try await client.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw LithosError.invalidResponse }
            if http.statusCode == 401 || (300..<400).contains(http.statusCode) {
                throw LithosError.signedOut
            }
            guard http.statusCode == 200 else { throw LithosError.http(http.statusCode) }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw LithosError.invalidResponse
            }
            return object
        }

        let me = try await get("api/me")
        let organization = (me["activeOrganization"] as? [String: Any])
            ?? (me["organization"] as? [String: Any])
        let organizationID = (me["activeOrganizationId"] as? String)
            ?? (me["organizationId"] as? String)
            ?? (organization?["id"] as? String)
        guard let organizationID,
              organizationID.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil else {
            throw LithosError.invalidResponse
        }

        let billing = try await get("api/billing", organizationID: organizationID)
        guard let raw = billing["balanceNanos"],
              let nanos = Decimal(string: String(describing: raw)) else { throw LithosError.invalidResponse }
        let dollars = NSDecimalNumber(decimal: nanos).dividing(by: 1_000_000_000)
        if nanos > 0 && nanos < 10_000_000 {
            return String(localized: "lithos.balance.subcent", defaultValue: "Less than $0.01")
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        guard let amount = formatter.string(from: dollars) else { throw LithosError.invalidResponse }
        return amount
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                willPerformHTTPRedirection response: HTTPURLResponse,
                                newRequest request: URLRequest,
                                completionHandler: @escaping (URLRequest?) -> Void) {
        // 会话 Cookie 不跟随控制台响应跳往认证域或任何其它地址。
        completionHandler(nil)
    }
}

private enum LithosError: LocalizedError, Equatable {
    case signedOut
    case http(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .signedOut:
            String(localized: "lithos.balance.signedOut", defaultValue: "Sign in to LithosAI.")
        case .http(let status):
            String(format: String(localized: "lithos.balance.httpError", defaultValue: "LithosAI returned HTTP %lld."), status)
        case .invalidResponse:
            String(localized: "lithos.balance.invalidResponse", defaultValue: "LithosAI returned unexpected account or balance data.")
        }
    }
}
