import CoreGraphics
import Foundation
import SwiftUI

/// 一个最小但完整的 SVG `path` `d` 属性解析器。
///
/// 支持全部 SVG 1.1 路径命令：`M/m L/l H/h V/v C/c S/s Q/q T/t A/a Z/z`，
/// 其中椭圆弧 `A/a` 会按照 SVG 规范转换为三次贝塞尔曲线。
/// 有了它，DeepSeek 官方鲸鱼图标的矢量路径可以原样内嵌，无需任何图片资源，
/// 因此在菜单栏里任意尺寸都不会模糊，也可以自由着色。
enum SVGPathParser {

    private static let commandLetters: Set<Character> = ["M", "m", "L", "l", "H", "h", "V", "v",
                                                         "C", "c", "S", "s", "Q", "q", "T", "t",
                                                         "A", "a", "Z", "z"]

    /// 把 SVG 路径字符串转换成 `Path`。
    static func path(from data: String) -> Path {
        var scanner = Scanner(data)
        var path = Path()

        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        /// 上一个三次/二次贝塞尔曲线的控制点，用于 `S`/`T` 的对称推导。
        var lastControl: CGPoint?
        /// 上一条实际执行的命令，用于隐式重复与 `S`/`T` 判断。
        var segmentCommand: Character = " "
        /// 最近读到（或隐式推导出）的命令字母。
        var command: Character = " "

        parse: while true {
            scanner.skipSeparators()
            if scanner.isAtEnd { break }

            if let letter = scanner.peek(), commandLetters.contains(letter) {
                command = letter
                scanner.advance()
            } else if segmentCommand == " " || segmentCommand == "Z" || segmentCommand == "z" {
                break // 路径不能以数字开头，也不能在 Z 之后隐式重复。
            } else {
                // 隐式重复上一条命令；`M` 之后隐式重复的是 `L`。
                switch segmentCommand {
                case "M": command = "L"
                case "m": command = "l"
                default: command = segmentCommand
                }
            }

            let relative = command.isLowercase
            let absolute = Character(command.uppercased())

            func resolve(_ x: Double, _ y: Double) -> CGPoint {
                relative
                    ? CGPoint(x: current.x + x, y: current.y + y)
                    : CGPoint(x: x, y: y)
            }

            switch absolute {
            case "M":
                guard let x = scanner.scanNumber(), let y = scanner.scanNumber() else { break parse }
                let point = resolve(x, y)
                path.move(to: point)
                current = point
                subpathStart = point
                lastControl = nil

            case "L":
                guard let x = scanner.scanNumber(), let y = scanner.scanNumber() else { break parse }
                let point = resolve(x, y)
                path.addLine(to: point)
                current = point
                lastControl = nil

            case "H":
                guard let x = scanner.scanNumber() else { break parse }
                let point = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: point)
                current = point
                lastControl = nil

            case "V":
                guard let y = scanner.scanNumber() else { break parse }
                let point = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: point)
                current = point
                lastControl = nil

            case "C":
                guard let x1 = scanner.scanNumber(), let y1 = scanner.scanNumber(),
                      let x2 = scanner.scanNumber(), let y2 = scanner.scanNumber(),
                      let x = scanner.scanNumber(), let y = scanner.scanNumber() else { break parse }
                let control1 = resolve(x1, y1)
                let control2 = resolve(x2, y2)
                let point = resolve(x, y)
                path.addCurve(to: point, control1: control1, control2: control2)
                current = point
                lastControl = control2

            case "S":
                guard let x2 = scanner.scanNumber(), let y2 = scanner.scanNumber(),
                      let x = scanner.scanNumber(), let y = scanner.scanNumber() else { break parse }
                let reflected: CGPoint
                if let lastControl, segmentCommand == "C" || segmentCommand == "c" || segmentCommand == "S" || segmentCommand == "s" {
                    reflected = CGPoint(x: current.x * 2 - lastControl.x, y: current.y * 2 - lastControl.y)
                } else {
                    reflected = current
                }
                let control2 = resolve(x2, y2)
                let point = resolve(x, y)
                path.addCurve(to: point, control1: reflected, control2: control2)
                current = point
                lastControl = control2

            case "Q":
                guard let x1 = scanner.scanNumber(), let y1 = scanner.scanNumber(),
                      let x = scanner.scanNumber(), let y = scanner.scanNumber() else { break parse }
                let control = resolve(x1, y1)
                let point = resolve(x, y)
                path.addQuadCurve(to: point, control: control)
                current = point
                lastControl = control

            case "T":
                guard let x = scanner.scanNumber(), let y = scanner.scanNumber() else { break parse }
                let reflected: CGPoint
                if let lastControl, segmentCommand == "Q" || segmentCommand == "q" || segmentCommand == "T" || segmentCommand == "t" {
                    reflected = CGPoint(x: current.x * 2 - lastControl.x, y: current.y * 2 - lastControl.y)
                } else {
                    reflected = current
                }
                let point = resolve(x, y)
                path.addQuadCurve(to: point, control: reflected)
                current = point
                lastControl = reflected

            case "A":
                guard let rx = scanner.scanNumber(), let ry = scanner.scanNumber(),
                      let rotation = scanner.scanNumber(),
                      let largeArc = scanner.scanFlag(), let sweep = scanner.scanFlag(),
                      let x = scanner.scanNumber(), let y = scanner.scanNumber() else { break parse }
                let point = resolve(x, y)
                appendArc(to: &path, from: current, to: point,
                          rx: rx, ry: ry, xAxisRotation: rotation,
                          largeArc: largeArc, sweep: sweep)
                current = point
                lastControl = nil

            case "Z":
                path.closeSubpath()
                current = subpathStart
                lastControl = nil

            default:
                break parse
            }

