import SwiftUI
import SharedData

struct MeetingDetailView: View {
    enum DetailTab: String, CaseIterable, Identifiable {
        case overview = "概览"
        case weekend = "周末"
        case weather = "天气"
        case analysis = "分析"

        var id: String { rawValue }
    }

    @EnvironmentObject var model: AppModel
    let meeting: Meeting
    @State var tab: DetailTab = .overview
    @State var forecast: PitPulseForecast?
    @State var forecastStatus = "正在读取预报…"
    @State var mapExpanded = false

    var sortedSessions: [Session] {
        meeting.sessions.sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            subTabs
            ScrollView {
                Group {
                    switch tab {
                    case .overview: overview
                    case .weekend: weekend
                    case .weather: weather
                    case .analysis: analysis
                    }
                }
                .padding(.horizontal, PitPulseTheme.pagePadding)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(CalendarScrollAppearance())
            }
        }
        .task(id: "\(meeting.id)-\(model.serverAddress)") {
            forecast = nil
            forecastStatus = "正在读取预报…"
            do {
                let result = try await MeetingForecast.load(meetingID: meeting.id, model: model)
                try Task.checkCancellation()
                forecast = result.forecast
                forecastStatus = result.stale ? "\(result.forecast.statusText) · 已过期" : result.forecast.statusText
            } catch is CancellationError {
                return
            } catch {
                forecastStatus = "天气暂不可用：\(error.localizedDescription)"
            }
        }
        .onDisappear { model.mapStore.pause() }
    }

    // MARK: Header

    var header: some View {
        HStack(alignment: .top, spacing: 11) {
            Text(CountryFlag.display(country: meeting.country, code: meeting.countryCode))
                .font(.system(size: 20))
                .accessibilityLabel("举办国 \(meeting.country)")

            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.name)
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.2)
                    .lineLimit(1)
                Text("\(meeting.circuit?.name ?? meeting.location) · \(meeting.location)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("第 \(meeting.round.map(String.init) ?? "—") 站")
                    Text("·")
                    Text("\(meeting.startDate.formatted(.dateTime.month().day())) – \(meeting.endDate.formatted(.dateTime.month().day()))")
                        .monospacedDigit()
                    Text("·")
                    Text(meeting.status.displayName)
                        .foregroundStyle(meeting.status == .scheduled ? Color.secondary : Color.orange)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                Text(String(meeting.season))
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Text("R\(meeting.round.map(String.init) ?? "—")")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, PitPulseTheme.pagePadding)
        .padding(.bottom, 10)
    }

    var subTabs: some View {
        LiquidSegmented(
            items: DetailTab.allCases.map { .init(value: $0, title: $0.rawValue) },
            selection: $tab
        )
        .padding(.horizontal, PitPulseTheme.pagePadding)
        .padding(.bottom, 2)
    }

    // MARK: Overview

}
