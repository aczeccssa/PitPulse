import SwiftUI
import PitPulseData
import PitPulseShared

struct OverviewScreen: View {
    @EnvironmentObject private var model: MobileModel
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PulseHeading(eyebrow: "Race Weekend", title: "下一场比赛")
                    if let next = CalendarLogic.nextSession(in: model.meetings, now: .now) {
                        NavigationLink { WeekendScreen(meeting: next.meeting) } label: {
                            PulseCard {
                                VStack(alignment: .leading, spacing: 18) {
                                    HStack { Text("F1 · R\(next.meeting.round ?? 0)").font(.caption.bold()).foregroundStyle(PulseStyle.red); Spacer(); Image(systemName: "arrow.up.right").font(.caption) }
                                    Text(next.meeting.name).font(.title.bold()).multilineTextAlignment(.leading)
                                    Text("\(next.meeting.location), \(next.meeting.country)").font(.subheadline).foregroundStyle(.secondary)
                                    CircuitOutlineView(meetingID: next.meeting.id).frame(height: 140).padding(.vertical, 8)
                                    TimelineView(.periodic(from: .now, by: 1)) { context in
                                        Text(CalendarLogic.countdownText(until: next.session.startTime, now: context.date))
                                            .font(.title2.bold().monospacedDigit()).contentTransition(.numericText())
                                    }
                                    Text("\(next.session.sessionType.displayName) · \(next.session.startTime.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.buttonStyle(PulsePressStyle())
                        PulseCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("比赛周末").font(.headline)
                                ForEach(next.meeting.sessions.filter { $0.startTime > Date() }.prefix(3)) { session in
                                    HStack { Text(session.sessionType.displayName).font(.subheadline.bold()); Spacer(); Text(session.startTime, format: .dateTime.weekday().hour().minute()).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    } else if model.loadState.isLoading { ProgressView("加载赛历…") }
                    else { ContentUnavailableView("暂无下一场比赛", systemImage: "flag.checkered", description: Text(model.loadState.errorText ?? "当前赛季没有待开始的场次。")) }
                    Button { model.settingsPresented = true } label: {
                        PulseCard {
                            HStack(spacing: 14) {
                                if let favorite = model.favoriteStanding {
                                    AssetImage(name: MotorsportAssetName.helmetName(driverID: favorite.id, name: favorite.driverName, season: model.season)).frame(width: 52, height: 48)
                                    VStack(alignment: .leading, spacing: 5) { Label("喜欢的车手", systemImage: "star.fill").font(.caption).foregroundStyle(PulseStyle.red); Text(favorite.driverName).font(.headline); Text("P\(favorite.position) · \(favorite.points.formatted()) PTS").font(.caption2).foregroundStyle(.secondary) }
                                } else { Label("选择喜欢的车手", systemImage: "star").font(.headline) }
                                Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.buttonStyle(PulsePressStyle())
                }.padding(20)
            }.background(PulseStyle.background)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { PulseSettingsButton() } }
                .refreshable { await model.loadCalendar(force: true); await model.loadF1Roster(force: true) }
        }
    }
}

struct CalendarScreen: View {
    @EnvironmentObject private var model: MobileModel
    private func raceDate(_ meeting: Meeting) -> Date { meeting.sessions.first { $0.sessionType == .race }?.startTime ?? meeting.endDate }
    private var past: [Meeting] { model.meetings.filter { raceDate($0) < Date() } }
    private var future: [Meeting] { model.meetings.filter { raceDate($0) >= Date() } }
    var body: some View {
        NavigationStack {
            ScrollViewReader { reader in
                List {
                    if !past.isEmpty {
                        Section { ForEach(past) { meeting in row(meeting).id(meeting.id) } }
                        footer: { Label("回顾", systemImage: "triangle.fill").font(.caption.bold()).foregroundStyle(PulseStyle.red) }
                    }
                    if !future.isEmpty {
                        Section { ForEach(future) { meeting in row(meeting).id(meeting.id) } }
                        header: { Label("前瞻", systemImage: "arrowtriangle.down.fill").font(.caption.bold()).foregroundStyle(PulseStyle.red) }
                    }
                    if model.meetings.isEmpty { ContentUnavailableView("暂无赛历", systemImage: "calendar", description: Text(model.loadState.errorText ?? "正在加载…")) }
                }
                .listStyle(.plain).scrollContentBackground(.hidden).background(PulseStyle.background)
                .onChange(of: model.meetings.map(\.id), initial: true) { _, _ in
                    if let next = future.first { reader.scrollTo(next.id, anchor: .center) }
                }
            }
            .navigationTitle("赛历 · \(String(model.season))").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { PulseSettingsButton() } }
            .refreshable { await model.loadCalendar(force: true) }
            .task(id: model.dataContext) { await model.loadCalendar() }
        }
    }
    private func row(_ meeting: Meeting) -> some View {
        NavigationLink { WeekendScreen(meeting: meeting) } label: {
            HStack(spacing: 14) {
                Text(meeting.round.map(String.init) ?? "—").font(.system(size: 30, weight: .heavy, design: .rounded)).frame(width: 42, alignment: .leading)
                VStack(alignment: .leading, spacing: 7) {
                    Text("\(CountryFlag.emoji(for: meeting.countryCode) ?? "")  \(meeting.location)").font(.caption.weight(.semibold))
                    Text(meeting.name).font(.headline).lineLimit(2)
                    Text(raceDate(meeting), format: .dateTime.year().month(.twoDigits).day()).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                CircuitOutlineView(meetingID: meeting.id).frame(width: 88, height: 54)
            }.padding(.vertical, 17)
        }.listRowBackground(PulseStyle.background).listRowSeparator(.visible)
    }
}

private struct CircuitEnvelope: Decodable {
    struct DataValue: Decodable {
        struct Feature: Decodable {
            struct Geometry: Decodable { let coordinates: [[Double]] }
            let geometry: Geometry
        }
        let geometry: Feature?
    }
    let data: DataValue
}

struct CircuitOutlineView: View {
    @EnvironmentObject private var model: MobileModel
    let meetingID: String
    @State private var points: [[Double]] = []
    var body: some View {
        Group {
            if points.isEmpty { Image(systemName: "map").font(.title2).foregroundStyle(.tertiary) }
            else { CircuitPath(points: points).stroke(.primary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)).padding(4) }
        }.accessibilityLabel(points.isEmpty ? "暂无赛道轮廓" : "赛道轮廓")
            .task(id: model.dataContext + meetingID) {
                guard let url = model.serverURL else { return }
                do {
                    let data = try await APIClient(baseURL: url).mapData(path: "/api/v1/meetings/\(meetingID)/geometry", token: model.currentToken)
                    points = try JSONDecoder().decode(CircuitEnvelope.self, from: data).data.geometry?.geometry.coordinates.filter { $0.count >= 2 && $0.allSatisfy(\.isFinite) } ?? []
                } catch { points = [] }
            }
    }
}

private struct CircuitPath: Shape {
    let points: [[Double]]
    func path(in rect: CGRect) -> Path {
        guard let first = points.first else { return Path() }
        let cosine = cos(first[1] * .pi / 180)
        var projected = points.map { CGPoint(x: $0[0] * cosine, y: -$0[1]) }
        let width = (projected.map(\.x).max() ?? 0) - (projected.map(\.x).min() ?? 0)
        let height = (projected.map(\.y).max() ?? 0) - (projected.map(\.y).min() ?? 0)
        if rect.width > rect.height && height > width { projected = projected.map { CGPoint(x: $0.y, y: -$0.x) } }
        let xs = projected.map(\.x), ys = projected.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(), maxX > minX, maxY > minY else { return Path() }
        let scale = min(rect.width / (maxX - minX), rect.height / (maxY - minY))
        let dx = rect.midX - (maxX + minX) * scale / 2, dy = rect.midY - (maxY + minY) * scale / 2
        return Path { path in
            for (index, point) in projected.enumerated() {
                let p = CGPoint(x: point.x * scale + dx, y: point.y * scale + dy)
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
        }
    }
}

struct WeekendScreen: View {
    let meeting: Meeting
    @State private var section = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PulseHeading(eyebrow: "Race Weekend · R\(meeting.round ?? 0)", title: meeting.name)
                Text("\(meeting.location), \(meeting.country)").foregroundStyle(.secondary)
                Picker("周末详情", selection: $section) {
                    Text("概览").tag(0); Text("赛程").tag(1); Text("天气").tag(2); Text("成绩").tag(3)
                }.pickerStyle(.segmented)
                if section == 0 {
                    PulseCard {
                        VStack(alignment: .leading, spacing: 16) {
                            LabeledContent("赛道", value: meeting.circuit?.name ?? meeting.location)
                            LabeledContent("赛季", value: String(meeting.season))
                            LabeledContent("比赛周末", value: meeting.startDate.formatted(date: .abbreviated, time: .omitted))
                            LabeledContent("状态", value: meeting.status.displayName)
                            CircuitOutlineView(meetingID: meeting.id).frame(height: 120)
                        }.font(.subheadline)
                    }
                } else if section == 2 {
                    WeekendWeather(meetingID: meeting.id)
                } else {
                PulseCard {
                    VStack(spacing: 0) {
                        ForEach(meeting.sessions.filter { section != 3 || $0.startTime < Date() }.sorted { $0.startTime < $1.startTime }) { session in
                            NavigationLink { ResultsScreen(session: session, meeting: meeting) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(session.sessionType.displayName).font(.headline)
                                        Text(session.status.displayName).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 5) {
                                        Text(session.startTime.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                                        Text(session.startTime.formatted(date: .omitted, time: .shortened)).font(.subheadline.bold().monospacedDigit())
                                    }
                                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                                }.padding(.vertical, 14)
                            }.buttonStyle(PulsePressStyle())
                            if session.id != meeting.sessions.last?.id { Divider().overlay(Color.primary.opacity(0.04)) }
                        }
                    }
                }
                }
                Text("点击场次查看成绩与逐圈遥测。时间按设备时区显示。").font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }.background(PulseStyle.background).navigationTitle("比赛周末").navigationBarTitleDisplayMode(.inline)
            .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: section)
    }
}


