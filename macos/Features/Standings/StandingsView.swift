import AppKit
import SwiftUI

struct StandingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            Picker("积分榜", selection: Binding(
                get: { model.showingConstructorStandings },
                set: { model.selectStandings(isConstructor: $0) }
            )) {
                Text("车手").tag(false)
                Text("车队").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("选择车手或车队积分榜")

            HStack {
                Text(model.showingConstructorStandings ? "车队积分" : "车手积分")
                    .font(.headline)
                Spacer()
                Picker("赛季", selection: Binding(
                    get: { model.selectedSeason },
                    set: { model.selectSeason($0) }
                )) {
                    ForEach((max(1950, model.selectedSeason - 5)...model.selectedSeason + 1).reversed(), id: \.self) {
                        Text(String($0)).tag($0)
                    }
                }
                .labelsHidden()
                .accessibilityLabel("选择积分赛季")
            }

            if let error = model.standingsError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .accessibilityLabel("积分榜刷新失败：\(error)")
            }

            if model.showingConstructorStandings {
                standingRows(model.constructorStandings) { row in
                    HStack(spacing: 8) {
                        Text("\(row.position)").frame(width: 24, alignment: .trailing).monospacedDigit()
                        teamImage(row.constructorId)
                        Text(row.constructorName).lineLimit(1)
                        Spacer()
                        Text("\(row.points.formatted()) 分 · \(row.wins) 胜")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            } else {
                standingRows(model.driverStandings) { row in
                    HStack(spacing: 8) {
                        Text("\(row.position)").frame(width: 24, alignment: .trailing).monospacedDigit()
                        if let image = MotorsportAsset.image(kind: .helmet, id: row.driverId, season: model.selectedSeason) {
                            Image(nsImage: image).resizable().scaledToFit().frame(width: 30, height: 30).accessibilityHidden(true)
                        } else {
                            Text(MotorsportAsset.abbreviation(row.driverName)).font(.caption2.bold())
                                .frame(width: 30, height: 30).background(.quaternary, in: Circle()).accessibilityHidden(true)
                        }
                        VStack(alignment: .leading) {
                            Text(row.driverName).lineLimit(1)
                            Text(row.constructor).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text("\(row.points.formatted()) 分 · \(row.wins) 胜")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            if let meta = model.standingsMeta { DataProvenance(meta: meta) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .task(id: "\(model.selectedSeason)-\(model.showingConstructorStandings)") {
            await model.refreshStandings()
        }
    }

    @ViewBuilder private func standingRows<Row: Identifiable, Content: View>(
        _ rows: [Row], @ViewBuilder content: @escaping (Row) -> Content
    ) -> some View {
        if rows.isEmpty {
            ContentUnavailableView(model.standingsError == nil ? "暂无积分" : "无法读取积分榜", systemImage: "trophy")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in content(row); Divider().padding(.leading, 48) }
                }
            }
        }
    }

    @ViewBuilder private func teamImage(_ id: String) -> some View {
        if let image = MotorsportAsset.image(kind: .teamLogo, id: id, season: model.selectedSeason) {
            Image(nsImage: image).resizable().scaledToFit().frame(width: 32, height: 28).accessibilityHidden(true)
        } else {
            Image(systemName: "flag.checkered").frame(width: 32, height: 28).accessibilityHidden(true)
        }
    }
}
