import Charts
import SharedData
import SwiftUI

struct ResultsScreen: View {
    @EnvironmentObject private var model: MobileModel
    let session: Session
    let meeting: Meeting
    @State private var results: [SessionResult] = []
    @State private var error: String?
    @State private var loading = false
    @State private var quality: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PulseHeading(eyebrow: "Weekend Results", title: session.sessionType.displayName)
                Text("\(meeting.name) · R\(meeting.round ?? 0)").font(.subheadline).foregroundStyle(.secondary)
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if let quality { Text(quality).font(.caption2).foregroundStyle(.secondary) }
                if let error { Text(error).foregroundStyle(.orange) }
                PulseCard {
                    VStack(spacing: 0) {
                        HStack { Text("#   车手"); Spacer(); Text("成绩 / 最快圈") }.font(.caption2).foregroundStyle(.secondary).padding(.bottom, 12)
                        ForEach(results) { row in
                            NavigationLink { DriverAnalysisScreen(sessionID: session.id, driverID: row.driverId, name: row.driverName) } label: {
                                HStack(spacing: 12) {
                                    Text(row.position.map(String.init) ?? "—").frame(width: 22).monospacedDigit()
                                    AssetImage(name: MotorsportAssetName.helmetName(driverID: row.driverId, name: row.driverName, season: meeting.season)).frame(width: 34, height: 30)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(MotorsportAssetName.abbreviation(row.driverName)).font(.subheadline.bold())
                                        HStack(spacing: 4) { AssetImage(name: MotorsportAssetName.name(kind: .teamLogo, id: row.constructorId, season: meeting.season)).frame(width: 15, height: 12); Text(row.team).font(.system(size: 9)).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(row.position == nil ? row.classificationLabel : (row.time ?? row.bestLap ?? row.gap ?? row.classificationLabel)).font(.caption.monospacedDigit())
                                        Text(row.points.map { "\($0.formatted()) PTS" } ?? "—").font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.secondary)
                                }.padding(.vertical, 12)
                            }.buttonStyle(.plain)
                            Divider()
                        }
                        if results.isEmpty && !loading { Text("暂无成绩，场次结束并同步后可查看。").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 24) }
                    }
                }
                Text("点击车手查看圈速、分段和遥测。缺失数据保留为空。").font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }.background(PulseStyle.background).navigationTitle("场次成绩").navigationBarTitleDisplayMode(.inline)
            .task { await load() }.refreshable { await load() }
    }
    private func load() async {
        guard let url = model.serverURL else { error = "请检查服务器地址"; return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let response = try await APIClient(baseURL: url).sessionResults(sessionId: session.id, token: model.currentToken)
            results = response.data
            quality = (response.meta.stale ? "缓存过期 · " : "") + response.meta.quality.displayName
        }
        catch { self.error = MobileModel.message(for: error) }
    }
}
