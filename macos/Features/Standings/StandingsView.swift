import AppKit
import Charts
import SwiftUI
import SharedData

struct StandingsView: View {
    @ObservedObject var model: AppModel
    @State var selectedID: String?
    @State var detail: StandingDetailTarget?

    var isConstructor: Bool { model.showingConstructorStandings }

    var sortedDrivers: [DriverStanding] {
        model.driverStandings.sorted { $0.position < $1.position }
    }

    var sortedConstructors: [ConstructorStanding] {
        model.constructorStandings.sorted { $0.position < $1.position }
    }

    var effectiveSelection: String? {
        if let selectedID,
           (isConstructor ? sortedConstructors.contains { $0.constructorId == selectedID }
                          : sortedDrivers.contains { $0.driverId == selectedID }) {
            return selectedID
        }
        if !isConstructor, let favorite = model.favoriteDriverId(for: .f1),
           sortedDrivers.contains(where: { $0.driverId == favorite }) {
            return favorite
        }
        return isConstructor ? sortedConstructors.first?.constructorId : sortedDrivers.first?.driverId
    }

    var body: some View {
        Group {
            if let detail {
                StandingDetailView(model: model, target: detail) { self.detail = nil }
            } else {
                standingsPage
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: model.selectedSeason) { _, _ in
            selectedID = nil
            detail = nil
        }
        .onChange(of: model.serverAddress) { _, _ in
            selectedID = nil
            detail = nil
        }
        .onChange(of: model.showingConstructorStandings) { _, _ in
            selectedID = nil
            detail = nil
        }
        .task(id: "\(model.selectedSeason)-\(model.showingConstructorStandings)") { await model.refreshStandings() }
    }

    var standingsPage: some View {
        VStack(spacing: 0) {
            toolbar
            ScrollView {
                VStack(alignment: .leading, spacing: PitPulseTheme.cardSpacing) {
                    if let error = model.standingsError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 2)
                    }

                    if isConstructor ? sortedConstructors.isEmpty : sortedDrivers.isEmpty {
                        emptyStandings
                    } else {
                        hero
                        table
                        if let selection = effectiveSelection {
                            StandingTrendCard(
                                model: model,
                                kind: isConstructor ? "constructors" : "drivers",
                                id: selection,
                                season: model.selectedSeason,
                                officialPoints: selectedPoints(selection),
                                title: selectedTitle(selection),
                                openDetail: { openDetail(selection) }
                            )
                        }
                    }
                }
                .padding(.horizontal, PitPulseTheme.pagePadding)
                .padding(.top, 10)
                .padding(.bottom, 14)
                .background(CalendarScrollAppearance())
            }
        }
    }

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

            Spacer(minLength: 6)

            if model.isRefreshing { ProgressView().controlSize(.mini) }

            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 4) {
                    modeButton("车手", active: !isConstructor) { model.selectStandings(isConstructor: false) }
                    modeButton("车队", active: isConstructor) { model.selectStandings(isConstructor: true) }
                }
            }
        }
        .padding(.horizontal, PitPulseTheme.pagePadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    func modeButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(active ? PitPulseTheme.accent : Color.secondary)
                .padding(.horizontal, 12)
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

    var emptyStandings: some View {
        EmptyStateCard(
            symbol: "trophy",
            title: model.standingsError == nil ? "暂无积分" : "无法读取积分榜",
            message: model.standingsError == nil ? "该赛季还没有可用的积分数据。" : "稍后重试，或检查服务器连接。"
        )
    }
}