private struct WeekendForecast: Decodable {
    struct Forecast: Decodable {
        struct Hour: Decodable {
            let utc: String
            let airTemp: Double?
            let precipitationProbability: Double?
            let windSpeed: Double?
        }
        let status: String
        let hours: [Hour]
    }
    struct Meta: Decodable { let stale: Bool }
    let data: Forecast
    let meta: Meta
}

private struct WeekendWeather: View {
    @EnvironmentObject private var model: MobileModel
    let meetingID: String
    @State private var forecast: WeekendForecast?
    @State private var error: String?
    var body: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 16) {
                Label("赛道天气", systemImage: "cloud.sun").font(.headline)
                if let forecast {
                    if forecast.meta.stale { Text("缓存天气已过期").font(.caption).foregroundStyle(.orange) }
                    if forecast.data.hours.isEmpty {
                        Text(forecast.data.status == "past_event" ? "已结束赛事不展示当前天气。" : "尚未进入天气预报范围。").font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(Array(forecast.data.hours.enumerated()), id: \.offset) { _, hour in
                        HStack {
                            Text(ISO8601DateFormatter().date(from: hour.utc)?.formatted(date: .abbreviated, time: .shortened) ?? hour.utc).font(.caption2)
                            Spacer()
                            Text(hour.airTemp.map { "\($0.formatted())°C" } ?? "—")
                            Text(hour.precipitationProbability.map { "\($0.formatted())%" } ?? "—").foregroundStyle(.secondary)
                        }.font(.caption.monospacedDigit())
                    }
                } else if let error { Text(error).font(.caption).foregroundStyle(.orange) }
                else { ProgressView("加载天气…") }
            }
        }
        .task(id: meetingID) {
            guard let url = model.serverURL else { error = "服务器地址无效"; return }
            do {
                let data = try await APIClient(baseURL: url).mapData(path: "/api/v1/meetings/\(meetingID)/weather", token: model.currentToken)
                forecast = try JSONDecoder().decode(WeekendForecast.self, from: data)
            } catch { self.error = MobileModel.message(for: error) }
        }
    }
}
