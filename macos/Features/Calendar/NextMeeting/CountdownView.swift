import AppKit
import SwiftUI
import SharedData

struct CountdownRow: View {
    let next: NextSession
    let now: Date

    var remaining: TimeInterval {
        max(0, next.session.startTime.timeIntervalSince(now))
    }

    var days: Int { Int(remaining) / 86_400 }
    var hours: Int { (Int(remaining) % 86_400) / 3_600 }
    var minutes: Int { (Int(remaining) % 3_600) / 60 }
    var seconds: Int { Int(remaining) % 60 }

    var body: some View {
        HStack(spacing: 5) {
            CountdownUnit(value: days, unit: "天")
            CountdownUnit(value: hours, unit: "时")
            CountdownUnit(value: minutes, unit: "分")
            CountdownUnit(value: seconds, unit: "秒")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("距下一节 \(days) 天 \(hours) 小时 \(minutes) 分")
    }
}

struct CountdownUnit: View {
    let value: Int
    let unit: String

    var body: some View {
        HStack(spacing: 1) {
            Text(String(format: "%02d", value))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(unit)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(minWidth: 26)
    }
}
