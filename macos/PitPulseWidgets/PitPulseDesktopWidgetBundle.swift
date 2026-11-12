import SharedComponents
import SwiftUI
import WidgetKit

@main
struct PitPulseDesktopWidgetBundle: WidgetBundle {
    var body: some Widget {
        RaceWeekendWidget()
        WeekendScheduleWidget()
        LiveTimingWidget()
        StandingsWidget()
        FavoriteDriverWidget()
        LastRaceWidget()
        UpcomingWidget()
    }
}
