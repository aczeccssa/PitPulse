import AppKit
import SwiftUI
import SharedData

extension CalendarView {
    @ViewBuilder
    var preview: some View {
        if let meeting = selectedMeeting {
            MeetingPreviewCard(meeting: meeting) {
                detailMeeting = meeting
            }
        } else {
            GlassCard {
                VStack(spacing: 8) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("选择一个分站")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    var mapMode: some View {
        VStack(spacing: 8) {
            MapView(store: model.mapStore, meetings: model.meetings)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            if let error = model.mapStore.error {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, PitPulseTheme.pagePadding)
        .padding(.bottom, 12)
    }

    var emptyState: some View {
        VStack(spacing: 10) {
            if model.connectionStatus == .loading {
                ProgressView().accessibilityLabel("读取 \(model.selectedSeason) 赛季")
            } else {
                EmptyStateCard(
                    symbol: AppSymbol.calendar.resolvedSystemName(),
                    title: "暂无赛历",
                    message: "该赛季尚未同步，或当前服务器没有数据。"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(PitPulseTheme.pagePadding)
    }

    func detailHeader(_ meeting: Meeting) -> some View {
        HStack(spacing: 10) {
            Button {
                detailMeeting = nil
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12.5, weight: .bold))
                    .frame(width: 28, height: 28)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("返回赛历")
            .accessibilityLabel("返回赛历")
            .accessibilityIdentifier("calendar.back")
            .keyboardShortcut(.cancelAction)

            Text(meeting.name)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PitPulseTheme.pagePadding)
        .padding(.vertical, 8)
    }
}
