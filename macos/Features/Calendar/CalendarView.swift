import AppKit
import SwiftUI
import SharedData

struct CalendarView: View {
    @EnvironmentObject var model: AppModel
    @State var selectedMeetingID: String?
    @State var detailMeeting: Meeting?
    @State var showMap = false

    var selectedMeeting: Meeting? {
        if let selectedMeetingID, let match = model.meetings.first(where: { $0.id == selectedMeetingID }) {
            return match
        }
        return CalendarLogic.featuredMeeting(in: model.meetings, now: Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            if let detailMeeting {
                detailHeader(detailMeeting)
                MeetingDetailView(meeting: detailMeeting)
            } else {
                toolbar
                if showMap, !model.meetings.isEmpty {
                    mapMode
                } else if model.meetings.isEmpty {
                    emptyState
                } else {
                    masterDetail
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: "\(model.serverAddress)-\(model.selectedSeason)-\(showMap)") {
            if showMap {
                await model.mapStore.load(model: model, meeting: nil)
                model.mapStore.onMeeting = { id in
                    selectedMeetingID = id
                    showMap = false
                }
            } else {
                model.mapStore.pause()
            }
        }
        .onAppear {
            if selectedMeetingID == nil {
                selectedMeetingID = CalendarLogic.featuredMeeting(in: model.meetings, now: Date())?.id
            }
        }
        .onDisappear { model.mapStore.pause() }
        .onChange(of: model.selectedSeason) { _, _ in
            detailMeeting = nil
            selectedMeetingID = nil
        }
        .onChange(of: model.serverAddress) { _, _ in
            detailMeeting = nil
            selectedMeetingID = nil
        }
        .onChange(of: model.meetings) { _, meetings in
            if selectedMeetingID == nil {
                selectedMeetingID = CalendarLogic.featuredMeeting(in: meetings, now: Date())?.id
            }
        }
    }

    // MARK: Toolbar

    var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                Button { model.selectSeason(model.selectedSeason - 1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 11.5, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("上一年")

                Text(String(model.selectedSeason))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 34)

                Button { model.selectSeason(model.selectedSeason + 1) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 11.5, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("下一年")
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .glassEffect(.regular, in: Capsule())

            Text("\(model.meetings.count) 站")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            Spacer(minLength: 8)

            if model.isRefreshing {
                ProgressView().controlSize(.mini)
            }

            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 4) {
                    segmentButton(title: "列表", symbol: "list.bullet", active: !showMap) { showMap = false }
                    segmentButton(title: "地图", symbol: "map", active: showMap) { showMap = true }
                }
            }
        }
        .padding(.horizontal, PitPulseTheme.pagePadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    func segmentButton(title: String, symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10.5, weight: .semibold))
                Text(title).font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(active ? PitPulseTheme.accent : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(
            active
                ? .regular.tint(PitPulseTheme.accent.opacity(0.18)).interactive()
                : .regular.interactive(),
            in: Capsule()
        )
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    // MARK: Master detail

    var masterDetail: some View {
        meetingList
            .padding(.horizontal, PitPulseTheme.pagePadding)
            .padding(.bottom, 10)
    }
}
