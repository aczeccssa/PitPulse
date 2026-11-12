import AppKit
import Charts
import SwiftUI
import SharedData

struct TrackHeatmap: View {
    let location: [AnalysisLocation]
    let telemetry: [AnalysisTelemetry]
    let metric: String
    var body: some View {
        let rows = location.filter { $0.x != nil && $0.y != nil }.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        let values = rows.map { row -> Double? in
            guard let car = AnalysisMath.telemetry(at: row.date, in: telemetry) else { return nil }
            return metric == "速度" ? car.speed : metric == "油门" ? car.throttle : car.brake
        }
        Canvas { context, size in
            guard let minX = rows.compactMap(\.x).min(), let maxX = rows.compactMap(\.x).max(),
                let minY = rows.compactMap(\.y).min(), let maxY = rows.compactMap(\.y).max(), rows.count > 1 else { return }
            let scale = min((size.width - 24) / max(maxX - minX, 1), (size.height - 24) / max(maxY - minY, 1))
            let left = (size.width - (maxX - minX) * scale) / 2
            let top = (size.height - (maxY - minY) * scale) / 2
            let low = metric == "速度" ? values.compactMap { $0 }.min() ?? 0 : 0
            let high = metric == "速度" ? values.compactMap { $0 }.max() ?? 1 : 100
            for index in 1..<rows.count {
                guard let aDate = rows[index - 1].date, let bDate = rows[index].date,
                    bDate.timeIntervalSince(aDate) <= 2 else { continue }
                let a = CGPoint(x: left + (rows[index - 1].x! - minX) * scale, y: size.height - top - (rows[index - 1].y! - minY) * scale)
                let b = CGPoint(x: left + (rows[index].x! - minX) * scale, y: size.height - top - (rows[index].y! - minY) * scale)
                guard hypot(a.x - b.x, a.y - b.y) < size.width / 3 else { continue }
                var path = Path(); path.move(to: a); path.addLine(to: b)
                let color = values[index].map { Color(hue: 0.66 * (1 - min(max(($0 - low) / max(high - low, 1), 0), 1)), saturation: 0.85, brightness: 0.95) } ?? Color.gray
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
        }
        .accessibilityLabel("真实赛道行车轨迹，\(metric)热力图，\(rows.count)个坐标，\(values.compactMap { $0 }.count)个已对齐采样")
    }
}
