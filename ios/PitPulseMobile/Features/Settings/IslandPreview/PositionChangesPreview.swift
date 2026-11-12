import SceneKit
import SharedComponents
import SharedData
import SwiftUI

struct PositionChangesPreview: View {
    typealias Driver = PitPulseActivityAttributes.Driver
    let elapsed: Double
    let reduceMotion: Bool
    let rowHeight: CGFloat = 27
    var cars: [Driver] {
        [("Lando NORRIS", "norris"), ("Max VERSTAPPEN", "max_verstappen"),
         ("Charles LECLERC", "leclerc"), ("Oscar PIASTRI", "piastri"),
         ("George RUSSELL", "russell"), ("Lewis HAMILTON", "hamilton"),
         ("Fernando ALONSO", "alonso"), ("Carlos SAINZ", "sainz"),
         ("Pierre GASLY", "gasly"), ("Alex ALBON", "albon"),
         ("Esteban OCON", "ocon"), ("Lance STROLL", "stroll"),
         ("Kimi ANTONELLI", "antonelli"), ("Oliver BEARMAN", "bearman"),
         ("Liam LAWSON", "lawson"), ("Isack HADJAR", "hadjar"),
         ("Nico HULKENBERG", "hulkenberg"), ("Gabriel BORTOLETO", "bortoleto"),
         ("Franco COLAPINTO", "colapinto"), ("Sergio PEREZ", "perez"),
         ("Valtteri BOTTAS", "bottas"), ("Arvid LINDBLAD", "arvid_lindblad")].map {
            Driver(name: $0.0, asset: "helmet-\($0.1)-2026")
        }
    }
    private static let eventTimes: [Double] = [0, 12, 15, 19, 24, 28, 40, 52, 64, 76]
    static func event(at elapsed: Double) -> Int {
        let time = elapsed.truncatingRemainder(dividingBy: 100)
        return eventTimes.lastIndex(where: { $0 <= time }) ?? 0
    }
    static func phase(at elapsed: Double) -> Double {
        elapsed.truncatingRemainder(dividingBy: 100) - eventTimes[event(at: elapsed)]
    }
    func order(_ scene: Int) -> [Int] {
        var result = Array(0..<22)
        guard scene > 0, scene < 9 else { return result }
        for index in 1...scene {
            switch index {
            case 1: result.swapAt(6, 7)
            case 2: result.swapAt(7, 8)
            case 3: result.swapAt(8, 9)
            case 4: result.swapAt(9, 10)
            case 5: result.swapAt(10, 11)
            case 6: result.swapAt(2, 3)
            case 7: result.swapAt(4, 5); result.swapAt(16, 17)
            case 8: result.swapAt(0, 1)
            default: break
            }
        }
        return result
    }
    func positions(_ order: [Int]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: order.enumerated().map { (String($0.element), $0.offset + 1) })
    }
    func focus(_ scene: Int) -> Int {
        var tracker = IslandPositionFocus()
        tracker.update(positions: positions(order(0)), now: 0)
        if scene > 0 {
            for index in 1...scene { tracker.update(positions: positions(order(index)), now: Self.eventTimes[index]) }
        }
        return tracker.driverID.flatMap(Int.init) ?? 0
    }
    func eased(_ t: Double) -> Double { let x = min(1, max(0, t)); return 1 - pow(1 - x, 3) }
    var body: some View {
        let scene = Self.event(at: elapsed)
        let phase = Self.phase(at: elapsed)
        let old = order(scene == 0 ? 9 : scene - 1), next = order(scene)
        let oldFocus = focus(scene == 0 ? 9 : scene - 1), nextFocus = focus(scene)
        let exchange = reduceMotion ? 1 : eased((phase - 0.65) / 0.65)
        // While the same car keeps changing position, move its viewport along
        // with the rows so the focused helmet stays anchored in the center.
        let scroll = oldFocus == nextFocus ? exchange : (reduceMotion ? 1 : eased(phase / 0.65))
        let oldStart = min(17, max(0, (old.firstIndex(of: oldFocus) ?? 0) - 2))
        let newStart = min(17, max(0, (next.firstIndex(of: nextFocus) ?? 0) - 2))
        let start = Double(oldStart) + Double(newStart - oldStart) * scroll
        let leaderID = (exchange < 0.5 ? old : next)[0]
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("LAP").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    ActivityNumberText("\(32 + min(scene, 5))/71").font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("LIVE").font(.system(size: 7, weight: .heavy)).padding(.horizontal, 4).padding(.vertical, 2).background(.white, in: Capsule()).foregroundStyle(.black)
                }
                Rectangle().fill(.white.opacity(0.15)).frame(height: 1)
                HStack(spacing: 5) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("P1").font(.system(size: 9)).foregroundStyle(.secondary)
                        Text(MotorsportAssetName.abbreviation(cars[leaderID].name))
                            .font(.system(size: 17, weight: .heavy)).foregroundStyle(PulseStyle.red)
                    }
                    if let asset = cars[leaderID].asset { MotorsportImages.image(named: asset).resizable().scaledToFit().frame(width: 44, height: 44) }
                }
            }.frame(width: 105, alignment: .leading)
            Rectangle().fill(.white.opacity(0.12)).frame(width: 1)
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    ForEach(0..<22, id: \.self) { id in
                        let a = old.firstIndex(of: id)!, b = next.firstIndex(of: id)!
                        let position = exchange < 0.5 ? a + 1 : b + 1
                        HStack(spacing: 5) {
                            ActivityNumberText("\(b + 1)")
                                .environment(\.activityPreviewNumbers, .init(previous: ["\(b + 1)": "\(a + 1)"], progress: exchange, reduceMotion: reduceMotion))
                                        .font(.system(size: 10, weight: .semibold)).frame(width: 16)
                            if let asset = cars[id].asset { MotorsportImages.image(named: asset).resizable().scaledToFit().frame(width: 25, height: 25) }
                            Text(MotorsportAssetName.abbreviation(cars[id].name)).font(.system(size: 10, weight: .semibold))
                            if a != b {
                                Image(systemName: b < a ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                                    .font(.system(size: 7)).foregroundStyle(b < a ? .green : .red)
                            }
                            Spacer(minLength: 0)
                            Text(position == 1 ? "LEADER" : String(format: "+%.3f", Double(position - 1) * 1.271 + Double(id) * 0.023))
                                .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4).frame(width: geometry.size.width, height: rowHeight)
                        .background(id == nextFocus ? Color.red.opacity(0.20) : .clear, in: RoundedRectangle(cornerRadius: 4))
                        .opacity(a != b && id != nextFocus ? 1 - 0.65 * sin(.pi * exchange) : 1)
                        .zIndex(id == nextFocus ? 1 : 0)
                        .offset(x: a == b ? 0 : (id == nextFocus ? 9 : -9) * sin(.pi * exchange),
                                y: (Double(a) + Double(b - a) * exchange - start) * rowHeight)
                    }
                }
            }.frame(height: rowHeight * 5).clipped()
        }.frame(height: rowHeight * 5)
        .accessibilityElement(children: .combine)
    }
}
