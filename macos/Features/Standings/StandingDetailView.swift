import AppKit
import SwiftUI
import SharedData

struct StandingDetailTarget: Identifiable {
    let kind: String
    let id: String
    let title: String
    let season: Int
    let position: Int
    let points: Double
    let wins: Int
    let team: String?

    var identity: String { "\(kind)-\(id)" }
}

struct StandingDetailView: View {
    @ObservedObject var model: AppModel
    let target: StandingDetailTarget
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summary
                    SeasonAnalysisView(
                        model: model,
                        kind: target.kind,
                        id: target.id,
                        season: target.season,
                        officialPoints: target.points
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, PitPulseTheme.pagePadding)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .background(CalendarScrollAppearance())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var header: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12.5, weight: .bold))
                    .frame(width: 28, height: 28)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("返回积分榜")
            .accessibilityLabel("返回积分榜")
            .accessibilityIdentifier("standings.back")
            .keyboardShortcut(.cancelAction)

            if target.kind == "constructors" {
                if let image = MotorsportAsset.image(kind: .teamLogo, id: target.id, season: target.season) {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 34, height: 34)
                        .accessibilityHidden(true)
                }
            } else {
                DriverHelmetAvatar(
                    driverID: target.id,
                    name: target.title,
                    season: target.season,
                    size: 34
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(target.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                Text("\(String(target.season)) 赛季 · \(target.team ?? (target.kind == "constructors" ? "车队" : "车手"))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 1) {
                Text("P\(target.position)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("\(target.points.formatted()) 分")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, PitPulseTheme.pagePadding)
        .padding(.vertical, 8)
    }

    var summary: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 8) {
                summaryMetric("排名", "第 \(target.position) 名", tint: PitPulseTheme.accent)
                summaryMetric("积分", target.points.formatted())
                summaryMetric("胜场", "\(target.wins)")
                summaryMetric("赛季", String(target.season))
            }
        }
    }

    func summaryMetric(_ label: String, _ value: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
