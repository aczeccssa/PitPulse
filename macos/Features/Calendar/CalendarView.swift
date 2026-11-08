import AppKit
import SwiftUI

struct CalendarView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedMeeting: Meeting?
    @State private var showMap = false

    var body: some View {
        VStack(spacing: 0) {
            if let selectedMeeting {
                detailHeader(selectedMeeting)
                Divider()
                MeetingDetailView(meeting: selectedMeeting)
            } else {
                seasonPicker
                Divider()
                if showMap && !model.meetings.isEmpty {
                    MapView(store: model.mapStore, meetings: model.meetings).frame(maxHeight: .infinity)
                    if let error = model.mapStore.error { Text(error).font(.caption).padding(8) }
                } else if model.meetings.isEmpty {
                    emptyState
                } else {
                    ScrollViewReader { proxy in
                      ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(model.meetings) { meeting in
                                Button {
                                    selectedMeeting = meeting
                                } label: {
                                    HStack {
                                        MeetingRow(meeting: meeting)
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.vertical, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .id(meeting.id)
                                if meeting.id != model.meetings.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .background(CalendarScrollAppearance())
                      }
                      .onAppear {
                          if let meeting = CalendarLogic.featuredMeeting(in: model.meetings, now: Date()) {
                              proxy.scrollTo(meeting.id, anchor: .top)
                          }
                      }
                    }
                }
            }
        }
        .task(id: "\(model.serverAddress)-\(model.selectedSeason)-\(showMap)") {
            if showMap {
                await model.mapStore.load(model: model, meeting: nil)
                model.mapStore.onMeeting = { id in selectedMeeting = model.meetings.first { $0.id == id } }
            } else { model.mapStore.pause() }
        }
        .onDisappear { model.mapStore.pause() }
        .onChange(of: model.selectedSeason) { _, _ in selectedMeeting = nil }
        .onChange(of: model.serverAddress) { _, _ in selectedMeeting = nil }
    }

    private func detailHeader(_ meeting: Meeting) -> some View {
        HStack(spacing: 10) {
            Button {
                selectedMeeting = nil
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 24, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回赛历")
            Text(meeting.name)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var seasonPicker: some View {
        HStack(spacing: 12) {
            Button {
                model.selectSeason(model.selectedSeason - 1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("上一年")

            Text("\(String(model.selectedSeason)) 赛季")
                .font(.headline)
                .frame(minWidth: 110)

            Button {
                model.selectSeason(model.selectedSeason + 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("下一年")

            Spacer()
            Button { showMap.toggle() } label: { Image(systemName: showMap ? "list.bullet" : "map") }.buttonStyle(.borderless).accessibilityLabel(showMap ? "显示赛历列表" : "显示赛历地图")

            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: AppSymbol.calendar.resolvedSystemName())
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            if model.connectionStatus == .loading {
                ProgressView().accessibilityLabel("读取 \(model.selectedSeason) 赛季")
            } else {
                Text("暂无赛历").font(.headline)
                Text("该赛季尚未同步，或当前筛选没有数据。切换服务器或年份后重试。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MeetingRow: View {
    let meeting: Meeting

    var body: some View {
        HStack(spacing: 10) {
            Text(CountryFlag.emoji(for: meeting.countryCode) ?? "🌐")
                .font(.title2)
                .accessibilityLabel("举办国 \(meeting.country)")
            VStack(alignment: .leading, spacing: 3) {
                Text(meeting.name)
                    .font(.body.weight(.medium))
                Text("第 \(meeting.round.map(String.init) ?? "—") 站 · \(meeting.location)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(meeting.startDate.formatted(.dateTime.month().day()))\n\(meeting.endDate.formatted(.dateTime.month().day()))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
            statusLabel
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var statusLabel: some View {
        if meeting.status != .scheduled {
            Text(meeting.status.displayName)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.thinMaterial, in: Capsule())
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
