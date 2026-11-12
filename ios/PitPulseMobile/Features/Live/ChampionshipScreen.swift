import Charts
import SharedData
import SwiftUI

struct ChampionshipScreen: View {
    @EnvironmentObject private var model: MobileModel
    @State private var drivers: [DriverStanding] = []
    @State private var teams: [ConstructorStanding] = []
    let mode: Int
    @State private var selectedID: String?
    @State private var analysis: SeasonAnalysis?
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PulseHeading(eyebrow: "Formula 1 · \(model.season)", title: mode == 0 ? "车手积分" : "车队积分")
                    if let id = selectedID {
                        PulseCard {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(spacing: 16) {
                                    AssetImage(name: MotorsportAssetName.name(kind: mode == 0 ? .helmet : .teamLogo, id: id, season: model.season)).frame(width: 94, height: 100)
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(selectedName).font(.title3.bold())
                                            if mode == 0 {
                                                Button { model.favoriteDriverID = model.favoriteDriverID == selectedID ? nil : selectedID } label: {
                                                    Image(systemName: model.favoriteDriverID == selectedID ? "star.fill" : "star")
                                                }.buttonStyle(.plain).foregroundStyle(PulseStyle.red).accessibilityLabel("收藏 \(selectedName)")
                                            }
                                        }
                                        if mode == 0, let row = drivers.first(where: { $0.id == selectedID }) {
                                            HStack(spacing: 5) {
                                                AssetImage(name: MotorsportAssetName.name(kind: .teamLogo, id: row.constructorIds.first ?? "", season: model.season)).frame(width: 22, height: 16)
                                                Text(row.constructor).font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                        Text("\(selectedPoints.formatted()) PTS").font(.headline.monospacedDigit()).foregroundStyle(PulseStyle.red)
                                    }
                                }
                                Text("赛季积分趋势").font(.caption).foregroundStyle(.secondary)
                                if let analysis, analysis.hasData {
                                    Chart(trend, id: \.round) { item in
                                        AreaMark(x: .value("站", item.round), y: .value("积分", item.points)).foregroundStyle(PulseStyle.red.opacity(0.12))
                                        LineMark(x: .value("站", item.round), y: .value("积分", item.points)).foregroundStyle(PulseStyle.red).symbol(.circle)
                                    }.frame(height: 150)
                                } else { Text(loading ? "加载趋势…" : "暂无趋势数据").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(.orange) }
                    PulseCard {
                        VStack(spacing: 0) {
                            if mode == 0 {
                                ForEach(drivers) { row in
                                    Button { selectedID = row.id } label: {
                                        standingRow(position: row.position, name: row.driverName, points: row.points, asset: MotorsportAssetName.helmetName(driverID: row.id, name: row.driverName, season: model.season), teamAsset: MotorsportAssetName.name(kind: .teamLogo, id: row.constructorIds.first ?? "", season: model.season), teamName: row.constructor, favorite: model.favoriteDriverID == row.id)
                                    }.buttonStyle(.plain)
                                }
                            } else {
                                ForEach(teams) { row in
                                    Button { selectedID = row.id } label: {
                                        standingRow(position: row.position, name: row.constructorName, points: row.points, asset: MotorsportAssetName.name(kind: .teamLogo, id: row.id, season: model.season))
                                    }.buttonStyle(.plain)
                                }
                            }
                            if drivers.isEmpty && teams.isEmpty { ContentUnavailableView("暂无积分", systemImage: "chart.bar", description: Text("当前服务器未返回 F1 积分。请在设置中检查 F1 数据，确认已连接有数据的服务器。")) }
                        }
                    }
                }.padding(20)
            }.background(PulseStyle.background)
                .toolbar { ToolbarItem(placement: .topBarLeading) { PulseSettingsButton() } }
                .task(id: model.dataContext) { await load() }
                .refreshable { await load() }
                .task(id: "\(mode):\(selectedID ?? ""):\(model.dataContext)") { await loadTrend() }
        }
    }
    private var selectedName: String { mode == 0 ? drivers.first { $0.id == selectedID }?.driverName ?? "—" : teams.first { $0.id == selectedID }?.constructorName ?? "—" }
    private var selectedPoints: Double { mode == 0 ? drivers.first { $0.id == selectedID }?.points ?? 0 : teams.first { $0.id == selectedID }?.points ?? 0 }
    private var trend: [(round: Int, points: Double)] {
        analysis?.cumulativePointsByRound ?? []
    }

    private func standingRow(position: Int, name: String, points: Double, asset: String, teamAsset: String? = nil, teamName: String? = nil, favorite: Bool = false) -> some View {
        HStack(spacing: 14) {
            Text("\(position)").font(.subheadline.bold().monospacedDigit()).frame(width: 22)
            AssetImage(name: asset).frame(width: 40, height: 36)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text(name).font(.subheadline.weight(.medium)).lineLimit(1)
                    if favorite { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(PulseStyle.red) }
                }
                if let teamAsset, let teamName {
                    HStack(spacing: 5) {
                        AssetImage(name: teamAsset).frame(width: 18, height: 13)
                        Text(teamName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Spacer(); Text(points.formatted()).font(.subheadline.bold().monospacedDigit())
        }.padding(.vertical, 14).contentShape(Rectangle())
            .background(selectedName == name ? PulseStyle.red.opacity(0.1) : .clear)
    }
    private func load() async {
        guard let url = model.serverURL else { error = "服务器地址无效"; return }
        let context = model.dataContext
        drivers = []; teams = []; selectedID = nil; analysis = nil
        error = nil
        let client = APIClient(baseURL: url)
        do {
            let response = try await client.driverStandings(season: model.season, token: model.currentToken)
            guard model.dataContext == context, !Task.isCancelled else { return }; drivers = response.data
        }
        catch { self.error = MobileModel.message(for: error) }
        do {
            let response = try await client.constructorStandings(season: model.season, token: model.currentToken)
            guard model.dataContext == context, !Task.isCancelled else { return }; teams = response.data
        }
        catch { self.error = MobileModel.message(for: error) }
        selectedID = mode == 0 ? drivers.first?.id : teams.first?.id
    }
    private func loadTrend() async {
        analysis = nil
        guard let id = selectedID, let url = model.serverURL else { return }
        loading = true; defer { loading = false }
        do {
            let response = try await APIClient(baseURL: url).seasonAnalysis(kind: mode == 0 ? "drivers" : "constructors", id: id, season: model.season, token: model.currentToken)
            try Task.checkCancellation(); analysis = response.data; error = nil
        } catch is CancellationError { } catch { if !Task.isCancelled { self.error = MobileModel.message(for: error) } }
    }
}
