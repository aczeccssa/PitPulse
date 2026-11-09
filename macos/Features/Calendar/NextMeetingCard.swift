import SwiftUI
import PitPulseData
import PitPulseShared

struct NextMeetingCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let meeting = CalendarLogic.featuredMeeting(in: model.meetings, now: context.date) {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(CountryFlag.display(country: meeting.country, code: meeting.countryCode))
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text(meeting.name).font(.title2.weight(.semibold))
                            Text(meeting.location).foregroundStyle(.secondary)
                            Text("\(meeting.startDate.formatted(.dateTime.month().day())) – \(meeting.endDate.formatted(.dateTime.month().day())) · 第 \(meeting.round.map(String.init) ?? "—") 站")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let next = CalendarLogic.nextSession(in: [meeting], now: context.date) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("接下来 · \(next.session.sessionType.displayName)").font(.headline)
                                    Text(next.session.startTime.formatted(.dateTime.weekday().hour().minute()))
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(CalendarLogic.countdownText(until: next.session.startTime, now: context.date))
                                    .font(.headline.monospacedDigit())
                            }
                            .padding(14)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                        }
                        MeetingMapView(meeting: meeting)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("比赛周末").font(.headline).padding(.bottom, 10)
                            ForEach(meeting.sessions.sorted { $0.startTime < $1.startTime }) { session in
                                HStack(spacing: 12) {
                                    Text(session.sessionType.displayName).font(.body.weight(.medium))
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text(session.startTime.formatted(.dateTime.weekday().hour().minute()))
                                            .monospacedDigit()
                                        if session.status == .cancelled || session.status == .postponed {
                                            Text(session.status.displayName)
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(.vertical, 11)
                                if session.id != meeting.sessions.sorted(by: { $0.startTime < $1.startTime }).last?.id { Divider() }
                            }
                        }
                        DisclosureGroup("数据详情") {
                            MetadataView(meta: model.meta, localLoadedAt: model.lastSuccessfulLoadAt)
                                .padding(.top, 6)
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    if model.isRefreshing {
                        ProgressView().accessibilityLabel("读取赛历")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ContentUnavailableView("暂无比赛", systemImage: "calendar", description: Text("刷新或选择其他赛季。"))
                    }
                }
            }
            .padding(20)
            .background(CalendarScrollAppearance())
        }
    }
}

struct MetadataView: View {
    let meta: ResponseMeta?
    let localLoadedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let meta {
                HStack {
                    Label(meta.quality.displayName, systemImage: meta.stale ? AppSymbol.warning.resolvedSystemName() : AppSymbol.cache.resolvedSystemName())
                    Spacer()
                    Text("revision \(meta.revision)")
                }
                if let source = meta.source {
                    Text("来源：\(source)")
                }
                if let fetchedAt = meta.fetchedAt {
                    Text("服务端抓取：\(fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                }
            }
            if let localLoadedAt {
                Text("本地最近成功读取：\(localLoadedAt.formatted(date: .abbreviated, time: .shortened))")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}
