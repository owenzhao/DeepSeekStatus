import SwiftUI

/// 余额卡片里各服务商区块共用的排版。
///
/// 卡片里并排放着 DeepSeek 和 LithosAI 两家的余额。如果两个区块各写各的字号和间距，
/// 右对齐的边缘、名称到金额的距离很快就会走样，整张卡片看着就是散的；所以这里固定一套：
///
/// - 第一行：服务商名称，右侧贴边放这个服务商自己的控件（API Key、开关）；
/// - 第二行：金额，大号粗体、等宽数字；
/// - 金额下面可选一行说明（赠送 / 充值 之类）。
///
/// 两个区块因此有一个共同的节奏：名称行打头，金额行是视觉重点，控件始终贴右边缘，
/// 中间的分隔线负责分组。
///
/// 字色沿用全局的 `WhaleTheme.contentTint` / `WhaleTheme.labelTint`：名称和金额是黑色，
/// 标题、赠送 / 充值、刷新时间、状态文案统一一档灰，操作是链接蓝。层级只靠字号和字重拉开。
enum BalanceCardStyle {
    /// 卡片标题「Account balance」。
    static let titleFont = Font.system(size: 11, weight: .semibold)
    /// 服务商名称（DeepSeek / LithosAI）。
    static let nameFont = Font.system(size: 11, weight: .semibold)
    /// 金额。
    static let amountFont = Font.system(size: 17, weight: .bold, design: .rounded)
    /// 金额下面的说明（赠送 / 充值）。
    static let captionFont = Font.system(size: 10)
    /// 登录中、出错之类的状态文案。
    static let messageFont = Font.system(size: 10.5)
    /// 右边缘的操作（刷新、登录 / 退出、更换 Key）。
    static let actionFont = Font.system(size: 10.5, weight: .semibold)
    /// 刷新时间这类补充信息。
    static let metaFont = Font.system(size: 9.5)

    /// 卡片底色的圆角容器，两个区块和标题共用。
    static let cornerRadius: CGFloat = 8
    static let padding: CGFloat = 10
    /// 区块之间的距离。
    static let blockSpacing: CGFloat = 8
}

/// 一个服务商的余额区块：名称行（右侧放控件）+ 金额 / 状态。
struct BalanceProviderBlock<Accessory: View, Content: View>: View {
    /// 服务商名称，不翻译。
    var name: String
    /// 贴右边缘的控件。
    @ViewBuilder var accessory: () -> Accessory
    /// 名称行下面的内容。
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(verbatim: name)
                    .font(BalanceCardStyle.nameFont)
                    .foregroundStyle(WhaleTheme.contentTint)
                Spacer(minLength: 6)
                accessory()
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 区块之间的细线。卡片底色本身很浅，用 `Divider()` 会偏重，这里自己画一条更淡的。
struct BalanceCardSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 1)
    }
}
