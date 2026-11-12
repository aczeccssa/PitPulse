import SwiftUI
import WidgetKit

@main
struct PitPulseLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        PitPulseLiveActivityWidget()
        RaceWeekendWidget()
        WeekendScheduleWidget()
        StandingsWidget()
        FavoriteDriverWidget()
        LastRaceWidget()
        UpcomingWidget()
    }
}
