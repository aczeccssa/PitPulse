import Foundation

public enum IslandContentMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case overview, battle, favorite, positionChanges
    public var id: String { rawValue }
    public var title: String {
        switch self { case .overview: "赛事脉搏"; case .battle: "领跑之争"; case .favorite: "我的车手"; case .positionChanges: "全场风云" }
    }
}
