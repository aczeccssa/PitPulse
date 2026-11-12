import AppKit
import SwiftUI
import SharedData

extension CalendarView {
    var finishedMeetings: [Meeting] {
        model.meetings.filter { $0.endDate < Date() }.sorted { $0.startDate > $1.startDate }
    }

    var upcomingMeetings: [Meeting] {
        model.meetings.filter { $0.endDate >= Date() }.sorted { $0.startDate < $1.startDate }
    }

    var meetingList: some View {
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

    func groupHeader(_ title: String, count: Int) -> some View {
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

    func row(_ meeting: Meeting) -> some View {
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
    func upcomingDetails(_ meeting: Meeting) -> some View {
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

    func dateRange(_ meeting: Meeting) -> String {
        let calendar = Calendar.current
        let start = meeting.startDate.formatted(.dateTime.month().day())
        let end = calendar.isDate(meeting.startDate, equalTo: meeting.endDate, toGranularity: .month)
            ? meeting.endDate.formatted(.dateTime.day())
            : meeting.endDate.formatted(.dateTime.month().day())
        return start == end ? start : "\(start)–\(end)"
    }
}
