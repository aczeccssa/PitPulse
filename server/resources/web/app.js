// PitPulse web dashboard. Plain script: the server embeds this file into the
// binary, so there is no build step to deploy.
(() => {
    "use strict";

    const ROUTES =["overview", "live", "calendar", "standings", "results"];
    const VIEW_TITLES = {
        overview: "概览",
        live: "实时计时",
        calendar: "赛历",
        standings: "积分榜",
        results: "比赛结果",
    };
    const SESSION_LABELS = {
        fp1: "一练",
        fp2: "二练",
        fp3: "三练",
        sprintQualifying: "冲刺排位",
        sprint: "冲刺赛",
        qualifying: "排位赛",
        race: "正赛",
    };
    const SESSION_NAME_LABELS = {
        race: "正赛",
        qualifying: "排位赛",
        sprint: "冲刺赛",
        "sprint qualifying": "冲刺排位",
        "sprint shootout": "冲刺排位",
        "practice 1": "一练",
        "practice 2": "二练",
        "practice 3": "三练",
        "first practice": "一练",
        "second practice": "二练",
        "third practice": "三练",
    };
    // Upstream sends both "All clear" and "AllClear"; normalise before lookup.
    const TRACK_STATUS = {
        allclear: { label: "赛道畅通", tone: "green" },
        green: { label: "赛道畅通", tone: "green" },
        yellow: { label: "黄旗", tone: "yellow" },
        yellowflag: { label: "黄旗", tone: "yellow" },
        safetycar: { label: "安全车", tone: "yellow" },
        sc: { label: "安全车", tone: "yellow" },
        vsc: { label: "虚拟安全车", tone: "yellow" },
        virtualsafetycar: { label: "虚拟安全车", tone: "yellow" },
        virtualsafetycarending: { label: "虚拟安全车结束", tone: "yellow" },
        red: { label: "红旗", tone: "red" },
        redflag: { label: "红旗", tone: "red" },
        chequered: { label: "方格旗", tone: "green" },
    };

    function trackInfo(value) {
        if (!value) return null;
        return TRACK_STATUS[String(value).toLowerCase().replace(/[^a-z]/g, "")] || null;
    }
    const STATUS_REASONS = {
        not_connected: "实时数据源未连接，比赛开始时自动重连。",
        upstream_silent: "上游数据暂无更新，等待下一次同步。",
        data_stale: "实时数据已过期，正在等待上游恢复。",
        replay_finished: "回放已结束。",
    };
    const CLASS_LABELS = {
        retired: "退赛",
        dnf: "退赛",
        "did not finish": "未完赛",
        disqualified: "取消资格",
        dsq: "取消资格",
        "did not start": "未发车",
        dns: "未发车",
        "did not qualify": "未通过排位",
        dnq: "未通过排位",
        "not classified": "未分类",
        nc: "未分类",
        withdrawn: "退出",
    };
    const QUALITY_LABELS = {
        pending: "待同步",
        partial: "部分完整",
        complete: "完整",
        full: "完整",
    };
    const TEAM_COLORS = [
        [/red bull/i, "#3671c6"],
        [/ferrari/i, "#e8002d"],
        [/mclaren/i, "#ff8000"],
        [/mercedes/i, "#27f4d2"],
        [/aston/i, "#229971"],
        [/alpine/i, "#ff87bc"],
        [/williams/i, "#64c4ff"],
        [/racing bulls|visa cash|rb f1/i, "#6692ff"],
        [/sauber|kick/i, "#52e252"],
        [/haas/i, "#b6babd"],
        [/cadillac/i, "#c9b037"],
        [/audi/i, "#f50537"],
    ];
    const GP_NAMES = [
        [/australian/i, "澳大利亚大奖赛"],
        [/chinese/i, "中国大奖赛"],
        [/japanese/i, "日本大奖赛"],
        [/bahrain/i, "巴林大奖赛"],
        [/saudi/i, "沙特阿拉伯大奖赛"],
        [/miami/i, "迈阿密大奖赛"],
        [/canadian/i, "加拿大大奖赛"],
        [/monaco/i, "摩纳哥大奖赛"],
        [/barcelona|spanish/i, "西班牙大奖赛"],
        [/austrian/i, "奥地利大奖赛"],
        [/british/i, "英国大奖赛"],
        [/belgian/i, "比利时大奖赛"],
        [/hungarian/i, "匈牙利大奖赛"],
        [/dutch/i, "荷兰大奖赛"],
        [/italian/i, "意大利大奖赛"],
        [/azerbaijan/i, "阿塞拜疆大奖赛"],
        [/singapore/i, "新加坡大奖赛"],
        [/united states|us grand prix/i, "美国大奖赛"],
        [/mexico/i, "墨西哥城大奖赛"],
        [/brazilian|são paulo|sao paulo/i, "巴西大奖赛"],
        [/las vegas/i, "拉斯维加斯大奖赛"],
        [/qatar/i, "卡塔尔大奖赛"],
        [/abu dhabi/i, "阿布扎比大奖赛"],
    ];

    const el = (id) => document.getElementById(id);
    const state = {
        view: "overview",
        calendar: [],
        calendarLoaded: false,
        calendarMode: "month",
        calendarMonth: null,
        calendarDay: null,
        snapshot: null,
        driversStandings: [],
        constructorStandings: [],
        standingsKind: "drivers",
        resultsCache: new Map(),
        results: { meetingId: null, sessionType: "race", token: 0 },
        lastResult: null,
        connection: "connecting",
        unauthorized: false,
        streamController: null,
        reconnectTimer: null,
        pollTimer: null,
        polling: false,
        attempt: 0,
        ticker: null,
        // Forecast for the next session, shown when no session is running.
        nextWeather: { key: null, pending: null, hour: null, status: "idle" },
    };

    /* ---------- session ---------- */

    // The dashboard is part of the service: the browser holds the HttpOnly
    // session cookie the server issued when the access link was opened, so
    // there is no token input and no token in page storage. If that link is
    // rotated or the session expires, say so instead of retrying forever.
    function markUnauthorized() {
        if (state.unauthorized) return;
        state.unauthorized = true;
        const toast = el("toast");
        if (!toast) return;
        toast.textContent = "访问会话已失效，请重新打开服务端生成的访问链接。";
        toast.hidden = false;
    }

    /* ---------- api ---------- */

    async function api(path) {
        const started = performance.now();
        const response = await fetch(path, {
            headers: { Accept: "application/json" },
            cache: "no-store",
            credentials: "same-origin",
        });
        if (response.status === 401) {
            setConnection("locked");
            markUnauthorized();
            throw new Error("unauthorized");
        }
        if (!response.ok) throw new Error(`${path} -> HTTP ${response.status}`);
        const body = await response.json();
        return { body, latency: Math.round(performance.now() - started) };
    }

    /* ---------- formatting ---------- */

    const pad = (value) => String(value).padStart(2, "0");

    function parseDate(value) {
        if (!value) return null;
        const date = new Date(value);
        return Number.isNaN(date.getTime()) ? null : date;
    }

    const localTime = new Intl.DateTimeFormat("zh-CN", {
        weekday: "short",
        hour: "2-digit",
        minute: "2-digit",
        hour12: false,
    });
    const localDate = new Intl.DateTimeFormat("zh-CN", {
        month: "numeric",
        day: "numeric",
    });
    const localDateTime = new Intl.DateTimeFormat("zh-CN", {
        month: "numeric",
        day: "numeric",
        hour: "2-digit",
        minute: "2-digit",
        hour12: false,
    });

    function formatTime(value) {
        const date = parseDate(value);
        return date ? localTime.format(date) : "待定";
    }

    // Session times read as a schedule ("周五 08:30"), so the weekday and the
    // clock are split so a narrow screen can stack them.
    const SHORT_WEEKDAYS = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"];

    function sessionTimeParts(value) {
        const date = parseDate(value);
        if (!date) return { day: "待定", clock: "" };
        return {
            day: SHORT_WEEKDAYS[date.getDay()],
            clock: `${pad(date.getHours())}:${pad(date.getMinutes())}`,
        };
    }

    function formatSessionTime(value) {
        const { day, clock } = sessionTimeParts(value);
        return clock ? `${day} ${clock}` : day;
    }

    function formatDateTime(value) {
        const date = parseDate(value);
        return date ? localDateTime.format(date) : "";
    }

    function sessionNameLabel(name) {
        if (!name) return "";
        return SESSION_NAME_LABELS[name.trim().toLowerCase()] || name;
    }

    function sessionTypeLabel(type) {
        return SESSION_LABELS[type] || type || "";
    }

    function formatDateRange(start, end) {
        const from = parseDate(start);
        const to = parseDate(end);
        if (!from) return "";
        if (!to || from.toDateString() === to.toDateString()) return localDate.format(from);
        return `${localDate.format(from)} – ${localDate.format(to)}`;
    }

    function gpName(name) {
        const match = GP_NAMES.find(([pattern]) => pattern.test(name || ""));
        return match ? match[1] : name || "";
    }

    function meetingPlace(meeting) {
        return [meeting?.location, meeting?.country].filter(Boolean).join(" · ");
    }

    function roundLabel(meeting) {
        return meeting?.round ? `R${meeting.round}` : "—";
    }

    function teamColor(name) {
        if (!name) return "transparent";
        const match = TEAM_COLORS.find(([pattern]) => pattern.test(name));
        return match ? match[1] : "var(--line-strong)";
    }

    function driverCode(driver) {
        const name = (driver?.name || driver?.driverName || "").trim();
        if (!name) return driver?.number ? `#${driver.number}` : "—";
        const parts = name.split(/\s+/);
        return parts[parts.length - 1].slice(0, 3).toUpperCase();
    }

    // Artwork bundled with the apps, downscaled into resources/web/motorsport
    // by generate.py. Drivers resolve by Jolpica id, then racing number, then
    // surname, so live rows and standings both find their helmet.
    const HELMETS = new Set([
        "albon", "alonso", "antonelli", "arvid_lindblad", "bearman", "bortoleto",
        "bottas", "colapinto", "gasly", "hadjar", "hamilton", "hulkenberg",
        "lawson", "leclerc", "max_verstappen", "norris", "ocon", "perez",
        "piastri", "russell", "sainz", "stroll",
    ]);
    const HELMET_ALIASES = { verstappen: "max_verstappen", lindblad: "arvid_lindblad" };
    const TEAM_ASSETS = [
        [/red[\s_]?bull/i, "red_bull"],
        [/mercedes/i, "mercedes"],
        [/mclaren/i, "mclaren"],
        [/ferrari/i, "ferrari"],
        [/williams/i, "williams"],
        [/racing[\s_]?bulls|visa cash|^rb$|rb f1/i, "rb"],
        [/aston[\s_]?martin/i, "aston_martin"],
        [/alpine/i, "alpine"],
        [/haas/i, "haas"],
        [/audi|sauber|kick/i, "audi"],
        [/cadillac/i, "cadillac"],
    ];

    // These logos are drawn in near-black; the app's catalog carries a dark
    // appearance variant for exactly them, so the dark theme swaps them in.
    const DARK_LOGO_TEAMS = new Set(["aston_martin", "audi", "cadillac", "mercedes"]);

    function artImage(className, src) {
        const image = document.createElement("img");
        image.className = className;
        image.src = src;
        image.alt = "";
        image.loading = "lazy";
        image.decoding = "async";
        return image;
    }

    function helmetSlug(value) {
        const raw = String(value || "").trim().toLowerCase();
        if (!raw) return null;
        const key = raw
            .normalize("NFD")
            .replace(/[\u0300-\u036f]/g, "")
            .replace(/[^a-z0-9]+/g, "_")
            .replace(/^_|_$/g, "");
        const words = key.split("_").filter(Boolean);
        for (const candidate of [key, words[words.length - 1]]) {
            const slug = HELMET_ALIASES[candidate] || candidate;
            if (HELMETS.has(slug)) return slug;
        }
        return null;
    }

    function helmetImage(...values) {
        for (const value of values) {
            const slug = helmetSlug(value);
            if (slug) return artImage("avatar", `/motorsport/helmet-${slug}.png`);
        }
        return null;
    }

    function teamLogoImage(...values) {
        const match = TEAM_ASSETS.find(([pattern]) =>
            values.some((value) => value && pattern.test(String(value))),
        );
        if (!match) return null;
        const id = match[1];
        const light = `/motorsport/team-${id}.png`;
        const image = artImage("team-logo", light);
        if (DARK_LOGO_TEAMS.has(id)) {
            image.dataset.logoSrc = light;
            image.dataset.darkSrc = `/motorsport/team-${id}-dark.png`;
            if (currentTheme() === "dark") image.src = image.dataset.darkSrc;
        }
        return image;
    }

    function syncLogoTheme(theme) {
        for (const image of document.querySelectorAll("img[data-dark-src]")) {
            const src = theme === "dark" ? image.dataset.darkSrc : image.dataset.logoSrc;
            if (image.getAttribute("src") !== src) image.src = src;
        }
    }

    function compound(tire) {
        const value = (tire || "").toUpperCase();
        if (value.startsWith("S")) return { letter: "S", key: "soft" };
        if (value.startsWith("M")) return { letter: "M", key: "medium" };
        if (value.startsWith("H")) return { letter: "H", key: "hard" };
        if (value.startsWith("I")) return { letter: "I", key: "inter" };
        if (value.startsWith("W")) return { letter: "W", key: "wet" };
        return null;
    }

    /* ---------- theme ---------- */

    function currentTheme() {
        return document.documentElement.dataset.theme === "light" ? "light" : "dark";
    }

    function wireTheme() {
        const preference = window.matchMedia("(prefers-color-scheme: dark)");
        const update = () => {
            const theme = preference.matches ? "dark" : "light";
            document.documentElement.dataset.theme = theme;
            el("theme-color-meta").setAttribute("content", theme === "dark" ? "#0e0e10" : "#f2f3f5");
            syncLogoTheme(theme);
        };
        update();
        preference.addEventListener("change", update);
    }

    function number(value, unit, digits = 0) {
        if (value === null || value === undefined || Number.isNaN(Number(value))) return "—";
        return `${Number(value).toFixed(digits)}${unit}`;
    }

    function node(tag, className, text) {
        const element = document.createElement(tag);
        if (className) element.className = className;
        if (text !== undefined) element.textContent = text;
        return element;
    }

    function svgIcon(path, className) {
        const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
        svg.setAttribute("viewBox", "0 0 24 24");
        svg.setAttribute("fill", "none");
        svg.setAttribute("stroke", "currentColor");
        svg.setAttribute("stroke-width", "2");
        svg.setAttribute("stroke-linecap", "round");
        svg.setAttribute("stroke-linejoin", "round");
        svg.setAttribute("aria-hidden", "true");
        if (className) svg.setAttribute("class", className);
        const shape = document.createElementNS("http://www.w3.org/2000/svg", "path");
        shape.setAttribute("d", path);
        svg.append(shape);
        return svg;
    }

    /* ---------- calendar helpers ---------- */

    function seasonMeetings() {
        return state.calendar
            .filter((meeting) => meeting.round != null)
            .sort((a, b) => a.round - b.round);
    }

    function isFinished(meeting) {
        const end = parseDate(meeting?.endDate);
        return Boolean(end && end.getTime() < Date.now());
    }

    function upcomingEntry() {
        const now = Date.now();
        let best = null;
        for (const meeting of state.calendar) {
            if (meeting.status === "cancelled") continue;
            for (const session of meeting.sessions || []) {
                if (session.status === "cancelled") continue;
                const start = parseDate(session.startTime);
                if (!start || start.getTime() <= now) continue;
                if (!best || start < best.start) best = { meeting, session, start };
            }
        }
        return best;
    }

    function lastFinishedMeeting() {
        const finished = seasonMeetings().filter(isFinished);
        return finished.length ? finished[finished.length - 1] : null;
    }

    function raceSession(meeting) {
        return (meeting?.sessions || []).find((session) => session.sessionType === "race") || null;
    }

    const WEEKDAY_LABELS = ["一", "二", "三", "四", "五", "六", "日"];

    function dayKey(date) {
        const pad = (value) => String(value).padStart(2, "0");
        return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
    }

    function meetingSpan(meeting) {
        const start = parseDate(meeting?.startDate);
        if (!start) return null;
        const end = parseDate(meeting?.endDate) || start;
        return { start: dayKey(start), end: dayKey(end) };
    }

    function meetingsInMonth(meetings, year, month) {
        const first = dayKey(new Date(year, month, 1));
        const last = dayKey(new Date(year, month + 1, 0));
        return meetings.filter((meeting) => {
            const span = meetingSpan(meeting);
            return Boolean(span && span.start <= last && span.end >= first);
        });
    }

    function shortGpName(name) {
        return gpName(name).replace(/(大奖赛|Grand Prix)$/i, "") || name || "分站";
    }

    function seasonYear(meetings) {
        const first = meetings[0];
        return (
            first?.season ||
            Number(String(first?.id || "").split(":")[0]) ||
            new Date().getFullYear()
        );
    }

    /* ---------- live phase ---------- */

    const LIVE_GRACE_MS = 3 * 60 * 60 * 1000;

    // The live feed keeps serving the last session's payload after the chequered
    // flag, and a recorded replay can be days old. The calendar's session times
    // are authoritative: match the snapshot to its calendar session so a
    // non-race day never shows race timing as if it were current.
    function calendarSessionFor(snapshot) {
        const id = snapshot?.sessionId;
        const type = (snapshot?.sessionType || "").toLowerCase();
        const name = (snapshot?.meetingName || "").toLowerCase();
        const gp = gpName(snapshot?.meetingName).toLowerCase();
        const entries = state.calendar.flatMap((round) =>
            (round.sessions || []).map((session) => ({ round, session })),
        );
        if (id) {
            const byId = entries.find(({ session }) => session.id === id);
            if (byId) return byId.session;
        }
        if (!name) return null;
        const byName = entries.find(
            ({ round, session }) =>
                ((round.name || "").toLowerCase() === name ||
                    gpName(round.name).toLowerCase() === gp) &&
                (!type || (session.sessionType || "").toLowerCase() === type),
        );
        return byName?.session || null;
    }

    function sessionWindowExpired(snapshot) {
        const matched = calendarSessionFor(snapshot);
        if (!matched) return false;
        const end = parseDate(matched.endTime) || parseDate(matched.startTime);
        return Boolean(end && Date.now() - end.getTime() > LIVE_GRACE_MS);
    }

    function livePhase() {
        const snapshot = state.snapshot;
        if (!snapshot) return state.connection === "offline" ? "lost" : "loading";
        const status = (snapshot.sessionStatus || "").toLowerCase();
        const drivers = snapshot.drivers || [];
        const hasSession = Boolean(snapshot.sessionName || snapshot.meetingName);

        // Whatever status the feed claims, a session the calendar says ended
        // hours ago is not live: treat it as "no session" and show the last
        // result instead of stale timing.
        if (sessionWindowExpired(snapshot)) return "idle";
        if (snapshot.sourceStatus === "disconnected") {
            return hasSession && drivers.length ? "lost" : "idle";
        }
        if (/finish|finalis|finaliz|abort|ended?|ends|complete/.test(status)) return "finished";
        if (/not_started|not started|inactive|scheduled/.test(status) && !drivers.length) return "idle";
        if (!hasSession && !drivers.length) return "idle";
        return "live";
    }

    function snapshotLap(snapshot) {
        if (snapshot?.lapCount != null) {
            return snapshot.totalLaps
                ? `${snapshot.lapCount} / ${snapshot.totalLaps} 圈`
                : `第 ${snapshot.lapCount} 圈`;
        }
        return snapshot?.isTimeBased ? "计时赛" : "—";
    }

    function elapsedLabel(seconds) {
        if (seconds == null) return "";
        const total = Math.max(0, Math.round(seconds));
        const hours = Math.floor(total / 3600);
        const minutes = Math.floor((total % 3600) / 60);
        const secs = total % 60;
        return hours ? `${hours}:${pad(minutes)}:${pad(secs)}` : `${minutes}:${pad(secs)}`;
    }

    /* ---------- hero ---------- */

    function renderHero() {
        const phase = livePhase();
        const sessionMode = phase === "live" || phase === "finished" || phase === "lost";
        el("hero-upcoming").hidden = sessionMode;
        el("hero-live").hidden = !sessionMode;
        if (sessionMode) renderHeroLive(phase);
        else renderHeroUpcoming();
    }

    function renderHeroLive(phase) {
        const snapshot = state.snapshot;
        const meetingName = snapshot?.meetingName || "";
        el("hero-live-overline").textContent =
            phase === "finished" ? "已结束" : phase === "lost" ? "连接中断" : "正在进行";
        el("hero-live-country").textContent = snapshot?.countryCode || "";
        const badge = el("hero-live-badge");
        badge.dataset.tone = phase === "live" ? "live" : "done";
        badge.textContent =
            phase === "finished" ? "比赛已结束" : phase === "lost" ? "与实时源断开" : "比赛进行中";
        el("hero-live-title").textContent = meetingName
            ? gpName(meetingName)
            : sessionNameLabel(snapshot?.sessionName);
        const parts = [
            meetingName && gpName(meetingName) !== meetingName ? meetingName : "",
            sessionNameLabel(snapshot?.sessionName),
            snapshot?.circuitName,
        ].filter(Boolean);
        el("hero-live-sub").textContent = parts.join(" · ");

        const stats = [];
        if (snapshot?.lapCount != null) stats.push(snapshotLap(snapshot));
        const track = trackInfo(snapshot?.trackStatus);
        if (track) stats.push(track.label);
        if (snapshot?.elapsedSeconds != null) stats.push(`已用时 ${elapsedLabel(snapshot.elapsedSeconds)}`);
        if (phase === "lost") stats.push("以下为最后收到的数据");
        el("hero-live-stats").replaceChildren(...stats.map((value) => node("span", "", value)));
        el("hero-live-link").textContent =
            phase === "finished" ? "查看完整计时与赛果 →" : "查看完整实时计时 →";
    }

    function renderHeroUpcoming() {
        const entry = upcomingEntry();
        if (!entry) {
            el("next-overline").textContent = "赛历";
            el("next-meta").textContent = "";
            el("next-title").textContent = state.calendarLoaded ? "本赛季已无后续比赛" : "正在获取赛历…";
            el("next-sub").textContent = state.calendarLoaded
                ? "赛历中的比赛都已结束，可在赛历页查看历史分站。"
                : "PitPulse 自托管计时服务";
            el("sessions").replaceChildren();
            setCountdownIdle();
            return;
        }

        const { meeting, session } = entry;
        el("next-overline").textContent = meeting.round ? `下一站 · 第 ${meeting.round} 站` : "下一站";
        el("next-meta").textContent = meeting.country || meeting.countryCode || "";
        el("next-title").textContent = gpName(meeting.name);
        const sub = [
            meeting.name !== gpName(meeting.name) ? meeting.name : "",
            meetingPlace(meeting),
            `距${sessionTypeLabel(session.sessionType)} ${formatSessionTime(session.startTime)}`,
        ]
            .filter(Boolean)
            .join(" · ");
        el("next-sub").textContent = sub;
        renderSessionChips(meeting, session);
        startCountdown();
    }

    function renderSessionChips(meeting, nextSession) {
        const sessions = [...(meeting.sessions || [])].sort(
            (a, b) => (parseDate(a.startTime)?.getTime() || 0) - (parseDate(b.startTime)?.getTime() || 0),
        );
        const now = Date.now();
        const fragment = document.createDocumentFragment();
        for (const session of sessions) {
            const chip = node("div", "chip");
            chip.setAttribute("role", "listitem");
            const end = parseDate(session.endTime) || parseDate(session.startTime);
            const finished =
                session.status === "finished" ||
                session.status === "cancelled" ||
                Boolean(end && end.getTime() < now);
            if (session.sessionType === "race") chip.classList.add("is-race");
            if (finished) chip.classList.add("is-done");
            if (nextSession && nextSession.id === session.id) chip.classList.add("is-next");
            const time = sessionTimeParts(session.startTime);
            const clock = node("span", "chip-time");
            clock.append(node("span", "chip-day", time.day));
            if (time.clock) clock.append(node("span", "chip-clock", time.clock));
            chip.append(node("span", "chip-label", sessionTypeLabel(session.sessionType)), clock);
            fragment.append(chip);
        }
        el("sessions").replaceChildren(fragment);
    }

    function setCountdownIdle() {
        const countdown = el("countdown");
        if (!countdown) return;
        countdown.classList.add("is-idle");
        for (const unit of countdown.querySelectorAll("[data-unit]")) unit.textContent = "--";
    }

    function writeCountdown(target, countdownEl) {
        const remaining = Math.max(0, target.getTime() - Date.now());
        const seconds = Math.floor(remaining / 1000);
        const values = {
            days: Math.floor(seconds / 86400),
            hours: Math.floor((seconds % 86400) / 3600),
            minutes: Math.floor((seconds % 3600) / 60),
            seconds: seconds % 60,
        };
        countdownEl.classList.remove("is-idle");
        for (const [unit, value] of Object.entries(values)) {
            const cell = countdownEl.querySelector(`[data-unit="${unit}"]`);
            if (cell && cell.textContent !== pad(value)) cell.textContent = pad(value);
        }
    }

    function compactCountdown(target) {
        const remaining = Math.max(0, target.getTime() - Date.now());
        const seconds = Math.floor(remaining / 1000);
        const days = Math.floor(seconds / 86400);
        const hours = Math.floor((seconds % 86400) / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        const secs = seconds % 60;
        const clock = `${pad(hours)}:${pad(minutes)}:${pad(secs)}`;
        return days ? `${days} 天 ${clock}` : clock;
    }

    function startCountdown() {
        updateCountdowns();
        if (state.ticker) return;
        state.ticker = setInterval(updateCountdowns, 1000);
    }

    function updateCountdowns() {
        const entry = upcomingEntry();
        if (!el("hero-upcoming").hidden) {
            if (entry) writeCountdown(entry.start, el("countdown"));
            else setCountdownIdle();
        }
        for (const id of ["idle-countdown", "live-idle-countdown"]) {
            const target = el(id);
            if (target && !target.closest("[hidden]")) target.textContent = compactCountdown(entry.start);
        }
    }

    /* ---------- live card (overview) ---------- */

    function renderLiveCard() {
        const phase = livePhase();
        const snapshot = state.snapshot;
        const drivers = sortedDrivers(snapshot);

        el("session-line").textContent =
            [
                snapshot?.meetingName ? gpName(snapshot.meetingName) : "",
                sessionNameLabel(snapshot?.sessionName),
            ]
                .filter(Boolean)
                .join(" · ") ||
            (phase === "idle" ? "当前没有进行中的比赛" : "正在连接实时数据…");

        // The idle panel already states there is no session, so drop the duplicate line.
        el("session-line").hidden = phase === "idle";
        el("live-meta").hidden = phase === "idle" || phase === "loading";
        const track = trackInfo(snapshot?.trackStatus);
        const tag = el("track-tag");
        tag.textContent = track ? track.label : snapshot?.trackStatus || "—";
        tag.dataset.tone = track ? track.tone : "neutral";
        el("lap-count").textContent = snapshotLap(snapshot);

        const table = el("live-table");
        const idle = el("live-idle");
        const empty = el("live-empty");
        const showRows = drivers.length > 0 && phase !== "idle";

        table.hidden = !showRows;
        idle.hidden = phase !== "idle";
        empty.hidden = showRows || phase === "idle";
        if (!empty.hidden) empty.textContent = phase === "loading" ? "正在连接实时数据…" : "等待车手数据…";

        if (showRows) renderLiveRows(el("live-rows"), drivers.slice(0, 8));
        if (phase === "idle") renderIdlePanel();
    }

    function sortedDrivers(snapshot) {
        return (snapshot?.drivers || [])
            .filter((driver) => !driver.retired)
            .sort((a, b) => (a.position ?? 999) - (b.position ?? 999));
    }

    function renderIdlePanel() {
        const entry = upcomingEntry();
        el("idle-title").textContent = "当前没有进行中的比赛";
        el("idle-copy").textContent =
            STATUS_REASONS[state.snapshot?.statusReason] || "下一场比赛开始时会自动显示实时计时。";

        const nextBox = el("idle-next");
        nextBox.hidden = !entry;
        if (entry) {
            el("idle-next-name").textContent = `${gpName(entry.meeting.name)} · ${sessionTypeLabel(entry.session.sessionType)}`;
            el("idle-next-time").textContent = formatSessionTime(entry.session.startTime);
            el("idle-countdown").textContent = compactCountdown(entry.start);
        }

        const last = state.lastResult;
        const lastBox = el("idle-last");
        lastBox.hidden = !last;
        if (!last) return;
        el("idle-last-name").textContent = `${gpName(last.meeting.name)} · 正赛`;
        el("idle-podium").replaceChildren(
            ...last.rows.slice(0, 3).map((row) => {
                const pill = node("span", "");
                const dot = node("i", "");
                dot.style.setProperty("--team", teamColor(row.team));
                pill.append(dot, node("b", "", `P${row.position}`), document.createTextNode(` ${driverCode(row)}`));
                return pill;
            }),
        );
        el("idle-last-link").href = `#/results/${encodeURIComponent(last.meeting.id)}/race`;
    }

    /* ---------- live rows ---------- */

    function renderLiveRows(container, drivers) {
        const fragment = document.createDocumentFragment();
        drivers.forEach((driver, index) => {
            const row = node("div", "row");
            if (index === 0) row.classList.add("is-leader");
            row.style.setProperty("--team", teamColor(driver.team));
            row.title = [driver.name, driver.team].filter(Boolean).join(" · ");

            const pos = node("span", "pos", String(driver.position ?? index + 1));
            const code = node("span", "code");
            const helmet = helmetImage(driver.name, driver.number, driver.driverId);
            if (helmet) code.append(helmet);
            code.append(document.createTextNode(driverCode(driver)));
            if (driver.inPit) code.append(node("span", "pit", "PIT"));
            const tyre = node("span", "tyre");
            const info = compound(driver.tireCompound);
            tyre.textContent = info ? info.letter : "·";
            if (info) {
                tyre.dataset.compound = info.key;
                tyre.title = driver.tireCompound;
            }

            row.append(
                pos,
                code,
                node("span", "team", driver.team || ""),
                node("span", "gap", index === 0 ? "—" : driver.gap || "—"),
                node("span", "last", driver.lastLap || "—"),
                tyre,
            );
            fragment.append(row);
        });
        container.replaceChildren(fragment);
    }

    /* ---------- conditions ---------- */

    // Open-Meteo weather codes, so the forecast reads as weather and not a number.
    const WEATHER_CODES = {
        0: "晴",
        1: "大部晴朗",
        2: "局部多云",
        3: "阴",
        45: "雾",
        48: "雾凇",
        51: "小毛毛雨",
        53: "毛毛雨",
        55: "强毛毛雨",
        56: "冻毛毛雨",
        57: "强冻毛毛雨",
        61: "小雨",
        63: "中雨",
        65: "大雨",
        66: "冻雨",
        67: "强冻雨",
        71: "小雪",
        73: "中雪",
        75: "大雪",
        77: "米雪",
        80: "阵雨",
        81: "强阵雨",
        82: "暴雨",
        85: "阵雪",
        86: "强阵雪",
        95: "雷雨",
        96: "雷雨伴冰雹",
        99: "强雷雨伴冰雹",
    };

    function weatherCodeLabel(code) {
        if (code === null || code === undefined) return "—";
        return WEATHER_CODES[Number(code)] || "—";
    }

    function weatherEntryKey(entry) {
        return entry ? `${entry.meeting.id}:${entry.session.id}` : "";
    }

    // The live feed's readings only describe a session that is on track right
    // now. When nothing is running, show the next session's forecast instead of
    // an empty card: the weekend's weather is just as relevant before FP1.
    async function loadNextWeather(entry) {
        const key = weatherEntryKey(entry);
        if (!key) return;
        const cache = state.nextWeather;
        if (cache.key === key || cache.pending === key) return;
        state.nextWeather = { ...cache, pending: key };
        let hour = null;
        let status = "unavailable";
        try {
            const { body } = await api(
                `/api/v1/meetings/${encodeURIComponent(entry.meeting.id)}/weather`,
            );
            const data = body?.data || {};
            status = data.status || "unavailable";
            const target = entry.start.getTime();
            for (const candidate of Array.isArray(data.hours) ? data.hours : []) {
                const at = parseDate(candidate.utc);
                if (!at) continue;
                if (!hour || Math.abs(at.getTime() - target) < Math.abs(parseDate(hour.utc).getTime() - target)) {
                    hour = candidate;
                }
            }
        } catch {
            status = "unavailable";
        }
        state.nextWeather = { key, pending: null, hour, status };
        renderConditions();
    }

    function renderConditions() {
        const weather = livePhase() === "idle" ? null : state.snapshot?.weather;
        if (weather) {
            renderLiveConditions(weather);
            return;
        }
        renderForecastConditions();
    }

    function conditionItems(entries) {
        const fragment = document.createDocumentFragment();
        for (const item of entries) {
            const wrapper = node("div", "condition");
            wrapper.append(node("span", "label", item.label), node("span", "value", item.value));
            fragment.append(wrapper);
        }
        return fragment;
    }

    function rainCondition(label, value, fraction) {
        const rain = node("div", "condition is-wide");
        const bar = node("div", "rain-bar");
        const fill = node("i", "");
        fill.style.width = `${Math.round(Math.max(0, Math.min(1, fraction)) * 100)}%`;
        bar.append(fill);
        rain.append(node("span", "label", label), node("span", "value", value), bar);
        return rain;
    }

    function renderLiveConditions(weather) {
        el("conditions-grid").hidden = false;
        el("conditions-empty").hidden = true;
        el("conditions-meta").textContent = weather.utc ? `观测 ${formatTime(weather.utc)}` : "";

        const fragment = conditionItems([
            { label: "气温", value: number(weather.airTemp, "°") },
            { label: "赛道温度", value: number(weather.trackTemp, "°") },
            { label: "湿度", value: number(weather.humidity, "%") },
            {
                label: "风速",
                value: weather.windSpeed == null ? "—" : `${Number(weather.windSpeed).toFixed(1)} m/s`,
            },
        ]);
        fragment.append(
            rainCondition("降雨", weather.rainfall ? "有降雨" : "无降雨", weather.rainfall ? 1 : 0),
        );
        el("conditions-grid").replaceChildren(fragment);
    }

    function renderForecastConditions() {
        const grid = el("conditions-grid");
        const empty = el("conditions-empty");
        const meta = el("conditions-meta");
        const entry = upcomingEntry();
        if (!entry) {
            grid.hidden = true;
            grid.replaceChildren();
            empty.hidden = false;
            empty.textContent = state.calendarLoaded
                ? "赛历中的比赛都已结束，暂无天气预报。"
                : "正在获取赛历…";
            meta.textContent = "";
            return;
        }

        const key = weatherEntryKey(entry);
        meta.textContent = `${sessionTypeLabel(entry.session.sessionType)} · ${formatDateTime(entry.session.startTime)}`;
        loadNextWeather(entry);

        const cache = state.nextWeather;
        const hour = cache.key === key ? cache.hour : null;
        if (!hour) {
            grid.hidden = true;
            grid.replaceChildren();
            empty.hidden = false;
            const settled = cache.key === key && !cache.pending;
            empty.textContent = !settled
                ? "正在获取下一场天气预报…"
                : cache.status === "outside_forecast_window"
                  ? "下一场尚未进入预报窗口，赛前 16 天内提供。"
                  : "暂时无法获取下一场天气预报。";
            return;
        }

        grid.hidden = false;
        empty.hidden = true;
        const probability = Number(hour.precipitationProbability);
        const wet = Number.isFinite(probability) ? probability / 100 : 0;
        const fragment = conditionItems([
            { label: "气温", value: number(hour.airTemp, "°") },
            { label: "天气", value: weatherCodeLabel(hour.weatherCode) },
            {
                label: "风速",
                value: hour.windSpeed == null ? "—" : `${Number(hour.windSpeed).toFixed(1)} m/s`,
            },
            {
                label: "降水量",
                value: hour.precipitation == null ? "—" : `${Number(hour.precipitation).toFixed(1)} mm`,
            },
        ]);
        fragment.append(
            rainCondition(
                "降水概率",
                Number.isFinite(probability) ? `${Math.round(probability)}%` : "—",
                wet,
            ),
        );
        grid.replaceChildren(fragment);
    }

    /* ---------- rail standings ---------- */

    function renderRailStandings() {
        const list = el("standings-list");
        const empty = el("standings-empty");
        const standings = state.driversStandings.slice(0, 8);
        el("standings-season").textContent = standings[0]?.season ? `${standings[0].season} 赛季` : "";
        if (!standings.length) {
            list.replaceChildren();
            list.hidden = true;
            empty.hidden = false;
            return;
        }
        list.hidden = false;
        empty.hidden = true;

        const leader = Math.max(...standings.map((standing) => standing.points), 1);
        const fragment = document.createDocumentFragment();
        for (const standing of standings) {
            const item = node("li", "standing");
            const bar = node("span", "bar");
            const fill = node("i", "");
            fill.style.width = `${Math.max(4, (standing.points / leader) * 100)}%`;
            bar.append(fill);
            item.title = [standing.driverName, standing.constructor].filter(Boolean).join(" · ");
            const code = node("span", "code");
            const helmet = helmetImage(standing.driverId, standing.driverName);
            if (helmet) code.append(helmet);
            code.append(document.createTextNode(driverCode({ name: standing.driverName })));
            item.append(
                node("span", "rank", String(standing.position)),
                code,
                bar,
                node("span", "points", String(Math.round(standing.points))),
            );
            fragment.append(item);
        }
        list.replaceChildren(fragment);
    }

    /* ---------- live page ---------- */

    function renderLivePage() {
        const phase = livePhase();
        const snapshot = state.snapshot;
        const drivers = sortedDrivers(snapshot);

        const track = trackInfo(snapshot?.trackStatus);
        const tag = el("live-page-tag");
        tag.textContent = track ? track.label : snapshot?.trackStatus || "—";
        tag.dataset.tone = track ? track.tone : "neutral";
        el("live-page-lap").textContent = snapshotLap(snapshot);

        const sessionLine = [
            snapshot?.meetingName ? gpName(snapshot.meetingName) : "",
            sessionNameLabel(snapshot?.sessionName),
            snapshot?.circuitName,
        ].filter(Boolean);
        const season = seasonMeetings();
        const finishedCount = season.filter((meeting) => isFinished(meeting)).length;
        const idleSub = season.length
            ? `${seasonYear(season)} 赛季 · 已完成 ${finishedCount} 站`
            : "当前没有进行中的比赛";
        el("live-page-sub").textContent =
            phase === "idle"
                ? idleSub
                : sessionLine.length
                  ? sessionLine.join(" · ")
                  : "正在连接实时数据…";
        el("live-page-meta").hidden = phase === "idle" || phase === "loading";

        const labels = {
            loading: ["正在连接实时数据…", "连接成功后这里会显示当前会话。"],
            live: [
                snapshot?.sourceStatus === "stale" ? "实时数据显示延迟" : "比赛进行中",
                [snapshotLap(snapshot), elapsedLabel(snapshot?.elapsedSeconds)].filter(Boolean).join(" · "),
            ],
            finished: ["比赛已结束", "以下为收到的最终计时，赛果以官方分类为准。"],
            lost: ["实时连接中断", "以下为断开前收到的最后一份数据。"],
            idle: ["当前没有进行中的比赛", "下一场开始时会自动切换为实时计时。"],
        };
        el("live-phase").dataset.phase = phase;
        const [bannerTitle, bannerCopy] = labels[phase] || labels.loading;
        el("live-phase-title").textContent = bannerTitle;
        el("live-phase-copy").textContent = bannerCopy;
        // The idle panel carries the "no session" message, so the banner would only repeat it.
        el("live-phase").hidden = phase === "idle";

        const table = el("live-full-table");
        const idle = el("live-page-idle");
        const showRows = drivers.length > 0 && phase !== "idle";
        table.hidden = !showRows;
        idle.hidden = phase !== "idle";

        if (showRows) renderLiveRows(el("live-full-rows"), drivers);
        if (phase === "idle") {
            const entry = upcomingEntry();
            el("live-idle-copy").textContent =
                STATUS_REASONS[snapshot?.statusReason] || "比赛开始时这里会自动切换为实时计时。";
            el("live-idle-next").hidden = !entry;
            if (entry) {
                el("live-idle-next-name").textContent = `${gpName(entry.meeting.name)} · ${sessionTypeLabel(entry.session.sessionType)}`;
                el("live-idle-next-time").textContent = formatSessionTime(entry.session.startTime);
                el("live-idle-countdown").textContent = compactCountdown(entry.start);
            }
        }

        const last = state.lastResult;
        el("live-last-result").hidden = !last;
        if (!last) return;
        el("live-last-title").textContent = `${gpName(last.meeting.name)} · 正赛结果`;
        el("live-last-meta").textContent = last.meta?.stale ? "数据已标记过期" : "";
        el("live-last-content").replaceChildren(buildResultTable(last.rows, "race", last.meta));
        el("live-last-link").href = `#/results/${encodeURIComponent(last.meeting.id)}/race`;
    }

    /* ---------- calendar page ---------- */

    function meetingTone(meeting, ctx) {
        const live =
            (ctx.phase === "live" || ctx.phase === "finished" || ctx.phase === "lost") &&
            Boolean(ctx.liveName) &&
            gpName(meeting.name) === gpName(ctx.liveName);
        if (meeting.status === "cancelled") return { tone: "cancelled", label: "已取消", live: false };
        if (live) {
            return {
                tone: ctx.phase === "live" ? "live" : "done",
                label: ctx.phase === "live" ? "进行中" : "已结束",
                live: true,
            };
        }
        if (isFinished(meeting)) return { tone: "done", label: "已结束", live: false };
        if (ctx.upcoming && ctx.upcoming.meeting.id === meeting.id) {
            return { tone: "next", label: "下一站", live: false };
        }
        return { tone: "neutral", label: "未开始", live: false };
    }

    function defaultCalendarMonth(meetings, year) {
        const now = new Date();
        const today = dayKey(now);
        const running = meetings.some((meeting) => {
            const span = meetingSpan(meeting);
            return Boolean(span && span.start <= today && today <= span.end);
        });
        if (running) return now.getMonth();

        const upcoming = upcomingEntry();
        const next = upcoming ? parseDate(upcoming.session.startTime) : null;
        if (next && next.getFullYear() === year) return next.getMonth();

        const finished = meetings.filter(isFinished);
        const last = finished.length ? finished[finished.length - 1] : meetings[0];
        const date = parseDate(last?.startDate);
        return date && date.getFullYear() === year ? date.getMonth() : 0;
    }

    function renderCalendarPage() {
        const list = el("calendar-list");
        const empty = el("calendar-empty");
        const monthView = el("calendar-month-view");
        if (!state.calendar.length) {
            empty.hidden = false;
            list.hidden = true;
            monthView.hidden = true;
            el("calendar-count").textContent = "";
            return;
        }
        empty.hidden = true;

        const meetings = seasonMeetings();
        const year = seasonYear(meetings);
        const ctx = {
            phase: livePhase(),
            liveName: state.snapshot?.meetingName || "",
            upcoming: upcomingEntry(),
        };

        el("calendar-season").textContent = `${year} 赛季`;
        el("calendar-count").textContent = `${meetings.length} 站 · 已完成 ${meetings.filter(isFinished).length} 站`;

        for (const button of document.querySelectorAll("[data-calendar-mode]")) {
            const active = button.dataset.calendarMode === state.calendarMode;
            button.classList.toggle("is-active", active);
            button.setAttribute("aria-selected", String(active));
        }

        const monthMode = state.calendarMode === "month";
        monthView.hidden = !monthMode;
        list.hidden = monthMode;
        if (monthMode) renderCalendarMonth(meetings, year, ctx);
        else renderCalendarYear(meetings, ctx);
    }

    function renderCalendarMonth(meetings, year, ctx) {
        if (state.calendarMonth == null) state.calendarMonth = defaultCalendarMonth(meetings, year);
        const month = state.calendarMonth;
        const inMonth = meetingsInMonth(meetings, year, month);
        const finished = inMonth.filter(isFinished).length;

        el("calendar-month-title").textContent = `${year} 年 ${month + 1} 月`;
        el("calendar-month-sub").textContent = inMonth.length
            ? [
                  `${inMonth.length} 站`,
                  `已结束 ${finished} 站`,
                  finished < inMonth.length ? `待进行 ${inMonth.length - finished} 站` : "",
              ]
                  .filter(Boolean)
                  .join(" · ")
            : "本赛季该月没有分站";
        el("calendar-prev").disabled = month === 0;
        el("calendar-next").disabled = month === 11;

        const strip = el("calendar-strip");
        const stripFragment = document.createDocumentFragment();
        for (let index = 0; index < 12; index += 1) {
            const count = meetingsInMonth(meetings, year, index).length;
            const button = node("button", "cal-month");
            button.type = "button";
            button.classList.toggle("is-active", index === month);
            button.classList.toggle("has-races", count > 0);
            button.setAttribute("aria-pressed", String(index === month));
            button.setAttribute("aria-label", `${index + 1} 月，${count} 站`);
            button.append(
                node("span", "", String(index + 1).padStart(2, "0")),
                node("i", "cal-month-bar"),
            );
            button.onclick = () => {
                state.calendarMonth = index;
                state.calendarDay = null;
                renderCalendarPage();
            };
            stripFragment.append(button);
        }
        strip.replaceChildren(stripFragment);

        const grid = el("calendar-grid");
        const fragment = document.createDocumentFragment();
        for (const label of WEEKDAY_LABELS) fragment.append(node("span", "cal-weekday", label));
        const offset = (new Date(year, month, 1).getDay() + 6) % 7;
        const days = new Date(year, month + 1, 0).getDate();
        const todayKey = dayKey(new Date());
        for (let blank = 0; blank < offset; blank += 1) {
            fragment.append(node("span", "cal-day is-blank"));
        }

        for (let day = 1; day <= days; day += 1) {
            const key = dayKey(new Date(year, month, day));
            const events = inMonth.filter((meeting) => {
                const span = meetingSpan(meeting);
                return Boolean(span && span.start <= key && key <= span.end);
            });
            const cell = node("button", "cal-day");
            cell.type = "button";
            cell.classList.toggle("has-race", events.length > 0);
            cell.classList.toggle("is-today", key === todayKey);
            cell.classList.toggle("is-selected", key === state.calendarDay);
            cell.setAttribute("aria-pressed", String(key === state.calendarDay));
            cell.setAttribute(
                "aria-label",
                `${month + 1} 月 ${day} 日${events.length ? `，${events.length} 站赛事` : ""}`,
            );
            cell.append(node("span", "cal-day-num", String(day)));
            for (const meeting of events.slice(0, 2)) {
                const tone = meetingTone(meeting, ctx);
                const pill = node("span", "cal-pill", shortGpName(meeting.name));
                pill.dataset.tone = tone.tone;
                cell.append(pill);
            }
            if (events.length > 2) cell.append(node("span", "cal-more", `+${events.length - 2}`));
            cell.onclick = () => {
                state.calendarDay = state.calendarDay === key ? null : key;
                renderCalendarPage();
            };
            fragment.append(cell);
        }
        grid.replaceChildren(fragment);

        el("calendar-hint").textContent = state.calendarDay
            ? "已筛选指定日期，再次点击该日期可取消"
            : "点击日期筛选当日赛事";

        renderCalendarSide(inMonth, month, ctx);
    }

    function shiftCalendarMonth(delta) {
        if (state.calendarMonth == null) return;
        const next = state.calendarMonth + delta;
        if (next < 0 || next > 11) return;
        state.calendarMonth = next;
        state.calendarDay = null;
        renderCalendarPage();
    }

    function renderCalendarSide(inMonth, month, ctx) {
        const selected = state.calendarDay;
        const show = selected
            ? inMonth.filter((meeting) => {
                  const span = meetingSpan(meeting);
                  return Boolean(span && span.start <= selected && selected <= span.end);
              })
            : inMonth;
        el("calendar-side-title").textContent = selected
            ? `${month + 1} 月 ${Number(selected.slice(8))} 日赛事`
            : "本月赛事";
        el("calendar-side-count").textContent = `${show.length} 站`;

        const list = el("calendar-side-list");
        if (!show.length) {
            list.replaceChildren(node("p", "empty", selected ? "该日期没有赛事。" : "该月没有分站。"));
            return;
        }
        const fragment = document.createDocumentFragment();
        for (const meeting of show) {
            const tone = meetingTone(meeting, ctx);
            const start = parseDate(meeting.startDate);
            const row = node("a", "cal-event");
            row.href = `#/results/${encodeURIComponent(meeting.id)}/race`;
            if (tone.live) row.classList.add("is-live");

            const dateBlock = node("span", "cal-event-date");
            dateBlock.append(
                node("b", "", start ? String(start.getDate()) : "—"),
                node("small", "", start ? `${start.getMonth() + 1} 月` : ""),
            );

            const main = node("span", "cal-event-main");
            const meta = node("span", "cal-event-meta");
            meta.append(
                node("b", "", roundLabel(meeting)),
                node("span", "", formatDateRange(meeting.startDate, meeting.endDate)),
            );
            main.append(
                meta,
                node("strong", "", gpName(meeting.name)),
                node(
                    "span",
                    "cal-event-place",
                    [meetingPlace(meeting), meeting.circuit?.name].filter(Boolean).join(" · "),
                ),
            );

            const badge = node("span", "badge");
            badge.dataset.tone = tone.tone;
            badge.textContent = tone.label;

            row.append(dateBlock, main, badge);
            fragment.append(row);
        }
        list.replaceChildren(fragment);
    }

    function renderCalendarYear(meetings, ctx) {
        const ordered = [...meetings].sort(
            (a, b) =>
                (a.round ?? 99) - (b.round ?? 99) || (a.startDate || "").localeCompare(b.startDate || ""),
        );
        const fragment = document.createDocumentFragment();
        for (const meeting of ordered) {
            const tone = meetingTone(meeting, ctx);
            const row = node("a", "round-row");
            row.href = `#/results/${encodeURIComponent(meeting.id)}/race`;
            if (tone.live) row.classList.add("is-live");

            const main = node("div", "round-main");
            main.append(
                node("b", "", gpName(meeting.name)),
                node(
                    "span",
                    "",
                    [meetingPlace(meeting), meeting.name !== gpName(meeting.name) ? meeting.name : ""]
                        .filter(Boolean)
                        .join(" · "),
                ),
            );

            const badge = node("span", "badge");
            badge.dataset.tone = tone.tone;
            badge.textContent = tone.label;

            row.append(
                node("span", "round-number", roundLabel(meeting)),
                main,
                node("span", "round-date", formatDateRange(meeting.startDate, meeting.endDate)),
                badge,
                svgIcon("M9 5l7 7-7 7", "round-chevron"),
            );
            fragment.append(row);
        }
        el("calendar-list").replaceChildren(fragment);
    }

    /* ---------- standings page ---------- */

    function setStandingsKind(kind) {
        state.standingsKind = kind;
        for (const button of document.querySelectorAll("[data-standings]")) {
            const active = button.dataset.standings === kind;
            button.classList.toggle("is-active", active);
            button.setAttribute("aria-selected", active ? "true" : "false");
        }
        renderStandingsPage();
    }

    function renderStandingsPage() {
        const panel = el("standings-panel");
        const empty = el("standings-page-empty");
        const drivers = state.driversStandings;
        const constructors = state.constructorStandings;
        el("standings-page-season").textContent = drivers[0]?.season ? `${drivers[0].season} 赛季` : "赛季";

        if (!drivers.length && !constructors.length) {
            panel.replaceChildren();
            panel.hidden = true;
            empty.hidden = false;
            return;
        }
        panel.hidden = false;
        empty.hidden = true;

        if (state.standingsKind === "constructors") {
            el("standings-page-meta").textContent = "车队积分";
            panel.replaceChildren(buildConstructorTable(constructors));
        } else {
            el("standings-page-meta").textContent = "车手积分";
            panel.replaceChildren(buildDriverTable(drivers));
        }
    }

    function buildDriverTable(rows) {
        const leader = Math.max(...rows.map((row) => row.points), 1);
        const table = node("div", "dt");
        table.dataset.kind = "drivers";
        const head = node("div", "dt-head");
        for (const [label, className] of [
            ["名次", ""],
            ["", "col-code"],
            ["车手", "col-team"],
            ["积分占比", "col-bar"],
            ["胜场", "col-wins num"],
            ["积分", "num"],
        ]) {
            head.append(node("span", className, label));
        }
        table.append(head);
        for (const row of rows) {
            const item = node("div", "dt-row");
            item.style.setProperty("--team", teamColor(row.constructor));
            item.title = [row.driverName, row.constructor, `${row.wins ?? 0} 胜`].filter(Boolean).join(" · ");
            const who = node("div", "who");
            const helmet = helmetImage(row.driverId, row.driverName);
            if (helmet) who.append(helmet);
            who.append(node("b", "", row.driverName), node("span", "col-team", row.constructor || ""));
            const bar = node("span", "bar col-bar");
            const fill = node("i", "");
            fill.style.width = `${Math.max(3, (row.points / leader) * 100)}%`;
            bar.append(fill);
            item.append(
                node("span", "pos", String(row.position)),
                node("span", "code col-code", driverCode({ name: row.driverName })),
                who,
                bar,
                node("span", "num dim col-wins", String(row.wins ?? "—")),
                node("span", "num", String(Math.round(row.points))),
            );
            table.append(item);
        }
        return table;
    }

    function buildConstructorTable(rows) {
        const leader = Math.max(...rows.map((row) => row.points), 1);
        const table = node("div", "dt");
        table.dataset.kind = "constructors";
        const head = node("div", "dt-head");
        for (const [label, className] of [
            ["名次", ""],
            ["车队", ""],
            ["积分占比", "col-bar"],
            ["胜场", "col-wins num"],
            ["积分", "num"],
        ]) {
            head.append(node("span", className, label));
        }
        table.append(head);
        for (const row of rows) {
            const item = node("div", "dt-row");
            item.style.setProperty("--team", teamColor(row.constructorName));
            const who = node("div", "who");
            const logo = teamLogoImage(row.constructorName, row.constructorId);
            if (logo) who.append(logo);
            who.append(node("b", "", row.constructorName));
            const bar = node("span", "bar col-bar");
            const fill = node("i", "is-team");
            fill.style.width = `${Math.max(3, (row.points / leader) * 100)}%`;
            bar.append(fill);
            item.append(
                node("span", "pos", String(row.position)),
                who,
                bar,
                node("span", "num dim col-wins", String(row.wins ?? "—")),
                node("span", "num", String(Math.round(row.points))),
            );
            table.append(item);
        }
        return table;
    }

    /* ---------- results page ---------- */

    function resultSessions(meeting) {
        const order = ["race", "qualifying", "sprint", "sprintQualifying"];
        return (meeting?.sessions || [])
            .filter((session) => order.includes(session.sessionType))
            .sort((a, b) => order.indexOf(a.sessionType) - order.indexOf(b.sessionType));
    }

    function defaultResultsMeeting() {
        return lastFinishedMeeting() || upcomingEntry()?.meeting || seasonMeetings()[0] || null;
    }

    function renderResultsShell() {
        const select = el("results-round");
        const meetings = seasonMeetings();
        if (!state.calendarLoaded) {
            el("results-title").textContent = "比赛结果";
            el("results-sub").textContent = "正在获取赛历…";
            return;
        }
        if (!meetings.length) {
            el("results-title").textContent = "比赛结果";
            el("results-sub").textContent = "暂无赛历数据。";
            select.replaceChildren();
            return;
        }

        if (!state.results.meetingId || !meetings.some((meeting) => meeting.id === state.results.meetingId)) {
            const fallback = defaultResultsMeeting() || meetings[0];
            state.results.meetingId = fallback.id;
        }

        if (!select.options.length) {
            select.replaceChildren(
                ...meetings
                    .slice()
                    .sort((a, b) => b.round - a.round)
                    .map((meeting) => {
                        const option = document.createElement("option");
                        option.value = meeting.id;
                        option.textContent = `R${meeting.round} · ${gpName(meeting.name)}`;
                        return option;
                    }),
            );
        }
        select.value = state.results.meetingId;
    }

    function renderResultsSessions(meeting) {
        const sessions = resultSessions(meeting);
        const box = el("results-sessions");
        if (!sessions.length) {
            box.replaceChildren();
            return;
        }
        if (!sessions.some((session) => session.sessionType === state.results.sessionType)) {
            state.results.sessionType = sessions[0].sessionType;
        }
        box.replaceChildren(
            ...sessions.map((session) => {
                const button = node("button", "", sessionTypeLabel(session.sessionType));
                button.type = "button";
                button.setAttribute("role", "tab");
                button.dataset.session = session.sessionType;
                const active = session.sessionType === state.results.sessionType;
                button.classList.toggle("is-active", active);
                button.setAttribute("aria-selected", active ? "true" : "false");
                return button;
            }),
        );
    }

    function renderResultsPage() {
        renderResultsShell();
        const meeting = state.calendar.find((item) => item.id === state.results.meetingId);
        const panel = el("results-panel");
        el("result-summary").hidden = true;
        const meta = el("results-meta");
        if (!meeting) {
            panel.replaceChildren();
            meta.textContent = "";
            return;
        }
        renderResultsSessions(meeting);
        el("results-title").textContent = gpName(meeting.name);
        el("results-sub").textContent = [
            meeting.name !== gpName(meeting.name) ? meeting.name : "",
            meetingPlace(meeting),
            formatDateRange(meeting.startDate, meeting.endDate),
        ]
            .filter(Boolean)
            .join(" · ");

        const session = (meeting.sessions || []).find(
            (item) => item.sessionType === state.results.sessionType,
        );
        if (!session) {
            panel.replaceChildren(node("p", "empty", "该分站没有这类会话。"));
            meta.textContent = "";
            return;
        }

        const token = ++state.results.token;
        if (!state.resultsCache.has(session.id)) {
            panel.replaceChildren(node("p", "empty", "正在获取结果…"));
            meta.textContent = "";
            loadResults(session.id).then(() => {
                if (token === state.results.token) renderResultsPage();
            });
            return;
        }

        loadResults(session.id)
            .then(({ rows, meta: resultMeta }) => {
                if (token !== state.results.token) return;
                if (!rows.length) {
                    panel.replaceChildren(node("p", "empty", "该会话暂未同步结果数据。"));
                } else {
                    panel.replaceChildren(buildResultTable(rows, state.results.sessionType, resultMeta));
                    const summary = el("result-summary");
                    const leaders = [...rows].filter(row => row.position != null).sort((a, b) => a.position - b.position).slice(0, 3);
                    summary.replaceChildren(...leaders.map((row) => {
                        const item = node("section", "result-stat");
                        item.style.setProperty("--team", teamColor(row.team));
                        const identity = node("div", "result-stat-identity");
                        const logo = teamLogoImage(row.team, row.constructorId);
                        if (logo) identity.append(logo);
                        identity.append(node("span", "", row.team || ""));
                        item.append(node("span", "result-stat-label", `P${row.position}`), node("strong", "", row.driverName || row.driverId), identity);
                        return item;
                    }));
                    summary.hidden = !leaders.length;
                }
                meta.textContent = describeMeta(resultMeta);
            })
            .catch(() => {
                if (token !== state.results.token) return;
                state.resultsCache.delete(session.id);
                panel.replaceChildren(node("p", "empty", "结果加载失败，请稍后重试。"));
                meta.textContent = "";
            });
    }

    function describeMeta(meta) {
        if (!meta) return "";
        const parts = [];
        if (meta.source) parts.push(`来源 ${meta.source}`);
        if (meta.quality) parts.push(`数据${QUALITY_LABELS[meta.quality] || meta.quality}`);
        if (meta.fetchedAt) parts.push(`更新 ${formatDateTime(meta.fetchedAt)}`);
        if (meta.stale) parts.push("数据已标记过期");
        return parts.join(" · ");
    }

    function buildResultTable(rows, sessionType, meta) {
        const timing = sessionType === "qualifying" || sessionType === "sprintQualifying";
        const table = node("div", "dt");
        table.dataset.kind = "results";

        const columns = timing
            ? [
                  ["名次", ""],
                  ["", "col-code"],
                  ["车手", "col-team"],
                  ["Q1", "num"],
                  ["Q2", "num col-laps"],
                  ["Q3", "num col-points"],
              ]
            : [
                  ["名次", ""],
                  ["", "col-code"],
                  ["车手", "col-team"],
                  ["成绩", "num"],
                  ["圈数", "num col-laps"],
                  ["积分", "num col-points"],
              ];
        const head = node("div", "dt-head");
        for (const [label, className] of columns) head.append(node("span", className, label));
        table.append(head);

        const sorted = [...rows].sort((a, b) => (a.position ?? 999) - (b.position ?? 999));
        for (const row of sorted) {
            const item = node("div", "dt-row");
            item.style.setProperty("--team", teamColor(row.team));
            const who = node("div", "who");
            const status = CLASS_LABELS[(row.classification || "").toLowerCase()] || "";
            const logo = teamLogoImage(row.team, row.constructorId);
            if (logo) who.append(logo);
            who.append(
                node("b", "", row.driverName || row.driverId),
                node("span", "col-team", [row.team, status].filter(Boolean).join(" · ")),
            );
            const position = row.position ?? "—";

            if (timing) {
                item.append(
                    node("span", "pos", String(position)),
                    node("span", "code col-code", driverCode({ driverName: row.driverName })),
                    who,
                    node("span", "num", row.q1 || "—"),
                    node("span", "num col-laps", row.q2 || "—"),
                    node("span", "num col-points", row.q3 || "—"),
                );
            } else {
                const classified = (row.classification || "").toLowerCase() === "classified";
                item.append(
                    node("span", "pos", String(position)),
                    node("span", "code col-code", driverCode({ driverName: row.driverName })),
                    who,
                    node("span", "num", classified ? row.raceTime || row.time || "—" : status || "—"),
                    node("span", "num dim col-laps", row.laps == null ? "—" : String(row.laps)),
                    node("span", "num col-points", row.points == null ? "—" : String(row.points)),
                );
            }
            table.append(item);
        }

        if (meta?.stale) table.title = "该结果已被服务端标记为过期数据";
        return table;
    }

    function loadResults(sessionId) {
        let promise = state.resultsCache.get(sessionId);
        if (!promise) {
            promise = api(`/api/v1/sessions/${encodeURIComponent(sessionId)}/results`)
                .then(({ body }) => ({
                    rows: Array.isArray(body.data) ? body.data : [],
                    meta: body.meta || {},
                }))
                .catch((error) => {
                    state.resultsCache.delete(sessionId);
                    throw error;
                });
            state.resultsCache.set(sessionId, promise);
        }
        return promise;
    }

    async function loadLastResult() {
        const meeting = lastFinishedMeeting();
        if (!meeting) {
            state.lastResult = null;
            renderIdlePanel();
            renderLivePage();
            return;
        }
        if (state.lastResult?.meeting.id === meeting.id) return;
        const session = raceSession(meeting);
        if (!session) return;
        try {
            const { rows, meta } = await loadResults(session.id);
            state.lastResult = { meeting, session, rows, meta };
            renderIdlePanel();
            renderLivePage();
        } catch {
            state.lastResult = null;
        }
    }

    /* ---------- connection state ---------- */

    function setConnection(connection) {
        state.connection = connection;

    }

    function evaluateConnection() {
        if (state.unauthorized) return setConnection("locked");
        if (!state.streamController && !state.polling) return setConnection("offline");
        const phase = livePhase();
        if (phase === "loading") return setConnection("connecting");
        if (phase === "idle") return setConnection("idle");
        const snapshot = state.snapshot;
        if (snapshot?.sourceStatus === "stale") return setConnection("stale");
        if (snapshot?.sourceStatus === "disconnected") return setConnection("offline");
        if (phase === "finished") return setConnection("finished");
        setConnection("live");
    }

    function renderLiveEverything() {
        document.body.dataset.livePhase = livePhase();
        renderHero();
        renderLiveCard();
        renderLivePage();
        renderConditions();
        renderCalendarPage();
        evaluateConnection();
    }

    /* ---------- live stream ---------- */

    async function startStream() {
        if (state.streamController) return;
        const controller = new AbortController();
        state.streamController = controller;
        setConnection("connecting");

        try {
            const response = await fetch("/api/v1/live/stream", {
                signal: controller.signal,
                cache: "no-store",
                credentials: "same-origin",
            });
            if (response.status === 401) {
                state.streamController = null;
                markUnauthorized();
                evaluateConnection();
                return;
            }
            if (!response.ok || !response.body) throw new Error(`stream HTTP ${response.status}`);

            state.attempt = 0;
            state.polling = false;
            if (state.pollTimer) {
                clearInterval(state.pollTimer);
                state.pollTimer = null;
            }
            const reader = response.body.getReader();
            const decoder = new TextDecoder();
            let buffer = "";

            for (;;) {
                const { value, done } = await reader.read();
                if (done) break;
                buffer += decoder.decode(value, { stream: true });
                let boundary;
                while ((boundary = buffer.indexOf("\n\n")) >= 0) {
                    handleFrame(buffer.slice(0, boundary));
                    buffer = buffer.slice(boundary + 2);
                }
            }
            throw new Error("stream closed");
        } catch {
            if (controller.signal.aborted) return;
            state.streamController = null;
            evaluateConnection();
            startPolling();
            scheduleReconnect();
        }
    }

    function handleFrame(frame) {
        let event = "message";
        const data = [];
        for (const line of frame.split("\n")) {
            if (line.startsWith("event:")) event = line.slice(6).trim();
            else if (line.startsWith("data:")) data.push(line.slice(5).trimStart());
        }
        if (!data.length) return;
        const payload = data.join("\n");
        if (payload === "keep-alive") return;

        if (event === "snapshot") {
            try {
                applySnapshot(JSON.parse(payload));
            } catch {
                /* ignore a malformed frame */
            }
        } else if (event === "dataRefresh") {
            loadCalendar();
            loadStandings();
            loadLastResult();
        }
    }

    function applySnapshot(snapshot) {
        const before = livePhase();
        state.snapshot = snapshot;
        const after = livePhase();
        renderLiveEverything();
        if (after === "idle") renderIdlePanel();
        if (before !== after && after === "idle") loadLastResult();
    }

    function scheduleReconnect() {
        if (state.reconnectTimer) return;
        const delay = Math.min(15000, 1000 * 2 ** Math.min(state.attempt, 4));
        state.attempt += 1;
        state.reconnectTimer = setTimeout(() => {
            state.reconnectTimer = null;
            if (!document.hidden) startStream();
        }, delay);
    }

    function startPolling() {
        if (state.polling) return;
        state.polling = true;
        state.pollTimer = setInterval(async () => {
            try {
                const { body } = await api("/api/v1/live/snapshot");
                applySnapshot(body.data);
            } catch {
                if (state.unauthorized) {
                    clearInterval(state.pollTimer);
                    state.pollTimer = null;
                    state.polling = false;
                }
            }
        }, 15000);
    }

    /* ---------- loaders ---------- */

    async function loadCalendar() {
        try {
            const { body } = await api("/api/v1/calendar");
            state.calendar = Array.isArray(body.data) ? body.data : [];
            state.calendarLoaded = true;
            renderHero();
            renderCalendarPage();
            renderConditions();
            if (state.view === "results") renderResultsPage();
            updateCountdowns();
        } catch {
            if (state.unauthorized) return;
            state.calendarLoaded = true;
            el("next-title").textContent = "赛历加载失败";
            el("next-sub").textContent = "请检查服务端连接后刷新。";
        }
    }

    async function loadStandings() {
        try {
            const [drivers, constructors] = await Promise.all([
                api("/api/v1/standings/drivers"),
                api("/api/v1/standings/constructors"),
            ]);
            state.driversStandings = Array.isArray(drivers.body.data) ? drivers.body.data : [];
            state.constructorStandings = Array.isArray(constructors.body.data) ? constructors.body.data : [];
            renderRailStandings();
            renderStandingsPage();
        } catch {
            /* the empty states explain it */
        }
    }

    async function loadLiveSnapshot() {
        try {
            const { body } = await api("/api/v1/live/snapshot");
            applySnapshot(body.data);
        } catch {
            /* the stream will retry */
        }
    }

    /* ---------- routing ---------- */

    function currentRoute() {
        const parts = location.hash.replace(/^#\/?/, "").split("/").filter(Boolean);
        const view = ROUTES.includes(parts[0]) ? parts[0] : "overview";
        return { view, parts: parts.slice(1) };
    }

    function applyRoute() {
        const { view, parts } = currentRoute();
        state.view = view;
        el("workspace-title").textContent = VIEW_TITLES[view];
        document.body.dataset.view = view;
        if (view === "results") {
            if (parts[0]) state.results.meetingId = decodeURIComponent(parts[0]);
            if (parts[1]) state.results.sessionType = parts[1];
        }
        for (const section of document.querySelectorAll(".view")) {
            section.hidden = section.dataset.view !== view;
        }
        for (const link of document.querySelectorAll("[data-route]")) {
            const active = link.dataset.route === view;
            link.classList.toggle("is-active", active);
            if (active) link.setAttribute("aria-current", "page");
            else link.removeAttribute("aria-current");
        }
        document.title = `PitPulse · ${VIEW_TITLES[view] || "F1 实时计时"}`;
        document.querySelector(".app").scrollTo({ top: 0, behavior: "instant" });

        if (view === "calendar" && !state.calendarLoaded) loadCalendar();
        if (view === "standings" && !state.driversStandings.length) loadStandings();
        if (view === "results") {
            if (!state.calendarLoaded) loadCalendar().then(() => renderResultsPage());
            else renderResultsPage();
        }
        if (view === "live" && livePhase() === "idle") loadLastResult();
    }

    /* ---------- wiring ---------- */

    function wireChrome() {
        el("navigation-toggle").addEventListener("click", () => {
            const expanded = document.body.classList.toggle("navigation-expanded");
            el("navigation-toggle").setAttribute("aria-expanded", String(expanded));
            el("navigation-toggle").setAttribute("aria-label", expanded ? "收起导航" : "展开导航");
        });
        const density = el("density-toggle");
        try { document.body.classList.toggle("is-compact", localStorage.getItem("pitpulse-density") === "compact"); } catch {}
        const updateDensity = () => density.setAttribute("aria-pressed", String(document.body.classList.contains("is-compact")));
        updateDensity();
        density.addEventListener("click", () => {
            const compact = document.body.classList.toggle("is-compact");
            try { localStorage.setItem("pitpulse-density", compact ? "compact" : "comfortable"); } catch {}
            updateDensity();
        });
        el("focus-toggle").addEventListener("click", () => {
            const focused = document.body.classList.toggle("is-focused");
            el("focus-toggle").setAttribute("aria-pressed", String(focused));
            el("focus-toggle").textContent = focused ? "退出专注" : "专注计时";
            if (focused) location.hash = "#/live";
        });
        const fullscreen = el("fullscreen-toggle");
        fullscreen.hidden = !document.fullscreenEnabled;
        fullscreen.addEventListener("click", async () => {
            try {
                if (document.fullscreenElement) await document.exitFullscreen();
                else await document.documentElement.requestFullscreen();
            } catch { fullscreen.textContent = "全屏不可用"; }
        });
        document.addEventListener("fullscreenchange", () => {
            fullscreen.setAttribute("aria-pressed", String(!!document.fullscreenElement));
            fullscreen.textContent = document.fullscreenElement ? "退出全屏" : "全屏";
        });
        document.addEventListener("click", (event) => {
            const button = event.target.closest("[data-standings]");
            if (button) setStandingsKind(button.dataset.standings);
        });

        el("results-sessions").addEventListener("click", (event) => {
            const button = event.target.closest("[data-session]");
            if (!button) return;
            state.results.sessionType = button.dataset.session;
            const hash = `#/results/${encodeURIComponent(state.results.meetingId)}/${state.results.sessionType}`;
            if (location.hash !== hash) history.replaceState(null, "", hash);
            renderResultsPage();
        });

        el("results-round").addEventListener("change", (event) => {
            state.results.meetingId = event.target.value;
            state.results.sessionType = "race";
            const meeting = state.calendar.find((item) => item.id === state.results.meetingId);
            const sessions = resultSessions(meeting);
            if (sessions.length && !sessions.some((session) => session.sessionType === "race")) {
                state.results.sessionType = sessions[0].sessionType;
            }
            const hash = `#/results/${encodeURIComponent(state.results.meetingId)}/${state.results.sessionType}`;
            if (location.hash !== hash) history.replaceState(null, "", hash);
            renderResultsPage();
        });

        document.addEventListener("click", (event) => {
            const button = event.target.closest("[data-calendar-mode]");
            if (!button) return;
            state.calendarMode = button.dataset.calendarMode;
            state.calendarDay = null;
            renderCalendarPage();
        });

        el("calendar-prev").addEventListener("click", () => shiftCalendarMonth(-1));
        el("calendar-next").addEventListener("click", () => shiftCalendarMonth(1));

        window.addEventListener("hashchange", applyRoute);
    }

    function wireLifecycle() {
        document.addEventListener("visibilitychange", () => {
            if (document.hidden) {
                if (state.streamController) {
                    state.streamController.abort();
                    state.streamController = null;
                }
            } else if (!state.streamController) {
                startStream();
            }
        });
    }

    async function boot() {
        state.unauthorized = false;
        await Promise.allSettled([loadCalendar(), loadStandings()]);
        if (state.unauthorized) return;
        await loadLiveSnapshot();
        if (state.unauthorized) return;
        startStream();
        startCountdown();
        if (livePhase() === "idle") loadLastResult();
    }

    function init() {
        wireTheme();
        applyRoute();
        wireChrome();
        wireLifecycle();
        renderRailStandings();
        renderHero();
        renderLiveCard();
        renderLivePage();
        renderConditions();
        setStandingsKind("drivers");
        boot();
    }

    init();
})();
