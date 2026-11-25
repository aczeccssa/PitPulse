import SharedData
import SwiftUI

public struct NextSeasonScheduleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var schedule: NextSeasonSchedule?
    @State private var failed = false
    private let serverURL: URL?
    private let token: String?

    public init(serverURL: URL?, token: String?) {
        self.serverURL = serverURL
        self.token = token
    }

    public var body: some View {
        NavigationStack {
            List {
                if let schedule {
                    Section {
                        if schedule.events.isEmpty {
                            Text("Waiting for the official schedule.").foregroundStyle(.secondary)
                        }
                        Link("Formula 1 official calendar", destination: schedule.sourceUrl)
                        if failed {
                            Text("Refresh failed. Showing the last available schedule.")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("\(schedule.year, format: .number.grouping(.never)) F1 Schedule")
                            .accessibilityAddTraits(.isHeader)
                    }

                    ForEach(schedule.events) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.round.map { String(localized: "Round \($0)") } ?? String(localized: "Testing"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(event.location).font(.headline)
                            Text(event.name).font(.caption).foregroundStyle(.secondary)
                            Text(dates(for: event)).font(.subheadline)
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                } else if failed || serverURL == nil {
                    Text("Schedule unavailable.").foregroundStyle(.secondary)
                } else {
                    ProgressView("Loading schedule…")
                }
            }
            .navigationTitle("Next Season Schedule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .refreshable { await refresh() }
            .task(id: serverURL) {
                schedule = nil
                failed = false
                while !Task.isCancelled {
                    await refresh()
                    do {
                        try await Task.sleep(for: .seconds(60))
                    } catch {
                        break
                    }
                }
            }
        }
    }

    private func refresh() async {
        guard let serverURL else { return }
        do {
            let response = try await APIClient(baseURL: serverURL).nextSeasonSchedule(token: token)
            guard !Task.isCancelled else { return }
            schedule = response.data
            failed = false
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }

    private func dates(for event: NextSeasonSchedule.Event) -> String {
        let parser = Date.ISO8601FormatStyle(dateSeparator: .dash, timeZone: .gmt)
            .year().month().day()
        guard let start = try? parser.parse(event.startDate), let end = try? parser.parse(event.endDate) else {
            return "\(event.startDate) – \(event.endDate)"
        }
        let format = Date.IntervalFormatStyle(locale: locale, timeZone: .gmt).month(.abbreviated).day()
        return format.format(start..<end)
    }
}
