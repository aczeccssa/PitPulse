import AppKit
import SwiftUI

struct StandingsView: View {
    @ObservedObject var model: AppModel
    @State private var selectedDriver: DriverStanding?
    @State private var selectedConstructor: ConstructorStanding?

    var body: some View {
        Group {
            if let row = selectedDriver {
                StandingDetail(model: model, kind: "drivers", id: row.driverId, title: row.driverName, season: row.season, position: row.position, points: row.points, wins: row.wins, team: row.constructor) {
                    selectedDriver = nil
                }
            } else if let row = selectedConstructor {
                StandingDetail(model: model, kind: "constructors", id: row.constructorId, title: row.constructorName, season: row.season, position: row.position, points: row.points, wins: row.wins, team: nil) {
                    selectedConstructor = nil
                }
            } else {
                standingsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: model.selectedSeason) { _, _ in selectedDriver = nil; selectedConstructor = nil }
        .onChange(of: model.serverAddress) { _, _ in selectedDriver = nil; selectedConstructor = nil }
        .onChange(of: model.showingConstructorStandings) { _, _ in selectedDriver = nil; selectedConstructor = nil }
        .task(id: "\(model.selectedSeason)-\(model.showingConstructorStandings)") { await model.refreshStandings() }
    }

    private var standingsList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("赛季积分").font(.headline)
                Spacer()
                Button { model.selectSeason(model.selectedSeason - 1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless).accessibilityLabel("上一年")
                Text(String(model.selectedSeason)).font(.headline.monospacedDigit())
                Button { model.selectSeason(model.selectedSeason + 1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless).accessibilityLabel("下一年")
            }
            Picker("积分榜", selection: Binding(
                get: { model.showingConstructorStandings },
                set: { model.selectStandings(isConstructor: $0) }
            )) {
                Text("车手").tag(false)
                Text("车队").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden()
            .accessibilityLabel("选择车手或车队积分榜")

            if let error = model.standingsError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }

            if model.showingConstructorStandings {
                standingRows(model.constructorStandings) { row in
                    Button { selectedConstructor = row } label: {
                        HStack(spacing: 12) {
                            rank(row.position)
                            teamImage(row.constructorId)
                            Text(row.constructorName).font(.body.weight(.medium)).lineLimit(1)
                            Spacer(minLength: 8)
                            score(points: row.points, wins: row.wins)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 14).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityHint("查看车队积分详情")
                }
            } else {
                standingRows(model.driverStandings) { row in
                    Button { selectedDriver = row } label: {
                        HStack(spacing: 12) {
                            rank(row.position)
                            if let image = MotorsportAsset.image(kind: .helmet, id: row.driverId, season: model.selectedSeason) {
                                Image(nsImage: image).resizable().scaledToFit().frame(width: 32, height: 32).accessibilityHidden(true)
                            } else {
                                Text(MotorsportAsset.abbreviation(row.driverName)).font(.caption2.bold())
                                    .frame(width: 32, height: 32).background(.quaternary, in: Circle()).accessibilityHidden(true)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.driverName).font(.body.weight(.medium)).lineLimit(1)
                                Text(row.constructor).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            score(points: row.points, wins: row.wins)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 13).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityHint("查看车手积分详情")
                }
            }
            if let meta = model.standingsMeta { DataProvenance(meta: meta) }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    private func rank(_ position: Int) -> some View {
        Text(String(position)).font(.body.weight(.semibold)).monospacedDigit().frame(width: 24, alignment: .trailing)
    }

    private func score(points: Double, wins: Int) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("\(points.formatted()) 分").font(.body.weight(.semibold))
            Text("\(wins) 胜").font(.caption).foregroundStyle(.secondary)
        }.monospacedDigit().fixedSize()
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
                }.background(CalendarScrollAppearance())
            }
        }
    }

    @ViewBuilder private func teamImage(_ id: String) -> some View {
        if let image = MotorsportAsset.image(kind: .teamLogo, id: id, season: model.selectedSeason) {
            Image(nsImage: image).resizable().scaledToFit().frame(width: 32, height: 32)
                .padding(4).background(Color.gray.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
        } else {
            Image(systemName: "flag.checkered").frame(width: 40, height: 40).accessibilityHidden(true)
        }
    }
}

private struct StandingDetail: View {
    @ObservedObject var model: AppModel
    let kind: String
    let id: String
    let title: String
    let season: Int
    let position: Int
    let points: Double
    let wins: Int
    let team: String?
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("返回积分榜")
                .accessibilityLabel("返回积分榜")
                .accessibilityIdentifier("standings.back")
                .keyboardShortcut(.cancelAction)
                Text(title).font(.headline).lineLimit(1)
                Spacer(minLength: 0)
            }
            Text("\(String(season)) 赛季积分").foregroundStyle(.secondary)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let team { LabeledContent("车队", value: team) }
                    LabeledContent("排名", value: "第 \(position) 名")
                    LabeledContent("积分", value: points.formatted())
                    LabeledContent("获胜", value: "\(wins) 场")
                    SeasonAnalysisView(model: model, kind: kind, id: id, season: season, officialPoints: points)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CalendarScrollAppearance())
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
