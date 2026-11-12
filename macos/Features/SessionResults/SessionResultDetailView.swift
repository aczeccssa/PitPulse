import AppKit
import SwiftUI
import SharedData

struct SessionResultDetailView: View {
    @ObservedObject var model: AppModel
    let result: SessionResult
    let meeting: Meeting?
    let session: Session?
    let onBack: () -> Void

    var season: Int { meeting?.season ?? model.selectedSeason }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    resultSummary
                    DriverRaceFactsCard(model: model, result: result, season: season)
                    SessionAnalysisView(model: model, result: result, season: season)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, PitPulseTheme.pagePadding)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .background(CalendarScrollAppearance())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .textSelection(.enabled)
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
            .help("返回成绩")
            .accessibilityLabel("返回成绩")
            .accessibilityIdentifier("results.back")
            .keyboardShortcut(.cancelAction)

            DriverHelmetAvatar(
                driverID: result.driverId,
                name: result.driverName,
                season: season,
                size: 36
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(result.driverName)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                Text("\(result.team) · \(meeting?.name ?? "比赛成绩") · \(session?.sessionType.displayName ?? "Session")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            favoriteButton

            VStack(alignment: .trailing, spacing: 1) {
                Text(result.position.map { "P\($0)" } ?? "—")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(result.points.map { String(format: "%g 分", $0) } ?? "—")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, PitPulseTheme.pagePadding)
        .padding(.vertical, 10)
    }

    var favoriteButton: some View {
        let isFavorite = model.favoriteDriverId(for: .f1) == result.driverId
        return Button {
            model.setFavoriteDriver(isFavorite ? nil : result.driverId, name: result.driverName)
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(isFavorite ? Color.yellow : Color.secondary)
                .frame(width: 28, height: 28)
                .background(.primary.opacity(0.05), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isFavorite ? "取消关注 \(result.driverName)" : "关注 \(result.driverName)")
        .accessibilityLabel(isFavorite ? "取消关注" : "关注车手")
    }

    var resultSummary: some View {
        GlassCard(padding: 10) {
            VStack(alignment: .leading, spacing: 11) {
                CardHeader(title: "最终成绩")
                HStack(spacing: 8) {
                    summaryMetric("名次", result.position.map(String.init) ?? "—", tint: PitPulseTheme.accent)
                    summaryMetric("积分", result.points.map { String(format: "%g", $0) } ?? "—")
                    summaryMetric("完成圈数", result.laps.map(String.init) ?? "—")
                    summaryMetric("状态", result.classificationLabel)
                }
                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ResultFact(title: "比赛用时", value: (result.raceTime ?? result.time).flatMap(Double.init).map { AnalysisMath.duration($0) } ?? result.raceTime ?? result.time ?? "—")
                    ResultFact(title: "差距", value: result.gap ?? "—")
                    ResultFact(title: "最佳圈", value: result.bestLap ?? "—")
                    if session?.sessionType == .qualifying || session?.sessionType == .sprintQualifying {
                        ResultFact(title: "Q1", value: result.q1 ?? "—")
                        ResultFact(title: "Q2", value: result.q2 ?? "—")
                        ResultFact(title: "Q3", value: result.q3 ?? "—")
                    }
                }
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

struct ResultFact: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.medium)).monospacedDigit().lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
