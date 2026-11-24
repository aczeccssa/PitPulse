import AppKit
import Foundation
import SharedData

extension AppModel {
    func selectSeason(_ season: Int) {
        guard season >= 2000, season <= Calendar.current.component(.year, from: Date()) + 3 else {
            return
        }
        guard season != selectedSeason else { return }
        invalidateConnection()
        selectedSeason = season
        defaults.set(season, forKey: PreferenceKeys.selectedSeason)
        meetings = []
        meta = nil
        nextMeetingOverride = nil
        errorMessage = nil
        Task {
            await loadCachedIfAvailable()
            await refreshCalendar(server: configuredServer, season: season)
        }
    }

    @discardableResult
    func updateServerAddress(_ rawValue: String) -> Bool {
        do {
            let server = try ServerAddress(rawValue: rawValue)
            invalidateConnection()
            liveStore.stop(reason: "server_changed")
            serverAddress = server.url.absoluteString
            configuredServer = server
            defaults.set(serverAddress, forKey: PreferenceKeys.serverAddress)
            meetings = []
            meta = nil
            nextMeetingOverride = nil
            errorMessage = nil
            settingsMessage = "服务器已更新"
            Task {
                try? await reminderCoordinator.sync([])
                await loadCachedIfAvailable()
                await refreshTokenStatus()
                startLiveStream()
                await refreshCalendar(server: server, season: selectedSeason)
            }
            return true
        } catch {
            settingsMessage = error.localizedDescription
            return false
        }
    }

    func saveToken(_ token: String) {
        guard let server = configuredServer else {
            settingsMessage = APIClientError.invalidServerAddress(serverAddress).localizedDescription
            return
        }
        do {
            try credentials.save(token: token, for: server.url)
            isTokenStored = true
            settingsMessage = "Token 已保存到 Keychain"
            retryAttempt = 0
            retryTask?.cancel()
            startLiveStream()
            refresh(force: true)
        } catch {
            settingsMessage = error.localizedDescription
        }
    }

    func deleteToken() {
        guard let server = configuredServer else { return }
        do {
            try credentials.deleteToken(for: server.url)
            isTokenStored = false
            widgetPublisher?.clear()
            settingsMessage = "Token 已删除"
            retryAttempt = 0
            retryTask?.cancel()
            startLiveStream()
            refresh(force: true)
        } catch {
            settingsMessage = error.localizedDescription
        }
    }

    func refreshTokenStatus() async {
        guard let server = configuredServer else {
            isTokenStored = false
            return
        }
        do {
            isTokenStored = try credentials.token(for: server.url) != nil
        } catch {
            isTokenStored = false
            settingsMessage = error.localizedDescription
        }
    }

    func testConnection() async {
        guard let server = configuredServer else {
            settingsMessage = APIClientError.invalidServerAddress(serverAddress).localizedDescription
            return
        }
        settingsMessage = "正在连接…"
        do {
            let token = try credentials.token(for: server.url)
            let client = APIClient(baseURL: server.url, session: session)
            let response = try await client.health(token: token)
            settingsMessage = response.database ? "连接成功，数据库可用" : "已连接，但数据库不可用"
        } catch {
            settingsMessage = error.localizedDescription
        }
    }
    func setRemindersEnabled(_ enabled: Bool) async {
        guard enabled else {
            remindersEnabled = false
            defaults.set(false, forKey: PreferenceKeys.remindersEnabled)
            reminderMessage = nil
            try? await reminderCoordinator.sync([])
            return
        }

        do {
            guard try await reminderCoordinator.authorize() else {
                reminderPermissionDenied = true
                reminderMessage = "通知权限未开启；可在系统设置中允许 PitPulse 通知。"
                return
            }
            reminderPermissionDenied = false
            remindersEnabled = true
            defaults.set(true, forKey: PreferenceKeys.remindersEnabled)
            reminderMessage = "已开启全部 Session 提前 \(reminderMinutes) 分钟提醒。"
            await refreshReminderSettings()
        } catch {
            reminderMessage = "无法开启通知：\(error.localizedDescription)"
        }
    }

