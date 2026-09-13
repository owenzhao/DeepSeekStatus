import Foundation

/// 官方 `GET /user/balance` 的返回内容。
///
/// 接口只需要一个有效的 API Key（`Authorization: Bearer <key>`），没有额外参数，
/// 查询本身不消耗 token、也不扣余额。
struct DeepSeekBalance: Codable, Equatable, Sendable {

    /// 余额是否还够发起 API 调用。界面用它判断，而不是看总余额是否大于 0。
    var isAvailable: Bool

    /// 各币种的余额明细（`CNY` / `USD`），按币种遍历展示。
    var balanceInfos: [BalanceInfo]

    /// 单个币种的余额明细。金额在接口里是字符串，这里原样保留、只做展示拼接。
    struct BalanceInfo: Codable, Equatable, Sendable, Identifiable {
        /// 币种：`CNY` 或 `USD`。
        var currency: String
        /// 总可用余额（赠金 + 充值余额）。
        var totalBalance: String
        /// 未过期的赠金余额。
        var grantedBalance: String
        /// 充值余额。
        var toppedUpBalance: String

        var id: String { currency }

        /// 展示用的币种符号。官方目前只会返回 CNY / USD。
        var symbol: String { currency.uppercased() == "USD" ? "$" : "¥" }

        /// 给金额加上币种符号，例如 `¥110.00`。
        func amount(_ value: String) -> String { symbol + value }
    }

    /// 预览 / 离屏渲染用的示例数据。
    static let sample = DeepSeekBalance(
        isAvailable: true,
        balanceInfos: [BalanceInfo(currency: "CNY",
                                   totalBalance: "110.00",
                                   grantedBalance: "10.00",
                                   toppedUpBalance: "100.00")]
    )
}

/// 查询余额失败的原因。
enum BalanceError: LocalizedError, Equatable {
    /// API Key 无效 / 已过期（HTTP 401、403）。
    case unauthorized
    /// 其它 HTTP 错误。
    case http(status: Int)
    /// 网络层失败（断网、超时…）。
    case network(String)
    /// 返回的数据不是预期结构。
    case decoding

    /// 是否属于「Key 本身有问题」。界面据此把「更换 API Key」放在更显眼的位置。
    var suggestsReplacingKey: Bool {
        if case .unauthorized = self { return true }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return String(localized: "balance.error.unauthorized",
                          defaultValue: "The API key is invalid or expired. Replace it?")
        case .http(let status):
            return String(format: String(localized: "balance.error.server",
                                        defaultValue: "DeepSeek returned an error (HTTP %lld)."),
                          status)
        case .network(let message):
            return String(format: String(localized: "balance.error.network",
                                        defaultValue: "Couldn’t reach DeepSeek: %@"),
                          message)
        case .decoding:
            return String(localized: "balance.error.decoding",
                          defaultValue: "DeepSeek returned an unexpected response.")
        }
    }
}

/// 调用官方余额接口的极简客户端。
///
/// 刻意只依赖 `URLSession`：为了一个 GET 请求引入整套 SDK 不划算。
struct DeepSeekBalanceClient {

    static let endpoint = URL(string: "https://api.deepseek.com/user/balance")!

    var session: URLSession = .shared
    var timeout: TimeInterval = 15

    /// 查询余额。失败时抛出 `BalanceError`。
    func fetchBalance(apiKey: String) async throws -> DeepSeekBalance {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw BalanceError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw BalanceError.decoding }
        switch http.statusCode {
        case 200:
            break
        case 401, 403:
            throw BalanceError.unauthorized
        default:
            throw BalanceError.http(status: http.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(DeepSeekBalance.self, from: data)
        } catch {
            throw BalanceError.decoding
        }
    }
}
