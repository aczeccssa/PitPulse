import AppKit
import SwiftUI

struct MenuBarRootView: View {
    enum Section: String, CaseIterable, Identifiable {
        case next
        case calendar
        case results
        case standings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .next: "比赛"
            case .calendar: "赛历"
            case .results: "成绩"
            case .standings: "积分"
            }
        }

        var symbol: String {
            switch self {
            case .next: "flag.checkered"
            case .calendar: "calendar"
            case .results: "list.number"
            case .standings: "chart.bar.xaxis"
            }
        }
    }

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var liveStore: LiveStore
    @EnvironmentObject private var liveIsland: LiveIslandController
    @Environment(\.openSettings) private var openSettings
    @State private var section: Section = .next

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 4) {
                ForEach(Section.allCases) { item in
                    Button {
                        section = item
                    } label: {
                        Image(systemName: item.symbol).font(.system(size: 16, weight: .medium))
                        .foregroundStyle(section == item ? Color.white : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if section == item {
                                RoundedRectangle(cornerRadius: 9).fill(Color.accentColor)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .help(item.title)
                    .accessibilityLabel(item.title)
                    .accessibilityValue(section == item ? "已选中" : "")
                    .accessibilityAddTraits(section == item ? .isSelected : [])
                }
            }
            .padding(4)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Group {
                switch section {
                case .next:
                    NextMeetingCard()
                case .calendar:
                    CalendarView()
                case .results:
                    SessionResultsView(model: model)
                case .standings:
                    StandingsView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
        }
        .frame(width: 480, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            model.popupDidAppear()
        }
        .onDisappear {
            model.popupDidDisappear()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: AppSymbol.menuBar.resolvedSystemName())
                .font(.title3)
            Text("PitPulse")
                .font(.headline)
            if liveStore.snapshot.sourceMode == .replay {
                Text("回放").font(.caption).foregroundStyle(.orange)
            }
            Spacer()
            Button {
                model.refresh(force: true)
            } label: {
                Image(systemName: AppSymbol.refresh.resolvedSystemName())
            }
            .buttonStyle(.borderless)
            .help("刷新")
            .disabled(model.isRefreshing)

            Button {
                NSApp.keyWindow?.orderOut(nil)
                NSApp.activate()
                openSettings()
            } label: {
                Image(systemName: AppSymbol.settings.resolvedSystemName())
            }
            .buttonStyle(.borderless)
            .help("设置")
            .accessibilityLabel("设置")
            .accessibilityIdentifier("menuBar.settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Menu {
                Text(statusTitle)
                Text(liveStatusText)
                if let detail = statusDetail { Text(detail) }
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .frame(width: 30, height: 30)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("连接详情")
            .accessibilityLabel("连接详情")
            Spacer()
            Button {
                liveIsland.toggleManually()
            } label: {
                Label(liveIsland.isVisible ? "隐藏" : "显示", systemImage: liveIsland.isVisible ? "eye.slash" : "eye")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.quaternary, in: Capsule())
            }
            .buttonStyle(.plain)
            .help(liveIsland.isVisible ? "隐藏 Live Island" : "显示 Live Island")
            .accessibilityLabel(liveIsland.isVisible ? "隐藏 Live Island" : "显示 Live Island")
            .accessibilityIdentifier("menuBar.liveIsland")
            Menu {
                Button("退出 PitPulse", role: .destructive) { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(.quaternary, in: Circle())
            }
            .menuStyle(.borderlessButton)
            .help("更多操作")
            .accessibilityLabel("更多操作")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var liveStatusText: String {
        let snapshot = liveStore.snapshot
        let updated = snapshot.lastUpdatedLabel.map { " · \($0)" } ?? ""
        return "Live：\(snapshot.statusLabel)\(updated)"
    }

    private var statusTitle: String {
        switch model.connectionStatus {
        case .idle: "尚未连接"
        case .loading: "正在连接"
        case .connected: "在线"
        case .stale: "正在显示缓存"
        case .offline: "离线"
        case .requiresToken: "需要有效 Token"
        case .failed: "连接失败"
        }
    }

    private var statusDetail: String? {
        if let error = model.errorMessage {
            return error
        }
        if let date = model.lastSuccessfulLoadAt {
            return "最近成功：\(date.formatted(date: .abbreviated, time: .shortened))"
        }
        return nil
    }

}

struct PlaceholderView: View {
    let symbol: AppSymbol
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol.resolvedSystemName())
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