    func setReminderMinutes(_ minutes: Int) async {
        guard SessionReminderPlanner.allowedMinutes.contains(minutes) else { return }
        reminderMinutes = minutes
        defaults.set(minutes, forKey: PreferenceKeys.reminderMinutes)
        await refreshReminderSettings()
    }

    func favoriteDriverId(for series: LiveSeries) -> String? {
        series == .wec ? favoriteWecDriverId : favoriteDriverId
    }

    func setFavoriteDriver(_ id: String?, name: String? = nil, series: LiveSeries = .f1) {
        if series == .wec {
            favoriteWecDriverId = id
            // WEC drivers are not in the F1 roster, so keep a display name with the id.
            favoriteWecDriverName = id == nil ? nil : name
            if let id { defaults.set(id, forKey: PreferenceKeys.favoriteWecDriverId) }
            else { defaults.removeObject(forKey: PreferenceKeys.favoriteWecDriverId) }
            if let favoriteWecDriverName { defaults.set(favoriteWecDriverName, forKey: PreferenceKeys.favoriteWecDriverName) }
            else { defaults.removeObject(forKey: PreferenceKeys.favoriteWecDriverName) }
        } else {
            favoriteDriverId = id
            if let id { defaults.set(id, forKey: PreferenceKeys.favoriteDriverId) }
            else { defaults.removeObject(forKey: PreferenceKeys.favoriteDriverId) }
            publishFavoriteWidget()
        }
    }

    func setNotchAutoShowEnabled(_ enabled: Bool) {
        notchAutoShowEnabled = enabled
        defaults.set(enabled, forKey: PreferenceKeys.notchAutoShowEnabled)
    }

    func setNotchCollapseOnMouseExit(_ enabled: Bool) {
        notchCollapseOnMouseExit = enabled
        defaults.set(enabled, forKey: PreferenceKeys.notchCollapseOnMouseExit)
    }

    func setLiveSeries(_ series: LiveSeries) {
        guard series != liveSeries else { return }
        widgetPublisher?.clearLive()
        liveSeries = series
        defaults.set(series.rawValue, forKey: PreferenceKeys.liveSeries)
        if didBootstrap {
            startLiveStream()
        }
    }
    func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
    private func refreshReminderSettings() async {
        guard remindersEnabled, let server = configuredServer else { return }
        if selectedSeason == reminderSeason, lastSuccessfulAttemptAt != nil, meta?.stale == false {
            await syncReminders(meetings, server: server, season: selectedSeason)
        } else if didBootstrap {
            await refreshCalendar()
        }
    }

    var reminderSeason: Int { Calendar(identifier: .gregorian).component(.year, from: .now) }

    func loadCurrentSeasonReminders(server: ServerAddress) async {
        let season = reminderSeason
        guard remindersEnabled, networkAvailable, configuredServer == server else { return }
        do {
            let token = try credentials.token(for: server.url)
            let response = try await APIClient(baseURL: server.url, session: session).calendar(season: season, token: token)
            guard !Task.isCancelled, !response.meta.stale, remindersEnabled, configuredServer == server else { return }
            await syncReminders(response.data, server: server, season: season)
        } catch {
            guard !Task.isCancelled, remindersEnabled, configuredServer == server else { return }
            reminderMessage = "提醒赛历同步失败：\(error.localizedDescription)"
        }
    }

    func syncReminders(_ meetings: [Meeting], server: ServerAddress, season: Int) async {
        let authorized = await reminderCoordinator.authorization() == .authorized
        guard !Task.isCancelled, remindersEnabled, configuredServer == server, season == reminderSeason else { return }
        reminderPermissionDenied = !authorized
        guard authorized else {
            reminderMessage = "通知权限未开启；可在系统设置中允许 PitPulse 通知。"
            return
        }
        let desired = SessionReminderPlanner.reminders(
            meetings: meetings, serverIdentity: server.identity, season: season,
            minutesBefore: reminderMinutes, now: .now
        )
        do {
            try await reminderCoordinator.sync(desired)
            if remindersEnabled, configuredServer == server { reminderMessage = nil }
        } catch {
            if remindersEnabled, configuredServer == server { reminderMessage = "提醒安排失败：\(error.localizedDescription)" }
        }
    }
}
