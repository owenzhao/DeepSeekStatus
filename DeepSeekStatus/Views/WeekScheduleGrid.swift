import SwiftUI

/// 一周时段表：7 行（周一…周日）× 24 列（0…23 点，北京时间）。
///
/// 蓝色格子是高峰时段，灰色格子是空闲时段，当前所在的格子会用圆环标出来。
struct WeekScheduleGrid: View {
    var now: Date

    /// 行标题：周一 → 周日，跟随界面语言（"Mon" / 「周一」）。
    private var rowLabels: [String] { PricingFormatter.weekdaySymbolsMondayFirst }
    private let cellHeight: CGFloat = 7.5
    private let gap: CGFloat = 1.5
    private let labelWidth: CGFloat = 26
    private let tickHeight: CGFloat = 9

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Canvas(opaque: false, rendersAsynchronously: false) { context, size in
                draw(in: &context, size: size)
            }
            .frame(height: contentHeight)

            HStack(spacing: 14) {
                legendItem(color: WhaleTheme.brandBlue,
                           title: String(localized: "schedule.legend.peak", defaultValue: "Peak · Full price"))
                legendItem(color: Color.secondary.opacity(0.22),
                           title: String(localized: "schedule.legend.offPeak", defaultValue: "Off-peak · Half price"))
                Spacer()
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
    }

    private var contentHeight: CGFloat {
        CGFloat(rowLabels.count) * cellHeight + CGFloat(rowLabels.count - 1) * gap + tickHeight
    }

    private func legendItem(color: Color, title: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 9, height: 9)
            Text(title)
        }
    }

    // MARK: - 绘制

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let columns = 24
        let rows = rowLabels.count
        let availableWidth = size.width - labelWidth - CGFloat(columns - 1) * gap
        guard availableWidth > 0 else { return }
        let cellWidth = availableWidth / CGFloat(columns)
        let radius = min(2, cellWidth / 3)

        let calendar = DeepSeekPricing.calendar
        let currentWeekday = calendar.component(.weekday, from: now) // 1 = 周日
        let currentHour = calendar.component(.hour, from: now)
        let currentRow = (currentWeekday + 5) % 7 // 周一 → 0

        func rect(row: Int, column: Int) -> CGRect {
            CGRect(x: labelWidth + CGFloat(column) * (cellWidth + gap),
                   y: CGFloat(row) * (cellHeight + gap),
                   width: cellWidth,
                   height: cellHeight)
        }

        // 当前小时所在的列，加一层淡淡的底色。
        let hourBand = CGRect(x: labelWidth + CGFloat(currentHour) * (cellWidth + gap) - gap / 2,
                              y: 0,
                              width: cellWidth + gap,
                              height: CGFloat(rows) * cellHeight + CGFloat(rows - 1) * gap)
        context.fill(Path(roundedRect: hourBand, cornerRadius: 2), with: .color(.primary.opacity(0.07)))

        for row in 0..<rows {
            let weekdayLabel = context.resolve(
                Text(verbatim: rowLabels[row])
                    .font(.system(size: 8, weight: row == currentRow ? .bold : .medium))
                    .foregroundStyle(row == currentRow ? Color.primary : Color.secondary)
            )
            context.draw(weekdayLabel,
                         at: CGPoint(x: labelWidth - 7, y: rect(row: row, column: 0).midY),
                         anchor: .trailing)

            for column in 0..<columns {
                let isPeak = row < 5 && DeepSeekPricing.peakHourRanges.contains { $0.contains(column) }
                let path = Path(roundedRect: rect(row: row, column: column), cornerRadius: radius)
                context.fill(path, with: .color(isPeak
                                                ? WhaleTheme.brandBlue.opacity(0.92)
                                                : Color.secondary.opacity(0.18)))

                if row == currentRow && column == currentHour {
                    context.stroke(path, with: .color(.primary.opacity(0.85)), lineWidth: 1.3)
                }
            }
        }

        // 底部的小时刻度。
        let tickY = CGFloat(rows) * (cellHeight + gap) + 1
        for hour in [0, 6, 12, 18] {
            let label = context.resolve(
                Text(verbatim: "\(hour)").font(.system(size: 7.5)).foregroundStyle(Color.secondary)
            )
            context.draw(label,
                         at: CGPoint(x: labelWidth + CGFloat(hour) * (cellWidth + gap) + cellWidth / 2, y: tickY),
                         anchor: .top)
        }
        let endLabel = context.resolve(
            Text(verbatim: "24").font(.system(size: 7.5)).foregroundStyle(Color.secondary)
        )
        context.draw(endLabel,
                     at: CGPoint(x: labelWidth + CGFloat(columns) * (cellWidth + gap) - gap, y: tickY),
                     anchor: .topTrailing)
    }
}

#Preview("一周时段表") {
    WeekScheduleGrid(now: Date())
        .frame(width: 288)
        .padding()
}
