import SwiftUI

struct NextMeetingCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let next = model.nextSession {
                    meetingCard(next: next, now: context.date)
                } else {
                    emptyState
                }
            }
            .padding(16)
        }
    }

    private func meetingCard(next: NextSession, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(CountryFlag.display(country: next.meeting.country, code: next.meeting.countryCode))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(next.meeting.name)
                        .font(.title3.weight(.semibold))
                    Text(next.meeting.location)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if next.meeting.status != .scheduled {
                    Text(next.meeting.status.displayName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.thinMaterial, in: Capsule())
                }
            }

            Divider()

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(next.session.sessionType.displayName)
                        .font(.headline)
                    Text(next.session.startTime.formatted(date: .abbreviated, time: .shortened))
                        .font(.callout)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Label(CalendarLogic.countdownText(until: next.session.startTime, now: now), systemImage: AppSymbol.timer.resolvedSystemName())
                        .font(.callout.weight(.semibold))
                    Text("倒计时")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            MetadataView(meta: model.meta, localLoadedAt: model.lastSuccessfulLoadAt)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: AppSymbol.calendar.resolvedSystemName())
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(model.isRefreshing ? "正在加载赛历" : "暂无未来赛程")
                .font(.headline)
            Text("\(model.selectedSeason) 赛季没有可安排或仍有未来 Session 的赛事。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
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
