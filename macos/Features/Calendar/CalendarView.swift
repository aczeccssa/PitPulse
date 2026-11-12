import AppKit
import SwiftUI
import SharedData

struct CalendarView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedMeetingID: String?
    @State private var detailMeeting: Meeting?
    @State private var showMap = false

    private var selectedMeeting: Meeting? {
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

    private var toolbar: some View {
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

    private func segmentButton(title: String, symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
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

    private var masterDetail: some View {
        meetingList
            .padding(.horizontal, PitPulseTheme.pagePadding)
            .padding(.bottom, 10)
    }

    private var finishedMeetings: [Meeting] {
        model.meetings.filter { $0.endDate < Date() }.sorted { $0.startDate > $1.startDate }
    }

    private var upcomingMeetings: [Meeting] {
        model.meetings.filter { $0.endDate >= Date() }.sorted { $0.startDate < $1.startDate }
    }

    private var meetingList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    let upcoming = upcomingMeetings
                    if !upcoming.isEmpty {
                        groupHeader("待开始", count: upcoming.count)
                        ForEach(upcoming) { meeting in
                            row(meeting)
                        }
                    }
                    let finished = finishedMeetings
                    if !finished.isEmpty {
                        groupHeader("已结束", count: finished.count)
                            .padding(.top, upcoming.isEmpty ? 0 : 8)
                        ForEach(finished) { meeting in
                            row(meeting)
                        }
                    }
                }
                .padding(6)
            }
            .background(CalendarScrollAppearance())
            .onAppear {
                if let id = selectedMeeting?.id { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: selectedMeetingID) { _, id in
                guard let id else { return }
                withAnimation(.snappy(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func groupHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.6)
            Text(String(count))
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 5)
    }

    private func row(_ meeting: Meeting) -> some View {
        let isSelected = meeting.id == selectedMeeting?.id
        let isUpcoming = meeting.endDate >= Date()
        return Button {
            withAnimation(.snappy(duration: 0.2)) { selectedMeetingID = meeting.id }
            detailMeeting = meeting
        } label: {
            VStack(alignment: .leading, spacing: isUpcoming ? 5 : 0) {
                HStack(spacing: 8) {
                    Text("R\(meeting.round.map(String.init) ?? "—")")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(isSelected ? PitPulseTheme.accent : Color.secondary)
                        .frame(width: 30, alignment: .leading)

                    Text(CountryFlag.emoji(for: meeting.countryCode) ?? "🌐")
                        .font(.system(size: isUpcoming ? 15 : 13))
                        .accessibilityLabel("举办国 \(meeting.country)")

                    Text(meeting.name)
                        .font(.system(size: isUpcoming ? 13.5 : 12.5, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(isUpcoming ? dateRange(meeting) : meeting.startDate.formatted(.dateTime.month().day()))
                        .font(.system(size: isUpcoming ? 10.5 : 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(isUpcoming ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))

                    if !isUpcoming {
                        if meeting.status != .scheduled {
                            Text(meeting.status.displayName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.orange)
                                .frame(width: 34, alignment: .trailing)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.tertiary)
                                .frame(width: 34, alignment: .trailing)
                        }
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.quaternary)
                }

                if isUpcoming {
                    upcomingDetails(meeting)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, isUpcoming ? 10 : 9)
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.white.opacity(0.14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.26), lineWidth: 1)
                    }
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(PitPulseTheme.accent)
                            .frame(width: 2.5, height: isUpcoming ? 40 : 20)
                            .padding(.leading, 1)
                    }
            }
        }
        .overlay(alignment: .bottom) {
            if isUpcoming {
                Rectangle()
                    .fill(.primary.opacity(0.06))
                    .frame(height: 0.7)
                    .padding(.leading, 39)
                    .padding(.trailing, 9)
            }
        }
        .id(meeting.id)
        .accessibilityLabel("\(meeting.name)，第 \(meeting.round.map(String.init) ?? "—") 站，\(meeting.startDate.formatted(date: .abbreviated, time: .omitted))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Upcoming rounds carry one extra line: where the race is, when its next
    /// session starts and how long until then. No badge or background — the
    /// countdown alone carries the emphasis.
    @ViewBuilder
    private func upcomingDetails(_ meeting: Meeting) -> some View {
        let next = CalendarLogic.nextSession(in: [meeting], now: Date())
        HStack(spacing: 5) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.tertiary)

            Text(meeting.circuit?.name ?? meeting.location)
                .lineLimit(1)

            if let next {
                Text("·")
                    .foregroundStyle(.quaternary)
                Text(next.session.sessionType.displayName)
                Text(next.session.startTime.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            if let next {
                Text("\(CalendarLogic.countdownText(until: next.session.startTime, now: Date()))后")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PitPulseTheme.accent)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.leading, 38)
        .padding(.trailing, 2)
    }

    private func dateRange(_ meeting: Meeting) -> String {
        let calendar = Calendar.current
        let start = meeting.startDate.formatted(.dateTime.month().day())
        let end = calendar.isDate(meeting.startDate, equalTo: meeting.endDate, toGranularity: .month)
            ? meeting.endDate.formatted(.dateTime.day())
            : meeting.endDate.formatted(.dateTime.month().day())
        return start == end ? start : "\(start)–\(end)"
    }

    @ViewBuilder
    private var preview: some View {
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

    private var mapMode: some View {
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

    private var emptyState: some View {
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

    private func detailHeader(_ meeting: Meeting) -> some View {
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

// MARK: - Preview card

private struct MeetingPreviewCard: View {
    let meeting: Meeting
    let openDetail: () -> Void

    private var nextSession: NextSession? {
        CalendarLogic.nextSession(in: [meeting], now: Date())
    }

    var body: some View {
        GlassCard(padding: 15) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Text(CountryFlag.display(country: meeting.country, code: meeting.countryCode))
                        .font(.system(size: 30))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("第 \(meeting.round.map(String.init) ?? "—") 站")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(PitPulseTheme.accent)
                        Text(String(meeting.season))
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(meeting.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                    Text(meeting.location)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)

                VStack(alignment: .leading, spacing: 7) {
                    fact(icon: "calendar", value: "\(meeting.startDate.formatted(.dateTime.month().day())) – \(meeting.endDate.formatted(.dateTime.month().day()))")
                    if let circuit = meeting.circuit {
                        fact(icon: "mappin.and.ellipse", value: circuit.name ?? meeting.location)
                    }
                    fact(icon: "list.number", value: "\(meeting.sessions.count) 节 Session")
                }

                if let nextSession {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("下一节")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(PitPulseTheme.accent)
                        Text(nextSession.session.sessionType.displayName)
                            .font(.system(size: 13, weight: .semibold))
                        Text(nextSession.session.startTime.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PitPulseTheme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Spacer(minLength: 6)

                Button(action: openDetail) {
                    HStack(spacing: 5) {
                        Text("打开比赛详情")
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("查看该分站的周末、天气与分析")
            }
        }
    }

    private func fact(icon: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 12)
            Text(value)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }
}

// Apply the same native overlay scroller to each App list, never global preferences.
struct CalendarScrollAppearance: NSViewRepresentable {
    func makeNSView(context: Context) -> ScrollStyleAnchor {
        ScrollStyleAnchor()
    }

    func updateNSView(_ nsView: ScrollStyleAnchor, context: Context) {
        nsView.applyToEnclosingScrollView()
    }

    static func configure(_ scrollView: NSScrollView) {
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.verticalScroller?.controlSize = .small
        scrollView.horizontalScroller?.controlSize = .small
        scrollView.drawsBackground = false
    }

    final class ScrollStyleAnchor: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyToEnclosingScrollView()
        }

        func applyToEnclosingScrollView() {
            // SwiftUI may install the background before attaching its NSScrollView.
            DispatchQueue.main.async { [weak self] in
                guard let scrollView = self?.enclosingScrollView else { return }
                CalendarScrollAppearance.configure(scrollView)
            }
        }
    }
}
