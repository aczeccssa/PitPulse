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
            case .next: "下一站"
            case .calendar: "赛历"
            case .results: "成绩"
            case .standings: "积分"
            }
        }
    }

    @EnvironmentObject private var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @State private var section: Section = .next

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Picker("导航", selection: $section) {
                ForEach(Section.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Group {
                switch section {
                case .next:
                    NextMeetingCard()
                case .calendar:
                    CalendarView()
                case .results:
                    PlaceholderView(
                        symbol: .results,
                        title: "成绩尚未接入",
                        message: "T07 完成后显示真实比赛结果，这里不会展示占位名次。"
                    )
                case .standings:
                    PlaceholderView(
                        symbol: .standings,
                        title: "积分榜尚未接入",
                        message: "当前构建只覆盖赛历、Session 和下一站。"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
        }
        .frame(width: 430, height: 560)
        .onAppear {
            model.popupDidAppear()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: AppSymbol.menuBar.resolvedSystemName())
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("PitPulse")
                    .font(.headline)
                Text("F1 赛历与 Session")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                openSettings()
            } label: {
                Image(systemName: AppSymbol.settings.resolvedSystemName())
            }
            .buttonStyle(.borderless)
            .help("设置")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            statusIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.caption)
                if let detail = statusDetail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button("退出") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var statusIcon: some View {
        Image(systemName: model.statusSymbol.resolvedSystemName())
            .foregroundStyle(statusColor)
            .accessibilityLabel(model.statusSymbol.accessibilityLabel)
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

    private var statusColor: Color {
        switch model.connectionStatus {
        case .connected: .green
        case .loading: .accentColor
        case .requiresToken, .failed: .red
        case .stale, .offline: .orange
        case .idle: .secondary
        }
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