            segmentCommand = command
        }

        return path
    }

    // MARK: - 椭圆弧 → 三次贝塞尔

    /// SVG 规范 F.6 的端点参数转中心参数算法，再把每段（不超过 90°）用三次贝塞尔逼近。
    private static func appendArc(to path: inout Path,
                                  from start: CGPoint,
                                  to end: CGPoint,
                                  rx inputRx: Double,
                                  ry inputRy: Double,
                                  xAxisRotation: Double,
                                  largeArc: Bool,
                                  sweep: Bool) {
        var rx = abs(inputRx)
        var ry = abs(inputRy)

        // 半径为 0 或首尾重合：按直线/空段处理。
        if rx == 0 || ry == 0 { path.addLine(to: end); return }
        if abs(start.x - end.x) < 1e-12 && abs(start.y - end.y) < 1e-12 { return }

        let phi = xAxisRotation.truncatingRemainder(dividingBy: 360) * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        let dx2 = (start.x - end.x) / 2
        let dy2 = (start.y - end.y) / 2
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2

        // 半径过小时按规范放大。
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let scale = sqrt(lambda)
            rx *= scale
            ry *= scale
        }

        let sign: Double = (largeArc != sweep) ? 1 : -1
        let numerator = max(0, rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p)
        let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let coefficient = denominator == 0 ? 0 : sign * sqrt(numerator / denominator)
        let cxp = coefficient * (rx * y1p / ry)
        let cyp = coefficient * (-ry * x1p / rx)

        let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let dot = ux * vx + uy * vy
            let length = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            guard length > 0 else { return 0 }
            var value = acos(min(max(dot / length, -1), 1))
            if ux * vy - uy * vx < 0 { value = -value }
            return value
        }

        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var deltaTheta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && deltaTheta > 0 { deltaTheta -= 2 * .pi }
        if sweep && deltaTheta < 0 { deltaTheta += 2 * .pi }

        let segmentCount = max(1, Int(ceil(abs(deltaTheta) / (.pi / 2))))
        let delta = deltaTheta / Double(segmentCount)

        func map(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: cosPhi * x - sinPhi * y + cx,
                    y: sinPhi * x + cosPhi * y + cy)
        }

        var theta = theta1
        for _ in 0..<segmentCount {
            let theta2 = theta + delta
            let alpha = 4.0 / 3.0 * tan(delta / 4)
            let endPoint = map(rx * cos(theta2), ry * sin(theta2))
            let control1 = map(rx * cos(theta) - alpha * rx * sin(theta),
                               ry * sin(theta) + alpha * ry * cos(theta))
            let control2 = map(rx * cos(theta2) + alpha * rx * sin(theta2),
                               ry * sin(theta2) - alpha * ry * cos(theta2))
            path.addCurve(to: endPoint, control1: control1, control2: control2)
            theta = theta2
        }
    }

    // MARK: - 词法扫描

    private struct Scanner {
        private let characters: [Character]
        private var index = 0

        init(_ string: String) {
            characters = Array(string)
        }

        var isAtEnd: Bool { index >= characters.count }

        mutating func skipSeparators() {
            while index < characters.count {
                let character = characters[index]
                if character == " " || character == "," || character == "\n"
                    || character == "\r" || character == "\t" {
                    index += 1
                } else {
                    break
                }
            }
        }

        mutating func peek() -> Character? {
            skipSeparators()
            return index < characters.count ? characters[index] : nil
        }

        mutating func advance() {
            index += 1
        }

        /// 读取一个 SVG 数字：支持 `1`、`-1`、`.5`、`-.5`、`1.5e-3`，以及 `5.5.5` 这类粘连写法。
        mutating func scanNumber() -> Double? {
            skipSeparators()
            let start = index
            var sawDigit = false
            var sawDot = false
            var sawExponent = false

            while index < characters.count {
                let character = characters[index]
                if character.isNumber {
                    sawDigit = true
                    index += 1
                } else if character == "+" || character == "-" {
                    let isLeadingSign = index == start
                    let isExponentSign = sawExponent && index > start
                        && (characters[index - 1] == "e" || characters[index - 1] == "E")
                    if isLeadingSign || isExponentSign {
                        index += 1
                    } else {
                        break
                    }
                } else if character == "." {
                    if sawDot || sawExponent { break }
                    sawDot = true
                    index += 1
                } else if character == "e" || character == "E" {
                    if sawExponent || !sawDigit { break }
                    sawExponent = true
                    index += 1
                } else {
                    break
                }
            }

            guard sawDigit, let value = Double(String(characters[start..<index])) else {
                index = start
                return nil
            }
            return value
        }

        /// 读取圆弧标记，只接受单个 `0` 或 `1`。
        mutating func scanFlag() -> Bool? {
            skipSeparators()
            guard index < characters.count else { return nil }
            switch characters[index] {
            case "0": index += 1; return false
            case "1": index += 1; return true
            default: return nil
            }
        }
    }
}
