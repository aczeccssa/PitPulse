// PitPulse web dashboard. Plain script: the server embeds this file into the
// binary, so there is no build step to deploy.
(() => {
    "use strict";

    const ROUTES = ["home", "standings", "results", "schedule", "drivers", "head-to-head", "consistency", "tech-updates", "pu-elements", "destructors-championship"];
    let offeredSeasons = [];
    function seasonYears() {
        return offeredSeasons.map(entry => entry.year);
    }
    const defaultSeason = () => offeredSeasons[0]?.year || new Date().getFullYear();
    const VIEW_TITLES = {
        home: "Home",
        standings: "Standings",
        results: "Results",
        schedule: "Next Season Schedule",
        drivers: "Drivers",
        "driver-stats": "Driver Stats",
        "head-to-head": "Head To Head",
        consistency: "Consistency",
        "tech-updates": "Tech Updates",
        "pu-elements": "PU Elements Used",
        "destructors-championship": "Destructors Championship",
    };
    const SESSION_LABELS = {
        fp1: "Practice 1",
        fp2: "Practice 2",
        fp3: "Practice 3",
        sprintQualifying: "Sprint Qualifying",
        sprint: "Sprint",
        qualifying: "Qualifying",
        race: "Race",
    };
    const SESSION_NAME_LABELS = {
        race: "Race",
        qualifying: "Qualifying",
        sprint: "Sprint",
        "sprint qualifying": "Sprint Qualifying",
        "sprint shootout": "Sprint Qualifying",
        "practice 1": "Practice 1",
        "practice 2": "Practice 2",
        "practice 3": "Practice 3",
        "first practice": "Practice 1",
        "second practice": "Practice 2",
        "third practice": "Practice 3",
    };
    // Upstream sends both "All clear" and "AllClear"; normalise before lookup.
    const TRACK_STATUS = {
        allclear: { label: "Track clear", tone: "green" },
        green: { label: "Track clear", tone: "green" },
        yellow: { label: "Yellow flag", tone: "yellow" },
        yellowflag: { label: "Yellow flag", tone: "yellow" },
        safetycar: { label: "Safety Car", tone: "yellow" },
        sc: { label: "Safety Car", tone: "yellow" },
        vsc: { label: "Virtual Safety Car", tone: "yellow" },
        virtualsafetycar: { label: "Virtual Safety Car", tone: "yellow" },
        virtualsafetycarending: { label: "Virtual Safety Car ending", tone: "yellow" },
        red: { label: "Red flag", tone: "red" },
        redflag: { label: "Red flag", tone: "red" },
        chequered: { label: "Chequered flag", tone: "green" },
    };

    function trackInfo(value) {
        if (!value) return null;
        return TRACK_STATUS[String(value).toLowerCase().replace(/[^a-z]/g, "")] || null;
    }
    const STATUS_REASONS = {
        not_connected: "Live timing is disconnected. It will reconnect when the session starts.",
        upstream_silent: "Waiting for the next live timing update.",
        data_stale: "Live timing data is stale. Waiting for the feed to recover.",
        replay_finished: "Replay ended.",
    };
    const CLASS_LABELS = {
        retired: "Retired",
        dnf: "Retired",
        "did not finish": "Did not finish",
        disqualified: "Disqualified",
        dsq: "Disqualified",
        "did not start": "Did not start",
        dns: "Did not start",
        "did not qualify": "Did not qualify",
        dnq: "Did not qualify",
        "not classified": "Not classified",
        nc: "Not classified",
        withdrawn: "Withdrawn",
    };
    const QUALITY_LABELS = {
        pending: "Pending",
        partial: "Partial",
        complete: "Complete",
        full: "Complete",
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
    const el = (id) => document.getElementById(id);
    const state = {
        view: "home",
        driversStandings: [],
        constructorStandings: [],
        standingsKind: "drivers",
        resultsCache: new Map(),
        results: { meetingId: null, sessionType: "race", token: 0, detail: false },
        unauthorized: false,
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
        toast.textContent = "Your session expired. Open the latest PitPulse access link.";
        toast.hidden = false;
    }

    /* ---------- api ---------- */

    const pendingRequests = new Map();

    function api(path) {
        if (pendingRequests.has(path)) return pendingRequests.get(path);
        const request = fetchApi(path).finally(() => pendingRequests.delete(path));
        pendingRequests.set(path, request);
        return request;
    }

    async function fetchApi(path) {
        const started = performance.now();
        const response = await fetch(path, {
            headers: { Accept: "application/json", "X-PitPulse-Dashboard": "1" },
            cache: "no-store",
            credentials: "same-origin",
        });
        if (response.status === 401) {
            markUnauthorized();
            throw new Error("unauthorized");
        }
        if (!response.ok) throw new Error(`${path} -> HTTP ${response.status}`);
        const body = await response.json();
        return { body, latency: Math.round(performance.now() - started) };
    }

    function setLoading(label) {
        const loader = el("workspace-loader");
        if (label) el("workspace-loading-label").textContent = label;
        loader.hidden = !label;
        document.querySelector(".view:not([hidden])")?.setAttribute("aria-busy", String(Boolean(label)));
    }

    function animateChart(svg) {
        let index = 0;
        for (const mark of svg.querySelectorAll("path, polyline, polygon, line, rect, circle")) {
            if (mark.closest("defs") || mark.matches(".progress-grid, .progress-row-highlight, .record-grid, [pathLength]")) continue;
            const stroke = mark.getAttribute("stroke"), fill = mark.getAttribute("fill");
            if (fill === "transparent" || stroke === "transparent" || Number(mark.getAttribute("opacity") ?? 1) <= .3) continue;

            let from, to, duration;
            const dash = mark.getAttribute("stroke-dasharray");
            if (mark.matches("circle") && dash) {
                const [segment, gap] = dash.split(/\s+/).map(Number);
                if (!(segment > 0 && gap > 0)) continue;
                from = { strokeDasharray: `0 ${gap}` };
                to = { strokeDasharray: dash };
                duration = 560;
            } else if (mark.matches("path, polyline, line") && !dash && (stroke || mark.matches(".home-track-base"))) {
                const length = mark.getTotalLength();
                if (!length) continue;
                const pattern = `${length} ${length}`;
                from = { strokeDasharray: pattern, strokeDashoffset: length };
                to = { strokeDasharray: pattern, strokeDashoffset: 0 };
                duration = 540;
            } else if (mark.matches("circle")) {
                from = { opacity: 0, scale: ".35", transformBox: "fill-box", transformOrigin: "center" };
                to = { ...from, opacity: mark.getAttribute("opacity") ?? 1, scale: "1" };
                duration = 300;
            } else if (mark.matches("rect, polygon, path") && fill !== "none") {
                const tall = mark.matches("rect") && Number(mark.getAttribute("height")) > Number(mark.getAttribute("width"));
                from = { opacity: 0, scale: tall ? "1 .03" : ".03 1", transformBox: "fill-box", transformOrigin: tall ? "center bottom" : "left center" };
                to = { ...from, opacity: mark.getAttribute("opacity") ?? 1, scale: "1" };
                duration = 450;
            } else {
                continue;
            }
            mark.animate([from, to], {
                id: "chart-enter", duration, delay: Math.min(index++ * 7, 110),
                easing: "cubic-bezier(.2,.7,.25,1)", fill: "backwards",
            });
        }
    }

    function wireContentMotion() {
        const workspace = el("workspace");
        const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
        const charts = "svg[role=img]";
        const bars = ".mileage-bar, .home-progress-segments .is-complete";
        const sections = `.racing-workspace > :not(#season-results), #season-results > *, #standings-panel > *, ${charts}, .standings-card, .home-card`;
        const numbers = "strong, b, td, .num, .heat, .mileage-bar, .standings-leader > span, svg[role=img] text";
        const format = /^([+−-]?[$£€]?)(\d[\d,]*)(\.\d+)?(\s*(?:%|pts|points?|s|laps?|wins?|km|[kKmM])?)$/;
        const seen = new WeakSet();
        const rolling = new Map();
        let frame = 0;

        function count(now) {
            for (const [cell, { final, prefix, target, digits, suffix, grouped, start }] of rolling) {
                if (!cell.isConnected) { rolling.delete(cell); continue; }
                const progress = Math.min(1, (now - start) / 420);
                if (progress >= 1 || reduced.matches) {
                    cell.textContent = final;
                    rolling.delete(cell);
                    continue;
                }
                const value = target * (1 - (1 - progress) ** 3);
                cell.textContent = prefix + (grouped ? value.toLocaleString("en-GB", {
                    minimumFractionDigits: digits, maximumFractionDigits: digits,
                }) : value.toFixed(digits)) + suffix;
            }
            frame = rolling.size ? requestAnimationFrame(count) : 0;
        }

        const visible = new IntersectionObserver(entries => {
            for (const { target: item, isIntersecting } of entries) {
                if (!isIntersecting && item.isConnected) continue;
                visible.unobserve(item);
                if (!isIntersecting || reduced.matches) continue;
                if (item.matches(charts)) animateChart(item);
                if (item.matches(bars)) {
                    item.animate([
                        { clipPath: "inset(0 100% 0 0)" }, { clipPath: "inset(0)" },
                    ], { id: "chart-enter", duration: 450, easing: "ease-out" });
                }
                if (item.matches(sections)) {
                    item.animate([
                        { opacity: 0, transform: "translateY(8px)" },
                        { opacity: 1, transform: "translateY(0)" },
                    ], { duration: 250, easing: "cubic-bezier(.2,.75,.25,1)" });
                }
                if (!item.matches(numbers) || item.childElementCount || item.closest("[data-home-countdown]")) continue;
                const final = item.textContent;
                const metric = format.exec(final);
                if (!metric) continue;
                const [, prefix, integer, decimal = "", suffix] = metric;
                const target = Number(integer.replaceAll(",", "") + decimal);
                if (!Number.isFinite(target)) continue;
                item.animate([
                    { opacity: 0.25, translate: "0 .45em" },
                    { opacity: 1, translate: "0 0" },
                ], { duration: 240, easing: "ease-out" });
                // Keep chart labels stable for tooltips and SVG downloads.
                if (!target || item instanceof SVGElement) continue;
                rolling.set(item, { final, prefix, target, suffix, digits: decimal ? decimal.length - 1 : 0, grouped: integer.includes(","), start: performance.now() });
                if (!frame) frame = requestAnimationFrame(count);
            }
        }, { root: workspace });

        reduced.addEventListener("change", () => {
            if (reduced.matches) {
                for (const animation of workspace.getAnimations({ subtree: true })) {
                    if (animation.id === "chart-enter") animation.cancel();
                }
            }
        });
        const selector = `${sections}, ${numbers}, ${bars}`;
        function watch(element) {
            if (seen.has(element)) return;
            if (!element.matches(`${sections}, ${bars}`) && (element.childElementCount || !format.test(element.textContent))) return;
            seen.add(element);
            visible.observe(element);
        }
        new MutationObserver(changes => {
            if (reduced.matches) return;
            for (const change of changes) for (const item of change.addedNodes) {
                if (!(item instanceof Element) || !item.closest(".view")) continue;
                if (item.matches(selector)) watch(item);
                for (const child of item.querySelectorAll(selector)) watch(child);
            }
        }).observe(workspace, { childList: true, subtree: true });
    }

    /* ---------- formatting ---------- */

    const pad = (value) => String(value).padStart(2, "0");

    function parseDate(value) {
        if (!value) return null;
        const date = new Date(value);
        return Number.isNaN(date.getTime()) ? null : date;
    }

    const localTime = new Intl.DateTimeFormat("en-GB", {
        weekday: "short",
        hour: "2-digit",
        minute: "2-digit",
        hour12: false,
    });
    const localDate = new Intl.DateTimeFormat("en-GB", {
        month: "numeric",
        day: "numeric",
    });
    const localDateTime = new Intl.DateTimeFormat("en-GB", {
        month: "numeric",
        day: "numeric",
        hour: "2-digit",
        minute: "2-digit",
        hour12: false,
    });

    function formatTime(value) {
        const date = parseDate(value);
        return date ? localTime.format(date) : "TBD";
    }

    // Session times read as a schedule ("Fri 08:30"), so the weekday and the
    // clock are split so a narrow screen can stack them.
    const SHORT_WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

    function sessionTimeParts(value) {
        const date = parseDate(value);
        if (!date) return { day: "TBD", clock: "" };
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

    // The server binds each driver and constructor to season-specific artwork.
    const MEDIA_BINDINGS = (typeof window !== "undefined" && window.PITPULSE_BINDINGS) || {};
    let artSeasonValue = null;

    function useSeason(value) { const year = Number(value); if (year) artSeasonValue = year; }
    function requestedSeason() {
        const value = Number(new URLSearchParams(location.search).get('season'));
        return Number.isInteger(value) && (offeredSeasons.length ? seasonYears().includes(value) : value >= 1950 && value <= 2100) ? value : null;
    }

    function artSeason() {
        return requestedSeason() || artSeasonValue || Number(driverPages.season) || Number(state.driversStandings[0]?.season) || defaultSeason();
    }
    function assetRef(season, kind, id) {
        if (!id) return null;
        const variant = id.match(/-(dark|contrast)$/)?.[0] || "";
        const base = variant ? id.slice(0, -variant.length) : id;
        return MEDIA_BINDINGS.assets?.[`${kind}-${base}-${season}${variant}`] || null;
    }

    function hasAsset(season, kind, id) {
        return Boolean(assetRef(season, kind, id));
    }

    function mediaSrc(path, fallback) {
        return MEDIA_BINDINGS.assets?.[path]?.url || fallback;
    }

    function assetSrc(season, kind, id) {
        return assetRef(season, kind, id)?.url || MEDIA_BINDINGS.placeholders?.[kind]?.url;
    }

    if (typeof navigator !== "undefined" && "serviceWorker" in navigator) {
        navigator.serviceWorker.register("/media-worker.js").catch(() => {});
    }

    const TEAM_IDS = [
        [/red[\s_]?bull/i, "red_bull"],
        [/mercedes/i, "mercedes"],
        [/mclaren/i, "mclaren"],
        [/ferrari/i, "ferrari"],
        [/williams/i, "williams"],
        [/racing[\s_]?bulls|visa cash|^rb$|rb f1/i, "rb"],
        [/aston[\s_]?martin/i, "aston_martin"],
        [/alpine/i, "alpine"],
        [/haas/i, "haas"],
        [/sauber|kick/i, "sauber"],
        [/alfa/i, "alfa"],
        [/alphatauri|scuderia alpha/i, "alphatauri"],
        [/audi/i, "audi"],
        [/cadillac/i, "cadillac"],
    ];
    const TEAM_IDS_BY_ID = new Set(TEAM_IDS.map(([, id]) => id));

    // A display name, a Jolpica id and an old CDN slug all resolve to the one
    // constructor id the artwork is filed under.
    function teamAssetId(value) {
        const raw = String(value || "").trim();
        if (!raw) return null;
        if (TEAM_IDS_BY_ID.has(raw)) return raw;
        const match = TEAM_IDS.find(([pattern]) => pattern.test(raw));
        return match ? match[1] : null;
    }

    const MANUFACTURERS = {
        red_bull: { color: "#3671c6" },
        mercedes: { color: "#27f4d2" },
        mclaren: { color: "#ff8000" },
        ferrari: { color: "#e8002d" },
        williams: { color: "#64c4ff" },
        rb: { color: "#6692ff" },
        aston_martin: { color: "#229971" },
        alpine: { color: "#0093cc" },
        haas: { color: "#b6babd" },
        sauber: { color: "#52e252" },
        alfa: { color: "#c92d4b" },
        alphatauri: { color: "#5e8faa" },
        audi: { color: "#f50537" },
        cadillac: { color: "#c9b037" },
    };

    function artImage(className, src) {
        const image = document.createElement("img");
        image.className = className;
        image.src = src;
        image.alt = "";
        image.loading = "lazy";
        image.decoding = "async";
        return image;
    }

    // Jolpica ids are canonical; the alias table only covers the surnames the
    // live feed and the standings use when they carry no id.
    const DRIVER_ALIASES = {
        verstappen: "max_verstappen",
        lindblad: "arvid_lindblad",
        camara: "rafael_camara",
        hirakawa: "ryo_hirakawa",
        magnussen: "kevin_magnussen",
        schumacher: "mick_schumacher",
        vries: "de_vries",
    };

    function driverAssetId(value) {
        const raw = String(value || "").trim();
        if (!raw) return null;
        if (/^[a-z0-9_]+$/.test(raw)) return DRIVER_ALIASES[raw] || raw;
        const words = raw
            .normalize("NFD")
            .replace(/[\u0300-\u036f]/g, "")
            .toLowerCase()
            .split(/\s+/)
            .filter(Boolean);
        const surname = (words[words.length - 1] || "").replace(/[^a-z0-9]/g, "");
        return DRIVER_ALIASES[surname] || surname || null;
    }

    function driverAvatarImage(season, ...values) {
        const year = Number(season) || artSeason();
        for (const value of values) {
            const id = driverAssetId(value);
            const source = id && assetRef(year, "avatar-helmet", id)?.url;
            if (source) return artImage("avatar", source);
        }
        const placeholder = MEDIA_BINDINGS.placeholders?.["driver-photo"]?.url;
        return placeholder ? artImage("avatar", placeholder) : null;
    }

    function teamLogoImage(season, ...values) {
        const year = Number(season) || artSeason();
        const id = values.map(teamAssetId).find(Boolean);
        const light = assetSrc(year, "team-logo", id);
        if (!light) return null;
        const image = artImage("team-logo", light);
        const dark = hasAsset(year, "team-logo", `${id}-dark`) ? assetSrc(year, "team-logo", `${id}-dark`) : null;
        const contrast = hasAsset(year, "team-logo", `${id}-contrast`) ? assetSrc(year, "team-logo", `${id}-contrast`) : null;
        if (dark || contrast) {
            image.dataset.logoSrc = light;
            image.dataset.darkSrc = dark || light;
            image.dataset.contrastSrc = contrast || dark || light;
            if (currentTheme() === "dark") image.src = image.dataset.darkSrc;
        }
        return image;
    }

    function driverPhotoArt(driver, className = "driver-portrait") {
        const id = driverAssetId(driver?.driverId || driver?.id || driver?.driverName);
        const season = Number(driver?.season) || artSeason();
        const url = driver?.media?.driverPhoto?.url || driver?.media?.driver?.driverPhoto?.url
            || assetSrc(season, "driver-photo", id);
        return url ? artImage(className, url) : null;
    }

    function syncLogoTheme(theme) {
        for (const image of document.querySelectorAll("img[data-dark-src]")) {
            const src = image.dataset.onTeamColor === "true" ? image.dataset.contrastSrc : theme === "dark" ? image.dataset.darkSrc : image.dataset.logoSrc;
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
            if (state.view === "standings") renderStandingsPage();
            if (RACING_VIEWS.includes(state.view)) renderDriverPages();
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

    /* ---------- standings page ---------- */

    function setStandingsKind(kind) {
        state.standingsKind = kind;
        if (state.view === "standings") history.replaceState(null, "", `/${kind === 'constructors' ? 'constructor' : 'driver'}-standings${location.search}`);
        for (const button of document.querySelectorAll("[data-standings]")) {
            const active = button.dataset.standings === kind;
            button.classList.toggle("is-active", active);
            button.setAttribute("aria-selected", active ? "true" : "false");
        }
        renderStandingsPage();
    }

    const standingsHistory = { season: null, entries: [], loading: false, error: false, previous: {} };
    const standingsBySeason = new Map();
    const standingsPreferences = new Map();

    function standingsPreference(season, constructors) {
        const key = `${season}:${constructors ? 'constructors' : 'drivers'}`;
        if (!standingsPreferences.has(key)) standingsPreferences.set(key, { selected: null, metrics: new Set([0, 1, 2, 3, 4]), previous: false });
        return standingsPreferences.get(key);
    }

    function renderStandingsFilter(records, constructors, preference) {
        const button = el('standings-page-meta'), options = el('standings-selection-options');
        const noun = constructors ? 'constructors' : 'drivers';
        const selected = record => preference.selected === null || preference.selected.has(record.id);
        const count = records.filter(selected).length;
        button.replaceChildren(svgIcon(constructors ? 'M4 3h12v4H4zm3 4v6h6V7m-6 6-3 8m9-8 3 8M4 17h12' : 'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8m11 10v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75'), node('span', '', constructors ? 'Constructors' : 'Drivers'), node('b', '', String(count)));
        button.setAttribute('aria-label', `Select ${noun}: ${count} of ${records.length} selected`);
        el('standings-selection-title').textContent = `Select ${noun}`;
        const key = `${constructors}:${records.map(r => r.id).join(',')}`;
        if (options.dataset.key !== key) {
            options.dataset.key = key;
            options.replaceChildren();
            for (const record of records) {
                const label = node('label', 'standings-selection-option'), input = node('input', '');
                input.type = 'checkbox'; input.value = record.id;
                const logo = manufacturerLogo(record.team);
                label.append(input); if (logo) label.append(logo); label.append(node('span', '', constructors ? record.name.replace(/ F1 Team$/, '').replace(/^Red Bull$/, 'Red Bull Racing') : record.name));
                options.append(label);
            }
        }
        options.querySelectorAll('input').forEach(input => { input.checked = selected({ id: input.value }); });
        const actions = el('standings-selection').querySelector('.standings-selection-actions');
        actions.querySelector('[data-selection="all"]').disabled = count === records.length;
        actions.querySelector('[data-selection="clear"]').disabled = count === 0;
    }

    function wireStandingsFilter() {
        const button = el('standings-page-meta'), menu = el('standings-selection');
        const close = (restoreFocus = false) => { menu.hidden = true; button.setAttribute('aria-expanded', 'false'); if (restoreFocus) button.focus(); };
        button.onclick = () => {
            menu.hidden = !menu.hidden; button.setAttribute('aria-expanded', String(!menu.hidden));
            if (!menu.hidden) menu.querySelector('input')?.focus();
        };
        const preference = () => {
            const constructors = state.standingsKind === 'constructors';
            const rows = constructors ? state.constructorStandings : state.driversStandings;
            return standingsPreference(rows[0]?.season, constructors);
        };
        menu.onchange = () => {
            preference().selected = new Set([...menu.querySelectorAll('input:checked')].map(input => input.value));
            renderStandingsPage();
        };
        menu.querySelectorAll('[data-selection]').forEach(action => {
            action.onclick = () => {
                preference().selected = action.dataset.selection === 'all' ? null : new Set();
                renderStandingsPage();
            };
        });
        document.addEventListener('pointerdown', event => { if (!event.target.closest('.standings-filter')) close(); });
        document.addEventListener('keydown', event => { if (event.key === 'Escape' && !menu.hidden) { event.preventDefault(); close(true); } });
        menu.addEventListener('focusout', event => { if (event.relatedTarget && !event.relatedTarget.closest('.standings-filter')) close(); });
        window.addEventListener('popstate', () => close());
    }

    function loadStandingsHistory(season) {
        if (standingsHistory.season === season) return;
        const request = Symbol();
        Object.assign(standingsHistory, { season, request, entries: [], loading: true, error: false, previous: {} });
        Promise.all([
            api(`/api/v1/results/season?season=${season}`).then(r => r.body.data || []),
            api(`/api/v1/standings/drivers?season=${season - 1}`).then(r => r.body.data || []).catch(() => []),
            api(`/api/v1/standings/constructors?season=${season - 1}`).then(r => r.body.data || []).catch(() => []),
        ]).then(([entries, drivers, constructors]) => {
            if (standingsHistory.request !== request) return;
            standingsHistory.entries = entries.filter(e => e.sessions.race?.rows?.length).sort((a, b) => a.meeting.round - b.meeting.round);
            standingsHistory.previous = { drivers: drivers.find(r => r.position === 1), constructors: constructors.find(r => r.position === 1) };
        }).catch(() => {
            if (standingsHistory.request === request) standingsHistory.error = true;
        }).finally(() => {
            if (standingsHistory.request !== request) return;
            standingsHistory.loading = false;
            renderStandingsPage();
        });
    }

    function standingsModel(constructors) {
        const official = constructors ? state.constructorStandings : state.driversStandings;
        const records = official.map(row => ({
            id: constructors ? row.constructorId : row.driverId, name: constructors ? row.constructorName : row.driverName,
            team: constructors ? row.constructorName : row.constructor, position: row.position, points: row.points, row,
            totals: [], ranks: [], rounds: [], finishes: [], stats: [0, 0, 0, 0, 0]
        }));
        const byId = new Map(records.map(r => [r.id, r]));
        const entries = standingsHistory.entries;
        entries.forEach((entry, index) => {
            records.forEach(r => { r.rounds.push(0); r.totals.push(r.totals.at(-1) || 0); });
            for (const type of ['race', 'sprint']) for (const row of entry.sessions[type]?.rows || []) {
                const record = byId.get(constructors ? (row.constructorId || teamAssetId(row.team)) : row.driverId);
                if (!record) continue;
                record.rounds[index] += Number(row.points) || 0; record.totals[index] += Number(row.points) || 0;
                if (type === 'race') {
                    record.finishes.push(row.position || 99);
                    if (row.position === 1) record.stats[0]++;
                    if (row.position > 0 && row.position <= 3) record.stats[1]++;
                    if (row.points > 0) record.stats[2]++;
                    if (row.classification && row.classification.toLowerCase() !== 'classified') record.stats[4]++;
                }
            }
            for (const row of entry.sessions.qualifying?.rows || []) if (row.position === 1) { const record = byId.get(constructors ? (row.constructorId || teamAssetId(row.team)) : row.driverId); if (record) record.stats[3]++; }
            const ranked = [...records].sort((a, b) => {
                const diff = b.totals[index] - a.totals[index]; if (diff) return diff;
                for (let p = 1; p <= 30; p++) { const count = r => r.finishes.filter(v => v === p).length; const delta = count(b) - count(a); if (delta) return delta; }
                return a.position - b.position;
            }); ranked.forEach((r, i) => r.ranks.push(i + 1));
        });
        return { records, entries };
    }

    function standingsDownload(section, title) {
        const b = node('button', 'standings-download'); b.type = 'button'; b.setAttribute('aria-label', `Download ${title}`); b.append(svgIcon('M12 3v12m-5-5 5 5 5-5M4 15v6h16v-6'));
        b.onclick = async () => {
            b.disabled = true; b.setAttribute('aria-busy', 'true');
            section.querySelector('.standings-export-error')?.remove();
            try {
                const svg = section.querySelector('svg.standings-chart');
                const table = section.querySelector('table');
                let content = section.innerText;
                if (table) {
                    const rows = [...table.rows].map(row => [...row.cells].flatMap(cell => {
                        if (cell.classList.contains('standing-points')) return [cell.querySelector('b').textContent, cell.querySelector('small')?.textContent || '0'];
                        if (cell.tagName === 'TH' && cell.textContent === 'POINTS') return ['POINTS', 'GAP TO LEADER'];
                        return [cell.innerText.trim()];
                    }));
                    content = rows.map(row => row.map(value => '"' + value.replaceAll('"', '""') + '"').join(',')).join('\r\n');
                }
                if (svg) {
                    const copy = svg.cloneNode(true);
                    const dimensions = svg.viewBox.baseVal;
                    copy.setAttribute('width', dimensions.width);
                    copy.setAttribute('height', dimensions.height);
                    copy.querySelectorAll('[data-series]').forEach(series => series.style.removeProperty('opacity'));
                    copy.querySelectorAll('[tabindex]').forEach(item => item.removeAttribute('tabindex'));
                    await Promise.all([...copy.querySelectorAll('image')].map(async image => {
                        const response = await fetch(image.getAttribute('href'));
                        if (!response.ok) throw new Error('Image could not be exported');
                        const blob = await response.blob();
                        const data = await new Promise(resolve => { const reader = new FileReader(); reader.onload = () => resolve(reader.result); reader.readAsDataURL(blob); });
                        image.setAttribute('href', data);
                    }));
                    content = new XMLSerializer().serializeToString(copy);
                }
                const url = URL.createObjectURL(new Blob([content], { type: svg ? 'image/svg+xml' : table ? 'text/csv;charset=utf-8' : 'text/plain' }));
                const a = node('a', ''); a.href = url; a.download = title.toLowerCase().replace(/[^a-z0-9]+/g, '-') + (svg ? '.svg' : table ? '.csv' : '.txt'); a.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
            } catch {
                const error = node('p', 'standings-export-error', 'Download failed. Please try again.'); error.setAttribute('role', 'alert'); section.append(error);
            } finally { b.disabled = false; b.removeAttribute('aria-busy'); }
        }; return b;
    }

    function standingsCard(title) {
        const section = node('section', 'standings-card'), header = node('header', 'standings-card-head');
        header.append(node('h2', '', title), standingsDownload(section, title)); section.append(header); return section;
    }

    function standingsSvg(width, height, label) {
        const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg'); svg.classList.add('standings-chart'); svg.setAttribute('viewBox', `0 0 ${width} ${height}`); svg.setAttribute('role', 'img'); svg.setAttribute('aria-label', label);
        svg.setAttribute('xmlns', 'http://www.w3.org/2000/svg'); const palette = getComputedStyle(el('view-standings')); svg.style.color = palette.getPropertyValue('--muted-strong').trim(); svg.style.background = palette.getPropertyValue('--card').trim();
        return svg;
    }
    function chartShape(svg, tag, attributes, text) {
        const e = document.createElementNS('http://www.w3.org/2000/svg', tag); for (const [k, v] of Object.entries(attributes)) e.setAttribute(k, String(v)); if (text != null) e.textContent = text; svg.append(e); return e;
    }
    function chartFlag(svg, meeting, x, y, width = 15) { chartShape(svg, 'image', { href: flatFlag(meeting).src, x: x - width / 2, y, width, height: width * 2 / 3 }); }

    function standingsLineColor(team) {
        const color = manufacturerColor(team);
        if (currentTheme() === 'dark') return color;
        const slug = teamAssetId(team);
        return ({ mercedes: '#008f80', williams: '#187db0', haas: '#727b85', cadillac: '#8d7a19' })[slug] || color;
    }

    function standingsEvolution(model, constructors, ranking = false) {
        const noun = constructors ? 'Constructor' : 'Driver', title = `${noun} ${ranking ? 'Ranking' : 'Points'} Evolution`, section = standingsCard(title);
        if (!model.entries.length) { section.append(node('p', 'empty', standingsHistory.loading ? 'Loading race history…' : 'No race history available.')); return section; }
        const W = 620, H = ranking && model.totalRecords > 15 ? 390 : 350, left = 36, right = ranking ? 44 : 20, top = 32, bottom = 35;
        const previousChampion = standingsHistory.previous[constructors ? 'constructors' : 'drivers'];
        const max = Math.max(...model.records.flatMap(r => r.totals), model.preference.previous ? (previousChampion?.points || 0) : 0, 1), tick = max > 500 ? 100 : max > 100 ? 50 : max > 20 ? 10 : 5, ceil = Math.ceil(max / tick) * tick;
        const svg = standingsSvg(W, H, title), x = i => left + i * (W - left - right) / Math.max(1, model.entries.length - 1);
        const y = value => ranking ? top + (value - 1) * (H - top - bottom) / Math.max(1, model.totalRecords - 1) : H - bottom - value / ceil * (H - top - bottom);
        if (ranking) { for (let p = 1; p <= model.totalRecords; p++) { chartShape(svg, 'line', { x1: left, y1: y(p), x2: W - right, y2: y(p), stroke: 'currentColor', opacity: .12 }); chartShape(svg, 'text', { x: left - 9, y: y(p) + 3, 'text-anchor': 'end', 'font-size': 12, fill: 'currentColor' }, p); } }
        else for (let value = 0; value <= ceil; value += tick) { chartShape(svg, 'line', { x1: left, y1: y(value), x2: W - right, y2: y(value), stroke: 'currentColor', opacity: .14 }); chartShape(svg, 'text', { x: left - 8, y: y(value) + 3, 'text-anchor': 'end', 'font-size': 12, fill: 'currentColor' }, Math.round(value)); }
        model.entries.forEach((e, i) => chartFlag(svg, e.meeting, x(i), H - 18));
        const highlight = id => { svg.querySelectorAll('[data-series]').forEach(e => e.style.opacity = !id || e.dataset.series === id ? '1' : '.17'); };
        for (const r of [...model.records].reverse()) {
            const values = ranking ? r.ranks : r.totals, color = standingsLineColor(r.team), g = chartShape(svg, 'g', { 'data-series': r.id });
            const path = values.map((value, i) => { if (!i) return `M${x(i)},${y(value)}`; const middle = (x(i - 1) + x(i)) / 2; return ranking ? `C${middle},${y(values[i - 1])} ${middle},${y(value)} ${x(i)},${y(value)}` : `L${x(i)},${y(value)}`; }).join(' ');
            g.onpointerenter = () => highlight(r.id); g.onfocusout = () => highlight(null);
            const hit = chartShape(g, 'path', { d: path, fill: 'none', stroke: 'transparent', 'stroke-width': 12, 'pointer-events': 'stroke' }); hit.dataset.popover = r.name;
            chartShape(g, 'path', { d: path, fill: 'none', stroke: color, 'stroke-width': 2, 'stroke-linejoin': 'round', 'pointer-events': 'none' });
            values.forEach((value, i) => { const c = chartShape(g, 'circle', { cx: x(i), cy: y(value), r: 3, fill: color, tabindex: 0 }); c.dataset.popover = `${r.name} · R${model.entries[i].meeting.round} ${model.entries[i].meeting.country} · ${ranking ? 'P' + value : value + ' points'}`; c.setAttribute('aria-label', c.dataset.popover); c.onpointerenter = () => highlight(r.id); c.onfocus = () => highlight(r.id); });
            if (ranking) { if (constructors) { const logo = manufacturerLogo(r.team); if (logo) chartShape(g, 'image', { href: logo.src, x: W - right + 8, y: y(values.at(-1)) - 8, width: 21, height: 16 }); } else chartShape(g, 'text', { x: W - right + 8, y: y(values.at(-1)) + 3, fill: color, 'font-size': 12, 'font-weight': 700 }, driverCode({ name: r.name })); }
        }
        svg.onpointerleave = () => highlight(null); section.append(svg);
        if (!ranking) {
            const prev = standingsHistory.previous[constructors ? 'constructors' : 'drivers']; const label = node('label', 'standings-previous', 'Previous season champion'); const input = node('input', ''); input.type = 'checkbox'; input.setAttribute('aria-label', 'Show previous season champion'); input.disabled = !prev; input.checked = Boolean(prev && model.preference.previous); label.append(input);
            if (!prev) { label.classList.add('is-unavailable'); label.append(node('small', '', 'Unavailable')); label.tabIndex = 0; label.dataset.popover = standingsHistory.loading ? 'Loading previous season standings…' : 'Previous season standings are not available from the server.'; }
            if (prev && input.checked) { const baselineY = y(prev.points), line = chartShape(svg, 'g', { 'data-previous-champion': '' }); chartShape(line, 'line', { x1: left, y1: baselineY, x2: W - right, y2: baselineY, stroke: 'currentColor', 'stroke-dasharray': '5 4' }); chartShape(line, 'text', { x: left + 5, y: baselineY - 8, fill: 'currentColor', 'font-size': 12 }, `${Number(standingsHistory.season) - 1} champion (${prev.points} pts)`); }
            input.onchange = () => { model.preference.previous = input.checked; renderStandingsPage(); el('view-standings').querySelector('.standings-previous input')?.focus(); };
            section.querySelector('header').insertBefore(label, section.querySelector('.standings-download'));
        }
        return section;
    }

    function standingsStatistics(model, constructors) {
        const section = standingsCard(`${constructors ? 'Constructor' : 'Driver'} Season Stats`), controls = node('div', 'standings-stat-controls');
        const metrics = [['Wins', currentTheme() === 'light' ? '#a66a00' : '#ffcf40'], ['Podiums', '#237beb'], ['Finishes in points', currentTheme() === 'light' ? '#6b7280' : '#c5c8ce'], ['Pole positions', '#c22bdd'], ['DNF/DNS/DSQ', '#e10a19']];
        metrics.forEach(([label, color], index) => { const b = node('button', '', label); b.style.setProperty('--metric', color); b.type = 'button'; b.setAttribute('aria-pressed', String(model.preference.metrics.has(index))); b.onclick = () => { const visible = b.getAttribute('aria-pressed') !== 'true'; if (visible) model.preference.metrics.add(index); else model.preference.metrics.delete(index); b.setAttribute('aria-pressed', String(visible)); section.querySelectorAll(`[data-metric="${index}"]`).forEach(e => e.style.display = visible ? '' : 'none'); section.querySelector('.standings-metrics-empty').hidden = model.preference.metrics.size > 0; }; controls.append(b); }); section.append(controls);
        const metricEmpty = node('p', 'standings-metrics-empty', 'Select a metric to show season statistics.'); metricEmpty.hidden = model.preference.metrics.size > 0; metricEmpty.setAttribute('role', 'status'); section.append(metricEmpty);
        if (!model.entries.length) { section.append(node('p', 'empty', 'Season statistics require race history.')); return section; }
        const W = 620, H = 390, left = 28, top = 25, bottom = 55, plot = H - top - bottom, positive = Math.max(5, ...model.records.flatMap(r => r.stats.slice(0, 4))), negative = Math.max(3, ...model.records.map(r => r.stats[4])), scale = plot / (positive + negative + 3), zero = top + (positive + 1) * scale;
        const svg = standingsSvg(W, H, 'Wins, podiums, points finishes, poles and retirements'), step = (W - left - 15) / model.records.length, bw = Math.min(7, step / 6);
        for (let v = -Math.floor(negative / 5) * 5; v <= positive; v += 5) { const y = zero - v * scale; chartShape(svg, 'line', { x1: left, y1: y, x2: W - 10, y2: y, stroke: 'currentColor', opacity: .14 }); chartShape(svg, 'text', { x: left - 6, y: y + 3, 'text-anchor': 'end', fill: 'currentColor', 'font-size': 11 }, v); }
        model.records.forEach((r, i) => {
            const x = left + (i + .5) * step; r.stats.forEach((value, j) => { const bar = chartShape(svg, 'rect', { x: x + (j - 2.5) * bw, y: j === 4 ? zero : zero - value * scale, width: Math.max(1, bw - 1), height: value * scale, rx: 1, fill: metrics[j][1], 'data-metric': j, tabindex: 0 }); bar.dataset.popover = `${r.name} · ${metrics[j][0]}: ${value}`; bar.setAttribute('aria-label', bar.dataset.popover); bar.style.display = model.preference.metrics.has(j) ? '' : 'none'; });
            if (constructors) { const logo = manufacturerLogo(r.team); if (logo) chartShape(svg, 'image', { href: logo.src, x: x - 12, y: H - 34, width: 24, height: 18 }); }
            else chartShape(svg, 'text', { x: x - 2, y: H - 30, transform: `rotate(-48 ${x - 2} ${H - 30})`, 'text-anchor': 'end', fill: 'currentColor', 'font-size': 12 }, driverCode({ name: r.name }));
        });
        section.append(svg); return section;
    }

    function standingsDistribution(model, constructors) {
        const section = standingsCard(`${constructors ? 'Constructor' : 'Driver'} Points Distribution`), W = 620, rowH = 27, H = 95 + model.entries.length * rowH, svg = standingsSvg(W, H, 'Overall points and points distribution by race');
        const left = 28, right = 42, width = W - left - right, maximum = Math.max(1, ...model.entries.map((e, i) => model.records.reduce((n, r) => n + r.rounds[i], 0)));
        chartShape(svg, 'text', { x: 0, y: 15, fill: 'currentColor', 'font-size': 11, 'font-weight': 600 }, 'OVERALL');
        const overall = model.records.reduce((n, r) => n + r.points, 0);
        const bar = (y, values, total, denominator) => { let x = left; values.forEach((value, i) => { if (value <= 0) return; const r = model.records[i], rect = chartShape(svg, 'rect', { x, y, width: value / denominator * width, height: 21, fill: manufacturerColor(r.team), stroke: currentTheme() === 'dark' ? '#080e18' : '#fff', 'stroke-width': 1, tabindex: 0 }); rect.dataset.popover = `${r.name} · ${value} points · ${(100 * value / total).toFixed(1)}%`; if (!constructors && model.records.slice(0, i).some(other => other.team === r.team)) { const patternId = `stripe-${r.id}-${y}`; const pattern = chartShape(svg, 'pattern', { id: patternId, width: 6, height: 6, patternUnits: 'userSpaceOnUse', patternTransform: 'rotate(45)' }); chartShape(pattern, 'line', { x1: 0, y1: 0, x2: 0, y2: 6, stroke: '#fff', 'stroke-width': 2, opacity: .28 }); chartShape(svg, 'rect', { x, y, width: value / denominator * width, height: 21, fill: `url(#${patternId})`, 'pointer-events': 'none' }); } x += value / denominator * width; }); chartShape(svg, 'text', { x: x + 7, y: y + 15, fill: 'currentColor', 'font-size': 11, 'font-weight': 650 }, total.toLocaleString()); };
        bar(28, model.records.map(r => r.points), overall, Math.max(1, overall)); chartShape(svg, 'text', { x: 0, y: 78, fill: 'currentColor', 'font-size': 11, 'font-weight': 600 }, 'BY RACE');
        model.entries.forEach((entry, i) => { const y = 90 + i * rowH; chartFlag(svg, entry.meeting, 10, y + 5, 16); const values = model.records.map(r => r.rounds[i]); bar(y, values, values.reduce((a, b) => a + b, 0), maximum); }); section.append(svg); return section;
    }

    function renderStandingsPage() {
        if (state.view !== 'standings') return;
        const panel = el('standings-panel'), empty = el('standings-page-empty');
        const constructors = state.standingsKind === 'constructors', noun = constructors ? 'Constructor' : 'Driver';
        const season = requestedSeason() || defaultSeason();
        const data = loadStandings(season);
        const rows = constructors ? data.constructors : data.drivers;
        state.driversStandings = data.drivers;
        state.constructorStandings = data.constructors;
        useSeason(season);
        el('standings-page-season').replaceChildren(seasonSelector(season, value => { navigate(`/${constructors ? 'constructor' : 'driver'}-standings?season=${value}`); }));
        el('view-standings').querySelector('.page-head h1').textContent = `${noun} Standings`;
        el('workspace-title').textContent = `${noun} Standings`;
        if (rows.length) loadStandingsHistory(season);
        const loading = data.loading || (rows.length > 0 && standingsHistory.loading);
        setLoading(loading ? 'Loading standings…' : null);
        panel.hidden = loading || !rows.length;
        empty.hidden = loading || !!rows.length;
        el('standings-page-meta').hidden = panel.hidden;
        if (panel.hidden) {
            empty.textContent = data.errors.includes(constructors ? 'constructors' : 'drivers') ? 'Could not load standings. Refresh to retry.' : 'No standings available.';
            return;
        }
        el('standings-page-meta').textContent = `${constructors ? 'Constructors' : 'Drivers'} ${rows.length}`;
        const fullModel = standingsModel(constructors), leader = fullModel.records[0], preference = standingsPreference(season, constructors);
        renderStandingsFilter(fullModel.records, constructors, preference);
        const model = { ...fullModel, totalRecords: fullModel.records.length, preference, records: fullModel.records.filter(r => preference.selected === null || preference.selected.has(r.id)) }; panel.replaceChildren();
        const side = node('aside', 'standings-sidebar'), hero = node('section', `standings-leader${constructors ? ' standings-leader-constructor' : ''}`); hero.style.setProperty('--leader', manufacturerColor(leader.team));
        hero.append(node('h2', '', constructors ? "Constructors’ Championship Leader" : "Drivers’ Championship Leader"), node('strong', '', constructors ? leader.name : leader.name.split(' ').at(-1)), node('span', '', `${leader.points} points`));
        const slug = constructors ? teamAssetId(leader.team) : driverAssetId(leader.id);
        const artKind = constructors ? 'car-side' : 'driver-photo';
        const leaderArtwork = constructors ? leader.row?.media?.carSide?.url : leader.row?.media?.driverPhoto?.url;
        const leaderSrc = leaderArtwork || assetSrc(artSeason(), artKind, slug);
        if (leaderSrc) { const art = artImage(constructors ? 'standings-leader-car' : 'standings-leader-photo', leaderSrc); art.loading = 'eager'; hero.append(art); }
        if (constructors) { const logo = manufacturerLogo(leader.team); if (logo) { logo.className = 'standings-leader-logo'; hero.append(logo); } }
        side.append(hero);
        const tableSection = standingsCard(`${season} F1 ${noun} Standings`), table = node('table', 'standings-ranking'), head = table.createTHead().insertRow();['POS.', constructors ? 'CONSTRUCTOR' : 'DRIVER', 'POINTS', 'EVO.'].forEach(t => head.append(node('th', '', t))); const body = table.createTBody();
        model.records.forEach(r => {
            const tr = body.insertRow(); tr.append(node('td', '', String(r.position))); const who = node('td', ''), identity = seasonIdentity(constructors ? { team: r.team, driverName: r.name } : { ...r.row, team: r.team }); if (constructors) { delete identity.dataset.identityDriverId; identity.lastChild.textContent = r.name.replace(/ F1 Team$/, '').replace(/^Red Bull$/, 'Red Bull Racing'); } else identity.lastChild.textContent = r.name.split(' ').at(-1); identity.tabIndex = 0; who.append(identity); tr.append(who); const points = node('td', 'standing-points'); points.append(node('b', '', String(r.points))); if (r.position !== 1) points.append(node('small', '', String(r.points - leader.points))); tr.append(points);
            const previous = r.ranks.length > 1 ? r.ranks.at(-2) : null, delta = previous == null ? null : previous - r.position, evo = node('td', delta > 0 ? 'evo-up' : delta < 0 ? 'evo-down' : 'evo-flat', delta ? `${delta > 0 ? '⌃' : '⌄'} ${Math.abs(delta)}` : '—'); if (previous == null) evo.dataset.popover = 'Previous round ranking unavailable'; tr.append(evo);
        }); tableSection.append(table); side.append(tableSection); panel.append(side);
        const charts = node('div', 'standings-charts');
        if (model.records.length) charts.append(standingsEvolution(model, constructors), standingsEvolution(model, constructors, true), standingsStatistics(model, constructors), standingsDistribution(model, constructors));
        else { const message = `No ${constructors ? 'constructors' : 'drivers'} selected. Use the selection menu to show standings and charts.`; const row = body.insertRow(), cell = row.insertCell(); cell.colSpan = 4; cell.className = 'standings-selection-empty'; cell.textContent = message; const empty = node('p', 'standings-card standings-selection-empty', message); empty.setAttribute('role', 'status'); charts.append(empty); }
        tableSection.querySelector('.standings-download').disabled = !model.records.length;
        panel.append(charts);
        if (standingsHistory.error) panel.prepend(node('p', 'standings-data-status', 'Race history could not be loaded. Standings remain available.'));
    }

    function buildDriverTable(rows) {
        const leader = Math.max(...rows.map((row) => row.points), 1);
        const table = node("div", "dt");
        table.dataset.kind = "drivers";
        const head = node("div", "dt-head");
        for (const [label, className] of [
            ["Position", ""],
            ["", "col-code"],
            ["Driver", "col-team"],
            ["Points share", "col-bar"],
            ["Wins", "col-wins num"],
            ["Points", "num"],
        ]) {
            head.append(node("span", className, label));
        }
        table.append(head);
        for (const row of rows) {
            const item = node("div", "dt-row");
            item.style.setProperty("--team", teamColor(row.constructor));
            item.title = [row.driverName, row.constructor, `${row.wins ?? 0} wins`].filter(Boolean).join(" · ");
            const who = node("div", "who");
            const avatar = driverAvatarImage(row.season || artSeason(), row.driverId, row.driverName);
            if (avatar) who.append(avatar);
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
            ["Position", ""],
            ["Constructor", ""],
            ["Points share", "col-bar"],
            ["Wins", "col-wins num"],
            ["Points", "num"],
        ]) {
            head.append(node("span", className, label));
        }
        table.append(head);
        for (const row of rows) {
            const item = node("div", "dt-row");
            item.style.setProperty("--team", teamColor(row.constructorName));
            const who = node("div", "who");
            const logo = teamLogoImage(artSeason(), row.constructorName, row.constructorId);
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

    function resultsSeason() {
        const meetingYear = state.results.detail && /^(\d{4}):/.exec(state.results.meetingId)?.[1];
        return Number(meetingYear) || requestedSeason() || driverPages.season || defaultSeason();
    }


    function renderResultsPage() {
        loadSeasonResults(resultsSeason());
        setLoading(seasonResults.loading ? 'Loading results…' : null);
        if (seasonResults.loading) {
            el('season-results').replaceChildren();
            return;
        }
        if (state.results.detail) renderMeetingResult(); else renderSeasonResults();
    }
    seasonPopover();

    const seasonResults = { key: "", entries: [], loading: false, mode: "race", display: "points", failed: 0 };
    function resultsGpName(name) { return String(name || "").replace(/ Grand Prix$/i, " Grand Prix"); }

    function seasonIdentity(row, colored = false) {
        const box = node("span", colored ? "season-driver colored" : "season-driver");
        if (!row) { box.textContent = "—"; return box; }
        if (colored) { box.style.setProperty("--winner-color", manufacturerColor(row.team)); box.style.color = ["Ferrari", "Red Bull", "Red Bull Racing", "Alpine", "Alpine F1 Team"].includes(row.team) ? "#fff" : "#070d1c"; }
        box.dataset.popover = row.driverName || row.team;
        box.dataset.popoverType = "identity";
        box.dataset.identityName = row.driverName || row.team;
        box.dataset.identityDriverId = row.driverId || "";
        box.dataset.identityTeam = row.team || "";
        box.dataset.identityConstructor = row.constructorId || "";
        box.tabIndex = 0;
        const logo = manufacturerLogo(row.team || row.constructorId, colored);
        if (logo) box.append(logo);
        box.append(node("span", "", row.driverName || row.driverId));
        return box;
    }

    function seasonSection(title) {
        const section = node("section", "season-section");
        section.append(node("h2", "", title));
        return section;
    }

    function renderMeetingResult() {
        const root = el("season-results");
        const entry = seasonResults.entries.find(item => item.meeting.id === state.results.meetingId);
        if (!entry) {
            const message = seasonResults.failed ? "Could not load Grand Prix results. Refresh to retry." : "No results are available for this Grand Prix.";
            root.replaceChildren(node("p", "empty", message));
            const back = node("a", "result-back", "‹ Season Results");
            back.href = `/results?season=${resultsSeason()}`;
            root.append(back);
            return;
        }
        root.replaceChildren();
        const meeting = entry.meeting;
        const filters = node("div", "meeting-filters");
        filters.append(seasonSelector(meeting.season, value => { navigate(`/results?season=${value}`); }));
        const rounds = seasonResults.entries.filter(e => Object.values(e.sessions).some(s => s.rows?.length)).map(e => [e.meeting.id, e.meeting.country || e.meeting.name]);
        filters.append(driverSelector('Grand Prix', meeting.id, rounds, value => { navigate(`/results/${encodeURIComponent(value)}/race`); }));
        root.append(filters);
        const title = node("header", "meeting-result-heading");
        const back = node("a", "result-back", `‹ ${meeting.season} F1 Season Results`); back.href = `/results?season=${meeting.season}`;
        const countryCode = meeting.countryCode ? meeting.countryCode.toLowerCase() : "";
        const resultTitle = node("h1", "", `${meeting.name || meeting.country + " Grand Prix"} ${meeting.season} Results`); resultTitle.prepend(flatFlag(meeting)); title.append(back, resultTitle); root.append(title);
        const tabs = node("div", "meeting-tabs");
        const order = [["fp1", "Practice 1"], ["fp2", "Practice 2"], ["fp3", "Practice 3"], ["qualifying", "Qualifying"], ["sprintQualifying", "Sprint Qualifying"], ["sprint", "Sprint"], ["startingGrid", "Starting Grid"], ["race", "Race"], ["progress", "↗  Progress"]].filter(([value]) => value === "progress" || entry.sessions[value] || (value === "startingGrid" && entry.sessions.race?.rows.some(r => r.gridPosition)));
        order.sort((a, b) => { const time = v => v === "progress" ? Infinity : v === "startingGrid" ? new Date(meeting.sessions.find(s => s.sessionType === "race")?.startTime || 0).getTime() - 1 : new Date(meeting.sessions.find(s => s.sessionType === v)?.startTime || 0).getTime(); return time(a[0]) - time(b[0]); });
        for (const [value, label] of order) { const b = node("button", value === state.results.sessionType ? "is-active" : "", label); b.type = "button"; b.onclick = () => { navigate(`/results/${encodeURIComponent(meeting.id)}/${value}`); }; tabs.append(b); }
        if (state.results.sessionType === "progress") { const panel = buildProgressChart(entry); const bar = node("div", "results-titlebar"); bar.append(node("h2", "", "Progress"), tabs); panel.prepend(bar); root.append(panel); return; }
        const data = entry.sessions[state.results.sessionType];
        const rows = state.results.sessionType === "startingGrid" ? [...(entry.sessions.race?.rows || [])].filter(r => r.gridPosition).sort((a, b) => a.gridPosition - b.gridPosition) : data?.rows || [];
        const stats = node("div", "meeting-stat-grid");
        const raceRows = entry.sessions.race?.rows || [];
        const winner = raceRows.find(r => r.position === 1), pole = (entry.sessions.qualifying?.rows || []).find(r => r.position === 1), fastest = rows.filter(r => r.bestLap).sort((a, b) => lapSeconds(a.bestLap) - lapSeconds(b.bestLap))[0];
        const sessionName = { fp1: "Practice 1", fp2: "Practice 2", fp3: "Practice 3", qualifying: "Qualifying", sprintQualifying: "Sprint Qualifying", sprint: "Sprint", startingGrid: "Starting Grid", race: "Race" }[state.results.sessionType] || "Race";
        const leader = rows.find(r => Number(r.position) === 1);
        const fastestRow = raceRows.filter(r => r.bestLap).sort((a, b) => lapSeconds(a.bestLap) - lapSeconds(b.bestLap))[0];
        for (const [index, [label, row, value]] of [["Race Winner", winner, winner?.raceTime || winner?.time || "—"], ["Pole Position", pole, pole?.q3 || pole?.time || "—"], ["Fastest Lap", fastestRow, fastestRow?.bestLap || "—"]].entries()) {
            const card = node("article", "meeting-stat"), identity = seasonIdentity(row); card.dataset.popover = `${label} · ${row?.driverName || "No result"} · ${value}`;
            if (row) identity.lastChild.textContent = row.driverName.split(" ").at(-1);
            const paths = ["M8 3h8v6a4 4 0 0 1-8 0V3ZM8 5H4v3a4 4 0 0 0 4 4m8-7h4v3a4 4 0 0 1-4 4m-4 1v6m-4 2h8", "m13 2-9 12h7l-1 8 10-13h-7l0-7", "M9 2h6m-3 0v3m7 0 2 2M12 8v5l3 2M21 14a9 9 0 1 1-18 0 9 9 0 0 1 18 0"];
            const icon = node("span", "meeting-stat-icon"); icon.append(svgIcon(paths[index])); card.append(node("h3", "", label), icon, identity, node("strong", "", value)); stats.append(card);
        } root.append(stats);
        const panel = node("section", "meeting-results-panel"), bar = node("div", "results-titlebar"); bar.append(node("h2", "", sessionName), tabs); panel.append(bar);
        const scroll = node("div", "season-scroll"), table = node("table", "meeting-table");
        const type = state.results.sessionType, qualifying = ["qualifying", "sprintQualifying"].includes(type), grid = type === "startingGrid", racing = ["race", "sprint"].includes(type);
        const labels = ["POS.", "NO.", "DRIVER", "TEAM", ...(qualifying ? ["Q1", "Q2", "Q3"] : grid ? ["TIME"] : racing ? ["TIME", "GAP TO LEADER", "INTERVAL", "POINTS", "LAPS"] : ["TIME", "GAP", "LAPS"])];
        const head = table.createTHead().insertRow(); labels.forEach(label => head.append(node("th", "", label)));
        const body = table.createTBody(), timeSeconds = value => String(value || "").split(":").map(Number).reduce((a, b) => a * 60 + b, 0);
        const sorted = grid ? rows : [...rows].sort((a, b) => (a.position ?? 100) - (b.position ?? 100) || (b.laps || 0) - (a.laps || 0));
        for (const [index, row] of sorted.entries()) {
            const tr = body.insertRow(); tr.dataset.popover = `${row.driverName} · ${row.team} · ${sessionName}`; tr.style.setProperty("--manufacturer", manufacturerColor(row.team));
            const pos = grid ? row.gridPosition : row.position ?? "NC", previous = sorted[index - 1];
            let gap = "", interval = "", result = row.raceTime || row.time || row.bestLap || "—";
            const classified = String(row.classification).toLowerCase() === "classified";
            if (racing && !classified) result = row.laps === 0 ? "DNS" : String(row.classification || "DNF").toUpperCase();
            if (index && racing && (row.laps || 0) < (leader?.laps || 0)) gap = `+${leader.laps - (row.laps || 0)} lap${leader.laps - (row.laps || 0) > 1 ? "s" : ""}`;
            else if (index && (racing || !qualifying) && classified) { const delta = timeSeconds(result) - timeSeconds(racing ? (leader?.raceTime || leader?.time) : (leader?.bestLap || leader?.time)); if (Number.isFinite(delta) && delta >= 0) gap = `+${delta.toFixed(3)}${racing ? "s" : ""}`; }
            if (index && previous && classified && row.laps === previous.laps) { const delta = timeSeconds(result) - timeSeconds(previous.raceTime || previous.time || previous.bestLap); if (delta >= 0 && Number.isFinite(delta)) interval = `+${delta.toFixed(3)}s`; }
            const values = [pos, row.driverNumber || "—", row.driverName || row.driverId, row.team, ...(qualifying ? [row.q1 || "—", row.q2 || "—", row.q3 || "—"] : grid ? [(entry.sessions.qualifying?.rows || []).find(r => r.driverId === row.driverId)?.q3 || (entry.sessions.qualifying?.rows || []).find(r => r.driverId === row.driverId)?.q2 || (entry.sessions.qualifying?.rows || []).find(r => r.driverId === row.driverId)?.q1 || "—"] : racing ? [result, gap, interval, row.points ?? 0, row.laps ?? "—"] : [result, gap, row.laps ?? "—"])];
            values.forEach((value, i) => { const td = node("td", i === 1 ? "driver-number" : i === 2 ? "driver-cell" : "", String(value)); if (i === 2) { td.textContent = String(row.driverName || row.driverId).split(" ").at(-1); Object.assign(td.dataset, { popover: row.driverName, popoverType: "identity", identityDriverId: row.driverId, identityName: row.driverName, identityTeam: row.team }); } if (i === 3) { td.textContent = ""; const logo = teamLogoImage(artSeason(), row.team, row.constructorId); if (logo) td.append(logo); td.append(node("span", "", row.team.replace(" F1 Team", "").replace(/^Red Bull$/, "Red Bull Racing"))); } if (i === 4 && ["DNF", "DNS", "DSQ"].includes(value)) { td.replaceChildren(node("span", `result-status ${value.toLowerCase()}`, value)); } tr.append(td); });
        }
        if (!rows.length) { const td = body.insertRow().insertCell(); td.colSpan = labels.length; td.textContent = "No results available for this session."; }
        scroll.append(table); panel.append(scroll); root.append(panel);
    }

    function manufacturerColor(team) { return MANUFACTURERS[teamAssetId(team)]?.color || teamColor(team); }

    function manufacturerLogo(team, contrast = false) {
        const image = teamLogoImage(artSeason(), team);
        if (image && contrast) {
            image.dataset.onTeamColor = "true";
            if (image.dataset.contrastSrc) image.src = image.dataset.contrastSrc;
        }
        return image;
    }

    function progressLapLabel(seconds) { return `${Math.floor(seconds / 60)}:${(seconds % 60).toFixed(3).padStart(6, "0")}`; }

    function buildProgressChart(entry) {
        const section = node("section", "progress-panel");
        const controls = node("div", "progress-controls");
        for (const [label, color] of [["Practice 1", "#3b82f6"], ["Practice 2", "#10b981"], ["Practice 3", "#f59e0b"], ["Qualifying", "#ef4444"]]) { const b = node("button", "progress-chip", label); b.style.setProperty("--chip", color); controls.append(b); }
        const toggle = node("label", "progress-outliers", "Exclude outliers"); const input = document.createElement("input"); input.type = "checkbox"; input.checked = true; toggle.append(input); controls.append(toggle); section.append(controls);
        const sessions = ["fp1", "fp2", "fp3", "qualifying"], colors = ["#3b82f6", "#10b981", "#f59e0b", "#ef4444"];
        const map = new Map(); for (const type of sessions) for (const row of entry.sessions[type]?.rows || []) if (row.bestLap && Number.isFinite(lapSeconds(row.bestLap))) map.set(row.driverId, row);
        const qualifyingRows = entry.sessions.qualifying?.rows || []; const drivers = [...map.values()].sort((a, b) => (qualifyingRows.find(r => r.driverId === a.driverId)?.position ?? 99) - (qualifyingRows.find(r => r.driverId === b.driverId)?.position ?? 99)); const values = sessions.flatMap(type => (entry.sessions[type]?.rows || []).map(r => lapSeconds(r.bestLap)).filter(Number.isFinite)); const min = Math.floor(Math.min(...values) - .5), max = Math.ceil(Math.max(...values) + .5); const W = 1200, H = Math.max(560, drivers.length * 24 + 80), left = 48, right = 30, top = 8, bottom = 54, inner = W - left - right, step = (max - min) / 10; const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg"); svg.setAttribute("viewBox", `0 0 ${W} ${H}`); svg.setAttribute("role", "img"); svg.setAttribute("aria-label", "Driver fastest lap times by practice and qualifying session"); const ns = svg.namespaceURI;
        const line = (x1, y1, x2, y2, cls = "") => { const l = document.createElementNS(ns, "line"); Object.entries({ x1, y1, x2, y2 }).forEach(([k, v]) => l.setAttribute(k, v)); l.setAttribute("class", cls); svg.append(l); };
        for (let i = 0; i <= 10; i++) { const x = left + i * inner / 10; line(x, top, x, H - bottom, "progress-grid progress-vertical"); const t = document.createElementNS(ns, "text"); t.setAttribute("x", x); t.setAttribute("y", H - 20); t.setAttribute("text-anchor", "middle"); t.textContent = progressLapLabel(min + i * step); svg.append(t); }
        drivers.forEach((row, i) => {
            const y = top + 8 + i * 24; line(left, y, W - right, y, "progress-grid"); const text = document.createElementNS(ns, "text"); text.setAttribute("x", 10); text.setAttribute("y", y + 5); text.textContent = (row.driverName || row.driverId).normalize("NFD").replace(/[\u0300-\u036f]/g, "").split(" ").at(-1).slice(0, 3).toUpperCase(); svg.append(text); sessions.forEach((type, j) => {
                const r = (entry.sessions[type]?.rows || []).find(x => x.driverId === row.driverId); if (!r?.bestLap) return; const c = document.createElementNS(ns, "circle"); c.setAttribute("cx", left + (lapSeconds(r.bestLap) - min) / (max - min) * inner); c.setAttribute("cy", y); c.setAttribute("r", 5.7); c.setAttribute("fill", colors[j]); c.dataset.progressName = row.driverName; c.dataset.progressDriver = row.driverId;
                c.dataset.progressRows = JSON.stringify(sessions.map(session => { const r = (entry.sessions[session]?.rows || []).find(x => x.driverId === row.driverId); return { label: { fp1: "FP1", fp2: "FP2", fp3: "FP3", qualifying: "Q" }[session], time: r?.bestLap || null }; })); c.tabIndex = 0;
                c.dataset.session = type; c.dataset.seconds = String(lapSeconds(r.bestLap)); c.dataset.popover = `${["Practice 1", "Practice 2", "Practice 3", "Qualifying"][j]} · ${r.driverName} · ${r.bestLap}`; svg.append(c);
            });
        });
        const axis = document.createElementNS(ns, "text"); axis.setAttribute("x", W / 2); axis.setAttribute("y", H - 2); axis.setAttribute("text-anchor", "middle"); axis.setAttribute("class", "axis-title"); axis.textContent = "Lap time"; svg.append(axis); section.append(svg);
        controls.querySelectorAll(".progress-chip").forEach((button, i) => { if (!entry.sessions[sessions[i]]) { button.remove(); return; } button.setAttribute("aria-pressed", "true"); button.onclick = () => { const visible = button.getAttribute("aria-pressed") !== "true"; button.setAttribute("aria-pressed", String(visible)); svg.querySelectorAll(`circle[data-session="${sessions[i]}"]`).forEach(c => c.style.display = visible ? "" : "none"); }; });
        input.onchange = () => { const circles = [...svg.querySelectorAll("circle")], nums = circles.map(c => Number(c.dataset.seconds)).sort((a, b) => a - b), q1 = nums[Math.floor(nums.length * .25)], q3 = nums[Math.floor(nums.length * .75)], cap = q3 + 1.5 * (q3 - q1), bounded = input.checked ? nums.filter(v => v <= cap) : nums, low = Math.floor(Math.min(...bounded)), high = Math.ceil(Math.max(...bounded)); circles.forEach(c => { const v = Number(c.dataset.seconds); c.setAttribute("cx", left + (v - low) / (high - low) * inner); c.style.visibility = input.checked && v > cap ? "hidden" : "visible"; }); const texts = svg.querySelectorAll("text"); for (let i = 0; i <= 10; i++) { const value = low + i, x = left + (value - low) / (high - low) * inner; texts[i].textContent = progressLapLabel(value); texts[i].setAttribute("x", x); texts[i].style.display = value <= high ? "" : "none"; const grid = svg.querySelectorAll(".progress-vertical")[i]; grid.setAttribute("x1", x); grid.setAttribute("x2", x); grid.style.display = value <= high ? "" : "none"; } }; input.onchange(); return section;
    }

    function loadSeasonResults(season) {
        useSeason(season);
        if (seasonResults.key === season) return;
        const request = Symbol();
        Object.assign(seasonResults, { key: season, request, entries: [], loading: true, failed: 0 });
        api(`/api/v1/results/season?season=${season}`).then(({ body }) => {
            if (seasonResults.request === request) seasonResults.entries = Array.isArray(body.data) ? body.data : [];
        }).catch(() => {
            if (seasonResults.request === request) seasonResults.failed = 1;
        }).finally(() => {
            if (seasonResults.request !== request) return;
            seasonResults.loading = false;
            if (state.view === "results") renderResultsPage();
        });
    }

    function renderSeasonResults() {
        const root = el("season-results");
        const season = seasonResults.key;
        root.replaceChildren();
        const heading = node("header", "season-heading racing-page-head");
        heading.append(node("h1", "", `${season} F1 Season Results`));
        root.append(heading);
        const controls = node("div", "season-controls");
        controls.append(seasonSelector(season, value => { navigate(`/results?season=${value}`); }), node("span", "", "SEASON STATS"));
        const modes = node("div", "segmented");
        for (const [value, label] of [["race", "Race"], ["sprint", "Sprint"], ["combined", "Combined"]]) {
            const button = node("button", value === seasonResults.mode ? "is-active" : "", label);
            button.type = "button";
            button.setAttribute("aria-pressed", String(value === seasonResults.mode));
            button.onclick = () => { seasonResults.mode = value; renderSeasonResults(); };
            modes.append(button);
        }
        controls.append(modes); heading.append(controls); heading.querySelector(".season-badge")?.remove();
        root.append(node("p", "season-load-status", seasonResults.failed ? "Could not load season results. Refresh to retry." : `${seasonResults.entries.filter(e => e.sessions.race?.rows.length).length} races with results · Synced data only${seasonResults.entries.some(e => Object.values(e.sessions).some(s => s.meta?.stale)) ? " · Includes stale data" : ""}`));
        const entries = seasonResults.entries.filter(entry => Object.values(entry.sessions).some(session => (session.rows || []).length > 0));
        const types = seasonResults.mode === "combined" ? ["race", "sprint"] : [seasonResults.mode];
        const drivers = new Map(), teams = new Map();
        for (const entry of entries) for (const type of types) for (const row of entry.sessions[type]?.rows || []) {
            if (!drivers.has(row.driverId)) drivers.set(row.driverId, { row, wins: 0, podiums: 0, poles: 0, points: 0, finishes: [] });
            const d = drivers.get(row.driverId); d.points += row.points || 0;
            if (row.position != null && row.classification?.toLowerCase() === "classified") d.finishes.push(row.position);
            d.wins += row.position === 1 ? 1 : 0; d.podiums += row.position > 0 && row.position <= 3 ? 1 : 0;
            const id = row.constructorId || row.team;
            if (!teams.has(id)) teams.set(id, { row, wins: 0, podiums: 0, poles: 0, laps: 0 });
            const t = teams.get(id); t.wins += row.position === 1 ? 1 : 0; t.podiums += row.position > 0 && row.position <= 3 ? 1 : 0; t.laps += row.laps || 0;
        }
        for (const entry of entries) for (const type of types) {
            const pole = entry.sessions[type === "race" ? "qualifying" : "sprintQualifying"]?.rows.find(r => r.position === 1);
            if (pole && drivers.has(pole.driverId)) drivers.get(pole.driverId).poles++;
            if (pole && teams.has(pole.constructorId || pole.team)) teams.get(pole.constructorId || pole.team).poles++;
        }
        const cards = node("div", "season-stats");
        for (const [metric, title, unit] of [["wins", "Most wins", "wins"], ["podiums", "Most podiums", "podiums"], ["poles", "Most poles", "poles"]]) {
            const card = node("article", "season-stat"); card.append(node("h3", "", title));
            const pair = node("div", "season-stat-pair");
            for (const [map, label] of [[drivers, "DRIVER"], [teams, "CONSTRUCTOR"]]) {
                const best = [...map.values()].sort((a, b) => b[metric] - a[metric])[0];
                const cell = node("div", "stat-cell"); cell.append(node("small", "", label));
                const value = node("div", "stat-value"); value.append(node("strong", "", best?.[metric] ? String(best[metric]) : "—"), node("span", "", unit));
                cell.append(value);
                if (best?.[metric]) {
                    const art = map === drivers ? driverPhotoArt(best.row, "stat-portrait") : manufacturerLogo(best.row.team, true);
                    if (art) { art.className = "stat-portrait"; art.style.background = manufacturerColor(best.row.team); art.title = ""; if (map === drivers) { Object.assign(art.dataset, { popover: best.row.driverName, popoverType: "identity", identityDriverId: best.row.driverId, identityName: best.row.driverName, identityTeam: best.row.team }); } cell.append(art); }
                }
                pair.append(cell);
            }
            card.append(pair); cards.append(card);
        }
        root.append(cards);
        const insights = node("div", "season-insights");
        const average = [...drivers.values()].filter(d => d.finishes.length).sort((a, b) => a.finishes.reduce((x, y) => x + y, 0) / a.finishes.length - b.finishes.reduce((x, y) => x + y, 0) / b.finishes.length)[0];
        function insight(title, value, unit, row, detail, icon) {
            const card = seasonSection(title); card.classList.add("reference-insight");
            const iconBox = node("span", "insight-icon");
            const paths = { "◎": ["M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18", "M12 7a5 5 0 1 0 0 10 5 5 0 0 0 0-10", "M12 10a2 2 0 1 0 0 4 2 2 0 0 0 0-4"], "↗": ["M3 17l6-6 4 4 8-10", "M15 5h6v6"], "⤢": ["M14 3h7v7", "M21 3l-7 7", "M10 21H3v-7", "M3 21l7-7"], "⤡": ["M21 3l-7 7V4", "M14 10h6", "M3 21l7-7v6", "M10 14H4"], "♧": ["M14 5c3-3 7-3 7-3s0 4-3 7l-6 6-5-5z", "M7 10H3l-2 5 6-1", "M12 15l-1 6 5-2v-4", "M6 17l-3 4", "M16 6l2 2"] };
            const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
            svg.setAttribute("viewBox", "0 0 24 24"); svg.setAttribute("fill", "none"); svg.setAttribute("stroke", "currentColor"); svg.setAttribute("stroke-width", "1.7"); svg.setAttribute("stroke-linecap", "round"); svg.setAttribute("stroke-linejoin", "round"); svg.setAttribute("aria-hidden", "true");
            for (const d of paths[icon] || []) { const path = document.createElementNS(svg.namespaceURI, "path"); path.setAttribute("d", d); svg.append(path); }
            iconBox.append(svg); card.append(iconBox);
            const number = node("div", "insight-number"); number.append(node("strong", "", value), node("span", "", unit)); card.append(number);
            const caption = node("div", "insight-caption"); if (row) caption.append(seasonIdentity({ ...row, driverName: row.driverName?.split(" ").at(-1) }));
            if (detail) caption.append(node("span", "", detail)); card.append(caption); return card;
        }
        const avg = average ? (average.finishes.reduce((a, b) => a + b, 0) / average.finishes.length).toFixed(1) : "—";
        const gains = new Map(); let comeback = null;
        for (const entry of entries) for (const type of types) for (const row of entry.sessions[type]?.rows || []) {
            if (row.gridPosition > 0 && row.position > 0) {
                const gain = row.gridPosition - row.position;
                const prior = gains.get(row.driverId) || { row, gain: 0 }; prior.gain += gain; gains.set(row.driverId, prior);
                if (!comeback || gain > comeback.gain) comeback = { row, gain, meeting: entry.meeting };
            }
        }
        const mostGained = [...gains.values()].sort((a, b) => b.gain - a.gain)[0];
        const margins = entries.flatMap(entry => types.map(type => {
            const rows = entry.sessions[type]?.rows || [];
            const winner = rows.find(r => r.position === 1), runner = rows.find(r => r.position === 2);
            const gap = String(runner?.gap || "").trim();
            const parts = gap.replace(/^\+/, "").replace(/s$/, "").split(":").map(Number);
            let seconds = /^\+?\d+(?::\d+)?(?:\.\d+)?s?$/.test(gap) ? parts.reduce((a, b) => a * 60 + b, 0) : NaN;
            if (!Number.isFinite(seconds) && winner?.laps === runner?.laps) {
                const total = value => /^\d+:\d{2}:\d{2}\.\d+$/.test(value || "") ? value.split(":").map(Number).reduce((a, b) => a * 60 + b, 0) : NaN;
                seconds = total(runner?.raceTime) - total(winner?.raceTime);
            }
            return winner && seconds > 0 ? { winner, seconds, meeting: entry.meeting } : null;
        })).filter(Boolean).sort((a, b) => a.seconds - b.seconds);
        const marginCard = (title, result, icon) => insight(title, result ? `+${result.seconds.toFixed(3)}s` : "—", "", result?.winner, result ? `· R${result.meeting.round} ${meetingFlag(result.meeting)} ${result.meeting.country || resultsGpName(result.meeting.name)}` : "", icon);
        insights.append(insight("Best Average Finish", avg, "average", average?.row, "", "◎"),
            insight("Most Positions Gained", mostGained ? String(mostGained.gain) : "—", "places", mostGained?.row, "", "↗"),
            marginCard("Largest Winning Margin", margins.at(-1), "⤢"), marginCard("Closest Winning Margin", margins[0], "⤡"),
            insight("Biggest Comeback", comeback ? `+${comeback.gain}` : "—", "places", comeback?.row, comeback ? `· P${comeback.row.gridPosition} → P${comeback.row.position} · R${comeback.meeting.round} ${meetingFlag(comeback.meeting)} ${comeback.meeting.country}` : "", "♧"));
        const mileage = seasonSection("Team Mileage"); mileage.classList.add("team-mileage");
        const distances = new Map();
        for (const entry of entries) for (const type of types) for (const row of entry.sessions[type]?.rows || []) {
            const length = entry.meeting.circuit?.lengthKm;
            if (!(length > 0) || row.laps == null) continue;
            const id = row.constructorId || row.team; const t = distances.get(id) || { row, km: 0 }; t.km += row.laps * length; distances.set(id, t);
        }
        const ranked = [...distances.values()].sort((a, b) => b.km - a.km).slice(0, 3);
        for (const t of ranked) {
            const bar = node("div", "mileage-row"); const identity = seasonIdentity({ ...t.row, driverName: t.row.team });
            const value = node("b", "mileage-bar", `${t.km.toLocaleString("en-US", { minimumFractionDigits: 1, maximumFractionDigits: 1 })} km`);
            value.style.background = teamColor(t.row.team); value.style.width = `${70 * t.km / ranked[0].km}%`; bar.append(identity, value); mileage.append(bar);
        }
        if (!ranked.length) mileage.append(node("span", "unavailable-value", "—"));
        insights.append(mileage); root.append(insights);
        const gp = seasonSection("Grand Prix Results");
        const scroll = node("div", "season-scroll"), table = node("table", "season-table gp-table");
        const head = table.createTHead().insertRow();
        for (const title of ["GRAND PRIX", "DATE", "SPRINT POLEMAN", "SPRINT WINNER", "POLEMAN", "RACE WINNER", ""]) head.append(node("th", "", title));
        const body = table.createTBody();
        for (const entry of entries) {
            const tr = body.insertRow();
            tr.className = "gp-result-row";
            tr.tabIndex = 0;
            const openMeeting = () => { state.results.meetingId = entry.meeting.id; state.results.sessionType = "race"; state.results.detail = true; history.replaceState(null, "", `/results/${encodeURIComponent(entry.meeting.id)}/race`); renderResultsPage(); };
            tr.addEventListener("click", (event) => { if (!event.target.closest("a,button")) openMeeting(); });
            tr.addEventListener("keydown", (event) => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); openMeeting(); } });
            const name = node("td", ""); name.append(grandPrixLabel(entry.meeting)); tr.append(name);
            tr.append(node("td", "season-date", formatDateRange(entry.meeting.startDate, entry.meeting.endDate)));
            for (const type of ["sprintQualifying", "sprint", "qualifying", "race"]) {
                const td = node("td", "winner-cell"); td.append(seasonIdentity(entry.sessions[type]?.rows.find(r => r.position === 1), true)); tr.append(td);
            }
            const td = node("td", ""); const link = node("a", "season-open", "›"); link.href = `/results/${encodeURIComponent(entry.meeting.id)}/race`; link.setAttribute("aria-label", `View full ${resultsGpName(entry.meeting.name)} results`);
            td.append(link); tr.append(td);
        }
        scroll.append(table); gp.append(scroll); root.append(gp);
        const matrix = seasonSection("Driver Points and Positions by Round");
        const toggle = node("div", "segmented matrix-toggle");
        for (const [value, label] of [["points", "Points"], ["position", "Position"]]) {
            const button = node("button", seasonResults.display === value ? "is-active" : "", label); button.type = "button";
            button.setAttribute("aria-pressed", String(seasonResults.display === value)); button.onclick = () => { seasonResults.display = value; renderSeasonResults(); }; toggle.append(button);
        }
        const matrixBar = node("div", "results-titlebar"); matrixBar.append(matrix.querySelector("h2"), toggle); matrix.append(matrixBar);
        const ms = node("div", "season-scroll"), mt = node("table", "season-table points-table"); const mh = mt.createTHead().insertRow();
        for (const label of ["POS.", "DRIVER", "POINTS", ...entries.map(e => `R${e.meeting.round}`)]) mh.append(node("th", "", label));
        const mb = mt.createTBody();
        [...drivers.values()].sort((a, b) => b.points - a.points).forEach((d, index) => {
            const tr = mb.insertRow(); tr.append(node("td", "", String(index + 1))); const who = node("td", ""); who.append(seasonIdentity(d.row)); tr.append(who, node("td", "total-points", String(d.points)));
            for (const entry of entries) {
                const rows = types.flatMap(type => entry.sessions[type]?.rows.filter(r => r.driverId === d.row.driverId) || []);
                const position = rows.find(r => r.position != null)?.position;
                const status = rows.some(r => r.classification && r.classification.toLowerCase() !== "classified");
                const color = status ? "status" : position === 1 ? "p1" : position === 2 ? "p2" : position === 3 ? "p3" : position <= 6 ? "p6" : position <= 10 ? "p10" : "rest";
                const td = node("td", "heat-cell");
                const cellValue = rows.length ? String(seasonResults.display === "points" ? rows.reduce((a, r) => a + (r.points || 0), 0) : position ?? rows[0].classification) : "—";
                const heat = node("span", rows.length ? `heat ${color}` : "heat missing", cellValue);
                td.append(heat);
                td.title = "";
                td.dataset.popoverType = "score";
                td.dataset.popoverRound = `R${entry.meeting.round}`;
                td.dataset.popoverMeeting = resultsGpName(entry.meeting.name);
                td.dataset.popoverDriver = d.row.driverName || d.row.driverId;
                td.dataset.popoverTeam = d.row.team || "";
                td.dataset.popoverDriverId = d.row.driverId || "";
                td.dataset.popoverPosition = position == null ? "—" : `P${position}`;
                td.dataset.popoverPoints = rows.reduce((a, r) => a + (r.points || 0), 0);
                td.dataset.popoverSprint = rows.filter(r => r.sessionType === "sprint").reduce((a, r) => a + (r.points || 0), 0);
                tr.append(td);
            }
        });
        ms.append(mt); matrix.append(ms, node("p", "heat-legend", "Colors: P1 · P2 · P3 · P4–P6 · P7–P10 · P11+ · Status · — No result")); root.append(matrix);
        root.append(renderRecordChart(entries));
        installSeasonPopovers(root);
    }

    function installSeasonPopovers(root) {
        const textFor = (element) => {
            if (element.dataset.popover) return element.dataset.popover;
            if (element.title) return element.title;
            const label = element.querySelector("h2,h3,small")?.textContent?.trim();
            const value = element.querySelector("strong,.insight-number,.stat-value")?.textContent?.trim();
            return [label, value].filter(Boolean).join(" · ") || element.textContent.trim().replace(/\s+/g, " ").slice(0, 180);
        };
        root.querySelectorAll(".season-stat, .reference-insight, .team-mileage, .season-table td, .heat, .mileage-row, .record-section svg circle, .season-driver").forEach((element) => {
            const text = textFor(element);
            if (text && text !== "—") {
                element.dataset.popover = text;
                element.tabIndex = element.tabIndex < 0 ? 0 : element.tabIndex;
            }
        });
        root.querySelectorAll("td[data-popover-type='score']").forEach((cell) => {
            cell.dataset.popover = `${cell.dataset.popoverMeeting} · ${cell.dataset.popoverDriver}`;
            cell.removeAttribute("title");
            cell.tabIndex = 0;
        });
    }

    function seasonPopover() {
        let popover = document.getElementById("season-popover");
        if (popover) return popover;
        popover = node("div", "season-popover");
        popover.id = "season-popover";
        popover.setAttribute("role", "tooltip");
        document.body.append(popover);
        const show = (event) => {
            if (event.target.closest("#season-popover")) return;
            clearTimeout(hideTimer);
            const hovered = event.target.closest("[data-popover]");
            // The cell padding belongs to the same identity as its inner chip.
            const target = hovered?.closest(".winner-cell")?.querySelector("[data-popover-type='identity']") || hovered;
            if (!target) return;
            const cell = target.closest("[data-popover-type='score']");
            popover.replaceChildren();
            popover.classList.remove("popover-identity", "popover-progress", "popover-driver-profile");
            if (target.dataset.progressRows) {
                popover.classList.add("popover-progress");
                const name = target.dataset.progressName, code = name.normalize("NFD").replace(/[\u0300-\u036f]/g, "").split(" ").at(-1).slice(0, 3).toUpperCase();
                const heading = node("div", "progress-popover-heading"); heading.append(node("b", "", name.split(" ").at(-1)), node("span", "", `(${code})`)); popover.append(heading);
                const rows = JSON.parse(target.dataset.progressRows), table = node("table", "progress-popover-table"), head = table.createTHead().insertRow();
                ["", "Lap time", "vs FP1", "vs FP2", "vs FP3"].forEach(t => head.append(node("th", "", t)));
                const body = table.createTBody(), colors = ["#3b82f6", "#10b981", "#f59e0b", "#ef4444"];
                rows.forEach((row, i) => {
                    const tr = body.insertRow(); tr.append(node("td", "", row.label)); const time = node("td", "lap-time", row.time || "—"); time.style.setProperty("--lap-color", colors[i]); tr.append(time);
                    for (let j = 0; j < 3; j++) { const delta = i > j && row.time && rows[j].time ? lapSeconds(row.time) - lapSeconds(rows[j].time) : null; const td = node("td", delta == null ? "unavailable" : delta < 0 ? "delta-faster" : "delta-slower", delta == null ? "—" : `${delta >= 0 ? "+" : ""}${delta.toFixed(3)}s`); tr.append(td); }
                });
                popover.append(table);
                const svg = target.ownerSVGElement; if (svg) { svg.querySelectorAll(".progress-row-highlight").forEach(e => e.remove()); const rect = document.createElementNS(svg.namespaceURI, "rect"); rect.setAttribute("class", "progress-row-highlight"); rect.setAttribute("x", 48); rect.setAttribute("y", Number(target.getAttribute("cy")) - 12); rect.setAttribute("width", 1122); rect.setAttribute("height", 24); svg.insertBefore(rect, svg.firstChild); }
            } else if (target.dataset.popoverType === "identity") {
                popover.classList.add("popover-identity");
                if (target.dataset.identityDriverId) {
                    popover.classList.add("popover-driver-profile");
                    popover.append(driverProfile(target.dataset.identityDriverId, target.dataset.identityName, target.dataset.identityTeam));
                } else {
                    const avatar = node("span", "identity-avatar");
                    const logo = manufacturerLogo(target.dataset.identityTeam || target.dataset.identityConstructor); if (logo) avatar.append(logo);
                    popover.append(avatar, node("span", "", target.dataset.identityName));
                }
            } else if (cell) {
                const head = node("div", "popover-score-head");
                const avatar = driverAvatarImage(artSeason(), cell.dataset.popoverDriverId, cell.dataset.popoverDriver);
                if (avatar) { avatar.className = "popover-helmet"; head.append(avatar); }
                const identity = node("div", "popover-score-identity");
                identity.append(node("b", "", cell.dataset.popoverDriver), node("span", "", cell.dataset.popoverTeam));
                head.append(identity, node("b", "popover-round", cell.dataset.popoverRound)); popover.append(head);
                const lines = node("div", "popover-score-lines");
                const raceLine = node("div", "", "Race "); raceLine.append(node("strong", "", cell.dataset.popoverPosition), node("b", "", `${cell.dataset.popoverPoints} points`)); lines.append(raceLine);
                if (Number(cell.dataset.popoverSprint)) { const sprintLine = node("div", "", "Sprint race "); sprintLine.append(node("b", "", `${cell.dataset.popoverSprint} points`)); lines.append(sprintLine); }
                const total = node("div", "popover-total"); total.append(node("span", "", "TOTAL"), node("b", "", `${cell.dataset.popoverPoints} points`)); lines.append(total); popover.append(lines);
            } else {
                const title = node("div", "popover-generic-title", target.dataset.popover);
                const image = target.querySelector("img")?.cloneNode(true);
                if (image) { image.className = "popover-generic-image"; title.prepend(image); }
                popover.append(title);
            }
            popover.classList.add("is-visible");
            const rect = target.getBoundingClientRect();
            const width = popover.getBoundingClientRect().width;
            popover.style.left = `${Math.max(10, Math.min(window.innerWidth - width - 10, rect.left + rect.width / 2 - width / 2))}px`;
            const above = rect.top - popover.offsetHeight - 10;
            popover.style.top = `${Math.max(10, Math.min(window.innerHeight - popover.offsetHeight - 10, above >= 10 ? above : rect.bottom + 10))}px`;
        };
        let hideTimer;
        const hide = () => { popover.classList.remove("is-visible"); document.querySelectorAll(".progress-row-highlight").forEach(e => e.remove()); };
        document.addEventListener("pointerover", show);
        document.addEventListener("focusin", show);
        document.addEventListener("pointerout", (event) => { if (!event.relatedTarget?.closest?.("[data-popover],#season-popover")) hideTimer = setTimeout(hide, 140); });
        popover.addEventListener("pointerenter", () => clearTimeout(hideTimer));
        popover.addEventListener("pointerleave", () => { hideTimer = setTimeout(hide, 140); });
        document.addEventListener("focusout", hide);
        document.addEventListener("scroll", hide, true);
        window.addEventListener("popstate", hide);
        return popover;
    }

    function flatFlag(meeting) {
        // The calendar carries an alpha-2 code; the engineering reports only
        // carry a country name, so fall back to the same table the server uses.
        const code = String(meeting?.countryCode || engineeringCountry(meeting?.country || "") || "").toLowerCase();
        const image = artImage("flat-flag", mediaSrc(`flag-${code}`, `/motorsport/flag-${code}.png`));
        image.alt = meeting?.country || "";
        image.onerror = () => image.remove();
        return image;
    }

    function driverProfile(id, name, team) {
        const standing = state.driversStandings.find(d => d.driverId === id);
        const panel = node("div", "driver-profile"), main = node("div", "driver-profile-main");
        main.style.setProperty("--profile-team", manufacturerColor(team));
        const heading = node("div", "driver-profile-heading"), number = node("span", "driver-profile-number", standing?.driverNumber || "");
        const identity = node("div", "driver-profile-name");
        const parts = name.split(" "), surname = parts.pop(); identity.append(document.createTextNode(parts.join(" ") + " "), node("b", "", surname), node("small", "", team)); heading.append(number, identity);
        const metrics = node("div", "driver-profile-metrics");
        for (const [label, value] of [["RANK", standing ? `P${standing.position}` : "—"], ["POINTS", standing?.points ?? "—"]]) { const m = node("div", ""); m.append(node("small", "", label), node("strong", "", String(value))); metrics.append(m); }
        const photo = driverPhotoArt({ driverId: id, driverName: name }, "driver-profile-photo");
        if (photo) { photo.onerror = () => photo.remove(); main.append(photo); }
        main.append(heading, metrics); const actions = node("div", "driver-profile-actions"), detail = node("div", "driver-profile-detail"); detail.hidden = true;
        for (const [label, kind] of [["▥  Stats", "stats"], ["⚔  Head-to-head", "compare"]]) { const button = node("button", "", kind === "stats" ? "Stats" : "Head-to-head"); button.prepend(svgIcon(kind === "stats" ? "M5 20V10m7 10V4m7 16V8" : "m4 3 7 7-3 3-7-7m19-3-7 7 3 3 7-7M3 21l7-7m11 7-7-7")); button.type = "button"; button.onclick = () => { if (kind === 'stats') navigate(driverPageHref(`drivers/${encodeURIComponent(id)}`, { season: String(standing?.season || driverPages.season || defaultSeason()) })); else { const teammate = state.driversStandings.find(d => d.driverId !== id && d.constructor === standing?.constructor); openDriverComparison(standing || { driverId: id, driverName: name, constructor: team }, teammate); } }; actions.append(button); }
        panel.append(main, actions, detail); return panel;
    }

    /* ---------- Drivers, driver statistics and head-to-head ---------- */

    // A season is loaded once and shared by the roster, detail and comparisons.
    // Keep official totals separate from the results used to calculate statistics.
    const driverPages = { seasons: new Map(), season: null, driver: null, team: '', first: '', second: '', modes: { qualifying: 'combined', race: 'combined', gaps: 'combined', pole: 'combined' }, highlight: false, excludeDnf: false };
    const RACING_VIEWS = ['home', 'drivers', 'driver-stats', 'head-to-head', 'consistency', 'tech-updates', 'pu-elements', 'destructors-championship'];
    const shortDriverName = driver => (driver.driverName || driver.name || driver.driverId || '').split(' ').at(-1);
    const teamKey = team => teamAssetId(team) || String(team || '');
    const cleanTeamName = team => String(team || '').replace(/ F1 Team$/, '').replace(/^Red Bull$/, 'Red Bull Racing');
    const sessionRows = (entry, type) => entry.sessions[type]?.rows || [];
    const driverRow = (entry, type, id) => sessionRows(entry, type).find(row => row.driverId === id);
    const retiredResult = row => Boolean(row && /dnf|dns|dsq|disqual|retired|did not|not classified|withdrawn/i.test(row.classification || ''));
    const completedResult = row => row && !retiredResult(row) && Number(row.position) > 0;
    const mean = values => values.length ? values.reduce((a, b) => a + b, 0) / values.length : null;
    const pointsText = value => Number(value || 0).toLocaleString('en-US', { maximumFractionDigits: 1 });

    function driverPageHref(view, params = {}) {
        const query = new URLSearchParams({ season: String(driverPages.season || state.driversStandings[0]?.season || defaultSeason()), ...params });
        return `/${view}?${query}`;
    }

    function openDriverComparison(driver, other) {
        const team = teamKey(driver.constructor || driver.team);
        const season = driver.season || driverPages.season || state.driversStandings[0]?.season;
        navigate(driverPageHref('head-to-head', { season: String(season), driver1: driver.driverId, ...(other ? { driver2: other.driverId } : { team }) }));
    }

    function seasonDriver(driver, entries, season) {
        const latest = [...entries].reverse().map(entry => driverRow(entry, 'race', driver.driverId) || driverRow(entry, 'qualifying', driver.driverId)).find(Boolean);
        return { ...driver, season, ...(latest ? {
            constructor: latest.team || latest.constructorId || driver.constructor,
            driverNumber: latest.driverNumber || driver.driverNumber,
        } : {}) };
    }

    function loadDriverSeason(season) {
        if (driverPages.seasons.has(season)) return driverPages.seasons.get(season);
        const data = { loading: true, drivers: [], entries: [], error: false };
        driverPages.seasons.set(season, data);
        Promise.all([
            api(`/api/v1/standings/drivers?season=${season}`).then(r => r.body.data || []),
            api(`/api/v1/results/season?season=${season}`).then(r => r.body.data || []),
        ]).then(([drivers, entries]) => {
            data.entries = [...entries].sort((a, b) => a.meeting.round - b.meeting.round);
            data.drivers = drivers.map(driver => seasonDriver(driver, data.entries, season)).sort((a, b) => a.position - b.position);
        }).catch(() => { data.error = true; }).finally(() => {
            data.loading = false;
            if (driverPages.season === season || (state.view === 'driver-stats' && driverPages.season === season + 1)) renderDriverPages();
        });
        return data;
    }

    function driverPhoto(driver, className = 'driver-portrait') {
        return driverPhotoArt(driver, className);
    }

    function driverSelector(label, value, options, onchange) {
        const wrapper = node('label', 'racing-selector');
        wrapper.append(svgIcon(label === 'Season' ? 'M4 5h16v16H4zM8 3v4m8-4v4M4 10h16' : label === 'Team' ? 'M4 3h12v4H4zm3 4v6h6V7m-6 6-3 8m9-8 3 8' : 'M20 21v-2a7 7 0 0 0-14 0v2M13 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8'), node('span', '', label));
        const select = node('select', ''); select.setAttribute('aria-label', label);
        options.forEach(([id, name]) => { const option = node('option', '', name); option.value = String(id); select.append(option); }); select.value = String(value);
        select.onchange = () => onchange(select.value); wrapper.append(select); return wrapper;
    }

    // One season switcher for every tab: the choice lives in the URL so moving
    // between tabs keeps the year, and every tab offers the same list.
    function seasonSelector(season, onchange, label = 'Season') {
        return driverSelector(label, season, seasonYears().map(year => [year, year]), onchange);
    }

    function driverPageHead(root, title, data, detail = false) {
        const head = node('header', 'page-head racing-page-head'), filters = node('div', 'racing-page-filters');
        const heading = node('div', 'racing-title');
        if (detail) { const back = node('a', 'driver-back', '← Drivers'); back.href = driverPageHref('drivers'); heading.append(back); }
        heading.append(node('h1', '', title)); head.append(heading, filters); root.append(head);
        filters.append(driverSelector('Season', driverPages.season, seasonYears().map(y => [y, y]), value => {
            const route = state.view === 'driver-stats' ? `drivers/${encodeURIComponent(driverPages.driver)}` : state.view;
            navigate(driverPageHref(route, { season: value, ...(state.view === 'head-to-head' ? { team: driverPages.team, driver1: driverPages.first, driver2: driverPages.second } : state.view === 'consistency' ? { excludeDnf: driverPages.excludeDnf ? '1' : '0' } : {}) }));
        }));
        if (detail) filters.append(driverSelector('Drivers', driverPages.driver, data.drivers.map(d => [d.driverId, shortDriverName(d)]), value => { navigate(driverPageHref(`drivers/${encodeURIComponent(value)}`)); }));
        return filters;
    }

    function driverLoadState(root, data) {
        if (data.loading) { setLoading('Loading season data…'); return true; }
        if (!data.error && data.drivers.length) return false;
        const box = node('div', 'driver-page-message'); box.setAttribute('role', 'status');
        box.append(node('p', '', data.error ? 'Season data could not be loaded.' : 'No driver standings are available for this season.'));
        if (data.error) { const retry = node('button', 'workspace-button', 'Try again'); retry.onclick = () => { driverPages.seasons.delete(driverPages.season); renderDriverPages(); }; box.append(retry); }
        root.append(box); return true;
    }

    function driverStats(data, driver) {
        const races = data.entries.map(entry => ({ entry, row: driverRow(entry, 'race', driver.driverId) })).filter(r => r.row);
        const sprints = data.entries.map(entry => driverRow(entry, 'sprint', driver.driverId)).filter(Boolean);
        const qualifying = data.entries.map(entry => driverRow(entry, 'qualifying', driver.driverId)).filter(Boolean);
        const positions = races.filter(r => Number(r.row.position) > 0).map(r => r.row.position);
        const teammate = data.drivers.filter(d => d.driverId !== driver.driverId && teamKey(d.constructor) === teamKey(driver.constructor)).sort((a, b) => b.points - a.points)[0];
        return {
            races, sprints, qualifying, positions, teammate,
            wins: races.filter(r => completedResult(r.row) && r.row.position === 1).length,
            podiums: races.filter(r => completedResult(r.row) && r.row.position <= 3).length,
            inPoints: races.filter(r => r.row.points > 0).length,
            poles: qualifying.filter(r => r.position === 1).length,
            dnfs: races.filter(r => retiredResult(r.row)).length,
            average: mean(positions), best: positions.length ? Math.min(...positions) : null,
        };
    }

    function resultComparison(a, b) {
        if (!a || !b) return null;
        if (Number(a.position) > 0 && Number(b.position) > 0) return Math.sign(b.position - a.position);
        if (completedResult(a) && retiredResult(b)) return 1;
        if (completedResult(b) && retiredResult(a)) return -1;
        // Both retirements require a genuine classified order; do not infer a winner.
        return null;
    }

    function comparisonPoints(data, first, second, types, team = null) {
        const matches = [];
        for (const entry of data.entries) for (const type of types) {
            const a = driverRow(entry, type, first), b = driverRow(entry, type, second);
            if (team && (!a || !b || (a.constructorId || teamKey(a.team)) !== team || (b.constructorId || teamKey(b.team)) !== team)) continue;
            const winner = resultComparison(a, b);
            if (winner !== null) matches.push({ entry, type, a, b, winner });
        }
        return { matches, left: matches.filter(m => m.winner > 0).length, right: matches.filter(m => m.winner < 0).length, ties: matches.filter(m => m.winner === 0).length };
    }

    function rosterScores(data, driver) {
        const stats = driverStats(data, driver);
        const percentile = (type) => data.entries.flatMap(e => { const rows = sessionRows(e, type), row = rows.find(r => r.driverId === driver.driverId); return completedResult(row) && rows.length > 1 ? [100 * (rows.length - row.position) / (rows.length - 1)] : []; });
        const race = mean(percentile('race')), quali = mean(percentile('qualifying'));
        const sps = race == null ? null : quali == null ? race : .7 * race + .3 * quali;
        const paired = stats.teammate ? comparisonPoints(data, driver.driverId, stats.teammate.driverId, ['race', 'qualifying'], teamKey(driver.constructor)) : null;
        const tms = paired?.matches.length ? 100 * (paired.left + .5 * paired.ties) / paired.matches.length : null;
        return { sps, tms };
    }

    function scoreBadge(label, value) {
        const badge = node('span', 'driver-score'); badge.append(node('small', '', label), node('b', '', value == null ? '—' : value.toFixed(1)));
        if (value != null) { const grade = value >= 90 ? 'S' : value >= 75 ? 'A' : value >= 60 ? 'B' : value >= 50 ? 'C' : value >= 35 ? 'D' : 'F'; badge.append(node('span', `score-grade grade-${grade.toLowerCase()}`, grade)); } return badge;
    }

    function renderDrivers(root, data) {
        const filters = driverPageHead(root, 'Drivers', data);
        const help = node('details', 'driver-score-help'), summary = node('summary', '', 'ⓘ How scores work?');
        help.append(summary, node('p', '', 'SPS: 70% average race finishing percentile + 30% average qualifying percentile, using classified results. TMS: share of head-to-head race and qualifying wins against the current teammate (ties count as half). Both run from 0–100. S ≥ 90, A ≥ 75, B ≥ 60, C ≥ 50, D ≥ 35, F < 35. These are PitPulse scores, not official F1 ratings. Missing results are excluded.'));
        filters.prepend(help);
        if (driverLoadState(root, data)) return;
        const grid = node('div', 'drivers-grid');
        for (const driver of data.drivers) {
            const card = node('a', 'driver-board'); card.href = driverPageHref(`drivers/${encodeURIComponent(driver.driverId)}`); card.setAttribute('aria-label', `View ${driver.driverName} statistics`); card.style.setProperty('--team', manufacturerColor(driver.constructor)); card.style.setProperty('--team-ink', standingsLineColor(driver.constructor));
            const identity = node('div', 'driver-board-identity'); identity.append(node('h2', '', shortDriverName(driver)), node('p', '', cleanTeamName(driver.constructor)), node('strong', 'driver-board-number', driver.driverNumber || '—'));
            const logo = manufacturerLogo(driver.constructor); if (logo) { logo.className = 'driver-board-logo'; card.append(logo); }
            const scores = rosterScores(data, driver), footer = node('div', 'driver-board-scores'); footer.append(scoreBadge('SPS', scores.sps), scoreBadge('TMS', scores.tms));
            card.append(identity, footer); const photo = driverPhoto(driver); if (photo) card.append(photo); grid.append(card);
        }
        root.append(grid);
    }

    function driverMetric(label, value, description) {
        const box = node('div', 'driver-metric'); box.append(node('small', '', label), node('strong', '', String(value)), node('p', '', description)); return box;
    }

    function driverChart(title, width, height, label) {
        const card = standingsCard(title), svg = standingsSvg(width, height, label || title);
        // These pages use the same palette even if the standings tab was never opened.
        const palette = getComputedStyle(document.body); svg.style.background = palette.getPropertyValue('--card').trim(); svg.style.color = palette.getPropertyValue('--muted-strong').trim();
        card.append(svg); return { card, svg };
    }

    function chartTip(shape, text) {
        shape.dataset.popover = text; shape.setAttribute('aria-label', text); shape.setAttribute('tabindex', '0');
        chartShape(shape, 'title', {}, text); return shape;
    }

    function driverLegend(color) {
        const legend = node('div', 'driver-chart-legend');
        [['Race', color], ['Sprint', color], ['DNF/DNS/DSQ', '#ef4444'], ['Upcoming', 'transparent']].forEach(([label, c]) => { const item = node('span', '', label), mark = node('i', ''); mark.style.setProperty('--legend-color', c); if (label === 'Sprint' || label === 'Upcoming') mark.classList.add('outlined'); item.prepend(mark); legend.append(item); }); return legend;
    }

    function driverMiniMetric(data, driver, label, metric, total, description) {
        const section = node('section', 'standings-card driver-mini-metric');
        section.append(node('h2', '', label), node('strong', 'driver-stat-number', String(total)), node('p', 'driver-stat-description', description));
        const W = 460, H = 75, svg = standingsSvg(W, H, label + ' by round'), step = (W - 8) / Math.max(1, data.entries.length), color = standingsLineColor(driver.constructor);
        const valueFor = (row) => !row ? 0 : metric === 'points' ? Number(row.points) || 0 : metric === 'pole' ? (row.position === 1 ? 1 : 0) : completedResult(row) && (metric === 'win' ? row.position === 1 : row.position <= 3) ? 1 : 0;
        const maximum = Math.max(1, ...data.entries.map(e => valueFor(driverRow(e, metric === 'pole' ? 'qualifying' : 'race', driver.driverId))));
        data.entries.forEach((entry, i) => {
            const race = driverRow(entry, metric === 'pole' ? 'qualifying' : 'race', driver.driverId), sprint = driverRow(entry, metric === 'pole' ? 'sprintQualifying' : 'sprint', driver.driverId), value = valueFor(race), sprintValue = valueFor(sprint), x = 4 + i * step, upcoming = !sessionRows(entry, metric === 'pole' ? 'qualifying' : 'race').length;
            const h = Math.max(4, value / maximum * 50), bar = chartShape(svg, 'rect', { x, y: H - h - 3, width: Math.max(3, step - 3), height: h, rx: 1.5, fill: upcoming ? 'none' : retiredResult(race) ? '#ef4444' : value ? color : 'currentColor', opacity: value || retiredResult(race) || upcoming ? 1 : .25, stroke: upcoming ? 'currentColor' : 'none', 'stroke-width': 1 });
            chartTip(bar, `R${entry.meeting.round} ${entry.meeting.country} · ${race ? (metric === 'points' ? pointsText(value) + ' points' : (race.position ? 'P' + race.position : race.classification)) : upcoming ? 'Upcoming' : 'Did not participate'}`);
            if (sprintValue > 0) chartTip(chartShape(svg, 'rect', { x, y: H - 3 - Math.min(64, (value + sprintValue) / maximum * 50), width: Math.max(3, step - 3), height: Math.max(4, sprintValue / maximum * 50), rx: 1, fill: 'none', stroke: color, 'stroke-width': 1.5 }), `R${entry.meeting.round} Sprint · ${metric === 'points' ? sprintValue + ' points' : sprint?.position ? 'P' + sprint.position : '—'}`);
        }); section.append(svg, driverLegend(color)); return section;
    }

    function driverPerformance(data, driver, stats) {
        const { card, svg } = driverChart('Season Performance', 420, 330);
        const max = Math.max(1, stats.races.length), metrics = [['In Points', stats.inPoints, currentTheme() === 'light' ? '#6b7280' : '#d1d5db'], ['Podiums', stats.podiums, '#237beb'], ['Wins', stats.wins, '#ffcf40'], ['Poles', stats.poles, '#c22bdd'], ['DNF/DNS/DSQ', stats.dnfs, '#e10a19']];
        metrics.forEach(([label, value, color], i) => {
            const r = 132 - i * 23, cx = 224, cy = 163, start = -90, end = 180, point = a => [cx + r * Math.cos(a * Math.PI / 180), cy + r * Math.sin(a * Math.PI / 180)], path = (to) => { const [x, y] = point(start), [ex, ey] = point(to); return `M${x},${y} A${r},${r} 0 ${to - start > 180 ? 1 : 0} 1 ${ex},${ey}`; };
            chartShape(svg, 'path', { d: path(end), fill: 'none', stroke: 'currentColor', opacity: .12, 'stroke-width': 17, 'stroke-linecap': 'round' });
            chartShape(svg, 'text', { x: 205, y: cy - r + 4, 'text-anchor': 'end', fill: 'currentColor', 'font-size': 11 }, label);
            if (value) { const to = start + 270 * Math.min(1, value / max); chartTip(chartShape(svg, 'path', { d: path(to), fill: 'none', stroke: color, 'stroke-width': 17, 'stroke-linecap': 'round' }), `${label}: ${value}`); const [x, y] = point(to); chartShape(svg, 'text', { x, y: y + 3, 'text-anchor': 'middle', fill: '#121923', 'font-size': 10, 'font-weight': 700 }, value); }
        }); return card;
    }

    function driverPointsDonut(driver, stats) {
        const { card, svg } = driverChart('Race Finishes in the Points', 420, 330), total = stats.races.length, percentage = total ? stats.inPoints / total : 0, color = standingsLineColor(driver.constructor), r = 122, circumference = 2 * Math.PI * r;
        chartShape(svg, 'circle', { cx: 210, cy: 165, r, fill: 'none', stroke: 'currentColor', 'stroke-width': 50, opacity: .18 });
        if (total) chartTip(chartShape(svg, 'circle', { cx: 210, cy: 165, r, fill: 'none', stroke: color, 'stroke-width': 50, 'stroke-dasharray': `${percentage * circumference} ${circumference}`, transform: 'rotate(-90 210 165)' }), `${stats.inPoints} of ${total} races in the points`);
        chartShape(svg, 'text', { x: 210, y: 174, fill: 'currentColor', 'text-anchor': 'middle', 'font-size': 27, 'font-weight': 700 }, total ? `${Math.round(percentage * 100)}%` : '—'); return card;
    }

    function chartSummary(card, items) {
        const summary = node('div', 'driver-chart-summary'); items.forEach(([label, value]) => { const item = node('div', ''); item.append(node('small', '', label), node('b', '', String(value))); summary.append(item); }); card.querySelector('header').append(summary);
    }

    function driverFinishDistribution(driver, stats, fieldSize) {
        const { card, svg } = driverChart('Race Finish Position Distribution', 780, 650), positions = Array.from({ length: fieldSize }, (_, i) => i + 1), counts = positions.map(p => stats.positions.filter(v => v === p).length), nc = stats.races.length - stats.positions.length, max = Math.max(1, ...counts, nc), rowH = 560 / (fieldSize + 1), color = standingsLineColor(driver.constructor);
        card.classList.add('driver-finish-distribution'); chartSummary(card, [['Best', stats.best ? 'P' + stats.best : '—'], ['Average', stats.average?.toFixed(1) ?? '—']]);
        chartShape(svg, 'text', { x: 20, y: 25, fill: 'currentColor', 'font-size': 13 }, 'Sprint Races excluded');
        [...counts, nc].forEach((value, i) => { const y = 52 + i * rowH, label = i === fieldSize ? 'NC' : 'P' + (i + 1); chartShape(svg, 'text', { x: 36, y: y + 13, fill: 'currentColor', 'font-size': 11, 'text-anchor': 'end' }, label); if (value) chartTip(chartShape(svg, 'rect', { x: 46, y, width: value / max * 700, height: Math.max(10, rowH - 3), rx: 1.5, fill: color }), `${label}: ${value} races`); if (value) chartShape(svg, 'text', { x: 54, y: y + 13, fill: currentTheme() === 'dark' ? '#fff' : '#111', 'font-size': 11 }, value); }); return card;
    }

    function driverPointsEvolution(data, driver, previous) {
        const { card, svg } = driverChart('Points Evolution vs. Previous Season', 780, 460), color = standingsLineColor(driver.constructor);
        const current = data.entries.filter(e => sessionRows(e, 'race').length), prior = previous?.entries.filter(e => sessionRows(e, 'race').length) || [];
        const totals = entries => { let total = 0; return entries.map(e => { total += ['race', 'sprint'].reduce((n, type) => n + (Number(driverRow(e, type, driver.driverId)?.points) || 0), 0); return total; }); };
        const currentTotals = totals(current), previousTotals = totals(prior), max = Math.max(50, ...currentTotals, ...previousTotals), n = Math.max(2, data.entries.length, prior.length), left = 45, right = 18, top = 30, bottom = 50, x = i => left + i * (780 - left - right) / (n - 1), y = v => 410 - v / max * 370;
        for (let i = 0; i <= 5; i++) { const value = max * i / 5; chartShape(svg, 'line', { x1: left, y1: y(value), x2: 762, y2: y(value), stroke: 'currentColor', opacity: .13 }); chartShape(svg, 'text', { x: left - 8, y: y(value) + 4, 'text-anchor': 'end', fill: 'currentColor', 'font-size': 11 }, Math.round(value)); }
        [[previousTotals, '#718096', driverPages.season - 1], [currentTotals, color, driverPages.season]].forEach(([values, stroke, season]) => { if (!values.length) return; chartShape(svg, 'path', { d: values.map((v, i) => `${i ? 'L' : 'M'}${x(i)},${y(v)}`).join(' '), fill: 'none', stroke, 'stroke-width': 2.5 }); values.forEach((value, i) => chartTip(chartShape(svg, 'circle', { cx: x(i), cy: y(value), r: 2.5, fill: stroke }), `${season} · R${i + 1} · ${value} points`)); });
        for (let i = 0; i < n; i++)chartShape(svg, 'text', { x: x(i), y: 431, 'text-anchor': 'middle', fill: 'currentColor', 'font-size': 10 }, i + 1);
        chartShape(svg, 'text', { x: 400, y: 454, 'text-anchor': 'middle', fill: 'currentColor', 'font-size': 12 }, 'Rounds');
        const legend = node('p', 'driver-chart-note', `${driverPages.season} · ${shortDriverName(driver)}${prior.length ? '   /   ' + (driverPages.season - 1) : previous?.loading ? ' · Loading previous season…' : ' · Previous season data unavailable'}`); card.append(legend); return card;
    }

    function driverGridFlow(driver, stats) {
        const valid = stats.races.filter(r => Number.isInteger(r.row.gridPosition) && r.row.gridPosition >= 0), groups = new Map();
        for (const { row } of valid) { const start = row.gridPosition === 0 ? 'PL' : 'P' + row.gridPosition, end = completedResult(row) ? 'P' + row.position : 'NC', key = start + '|' + end; if (!groups.has(key)) groups.set(key, { start, end, count: 0 }); groups.get(key).count++; }
        const { card, svg } = driverChart('Starting Grid to Race Finish', 780, Math.max(480, groups.size * 30));
        if (!valid.length) { svg.remove(); card.querySelector('.standings-download').disabled = true; card.append(node('p', 'empty', 'Starting grid data is not available for this season.')); return card; }
        const H = Number(svg.getAttribute('viewBox').split(' ')[3]), top = 20, gap = 12, sort = (a, b) => a === 'NC' ? 1 : b === 'NC' ? -1 : a === 'PL' ? 1 : b === 'PL' ? -1 : Number(a.slice(1)) - Number(b.slice(1));
        const layout = field => { const keys = [...new Set([...groups.values()].map(g => g[field]))].sort(sort), scale = (H - top * 2 - gap * (keys.length - 1)) / valid.length; let y = top; const map = new Map(); keys.forEach(key => { const count = [...groups.values()].filter(g => g[field] === key).reduce((n, g) => n + g.count, 0); map.set(key, { y, height: count * scale, next: y }); y += count * scale + gap; }); return { map, scale }; };
        const left = layout('start'), right = layout('end'), positionColor = p => p === 'P1' ? '#d69b00' : p === 'P2' ? '#94a3b8' : p === 'P3' ? '#b96512' : p === 'NC' ? '#435067' : standingsLineColor(driver.constructor);
        for (const g of [...groups.values()].sort((a, b) => sort(a.start, b.start) || sort(a.end, b.end))) { const a = left.map.get(g.start), b = right.map.get(g.end), h1 = g.count * left.scale, h2 = g.count * right.scale, y1 = a.next, y2 = b.next; const shape = chartShape(svg, 'path', { d: `M62 ${y1} C340 ${y1} 440 ${y2} 718 ${y2} L718 ${y2 + h2} C440 ${y2 + h2} 340 ${y1 + h1} 62 ${y1 + h1} Z`, fill: positionColor(g.start), opacity: .55 }); chartTip(shape, `${g.start} → ${g.end}: ${g.count} race${g.count === 1 ? '' : 's'}`); a.next += h1; b.next += h2; }
        [[left, 53, 'start'], [right, 718, 'end']].forEach(([side, x, field]) => side.map.forEach((v, p) => { chartShape(svg, 'rect', { x, y: v.y, width: 9, height: v.height, rx: 2, fill: positionColor(p) }); chartShape(svg, 'text', { x: field === 'start' ? 45 : 735, y: v.y + v.height / 2 + 4, 'text-anchor': field === 'start' ? 'end' : 'start', fill: 'currentColor', 'font-size': 12 }, p); }));
        card.append(node('p', 'driver-chart-note', `${valid.length} races with starting grid data · PL = pit lane · NC = unclassified`)); return card;
    }

    function driverLapsLed(driver, stats) {
        const { card, svg } = driverChart('Laps Led per Race', 780, Math.max(180, stats.races.length * 27 + 50));
        chartShape(svg, 'text', { x: 24, y: 24, fill: 'currentColor', 'font-size': 13 }, 'Sprint Races excluded');
        const available = stats.races.filter(r => Number.isFinite(r.row.lapsLed));
        if (!available.length) { svg.remove(); card.querySelector('.standings-download').disabled = true; card.append(node('p', 'empty', 'Lap-by-lap leadership data is not available for this season.')); return card; }
        const max = Math.max(1, ...stats.races.map(r => r.row.laps || 0)), sum = available.reduce((n, r) => n + r.row.lapsLed, 0); chartSummary(card, [['Total', sum], ['Average', (sum / available.length).toFixed(1)]]);
        stats.races.forEach(({ entry, row }, i) => { const y = 40 + i * 27; chartFlag(svg, entry.meeting, 16, y + 3, 18); chartShape(svg, 'rect', { x: 40, y, width: (row.laps || 0) / max * 700, height: 20, fill: 'currentColor', opacity: .12 }); if (Number.isFinite(row.lapsLed)) chartTip(chartShape(svg, 'rect', { x: 40, y, width: row.lapsLed / max * 700, height: 20, fill: standingsLineColor(driver.constructor) }), `R${entry.meeting.round}: ${row.lapsLed} laps led`); }); return card;
    }

    function renderDriverDetail(root, data) {
        driverPageHead(root, 'Driver Stats', data, true); if (driverLoadState(root, data)) return;
        const driver = data.drivers.find(d => d.driverId === driverPages.driver);
        if (!driver) { root.append(node('p', 'empty', 'This driver has no standings for the selected season. Choose another driver.')); return; }
        const stats = driverStats(data, driver), color = manufacturerColor(driver.constructor), summary = node('section', 'driver-summary'); summary.style.setProperty('--team', color);
        const main = node('header', 'driver-summary-head'), photo = driverPhoto(driver); if (photo) main.append(photo);
        const identity = node('div', 'driver-summary-identity'), name = node('h2', '', driver.driverName); name.append(node('small', '', driverCode({ name: driver.driverName })));
        const team = node('p', ''), logo = manufacturerLogo(driver.constructor); if (logo) team.append(logo); team.append(document.createTextNode(cleanTeamName(driver.constructor))); identity.append(name, team);
        const position = node('div', 'driver-summary-position'); position.append(node('strong', '', `P${driver.position}`), node('small', '', `${pointsText(driver.points)} pts`)); main.append(identity, position);
        const actions = node('div', 'driver-summary-actions'), compare = node('button', 'workspace-button', 'Head-to-head'); compare.onclick = () => openDriverComparison(driver, stats.teammate); actions.append(compare); identity.append(actions);
        const metrics = node('div', 'driver-summary-metrics'), leader = data.drivers[0], teamDrivers = data.drivers.filter(d => teamKey(d.constructor) === teamKey(driver.constructor)), teamPoints = teamDrivers.reduce((n, d) => n + d.points, 0), difference = stats.teammate ? driver.points - stats.teammate.points : null;
        metrics.append(driverMetric('GAP TO LEADER', driver.position === 1 ? 'Leader' : `${pointsText(driver.points - leader.points)} pts`, driver.position === 1 ? 'Leading the championship' : `behind ${shortDriverName(leader)}`), driverMetric('TEAM SHARE', teamPoints ? `${(100 * driver.points / teamPoints).toFixed(1)}%` : '—', `of ${cleanTeamName(driver.constructor)} points (${driver.points}/${teamPoints})`), driverMetric('LEAD VS TEAMMATE', difference == null ? '—' : `${difference >= 0 ? '+' : ''}${difference} pts`, stats.teammate ? `${difference >= 0 ? 'ahead of' : 'behind'} ${shortDriverName(stats.teammate)}` : 'No teammate results available'));
        const teammateRaces = stats.teammate ? driverStats(data, stats.teammate).races.length : 0;
        const ownAverage = stats.races.length ? driver.points / stats.races.length : null, teammateAverage = teammateRaces ? stats.teammate.points / teammateRaces : null;
        const avgDifference = ownAverage != null && teammateAverage != null ? ownAverage - teammateAverage : null;
        metrics.append(driverMetric('AVG POINTS VS TEAMMATE', avgDifference == null ? '—' : `${avgDifference >= 0 ? '+' : ''}${avgDifference.toFixed(1)}`, avgDifference != null ? `${ownAverage.toFixed(1)} vs ${teammateAverage.toFixed(1)} · Sprints included` : 'No teammate race results available'));
        summary.append(main, metrics); root.append(summary);
        const minis = node('div', 'driver-mini-grid'), sprintWins = stats.sprints.filter(r => r.position === 1).length, sprintPodiums = stats.sprints.filter(r => r.position && r.position <= 3).length, sprintPoles = data.entries.filter(e => driverRow(e, 'sprintQualifying', driver.driverId)?.position === 1).length;
        minis.append(driverMiniMetric(data, driver, 'Grand Prix Wins', 'win', stats.wins, `${sprintWins} Sprint Win${sprintWins === 1 ? '' : 's'}`), driverMiniMetric(data, driver, 'Grand Prix Podiums', 'podium', stats.podiums, `${sprintPodiums} Sprint Podium${sprintPodiums === 1 ? '' : 's'}`), driverMiniMetric(data, driver, 'Season Points', 'points', pointsText(driver.points), `Avg. ${stats.races.length ? (driver.points / stats.races.length).toFixed(1) : '—'} (Sprints included)`), driverMiniMetric(data, driver, 'Poles', 'pole', stats.poles, `${sprintPoles} Sprint Pole${sprintPoles === 1 ? '' : 's'}`)); root.append(minis);
        const charts = node('div', 'driver-detail-charts'), left = node('div', 'driver-detail-column'), right = node('div', 'driver-detail-column'), rings = node('div', 'driver-rings');
        rings.append(driverPerformance(data, driver, stats), driverPointsDonut(driver, stats)); left.append(rings, driverPointsEvolution(data, driver, loadDriverSeason(driverPages.season - 1)), driverGridFlow(driver, stats));
        const fieldSize = Math.max(20, ...data.entries.map(e => sessionRows(e, 'race').length)); right.append(driverFinishDistribution(driver, stats, fieldSize), driverLapsLed(driver, stats)); charts.append(left, right); root.append(charts);
    }

    function sessionModeTypes(kind, mode) {
        const regular = kind === 'race' ? 'race' : 'qualifying', sprint = kind === 'race' ? 'sprint' : 'sprintQualifying'; return mode === 'combined' ? [regular, sprint] : mode === 'sprint' ? [sprint] : [regular];
    }

    function comparisonPairs(data) {
        const pairs = new Map();
        for (const entry of data.entries) for (const type of ['race', 'sprint', 'qualifying', 'sprintQualifying']) {
            const teams = new Map(); sessionRows(entry, type).forEach(row => { const key = row.constructorId || teamKey(row.team); if (!teams.has(key)) teams.set(key, []); teams.get(key).push(row); });
            teams.forEach((rows, team) => {
                for (let i = 0; i < rows.length; i++)for (let j = i + 1; j < rows.length; j++) {
                    const a = rows[i], b = rows[j], ids = [a.driverId, b.driverId].sort(), key = team + ':' + ids.join(':'); if (pairs.has(key)) continue;
                    const driver = id => data.drivers.find(d => d.driverId === id) || { driverId: id, driverName: rows.find(r => r.driverId === id).driverName, constructor: a.team, position: 999 };
                    const first = driver(ids[0]), second = driver(ids[1]); pairs.set(key, { key, team, teamName: a.team, first: first.position <= second.position ? first : second, second: first.position <= second.position ? second : first });
                }
            });
        }
        return [...pairs.values()];
    }

    function selectedComparisonPairs(data) {
        const pairs = comparisonPairs(data), first = data.drivers.find(d => d.driverId === driverPages.first), second = data.drivers.find(d => d.driverId === driverPages.second);
        if (first && second) return [{ key: first.driverId + ':' + second.driverId, team: teamKey(first.constructor), teamName: first.constructor, first, second, crossTeam: teamKey(first.constructor) !== teamKey(second.constructor) }];
        return pairs.filter(pair => (!driverPages.team || pair.team === driverPages.team) && (!first || pair.first.driverId === first.driverId || pair.second.driverId === first.driverId) && (!second || pair.first.driverId === second.driverId || pair.second.driverId === second.driverId));
    }

    function comparisonMode(card, key, kind, rerender) {
        const tabs = node('div', 'segmented comparison-mode'); tabs.setAttribute('aria-label', `${card.querySelector('h2').textContent} session type`);
        [['combined', 'Combined'], ['regular', kind === 'race' ? 'Race' : 'Qualifying'], ['sprint', kind === 'race' ? 'Sprint race' : 'Sprint Qualifying']].forEach(([mode, label]) => { const button = node('button', driverPages.modes[key] === mode ? 'is-active' : '', label); button.type = 'button'; button.setAttribute('aria-pressed', String(driverPages.modes[key] === mode)); button.onclick = () => { driverPages.modes[key] = mode; rerender(); }; tabs.append(button); });
        card.querySelector('header').append(tabs); return tabs;
    }

    function headToHeadBars(data, pairs, kind) {
        const title = kind === 'race' ? 'Race H2H' : 'Qualifying H2H', card = standingsCard(title); card.classList.add('h2h-bars-card'); comparisonMode(card, kind, kind, renderDriverPages);
        const summaries = pairs.map(pair => ({ ...pair, ...comparisonPoints(data, pair.first.driverId, pair.second.driverId, sessionModeTypes(kind, driverPages.modes[kind]), pair.crossTeam ? null : pair.team) })).filter(pair => pair.matches.length).sort((a, b) => Math.abs(b.left - b.right) / b.matches.length - Math.abs(a.left - a.right) / a.matches.length);
        if (!summaries.length) { card.append(node('p', 'empty', 'No shared results for the selected drivers and session type.')); card.querySelector('.standings-download').disabled = true; return card; }
        const W = 780, rowH = 61, svg = standingsSvg(W, Math.max(100, summaries.length * rowH), title); svg.classList.add('h2h-bars');
        summaries.forEach((pair, i) => {
            const swap = pair.right > pair.left, a = swap ? pair.second : pair.first, b = swap ? pair.first : pair.second, left = swap ? pair.right : pair.left, right = swap ? pair.left : pair.right, total = left + right, width = total ? Math.max(135, Math.min(W - 135, W * left / total)) : W / 2, y = i * rowH, color = manufacturerColor(a.constructor), other = manufacturerColor(b.constructor), g = chartShape(svg, 'g', {});
            chartShape(g, 'rect', { x: 0, y: y + 2, width: W, height: 52, rx: 4, fill: pair.crossTeam ? other : color }); chartShape(g, 'rect', { x: width, y: y + 2, width: W - width, height: 52, rx: 4, fill: '#000', opacity: .42 }); chartShape(g, 'path', { d: `M4 ${y + 2} H${width} V${y + 54} H4 Q0 ${y + 54} 0 ${y + 50} V${y + 6} Q0 ${y + 2} 4 ${y + 2}`, fill: color });
            const foreground = ['mclaren', 'mercedes', 'haas', 'williams', 'cadillac', 'rb'].includes(teamKey(a.constructor)) ? '#07111b' : '#fff';
            chartShape(g, 'text', { x: 14, y: y + 34, fill: foreground, 'font-size': 19, 'font-weight': 700 }, left); chartShape(g, 'text', { x: 47, y: y + 33, fill: foreground, 'font-size': 14, 'font-weight': 600 }, shortDriverName(a));
            chartShape(g, 'text', { x: W - 46, y: y + 33, fill: '#fff', 'text-anchor': 'end', 'font-size': 14, 'font-weight': 600 }, shortDriverName(b)); chartShape(g, 'text', { x: W - 14, y: y + 34, fill: '#fff', 'text-anchor': 'end', 'font-size': 19, 'font-weight': 700 }, right);
            const logo = manufacturerLogo(a.constructor, true); if (logo) chartShape(g, 'image', { href: logo.src, x: W / 2 - 23, y: y + 14, width: 46, height: 28 });
            chartTip(g, `${a.driverName} ${left} – ${right} ${b.driverName} · ${pair.ties} ties · ${pair.matches.length} comparable sessions`);
            g.setAttribute('role', 'link'); const open = () => openDriverComparison(a, b); g.onclick = open; g.onkeydown = event => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); open(); } };
        }); card.append(svg); return card;
    }

    function qualifyingGaps(data, pair, types) {
        const dots = [];
        for (const entry of data.entries) for (const type of types) {
            const a = driverRow(entry, type, pair.first.driverId), b = driverRow(entry, type, pair.second.driverId); if (!a || !b) continue;
            if (!pair.crossTeam && ((a.constructorId || teamKey(a.team)) !== pair.team || (b.constructorId || teamKey(b.team)) !== pair.team)) continue;
            // Compare each matching qualifying phase; a driver's Q1 is never compared to the other's Q3.
            const phases = ['q1', 'q2', 'q3'].filter(phase => Number.isFinite(lapSeconds(a[phase])) && Number.isFinite(lapSeconds(b[phase])));
            if (phases.length) phases.forEach(phase => dots.push({ entry, type, phase, gap: lapSeconds(a[phase]) - lapSeconds(b[phase]) }));
            else if (!['q1', 'q2', 'q3'].some(phase => a[phase] || b[phase]) && Number.isFinite(lapSeconds(a.bestLap)) && Number.isFinite(lapSeconds(b.bestLap))) dots.push({ entry, type, phase: 'Best lap', gap: lapSeconds(a.bestLap) - lapSeconds(b.bestLap) });
        }
        return dots;
    }

    function qualifyingGapCard(data, pairs) {
        const card = standingsCard('Teammate Qualifying Gaps'); card.classList.add('h2h-gap-card'); comparisonMode(card, 'gaps', 'qualifying', renderDriverPages);
        const toggle = node('label', 'standings-previous', 'Highlight last quali'), input = node('input', ''); input.type = 'checkbox'; input.checked = driverPages.highlight; input.onchange = () => { driverPages.highlight = input.checked; renderDriverPages(); }; toggle.append(input); card.querySelector('header').append(toggle);
        card.append(node('p', 'driver-chart-note', 'Each dot compares matching Q1, Q2 and Q3 (or SQ1, SQ2 and SQ3) lap times. Only phases with valid times for both drivers are included.'));
        const rows = pairs.map(pair => ({ ...pair, dots: qualifyingGaps(data, pair, sessionModeTypes('qualifying', driverPages.modes.gaps)) })).filter(pair => pair.dots.length).sort((a, b) => mean(a.dots.map(d => d.gap)) - mean(b.dots.map(d => d.gap)));
        if (!rows.length) { card.append(node('p', 'empty', 'No matching qualifying lap times are available for this selection.')); card.querySelector('.standings-download').disabled = true; return card; }
        const W = 1500, rowH = 156, svg = standingsSvg(W, rows.length * rowH, 'Qualifying lap time gaps for each driver pairing'), left = 34, width = W - 68, scale = width / 4;
        rows.forEach((pair, i) => {
            const y = i * rowH, color = standingsLineColor(pair.teamName), average = mean(pair.dots.map(d => d.gap)), wins = comparisonPoints(data, pair.first.driverId, pair.second.driverId, sessionModeTypes('qualifying', driverPages.modes.gaps), pair.crossTeam ? null : pair.team), firstName = driverCode({ name: pair.first.driverName }), secondName = driverCode({ name: pair.second.driverName });
            chartShape(svg, 'rect', { x: 0, y: y + 3, width: W, height: rowH - 12, rx: 8, fill: color, opacity: .07 });
            chartShape(svg, 'text', { x: 35, y: y + 31, fill: 'currentColor', 'font-size': 17, 'font-weight': 700 }, wins.left); chartShape(svg, 'text', { x: 75, y: y + 31, fill: color, 'font-size': 14, 'font-weight': 600 }, firstName); chartShape(svg, 'text', { x: W - 35, y: y + 31, 'text-anchor': 'end', fill: 'currentColor', 'font-size': 17, 'font-weight': 700 }, wins.right); chartShape(svg, 'text', { x: W - 75, y: y + 31, 'text-anchor': 'end', fill: color, 'font-size': 14, 'font-weight': 600 }, secondName);
            const logo = manufacturerLogo(pair.teamName); if (logo) chartShape(svg, 'image', { href: logo.src, x: W / 2 - 24, y: y + 14, width: 48, height: 29 });
            const meanText = average >= 0 ? `+${average.toFixed(3)}s` : `${average.toFixed(3)}s`; chartShape(svg, 'text', { x: 35, y: y + 52, fill: average <= 0 ? '#13b981' : '#ef4444', 'font-size': 11 }, meanText + ' mean'); chartShape(svg, 'text', { x: W - 35, y: y + 52, 'text-anchor': 'end', fill: average >= 0 ? '#13b981' : '#ef4444', 'font-size': 11 }, `${average > 0 ? '-' : '+'}${Math.abs(average).toFixed(3)}s mean`);
            chartShape(svg, 'rect', { x: left, y: y + 65, width, height: 50, rx: 3, fill: color, opacity: .13 });
            for (let tick = -2; tick <= 2; tick += .5) { const x = left + (tick + 2) * scale; chartShape(svg, 'line', { x1: x, y1: y + 65, x2: x, y2: y + 115, stroke: 'currentColor', opacity: tick === 0 ? .4 : .1 }); chartShape(svg, 'text', { x, y: y + 133, 'text-anchor': 'middle', fill: 'currentColor', 'font-size': 10 }, tick === 0 ? '0' : `${tick > 0 ? '+' : ''}${tick.toFixed(1)}s`); }
            const averageX = left + (Math.max(-2, Math.min(2, average)) + 2) * scale; chartShape(svg, 'line', { x1: averageX, y1: y + 65, x2: averageX, y2: y + 115, stroke: color, 'stroke-width': 2 });
            const last = pair.dots.at(-1); pair.dots.forEach((dot, j) => { const isLast = dot.entry.meeting.round === last.entry.meeting.round && dot.type === last.type, c = chartShape(svg, 'circle', { cx: left + (Math.max(-2, Math.min(2, dot.gap)) + 2) * scale, cy: y + 78 + (j % 3) * 12, r: 4.5, fill: color, opacity: !driverPages.highlight || isLast ? 1 : .18, stroke: driverPages.highlight && isLast ? 'currentColor' : 'none', 'stroke-width': 1.5 }); chartTip(c, `R${dot.entry.meeting.round} ${dot.entry.meeting.country} · ${dot.type === 'sprintQualifying' ? 'Sprint ' : ''}${dot.phase.toUpperCase()} · ${firstName} vs ${secondName}: ${dot.gap >= 0 ? '+' : ''}${dot.gap.toFixed(3)}s${Math.abs(dot.gap) > 2 ? ' (outside ±2s axis)' : ''}`); });
        }); card.append(svg); return card;
    }

    function teamPoleChart(data, pairs) {
        const card = standingsCard('Team Gap to Pole'); card.classList.add('h2h-pole-card'); comparisonMode(card, 'pole', 'qualifying', renderDriverPages);
        card.append(node('p', 'driver-chart-note', "Each team's fastest qualifying lap compared to the pole sitter's time in the same qualifying phase. Missing phases are omitted."));
        const types = sessionModeTypes('qualifying', driverPages.modes.pole), sessions = data.entries.flatMap(entry => types.filter(type => sessionRows(entry, type).length).map(type => ({ entry, type }))), teams = [...new Set(pairs.flatMap(p => p.crossTeam ? [p.team, teamKey(p.second.constructor)] : [p.team]))], W = 1500, H = 430, left = 45, right = 70, top = 25, bottom = 65, series = [];
        teams.forEach(team => { const values = sessions.map(({ entry, type }) => { const rows = sessionRows(entry, type), pole = rows.find(r => r.position === 1); if (!pole) return null; const phase = ['q3', 'q2', 'q1', 'bestLap'].find(k => Number.isFinite(lapSeconds(pole[k]))); if (!phase) return null; const times = rows.filter(r => (r.constructorId || teamKey(r.team)) === team).map(r => lapSeconds(r[phase])).filter(Number.isFinite); if (!times.length) return null; const gap = Math.min(...times) - lapSeconds(pole[phase]); return gap >= 0 ? gap : null; }); series.push({ team, values }); });
        const all = series.flatMap(s => s.values.filter(v => v !== null)); if (!all.length) { card.append(node('p', 'empty', 'No pole comparison lap times are available.')); card.querySelector('.standings-download').disabled = true; return card; }
        const svg = standingsSvg(W, H, 'Team gap to pole by qualifying session'), max = Math.max(1, Math.ceil(Math.max(...all))), x = i => left + i * (W - left - right) / Math.max(1, sessions.length - 1), y = v => H - bottom - v / max * (H - top - bottom);
        for (let i = 0; i <= 6; i++) { const v = max * i / 6; chartShape(svg, 'line', { x1: left, y1: y(v), x2: W - right, y2: y(v), stroke: 'currentColor', opacity: .13 }); chartShape(svg, 'text', { x: left - 7, y: y(v) + 3, 'text-anchor': 'end', fill: 'currentColor', 'font-size': 11 }, v === 0 ? '0' : `+${v.toFixed(1)}s`); }
        sessions.forEach(({ entry, type }, i) => chartShape(svg, 'text', { x: x(i), y: H - bottom + 20, transform: `rotate(-45 ${x(i)} ${H - bottom + 20})`, 'text-anchor': 'end', fill: 'currentColor', 'font-size': 10 }, `R${entry.meeting.round}${type === 'sprintQualifying' ? ' (SQ)' : ''}`));
        series.forEach(({ team, values }) => { const name = data.drivers.find(d => teamKey(d.constructor) === team)?.constructor || team, color = standingsLineColor(name); let path = ''; values.forEach((v, i) => { if (v == null) return; path += `${i && values[i - 1] != null ? 'L' : 'M'}${x(i)},${y(v)} `; }); chartShape(svg, 'path', { d: path, fill: 'none', stroke: color, 'stroke-width': 2 }); values.forEach((v, i) => { if (v !== null) chartTip(chartShape(svg, 'circle', { cx: x(i), cy: y(v), r: 3, fill: color }), `${cleanTeamName(name)} · R${sessions[i].entry.meeting.round} · +${v.toFixed(3)}s to pole`); }); const last = values.findLastIndex(v => v !== null), logo = manufacturerLogo(name); if (last >= 0 && logo) chartShape(svg, 'image', { href: logo.src, x: x(last) + 10, y: y(values[last]) - 9, width: 30, height: 18 }); }); card.append(svg); return card;
    }

    function popularComparisons(data, root) {
        const section = node('section', 'popular-comparisons');
        const head = node('div', 'popular-comparisons-head');
        const next = node('button', 'comparison-next');
        next.type = 'button';
        next.setAttribute('aria-label', 'Show more comparisons');
        next.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg>';
        head.append(node('h2', '', 'Popular Driver Comparisons'), next);
        section.append(head);
        const track = node('div', 'comparison-track');
        const pairs = comparisonPairs(data).sort((a, b) => Math.min(a.first.position, b.first.position) - Math.min(b.first.position, b.second.position));
        const used = new Set();
        for (const pair of pairs) {
            if (used.has(pair.team)) continue;
            used.add(pair.team);
            const card = node('a', 'comparison-board');
            card.href = driverPageHref('head-to-head', { driver1: pair.first.driverId, driver2: pair.second.driverId });
            card.style.setProperty('--team-a', manufacturerColor(pair.first.constructor));
            card.style.setProperty('--team-b', manufacturerColor(pair.second.constructor));
            card.setAttribute('aria-label', `Compare ${pair.first.driverName} and ${pair.second.driverName}`);
            const left = node('span', 'comparison-half first'), right = node('span', 'comparison-half second');
            left.setAttribute('aria-hidden', 'true'); right.setAttribute('aria-hidden', 'true');
            card.append(left, right, node('span', 'comparison-cut'));
            const a = driverPhoto(pair.first, 'comparison-photo first'), b = driverPhoto(pair.second, 'comparison-photo second');
            if (a) card.append(a);
            if (b) card.append(b);
            card.append(node('strong', 'comparison-vs', 'VS'), node('span', 'comparison-name first', shortDriverName(pair.first)), node('span', 'comparison-name second', shortDriverName(pair.second)));
            track.append(card);
        }
        section.append(track);
        const syncNext = () => { next.hidden = track.scrollLeft + track.clientWidth >= track.scrollWidth - 4; };
        next.onclick = () => track.scrollBy({ left: Math.max(240, track.clientWidth * .8), behavior: 'smooth' });
        track.addEventListener('scroll', syncNext, { passive: true });
        requestAnimationFrame(syncNext);
        root.append(section);
    }

    function renderHeadToHead(root, data) {
        const filters = driverPageHead(root, 'Head To Head', data);
        if (driverLoadState(root, data)) return;
        const teams = [...new Map(data.drivers.map(d => [teamKey(d.constructor), cleanTeamName(d.constructor)])).entries()];
        const route = (params) => { navigate(driverPageHref('head-to-head', { team: driverPages.team, driver1: driverPages.first, driver2: driverPages.second, ...params })); };
        filters.append(driverSelector('Team', driverPages.team, [['', 'All teams'], ...teams], value => route({ team: value, driver1: '', driver2: '' })));
        const available = data.drivers;
        filters.append(driverSelector('Driver 1', driverPages.first, [['', 'Select'], ...available.filter(d => d.driverId !== driverPages.second).map(d => [d.driverId, shortDriverName(d)])], value => route({ driver1: value, team: '' })), driverSelector('Driver 2', driverPages.second, [['', 'Select'], ...available.filter(d => d.driverId !== driverPages.first).map(d => [d.driverId, shortDriverName(d)])], value => route({ driver2: value, team: '' })));
        const intro = node('div', 'h2h-intro'); intro.append(node('h2', '', `${driverPages.season} F1 Head-to-Head`), node('p', '', 'Compare F1 drivers in qualifying, races and the championship, against their teammates or rivals from other teams.')); root.append(intro);
        popularComparisons(data, root); const pairs = selectedComparisonPairs(data);
        const first = data.drivers.find(d => d.driverId === driverPages.first), second = data.drivers.find(d => d.driverId === driverPages.second);
        if (first && second) {
            const summary = node('section', 'h2h-selected-summary'); summary.append(node('strong', '', `${first.driverName}  vs  ${second.driverName}`), node('span', '', `${pointsText(first.points)} pts · P${first.position}   /   ${pointsText(second.points)} pts · P${second.position}`)); const reset = node('a', '', 'Show all comparisons'); reset.href = driverPageHref('head-to-head'); summary.append(reset); root.append(summary);
        }
        const grid = node('div', 'h2h-grid'); grid.append(headToHeadBars(data, pairs, 'qualifying'), headToHeadBars(data, pairs, 'race')); root.append(grid, qualifyingGapCard(data, pairs), teamPoleChart(data, pairs));
    }

    // Linear interpolation (R-7) for quartiles; whiskers show the observed range.
    function positionQuantile(sorted, fraction) {
        if (!sorted.length) return null;
        const index = (sorted.length - 1) * fraction, lower = Math.floor(index), upper = Math.ceil(index);
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (index - lower);
    }

    function consistencyDistribution(data, type, excludeDnf) {
        const groups = new Map();
        for (const entry of data.entries) for (const row of sessionRows(entry, type)) {
            // Keep official numbered retirements unless excluded. Never invent a
            // finishing position for an unclassified result with no position.
            const position = Number(row.position);
            if (!Number.isInteger(position) || position < 1 || (excludeDnf && retiredResult(row))) continue;
            if (!groups.has(row.driverId)) {
                const driver = data.drivers.find(d => d.driverId === row.driverId) || { driverId: row.driverId, driverName: row.driverName, constructor: row.team || row.constructorId, position: 999 };
                groups.set(row.driverId, { driver, values: [] });
            }
            groups.get(row.driverId).values.push(position);
        }
        return [...groups.values()].map(group => {
            const values = group.values.sort((a, b) => a - b);
            return { ...group, min: values[0], q1: positionQuantile(values, .25), median: positionQuantile(values, .5), q3: positionQuantile(values, .75), max: values.at(-1), average: mean(values) };
        }).sort((a, b) => a.median - b.median || a.average - b.average || a.driver.position - b.driver.position);
    }

    function consistencyChart(data, type, title) {
        const groups = consistencyDistribution(data, type, driverPages.excludeDnf), card = standingsCard(title);
        card.classList.add('consistency-card'); card.dataset.session = type;
        if (!groups.length) { card.append(node('p', 'empty', 'No recorded positions for this season and selection.')); card.querySelector('.standings-download').disabled = true; return card; }
        const W = 780, H = 620, left = 34, right = 12, top = 24, bottom = 58;
        const maxPosition = Math.max(20, ...data.entries.map(e => sessionRows(e, type).length), ...groups.map(g => g.max));
        const y = position => top + (position - 1) / (maxPosition - 1) * (H - top - bottom), step = (W - left - right) / groups.length, boxWidth = Math.min(26, step * .72);
        const svg = standingsSvg(W, H, title), palette = getComputedStyle(document.body);
        svg.style.background = palette.getPropertyValue('--card').trim(); svg.style.color = palette.getPropertyValue('--muted-strong').trim();
        for (let position = 1; position <= maxPosition; position++) {
            chartShape(svg, 'line', { x1: left, y1: y(position), x2: W - right, y2: y(position), stroke: 'currentColor', opacity: .17 });
            chartShape(svg, 'text', { x: left - 7, y: y(position) + 4, 'text-anchor': 'end', fill: 'currentColor', 'font-size': 11, 'font-weight': 600 }, position);
        }
        const qualifying = type === 'qualifying' || type === 'sprintQualifying';
        const cutoffs = qualifying ? [[10, type === 'qualifying' ? 'Q3 Cutoff' : 'SQ3 Cutoff'], [maxPosition - (maxPosition > 20 ? 6 : 5), type === 'qualifying' ? 'Q2 Cutoff' : 'SQ2 Cutoff']] : [[type === 'sprint' ? 8 : 10, 'In points']];
        cutoffs.forEach(([position, label]) => {
            chartShape(svg, 'line', { x1: left, y1: y(position), x2: W - right, y2: y(position), stroke: 'currentColor', 'stroke-dasharray': '4 5', opacity: .8 });
            chartShape(svg, 'text', { x: qualifying ? left + 10 : W - right - 8, y: y(position) - 10, 'text-anchor': qualifying ? 'start' : 'end', fill: 'currentColor', 'font-size': 11, 'font-weight': 600 }, label);
        });
        const format = value => Number(value.toFixed(2));
        groups.forEach((group, i) => {
            const { driver, min, q1, median, q3, max, values } = group, x = left + step * (i + .5), color = manufacturerColor(driver.constructor);
            const link = chartShape(svg, 'a', { href: driverPageHref(`drivers/${encodeURIComponent(driver.driverId)}`), 'data-driver-id': driver.driverId });
            chartTip(link, `${driver.driverName} · ${values.length} results · Best P${min} · Q1 ${format(q1)} · Median ${format(median)} · Q3 ${format(q3)} · Worst P${max}`);
            chartShape(link, 'rect', { x: x - step * .44, y: top - 5, width: step * .88, height: H - top - 7, fill: 'transparent', 'aria-hidden': 'true', class: 'consistency-hitbox' });
            chartShape(link, 'line', { x1: x, y1: y(min), x2: x, y2: y(max), stroke: color, 'stroke-width': 1 });
            for (const position of [min, max]) chartShape(link, 'line', { x1: x - boxWidth * .3, y1: y(position), x2: x + boxWidth * .3, y2: y(position), stroke: color });
            chartShape(link, 'rect', { x: x - boxWidth / 2, y: y(q1) - Number(q1 === q3), width: boxWidth, height: Math.max(2, y(q3) - y(q1)), rx: 2, fill: color });
            chartShape(link, 'line', { x1: x - boxWidth / 2, y1: y(median), x2: x + boxWidth / 2, y2: y(median), stroke: '#000', opacity: .28, 'stroke-width': 2.2 });
            chartShape(link, 'text', { x: x + 2, y: H - bottom + 15, transform: `rotate(-48 ${x + 2} ${H - bottom + 15})`, 'text-anchor': 'end', fill: 'currentColor', 'font-size': 11, 'font-weight': 600 }, driverCode(driver));
        });
        card.append(svg); return card;
    }

    function renderConsistency(root, data) {
        const filters = driverPageHead(root, 'Consistency', data), toggle = node('label', 'racing-selector consistency-dnf', 'Exclude DNF');
        const info = node('span', 'consistency-info', 'ⓘ'); info.title = 'Exclude DNF, DNS and DSQ results from all four charts. Results without an official numbered position are always omitted. Boxes show the 25th–75th percentiles, the line is the median, and whiskers show the best and worst positions. Drivers are sorted by median position.';
        info.tabIndex = 0; info.dataset.popover = info.title; info.setAttribute('aria-label', info.title);
        const input = node('input', ''); input.type = 'checkbox'; input.setAttribute('role', 'switch'); input.setAttribute('aria-label', 'Exclude DNF'); input.checked = driverPages.excludeDnf;
        input.onchange = () => { navigate(driverPageHref('consistency', { excludeDnf: input.checked ? '1' : '0' })); };
        toggle.append(info, input); filters.prepend(toggle);
        if (driverLoadState(root, data)) return;
        const grid = node('div', 'consistency-grid');
        for (const [type, title] of [['race', 'Race Finishing Position Distribution'], ['sprint', 'Sprint Finishing Position Distribution'], ['qualifying', 'Qualifying Position Distribution'], ['sprintQualifying', 'Sprint Qualifying Position Distribution']]) grid.append(consistencyChart(data, type, title));
        root.append(grid);
    }

    function renderDriverPages() {
        if (!RACING_VIEWS.includes(state.view)) return;
        if (sectionFeature(state.view) && !SEASON_FEATURES.get(driverPages.season)) return;
        setLoading(null);
        delete document.body.dataset.seasonEmpty;
        const view = state.view === 'driver-stats' ? 'drivers' : state.view, root = el(`view-${view}`).querySelector('.racing-workspace'); root.replaceChildren();
        useSeason(driverPages.season);
        if (state.view === 'home') { renderHome(root); return; }
        if (['tech-updates', 'pu-elements', 'destructors-championship'].includes(state.view)) { renderEngineering(root); return; }
        const data = loadDriverSeason(driverPages.season);
        if (state.view === 'drivers') renderDrivers(root, data); else if (state.view === 'driver-stats') renderDriverDetail(root, data); else if (state.view === 'consistency') renderConsistency(root, data); else renderHeadToHead(root, data);
        installSeasonPopovers(root);
    }

    /* ---------- Technical updates and power unit allocation ---------- */
    const engineeringPages = { cache: new Map(), preferences: new Map() };

    // The server states which engineering sections exist for a season. Sections
    // it does not offer are removed from the navigation and never requested, so
    // an older season cannot show an empty table or a zero total.
    const SEASON_FEATURES = new Map();
    const SECTION_FEATURE = { 'pu-elements': 'powerUnit', 'destructors-championship': 'destructors' };

    function sectionFeature(view) { return SECTION_FEATURE[view] || null; }

    function sectionOffered(view, season) {
        const key = sectionFeature(view);
        if (!key) return true;
        const features = SEASON_FEATURES.get(Number(season));
        return !features || features[key] !== false;
    }

    function loadFeatures(season) {
        const year = Number(season);
        if (SEASON_FEATURES.has(year)) return SEASON_FEATURES.get(year);
        SEASON_FEATURES.set(year, null);
        api(`/api/v1/features?season=${year}`).then(({ body }) => {
            SEASON_FEATURES.set(year, body.data || {});
        }).catch(() => {
            SEASON_FEATURES.set(year, {});
        }).finally(() => {
            syncSectionNav(year);
            if (driverPages.season !== year) return;
            if (SECTION_FEATURE[state.view]) applyRoute();
        });
        return null;
    }

    function syncSectionNav(season = requestedSeason() || driverPages.season) {
        if (!season) return;
        // The navigation is the only place that knows a section exists, so it
        // resolves the capability map even when the reader never opens it.
        if (!SEASON_FEATURES.has(Number(season))) loadFeatures(season);
        for (const view of Object.keys(SECTION_FEATURE)) {
            const offered = sectionOffered(view, season);
            for (const link of document.querySelectorAll(`[data-route="${view}"]`)) link.hidden = !offered;
        }
    }
    function engineeringPreference(view, season) {
        const key = `${view}:${season}`;
        if (!engineeringPages.preferences.has(key)) engineeringPages.preferences.set(key, { teams: null, types: null, reasons: null, drivers: null, elements: null, major: false });
        return engineeringPages.preferences.get(key);
    }
    function engineeringData(view, season) {
        const key = `${view}:${season}`;
        if (engineeringPages.cache.has(key)) return engineeringPages.cache.get(key);
        const data = { loading: true, error: false, rows: [], usage: [], elements: [], penalties: [], meta: {} };
        engineeringPages.cache.set(key, data);
        api(`/api/v1/${view}?season=${season}`).then(response => {
            const body = response.body; data.meta = body.meta || {};
            if (view === 'tech-updates') data.rows = body.data || []; else Object.assign(data, body.data);
        }).catch(() => { data.error = true; }).finally(() => { data.loading = false; if (state.view === view && driverPages.season === season) renderDriverPages(); });
        return data;
    }
    function engineeringSelected(selection, value) { return selection === null || selection.has(value); }
    function engineeringFilterRows(rows, preference) {
        return rows.filter(row => engineeringSelected(preference.teams, row.team) && engineeringSelected(preference.types, row.type) && engineeringSelected(preference.reasons, row.reason));
    }
    function engineeringCounts(rows, key) {
        const counts = new Map(); rows.forEach(row => { const value = row[key] || 'Unknown'; counts.set(value, (counts.get(value) || 0) + 1); });
        return [...counts].map(([name, count]) => ({ name, count })).sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));
    }
    function engineeringMulti(label, options, preference, key, onchange, logos = false) {
        const wrapper = node('details', 'engineering-filter standings-filter'), summary = node('summary', 'racing-selector');
        summary.append(svgIcon(key === 'teams' ? 'M14 6a5 5 0 0 0-6 6L2 18l4 4 6-6a5 5 0 0 0 6-6l-4 4-4-4 4-4Z' : key === 'drivers' ? 'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8' : 'M3 5h18M6 12h12M10 19h4'), node('span', '', label), node('b', '')); summary.setAttribute('aria-label', `Select ${label.toLowerCase()}`);
        const menu = node('div', 'standings-selection'); menu.append(node('h2', '', `Select ${label.toLowerCase()}`));
        const actions = node('div', 'standings-selection-actions'), all = node('button', '', 'Select all'), clear = node('button', '', 'Clear');
        all.type = clear.type = 'button'; actions.append(all, clear); menu.append(actions);
        const list = node('div', 'standings-selection-options');
        const sync = () => {
            const selected = options.filter(option => engineeringSelected(preference[key], option)).length;
            summary.querySelector('b').textContent = String(selected); summary.setAttribute('aria-label', `Select ${label.toLowerCase()}: ${selected} of ${options.length} selected`);
            list.querySelectorAll('input').forEach(input => input.checked = engineeringSelected(preference[key], input.value));
            all.disabled = selected === options.length; clear.disabled = selected === 0;
        };
        options.forEach(option => {
            const row = node('label', 'standings-selection-option'), input = node('input'); input.type = 'checkbox'; input.value = option;
            row.append(input); if (logos) { const logo = manufacturerLogo(option); if (logo) row.append(logo); } row.append(node('span', '', option));
            input.onchange = () => { preference[key] = new Set([...list.querySelectorAll('input:checked')].map(i => i.value)); sync(); onchange(); }; list.append(row);
        });
        all.onclick = () => { preference[key] = null; sync(); onchange(); }; clear.onclick = () => { preference[key] = new Set(); sync(); onchange(); };
        menu.append(list); wrapper.append(summary, menu); sync();
        wrapper.addEventListener('keydown', event => { if (event.key === 'Escape') { wrapper.open = false; summary.focus(); } });
        wrapper.addEventListener('focusout', event => { if (event.relatedTarget && !wrapper.contains(event.relatedTarget)) wrapper.open = false; });
        wrapper.addEventListener('toggle', () => { if (wrapper.open) wrapper.closest('.racing-page-filters').querySelectorAll('details[open]').forEach(other => { if (other !== wrapper) other.open = false; }); });
        return wrapper;
    }
    document.addEventListener('pointerdown', event => document.querySelectorAll('.engineering-filter[open]').forEach(menu => { if (!menu.contains(event.target)) menu.open = false; }));
    function engineeringHead(root, title, view, season) {
        const head = node('header', 'page-head racing-page-head'), filters = node('div', 'racing-page-filters engineering-filters');
        head.append(node('h1', '', title), filters); root.append(head);
        filters.append(driverSelector('Season', season, seasonYears().map(y => [y, y]), value => { navigate(`/${view}?season=${value}`); })); return filters;
    }
    function engineeringStatus(root, data, view) {
        const label = view === 'tech-updates' ? 'technical updates' : view === 'pu-elements' ? 'power unit reports' : 'crash reports';
        if (data.loading) {
            setLoading(`Loading ${label}…`);
            return true;
        }
        if (data.error) {
            const message = node('div', 'driver-page-message'); message.setAttribute('role', 'status');
            message.append(node('p', '', `${label[0].toUpperCase() + label.slice(1)} could not be loaded.`));
            const retry = node('button', 'workspace-button', 'Try again');
            retry.onclick = () => { engineeringPages.cache.delete(`${view}:${driverPages.season}`); renderDriverPages(); };
            message.append(retry); root.append(message); return true;
        }
        const unavailable = view === 'tech-updates' ? data.meta.unavailable : view === 'destructors-championship' ? data.meta.sections?.incidents?.unavailable : Object.values(data.meta.sections || {}).every(meta => meta.unavailable);
        if (unavailable) {
            const empty = node('div', 'engineering-empty');
            empty.setAttribute('role', 'status');
            empty.append(node('p', 'engineering-empty-title', `No ${label} recorded for ${driverPages.season}`), node('p', 'engineering-empty-note', 'PitPulse only archives this section for the seasons it has collected reports for.'));
            root.append(empty);
            // This page cannot serve the season, so it stops offering a switch.
            document.body.dataset.seasonEmpty = 'true';
            return true;
        }
        const missing = Object.entries(data.meta.sections || {}).filter(([, meta]) => meta.unavailable).map(([name]) => ({ usage: 'PU usage', elements: 'element allocations', penalties: 'penalty reports' })[name] || name);
        const source = node('p', 'engineering-source', `Source: PitPulse${data.meta.stale ? ' · Historical archive' : ''}${missing.length ? ` · Unavailable: ${missing.join(', ')}` : ''}`); source.setAttribute('role', 'status'); root.append(source); return false;
    }

    function engineeringEmpty(card, message = 'No updates match the selected filters.') {
        card.querySelector('.standings-download').disabled = true; card.append(node('p', 'empty', message)); return card;
    }
    function engineeringColor(team) {
        return ({ mercedes: '#19e5ce', ferrari: '#ed002c', mclaren: '#ff8000', red_bull: '#3671c6', rb: '#6692ff', alpine: '#0093c5', haas: '#b6babd', audi: '#ff3600', williams: '#64c4ff', aston_martin: '#229971', cadillac: '#909090' })[teamKey(team)] || manufacturerColor(team);
    }
    function engineeringBars(title, values, logos = false) {
        const W = 360, rowH = 24, left = logos ? 44 : 5;
        const { card, svg } = driverChart(title, W, Math.max(150, values.length * rowH + 8));
        if (!values.length) { svg.remove(); return engineeringEmpty(card); }
        const maximum = Math.max(...values.map(v => v.count), 1);
        values.forEach((value, i) => {
            const y = i * rowH + 4, color = logos ? engineeringColor(value.name) : '#e10600', width = value.count / maximum * (W - left - 12);
            if (logos) { const logo = manufacturerLogo(value.name); if (logo) chartShape(svg, 'image', { href: logo.src, x: 3, y: y + 1, width: 30, height: 20 }); }
            const bar = chartShape(svg, 'rect', { x: left, y, width, height: 22, rx: 2, fill: color }); chartTip(bar, `${value.name} · ${value.count}`);
            chartShape(svg, 'text', { x: left + 6, y: y + 15, fill: logos ? (['mclaren', 'mercedes', 'haas', 'williams', 'cadillac', 'rb'].includes(teamKey(value.name)) ? '#07111b' : '#fff') : '#fff', 'font-size': 12, 'font-weight': 650 }, value.count);
            if (!logos) chartShape(svg, 'text', { x: left + 32, y: y + 15, fill: width > 210 ? '#fff' : 'var(--text)', 'font-size': 12 }, value.name);
        }); return card;
    }
    function engineeringDonut(title, values) {
        const card = standingsCard(title); if (!values.length) return engineeringEmpty(card);
        const body = node('div', 'engineering-donut'), svg = standingsSvg(220, 220, title), total = values.reduce((n, v) => n + v.count, 0), colors = ['#e10600', '#ffda4b', '#1f75ef'];
        const colorAt = i => colors[i] || '#64748b';
        const palette = getComputedStyle(document.body); svg.style.background = palette.getPropertyValue('--card'); svg.style.color = palette.getPropertyValue('--text');
        let offset = 0; const radius = 80, circ = 2 * Math.PI * radius;
        values.forEach((value, i) => {
            const fraction = value.count / total, length = fraction * circ, angle = (offset + length / 2) / circ * 2 * Math.PI - Math.PI / 2;
            const circle = chartShape(svg, 'circle', { cx: 110, cy: 110, r: radius, fill: 'none', stroke: colorAt(i), 'stroke-width': 44, 'stroke-dasharray': `${Math.max(0, length - 1)} ${circ}`, 'stroke-dashoffset': -offset, transform: 'rotate(-90 110 110)' }); chartTip(circle, `${value.name} · ${value.count} · ${(100 * fraction).toFixed(1)}%`);
            if (fraction >= .05) chartShape(svg, 'text', { x: 110 + radius * Math.cos(angle), y: 114 + radius * Math.sin(angle), 'text-anchor': 'middle', fill: i === 1 ? '#302500' : '#fff', 'font-size': 13, 'font-weight': 700 }, `${fraction >= .1 ? Math.round(100 * fraction) : (100 * fraction).toFixed(1)}%`);
            offset += length;
        });
        chartShape(svg, 'text', { x: 110, y: 110, 'text-anchor': 'middle', fill: 'currentColor', 'font-size': 25, 'font-weight': 750 }, total); chartShape(svg, 'text', { x: 110, y: 129, 'text-anchor': 'middle', fill: 'var(--muted-strong)', 'font-size': 11 }, 'updates');
        const legend = node('div', 'engineering-donut-legend'); legend.tabIndex = 0; legend.setAttribute('aria-label', `${title} legend`);
        values.forEach((value, i) => { const line = node('div'), dot = node('i'); dot.style.background = colorAt(i); line.title = value.name; line.append(dot, node('span', '', value.name), node('b', '', String(value.count))); legend.append(line); }); body.append(svg, legend); card.append(body); return card;
    }
    function engineeringMeetings(rows, data) {
        const rounds = [...new Set(rows.map(row => row.round))].sort((a, b) => a - b);
        return rounds.map(round => {
            const row = rows.find(r => r.round === round), stored = data.entries?.find(e => e.meeting.round === round)?.meeting;
            return stored || { round, country: row.country, countryCode: engineeringCountry(row.country) };
        });
    }
    function engineeringCountry(country) {
        return ({ Australia: 'AU', China: 'CN', Japan: 'JP', Miami: 'US', Canada: 'CA', Monaco: 'MC', Spain: 'ES', Austria: 'AT', Britain: 'GB', 'Great Britain': 'GB', Belgium: 'BE', Hungary: 'HU', Netherlands: 'NL', Italy: 'IT', Azerbaijan: 'AZ', Qatar: 'QA', Singapore: 'SG', 'United States': 'US', Mexico: 'MX', Brazil: 'BR', 'São Paulo': 'BR', Malaysia: 'MY', Bahrain: 'BH', 'Saudi Arabia': 'SA', 'Abu Dhabi': 'AE', Portugal: 'PT', France: 'FR', Russia: 'RU', Turkey: 'TR' })[country] || '';
    }
    function techRoundCharts(rows, seasonData, major, preference) {
        const teamOrder = ['mclaren', 'ferrari', 'red_bull', 'mercedes', 'aston_martin', 'haas', 'alpine', 'rb', 'williams', 'audi', 'cadillac'];
        const teams = engineeringCounts(rows, 'team').map(v => v.name).sort((a, b) => teamOrder.indexOf(teamKey(a)) - teamOrder.indexOf(teamKey(b))), meetings = engineeringMeetings(rows, seasonData), W = 900, left = 58, right = 35, step = (W - left - right) / Math.max(1, meetings.length);
        const rounds = driverChart('Updates by Team and Grand Prix', 360, Math.max(190, meetings.length * 24 + 35));
        const timeline = driverChart('Tech Updates Over Time', W, Math.max(260, teams.length * 43 + 65));
        const cumulative = driverChart('Cumulative Updates by Team and Grand Prix', W, 480);
        const toggle = node('label', 'consistency-dnf engineering-major', 'Highlight major updates'), input = node('input'); input.type = 'checkbox'; input.setAttribute('role', 'switch'); input.checked = major; input.setAttribute('aria-label', 'Highlight major updates'); toggle.append(input);
        input.onchange = () => { preference.major = input.checked; timeline.svg.querySelectorAll('.tech-major-ring').forEach(r => r.style.display = input.checked ? '' : 'none'); }; timeline.card.querySelector('header').insertBefore(toggle, timeline.card.querySelector('.standings-download'));
        if (!rows.length) { for (const item of [rounds, timeline, cumulative]) { item.svg.remove(); engineeringEmpty(item.card); } return [rounds.card, timeline.card, cumulative.card]; }
        const counts = (team, round) => rows.filter(r => r.team === team && r.round === round).length, maxRound = Math.max(1, ...meetings.map(m => rows.filter(r => r.round === m.round).length));
        meetings.forEach((meeting, i) => {
            const y = 7 + i * 24; chartFlag(rounds.svg, meeting, 14, y + 4, 17); let x = 33, total = 0;
            teams.forEach(team => { const count = counts(team, meeting.round); if (!count) return; const width = count / maxRound * 294; chartTip(chartShape(rounds.svg, 'rect', { x, y, width, height: 22, fill: engineeringColor(team), stroke: 'var(--card)', 'stroke-width': 1 }), `${meeting.country} · R${meeting.round} · ${team}: ${count}`); x += width; total += count; }); chartShape(rounds.svg, 'text', { x: x + 6, y: y + 16, fill: 'currentColor', 'font-size': 12, 'font-weight': 650 }, total);
        });
        for (let value = 0; value <= maxRound; value += 5) { const x = 33 + value / maxRound * 294; chartShape(rounds.svg, 'text', { x, y: meetings.length * 24 + 29, fill: 'currentColor', 'text-anchor': 'middle', 'font-size': 11 }, value); }
        const maxCount = Math.max(1, ...teams.flatMap(team => meetings.map(m => counts(team, m.round))));
        teams.forEach((team, i) => {
            const y = 22 + i * 43; chartShape(timeline.svg, 'line', { x1: left, y1: y, x2: W - right, y2: y, stroke: 'currentColor', opacity: .2 });
            const logo = manufacturerLogo(team); if (logo) chartShape(timeline.svg, 'image', { href: logo.src, x: 4, y: y - 13, width: 38, height: 26 });
            meetings.forEach((meeting, j) => {
                const count = counts(team, meeting.round); if (!count) return; const x = left + step * (j + .5), radius = Math.max(3, count / maxCount * 50), majorRows = rows.filter(r => r.team === team && r.round === meeting.round && r.major);
                chartTip(chartShape(timeline.svg, 'circle', { cx: x, cy: y, r: radius, fill: engineeringColor(team), opacity: .78 }), `${team} · ${meeting.country} · R${meeting.round}: ${count} updates${majorRows.length ? ` · ${majorRows.length} major` : ''}\n${rows.filter(r => r.team === team && r.round === meeting.round).map(r => r.component).join(', ')}`);
                if (majorRows.length) { const ring = chartShape(timeline.svg, 'circle', { cx: x, cy: y, r: radius + 4, fill: 'none', stroke: engineeringColor(team), 'stroke-width': 1.5, 'pointer-events': 'none', class: 'tech-major-ring' }); ring.style.display = major ? '' : 'none'; }
            });
        });
        meetings.forEach((meeting, i) => chartFlag(timeline.svg, meeting, left + step * (i + .5), teams.length * 43 + 26, 18));
        const maxTotal = Math.ceil(Math.max(...teams.map(team => rows.filter(r => r.team === team).length), 1) / 5) * 5, top = 18, bottom = 430, cy = value => bottom - value / maxTotal * (bottom - top);
        for (let value = 0; value <= maxTotal; value += 5) { chartShape(cumulative.svg, 'line', { x1: left, y1: cy(value), x2: W - right, y2: cy(value), stroke: 'currentColor', opacity: .15 }); chartShape(cumulative.svg, 'text', { x: left - 8, y: cy(value) + 4, 'text-anchor': 'end', fill: 'currentColor', 'font-size': 11 }, Math.round(value)); }
        teams.forEach(team => { let total = 0; const points = meetings.map((meeting, i) => { total += counts(team, meeting.round); const x = left + step * (i + .5), y = cy(total); chartTip(chartShape(cumulative.svg, 'circle', { cx: x, cy: y, r: 3, fill: engineeringColor(team) }), `${team} · R${meeting.round}: ${total} cumulative updates`); return `${x},${y}`; }); chartShape(cumulative.svg, 'polyline', { points: points.join(' '), fill: 'none', stroke: engineeringColor(team), 'stroke-width': 2, 'pointer-events': 'none' }); });
        meetings.forEach((meeting, i) => chartFlag(cumulative.svg, meeting, left + step * (i + .5), 451, 18));
        return [rounds.card, timeline.card, cumulative.card];
    }
    function renderTechUpdates(root) {
        const season = driverPages.season, view = 'tech-updates', data = engineeringData(view, season), preference = engineeringPreference(view, season), filters = engineeringHead(root, 'Tech Updates', view, season);
        const content = node('div', 'engineering-content'); root.append(content);
        const render = () => {
            content.replaceChildren(); if (engineeringStatus(content, data, view)) return;
            const rows = engineeringFilterRows(data.rows, preference), grid = node('div', 'tech-updates-grid'), components = engineeringBars('Updated Components', engineeringCounts(rows, 'component'));
            components.classList.add('tech-components'); const help = node('span', 'engineering-help', 'ⓘ Components'); help.tabIndex = 0; help.dataset.popover = 'Counts refer to reported component updates. One team may report several components at a Grand Prix.'; components.querySelector('header').insertBefore(help, components.querySelector('.standings-download'));
            const [rounds, timeline, cumulative] = techRoundCharts(rows, {}, preference.major, preference); rounds.classList.add('tech-rounds'); timeline.classList.add('tech-timeline'); cumulative.classList.add('tech-cumulative');
            const main = node('div', 'tech-main-grid'); main.append(engineeringBars('Updates per Team', engineeringCounts(rows, 'team'), true), engineeringDonut('Types of Upgrades', engineeringCounts(rows, 'type')), engineeringDonut('Primary Reasons for Updates', engineeringCounts(rows, 'reason')), rounds, timeline, cumulative); grid.append(main, components); content.append(grid);
            installSeasonPopovers(content);
        };
        for (const [label, key, field] of [['Constructors', 'teams', 'team'], ['Types', 'types', 'type'], ['Primary Reasons', 'reasons', 'reason']]) filters.append(engineeringMulti(label, engineeringCounts(data.rows, field).map(v => v.name).sort(), preference, key, render, key === 'teams'));
        render();
    }
    const elementLabel = code => ({ 'ce': 'PU-CE', 'ex': 'EXH', 'anc': 'PU-ANC' })[code] || code.toUpperCase();
    const elementKey = code => ({ 'mguk': 'mgu-k', 'mguh': 'mgu-h' })[code] || code;
    function powerUnitRows(data, preference) {
        return data.usage.filter(row => engineeringSelected(preference.teams, row.team) && engineeringSelected(preference.drivers, row.driverCode));
    }
    function engineeringPenaltyRows(rows) {
        const grouped = new Map(); rows.forEach(row => {
            const key = `${row.round}:${row.driverCode}`; let combined = grouped.get(key);
            if (!combined) { combined = { ...row, penaltyItems: [], elements: [], sourceDocuments: [], gridPositions: 0, startsFromPitLane: false }; grouped.set(key, combined); }
            combined.gridPositions += Number(row.gridPositions) || 0; combined.startsFromPitLane ||= Boolean(row.startsFromPitLane);
            combined.startingPosition = row.startingPosition || combined.startingPosition; combined.pitLaneReason ||= row.pitLaneReason;
            combined.penaltyItems.push(...(row.penaltyItems || [])); combined.elements.push(...(row.elements || [])); combined.sourceDocuments.push(...(row.sourceDocuments || []));
            combined.allocationDriverName ||= row.allocationDriverName;
        });
        return [...grouped.values()].map(row => ({ ...row, elements: [...new Set(row.elements)], sourceDocuments: [...new Map(row.sourceDocuments.map(source => [source.url, source])).values()] }));
    }
    function powerUnitClass(used, quota) { return used == null ? 'pu-missing' : !Number.isFinite(quota) || quota < 1 ? 'pu-neutral' : used > quota ? 'pu-over' : used === quota ? 'pu-limit' : 'pu-within'; }
    function renderPowerUnit(root) {
        const season = driverPages.season, view = 'pu-elements', data = engineeringData(view, season), preference = engineeringPreference(view, season), filters = engineeringHead(root, 'PU Elements Used', view, season), content = node('div', 'engineering-content'); root.append(content);
        const render = () => {
            content.replaceChildren(); if (engineeringStatus(content, data, view)) return;
            const rows = powerUnitRows(data, preference), elements = data.elements.filter(e => engineeringSelected(preference.elements, e.code)), grid = node('div', 'pu-overview-grid'), card = standingsCard('Power Unit Elements Used'), scroll = node('div', 'engineering-table-scroll'), table = node('table', 'pu-usage-table'), head = table.createTHead().insertRow();
            ['DRIVER', 'ENGINE', ...elements.map(e => elementLabel(e.code)), 'TOTAL'].forEach(label => head.append(node('th', '', label)));
            const body = table.createTBody(); rows.forEach(row => {
                const tr = body.insertRow(), who = node('td'); const link = node('a', 'pu-driver'); link.href = engineeringDriverHref(row); const logo = manufacturerLogo(row.team); if (logo) link.append(logo); link.append(node('span', '', row.driverName)); who.append(link); tr.append(who, node('td', 'pu-engine', row.engineManufacturer || '—'));
                elements.forEach(element => { const used = row.used[element.code], quota = Number(element.quota), cell = node('td', powerUnitClass(used, quota)); cell.append(node('b', '', used == null ? '—' : String(used))); if (used != null && quota > 0) cell.append(node('small', '', `/${quota}`)); cell.tabIndex = 0; cell.dataset.popover = `${row.driverName} · ${element.name}: ${used == null ? 'not reported' : used}${quota > 0 ? ` / ${quota} allowed` : ''}${quota > 0 && used > quota ? ' · Allocation exceeded; see official penalty decisions below.' : ''}`; tr.append(cell); });
                const total = elements.reduce((sum, e) => sum + (Number(row.used[e.code]) || 0), 0); tr.append(node('td', 'pu-total', String(total)));
            });
            if (!rows.length) { const td = body.insertRow().insertCell(); td.colSpan = elements.length + 3; td.className = 'empty'; td.textContent = data.usage.length ? 'No drivers match the selected filters.' : 'No recorded power unit usage for this season.'; card.querySelector('.standings-download').disabled = true; }
            if (!elements.length && rows.length) card.append(node('p', 'empty', data.elements.length ? 'Select elements to display their usage.' : 'Season element allocations are unavailable.'));
            scroll.append(table); card.append(scroll); const legend = node('div', 'pu-allocation-legend'); for (const [cls, text] of [['pu-within', 'Within allocation'], ['pu-limit', 'At allocation'], ['pu-over', 'Over allocation']]) legend.append(node('span', cls, text)); card.append(legend); grid.append(card);
            const totals = data.elements.filter(e => engineeringSelected(preference.elements, e.code)).map(e => ({ name: elementLabel(e.code), count: rows.reduce((sum, row) => sum + (Number(row.used[e.code]) || 0), 0) })).sort((a, b) => b.count - a.count);
            const totalsCard = engineeringBars('Elements Used by Component', totals); grid.append(totalsCard); content.append(grid);
            renderPowerUnitPenalties(content, data, preference);
            installSeasonPopovers(content);
        };
        filters.append(engineeringMulti('Constructors', [...new Set(data.usage.map(r => r.team))].sort(), preference, 'teams', render, true), engineeringMulti('Drivers', data.usage.map(r => r.driverCode).sort(), preference, 'drivers', render), engineeringMulti('Elements', data.elements.map(e => e.code), preference, 'elements', render)); render();
    }
    function engineeringDriverHref(row) {
        const driver = state.driversStandings.find(d => driverCode(d).normalize('NFD').replace(/[\u0300-\u036f]/g, '') === row.driverCode);
        return driver ? driverPageHref(`drivers/${encodeURIComponent(driver.driverId)}`) : driverPageHref('drivers');
    }
    function renderPowerUnitPenalties(content, data, preference) {
        const card = standingsCard('Power Unit Grid Penalties'); card.classList.add('pu-penalties');
        const rows = data.penalties.filter(p => engineeringSelected(preference.teams, p.constructorName) && engineeringSelected(preference.drivers, p.driverCode) && (preference.elements === null || p.elements?.some(code => engineeringSelected(preference.elements, elementKey(code)))));
        if (!rows.length) { engineeringEmpty(card, data.meta.sections?.penalties?.unavailable ? 'Penalty reports could not be loaded.' : data.penalties.length ? 'No penalties match the selected filters.' : 'No reported power unit grid penalties for this season.'); content.append(card); return; }
        const penalties = engineeringPenaltyRows(rows);
        const allTable = node('table', 'pu-export-table'); allTable.hidden = true; const exportHead = allTable.createTHead().insertRow();['ROUND', 'DRIVER', 'COMPONENTS CHANGED', 'PENALTY', 'STARTING'].forEach(t => exportHead.append(node('th', '', t))); const exportBody = allTable.createTBody(); card.append(allTable);
        [...new Set(penalties.map(p => p.round))].sort((a, b) => b - a).forEach(round => {
            const roundPenalties = penalties.filter(p => p.round === round).sort((a, b) => a.gridPositions - b.gridPositions || String(a.driverName).localeCompare(b.driverName)), group = node('section', 'pu-penalty-group'), header = node('h3', 'pu-penalty-heading'), first = roundPenalties[0];
            const country = String(first.grandPrixName || '').replace(/ Grand Prix$/, '').replace(/^São Paulo$/, 'Brazil'), flag = flatFlag({ country, countryCode: engineeringCountry(country) }); if (engineeringCountry(country)) header.append(node('span', 'round-badge', `R${round}`), flag); header.append(node('span', '', country)); group.append(header);
            const scroll = node('div', 'engineering-table-scroll'), table = node('table', 'pu-penalty-table'), head = table.createTHead().insertRow();['DRIVER', 'COMPONENTS CHANGED', 'PENALTY', 'STARTING'].forEach(t => head.append(node('th', '', t))); const body = table.createTBody();
            roundPenalties.forEach(p => {
                const tr = body.insertRow(), who = node('td'), link = node('a', 'pu-driver'); link.href = engineeringDriverHref(p); const logo = manufacturerLogo(p.constructorName); if (logo) link.append(logo); link.append(node('span', '', p.driverName)); who.append(link); if (p.allocationDriverName && p.allocationDriverName !== p.driverName) who.append(node('small', 'pu-allocation-owner', `PU allocation: ${p.allocationDriverName}`)); tr.append(who);
                const changes = node('td', 'pu-changes'); (p.penaltyItems || []).forEach(item => { const chip = node('span', 'pu-component-chip'); chip.append(node('small', '', item.elementNumber ? `#${item.elementNumber}` : ''), node('span', '', elementLabel(elementKey(item.elementCode))), node('b', '', `+${item.gridPositions}`)); changes.append(chip); }); if (!changes.children.length) changes.textContent = (p.elements || []).map(code => elementLabel(elementKey(code))).join(', '); tr.append(changes);
                const penalty = node('td'); penalty.append(node('span', 'pu-penalty-badge', `${p.gridPositions} places`)); const starting = node('td', 'pu-starting', p.startsFromPitLane ? 'Pit lane' : p.startingPosition ? `P${p.startingPosition}` : 'Back of the field'); if (p.pitLaneReason) starting.dataset.popover = p.pitLaneReason; tr.append(penalty, starting);
                const exportRow = exportBody.insertRow();[String(round), p.driverName, changes.textContent, `${p.gridPositions} places`, starting.textContent].forEach(text => exportRow.append(node('td', '', text)));
                const sources = (p.sourceDocuments || []).filter(s => { try { return new URL(s.url).hostname === 'www.fia.com'; } catch { return false; } });
                if (sources.length) { const source = node('a', 'pu-source-link', 'ⓘ'); source.href = sources[0].url; source.target = '_blank'; source.rel = 'noopener noreferrer'; source.setAttribute('aria-label', `FIA decision for ${p.driverName}, round ${round}`); source.title = 'View FIA decision'; starting.append(source); }

            }); scroll.append(table); group.append(scroll); card.append(group);
        }); content.append(card);
    }
    /* Crash reports contain the published corrections. Never apply the audit diffs twice. */
    const crashMoney = value => new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 }).format(value);
    const crashCompact = value => value >= 1e6 ? `$${Number((value / 1e6).toFixed(2))}m` : value >= 1000 ? `$${Number((value / 1000).toFixed(1))}k` : crashMoney(value);
    function crashModel(source, preference) {
        const rows = source.filter(row => engineeringSelected(preference.teams, row.team) && engineeringSelected(preference.drivers, row.driverName));
        const drivers = new Map(), teams = new Map(), components = new Map(), events = new Map();
        for (const row of rows) {
            const cost = row.components.reduce((sum, part) => sum + part.price * part.quantity, 0);
            let driver = drivers.get(row.driverId); if (!driver) { driver = { id: row.driverId, name: row.driverName, team: row.team, total: 0, rounds: new Map() }; drivers.set(row.driverId, driver); }
            driver.total += cost; driver.rounds.set(row.round, (driver.rounds.get(row.round) || 0) + cost);
            let team = teams.get(row.team); if (!team) { team = { name: row.team, total: 0, drivers: new Map(), rounds: new Map() }; teams.set(row.team, team); }
            team.total += cost; team.drivers.set(row.driverId, { name: row.driverName, total: (team.drivers.get(row.driverId)?.total || 0) + cost }); team.rounds.set(row.round, (team.rounds.get(row.round) || 0) + cost);
            const key = `${row.round}:${row.driverId}`; let event = events.get(key); if (!event) { event = { ...row, total: 0 }; events.set(key, event); } event.total += cost;
            row.components.forEach(part => {
                const key = `${part.componentId}:${part.price}`; let component = components.get(key);
                if (!component) { component = { name: part.name, price: part.price, quantity: 0, total: 0 }; components.set(key, component); }
                component.quantity += part.quantity; component.total += part.price * part.quantity;
            });
        }
        const ranked = values => [...values.values()].sort((a, b) => b.total - a.total || a.name.localeCompare(b.name));
        return { rows, drivers: ranked(drivers), teams: ranked(teams), components: ranked(components), events: [...events.values()].sort((a, b) => b.total - a.total || a.driverName.localeCompare(b.driverName)), meetings: engineeringMeetings(source, {}), total: [...teams.values()].reduce((sum, team) => sum + team.total, 0) };
    }
    function crashIdentity(name, team) {
        const who = node('span', 'crash-driver'); const logo = manufacturerLogo(team); if (logo) who.append(logo); who.append(node('span', '', name)); return who;
    }
    function crashTable(title, headers, rows, classes = '') {
        const card = standingsCard(title); card.classList.add('crash-table-card'); if (classes) card.classList.add(classes);
        const scroll = node('div', 'engineering-table-scroll'), table = node('table', 'crash-table');
        const head = table.createTHead().insertRow(); headers.forEach(text => head.append(node('th', '', text)));
        const body = table.createTBody(); rows.forEach(cells => { const tr = body.insertRow(); cells.forEach(value => { const td = node('td'); if (value instanceof Node) td.append(value); else td.textContent = String(value); tr.append(td); }); }); scroll.append(table); card.append(scroll);
        if (!rows.length) engineeringEmpty(card, 'No crash reports match the selected filters.'); return card;
    }
    function crashConstructorChart(model) {
        const W = 1000, H = 605, left = 50, right = 14, top = 30, bottom = 38, chart = driverChart('Constructor Crash Costs', W, H), { card, svg } = chart;
        if (!model.teams.length) { svg.remove(); return engineeringEmpty(card, 'No crash reports match the selected filters.'); }
        const max = Math.max(1, ...model.teams.map(t => t.total)), tick = crashTick(max), ceil = Math.ceil(max / tick) * tick, y = v => H - bottom - v / ceil * (H - top - bottom), step = (W - left - right) / model.teams.length;
        crashAxis(svg, { left, right, top, bottom, W, H, ceil, tick });
        model.teams.forEach((team, i) => {
            const x = left + step * (i + .08), width = step * .9, color = engineeringColor(team.name); let total = 0;
            [...team.drivers.values()].sort((a, b) => b.total - a.total).forEach(driver => {
                const height = driver.total / ceil * (H - top - bottom); total += driver.total;
                const bar = chartShape(svg, 'rect', { x, y: y(total), width, height, fill: color, stroke: 'var(--card)', 'stroke-width': 1 }); chartTip(bar, `${team.name} · ${driver.name}: ${crashMoney(driver.total)}`);
                if (height > 20) chartShape(svg, 'text', { x: x + width / 2, y: y(total) + height / 2 + 4, 'text-anchor': 'middle', 'font-size': 10, 'font-weight': 650, fill: crashInk(team.name) }, crashCompact(driver.total));
            });
            chartShape(svg, 'text', { x: x + width / 2, y: y(team.total) - 7, 'text-anchor': 'middle', 'font-size': 10, 'font-weight': 700, fill: 'var(--text)' }, crashCompact(team.total));
            const logo = manufacturerLogo(team.name); if (logo) chartShape(svg, 'image', { href: logo.src, x: x + width / 2 - 15, y: H - 27, width: 30, height: 20 });
        }); return card;
    }
    function crashInk(team) { return ['haas', 'williams', 'mercedes', 'cadillac', 'rb', 'mclaren'].includes(teamKey(team)) ? '#101114' : '#fff'; }
    function crashTick(max) { const magnitude = 10 ** Math.floor(Math.log10(Math.max(max, 1))); return [1, 2, 5, 10].map(n => n * magnitude / 10).find(t => max / t <= 8) || magnitude; }
    function crashAxis(svg, { left, right, bottom, W, H, ceil, tick }) {
        for (let value = 0; value <= ceil; value += tick) { const y = H - bottom - value / ceil * (H - bottom - 30); chartShape(svg, 'line', { x1: left, y1: y, x2: W - right, y2: y, stroke: 'currentColor', opacity: .15 }); chartShape(svg, 'text', { x: left - 8, y: y + 3, 'text-anchor': 'end', 'font-size': 10, fill: 'currentColor' }, crashCompact(value)); }
    }
    function crashEvolution(model, constructors = false) {
        const title = `Cumulative ${constructors ? 'Constructor' : 'Driver'} Crash Costs`, W = 1000, H = 615, left = 52, right = 14, top = 30, bottom = 35, { card, svg } = driverChart(title, W, H), series = constructors ? model.teams : model.drivers;
        if (!series.length) { svg.remove(); return engineeringEmpty(card, 'No crash reports match the selected filters.'); }
        const max = Math.max(...series.map(s => s.total), 1), tick = crashTick(max), ceil = Math.ceil(max / tick) * tick, x = i => left + i * (W - left - right) / Math.max(1, model.meetings.length - 1), y = v => H - bottom - v / ceil * (H - top - bottom);
        crashAxis(svg, { left, right, top, bottom, W, H, ceil, tick });
        model.meetings.forEach((meeting, i) => chartFlag(svg, meeting, x(i), H - 18, 15));
        const highlight = id => svg.querySelectorAll('[data-crash-series]').forEach(shape => shape.style.opacity = !id || shape.dataset.crashSeries === id ? '1' : '.12');
        [...series].reverse().forEach((item, index) => {
            const color = engineeringColor(constructors ? item.name : item.team), id = String(index); let total = 0;
            const points = model.meetings.map((meeting, i) => { total += item.rounds.get(meeting.round) || 0; return { x: x(i), y: y(total), total, meeting }; });
            const line = chartShape(svg, 'polyline', { points: points.map(p => `${p.x},${p.y}`).join(' '), fill: 'none', stroke: color, 'stroke-width': 1.8 }); line.dataset.crashSeries = id;
            points.forEach(p => { const dot = chartTip(chartShape(svg, 'circle', { cx: p.x, cy: p.y, r: 2.1, fill: color }), `${item.name} · ${p.meeting.round === 0 ? 'Pre-season' : `R${p.meeting.round}`} ${p.meeting.country}: ${crashMoney(p.total)}`); dot.dataset.crashSeries = id; dot.onmouseenter = dot.onfocus = () => highlight(id); dot.onmouseleave = dot.onblur = () => highlight(null); });
        }); return card;
    }
    function crashEventChart(model) {
        const W = 1000, H = Math.max(180, model.meetings.length * 21 + 42), left = 27, right = 57, top = 8, bottom = 36, { card, svg } = driverChart('Crash Costs by Event (by Driver)', W, H);
        if (!model.rows.length) { svg.remove(); return engineeringEmpty(card, 'No crash reports match the selected filters.'); }
        const totals = model.meetings.map(meeting => model.events.filter(e => e.round === meeting.round).reduce((sum, e) => sum + e.total, 0)), max = Math.max(...totals, 1), tick = crashTick(max), ceil = Math.ceil(max / tick) * tick, x = v => left + v / ceil * (W - left - right);
        for (let value = 0; value <= ceil; value += tick) { chartShape(svg, 'line', { x1: x(value), y1: top, x2: x(value), y2: H - bottom, stroke: 'currentColor', opacity: .15 }); chartShape(svg, 'text', { x: x(value), y: H - 13, 'text-anchor': 'middle', 'font-size': 10, fill: 'currentColor' }, crashCompact(value)); }
        model.meetings.forEach((meeting, i) => {
            const y = top + i * 21; chartFlag(svg, meeting, 12, y + 4, 15); let total = 0;
            model.events.filter(e => e.round === meeting.round).forEach(event => { const bar = chartShape(svg, 'rect', { x: x(total), y, width: x(event.total) - left, height: 20, rx: 1, fill: engineeringColor(event.team), stroke: 'var(--card)', 'stroke-width': 1 }); chartTip(bar, `${event.driverName} · ${meeting.country}: ${crashMoney(event.total)}`); total += event.total; });
            chartShape(svg, 'text', { x: x(total) + 5, y: y + 14, 'font-size': 10, 'font-weight': 600, fill: 'var(--text)' }, crashCompact(total));
        }); return card;
    }
    function crashCorrections(data) {
        const block = node('div', 'crash-source'); block.append(node('p', '', 'Figures are observations and estimates from the PitPulse archive, not official repair costs.'));
        if (data.meta.sections?.corrections?.unavailable) { block.append(node('p', '', 'Correction history is currently unavailable.')); return block; }
        const details = node('details', 'crash-corrections'), rows = data.corrections || []; details.append(node('summary', '', `${rows.length} corrections have been made to the source data.`));
        rows.forEach(row => { const item = node('div', 'crash-correction'); item.append(node('strong', '', `R${row.round} · ${row.driverSeason?.driver?.name || 'Unknown'} · ${row.components?.name || 'Component'}`), node('p', '', `${row.diff === 'removed' ? 'Removed' : 'Added'} ×${row.quantity} · ${row.note || 'Source correction'}`)); details.append(item); }); block.append(details); return block;
    }
    function renderDestructors(root) {
        const view = 'destructors-championship', season = driverPages.season, data = engineeringData(view, season), preference = engineeringPreference(view, season), filters = engineeringHead(root, 'Destructors Championship', view, season), content = node('div', 'engineering-content'); root.append(content);
        const render = () => {
            content.replaceChildren(); if (engineeringStatus(content, data, view)) return;
            const model = crashModel(data.rows, preference), grid = node('div', 'destructors-grid'), aside = node('aside', 'crash-sidebar'), main = node('div', 'crash-main');
            aside.append(crashTable('Driver Crash Standings', ['POS.', 'DRIVER', 'TOTAL COSTS'], model.drivers.map((driver, i) => [i + 1, crashIdentity(driver.name, driver.team), crashMoney(driver.total)]), 'crash-standings'), crashCorrections(data));
            const components = crashTable('Crash Costs by Component', ['COMPONENT', 'UNIT PRICE', 'QUANTITY', 'TOTAL COST'], model.components.map(part => [part.name, crashMoney(part.price), part.quantity, crashMoney(part.total)]));
            const footer = components.querySelector('table').createTFoot().insertRow(); footer.append(node('td', '', 'TOTAL'), node('td'), node('td'), node('td', '', crashMoney(model.total)));
            const expensive = crashTable('Most Expensive Crashes', ['RANK', 'DRIVER', 'GRAND PRIX', 'TOTAL COST'], model.events.filter(event => event.total > 0).slice(0, 30).map((event, i) => { const location = node('span', 'crash-event-name'); location.append(flatFlag({ country: event.country, countryCode: engineeringCountry(event.country) }), node('span', '', event.round === 0 ? `${event.country} · Pre-season` : event.country)); return [i + 1, event.driverName, location, crashMoney(event.total)]; }));
            main.append(crashConstructorChart(model), crashEvolution(model), crashEvolution(model, true), crashEventChart(model), components, expensive); grid.append(aside, main); content.append(grid); installSeasonPopovers(content);
        };
        filters.append(engineeringMulti('Drivers', [...new Set(data.rows.map(row => row.driverName))].sort(), preference, 'drivers', render), engineeringMulti('Constructors', [...new Set(data.rows.map(row => row.team))].sort(), preference, 'teams', render, true)); render();
    }

    function renderEngineering(root) {
        if (state.view === 'tech-updates') renderTechUpdates(root); else if (state.view === 'destructors-championship') renderDestructors(root); else renderPowerUnit(root);
    }

    /* ---------- Home: season overview and evidence from stored race results ---------- */
    const homePages = { cache: new Map(), category: 'All', geometry: new Map() };
    function homeData(season) {
        if (homePages.cache.has(season)) return homePages.cache.get(season);
        const data = { loading: true, summary: {}, drivers: [], constructors: [], entries: [], calendar: [], errors: [], meta: {} }; homePages.cache.set(season, data);
        const tasks = [['summary', `/api/v1/home?season=${season}`], ['drivers', `/api/v1/standings/drivers?season=${season}`], ['constructors', `/api/v1/standings/constructors?season=${season}`], ['calendar', `/api/v1/calendar?season=${season}`], ['entries', `/api/v1/results/season?season=${season}`]];
        Promise.allSettled(tasks.map(async ([key, url]) => { try { const { body } = await api(url); data[key] = body.data; data.meta[key] = body.meta || {}; } catch { data.errors.push(key); } })).finally(() => { data.loading = false; if (state.view === 'home' && driverPages.season === season) renderDriverPages(); }); return data;
    }
    function homeSchedule(calendar, entries, now = Date.now()) {
        const meetings = calendar.filter(m => m.round != null && m.status !== 'cancelled' && m.status !== 'postponed').sort((a, b) => (a.round || 0) - (b.round || 0));
        const sessions = meetings.flatMap(meeting => (meeting.sessions || []).filter(session => !['cancelled', 'postponed', 'finished'].includes(session.status)).map(session => ({ meeting, session, start: Date.parse(session.startTime), end: Date.parse(session.endTime) || Date.parse(session.startTime) + 7200000 }))).filter(s => Number.isFinite(s.start)).sort((a, b) => a.start - b.start);
        const current = sessions.find(s => s.start <= now && s.end > now), next = sessions.find(s => s.start > now), display = (current || next)?.meeting || meetings.at(-1);
        const completed = new Set(entries.filter(entry => sessionRows(entry, 'race').length).map(entry => entry.meeting.id));
        return { current, next, display, completed: meetings.filter(m => completed.has(m.id)).length, total: meetings.length };
    }
    function homeRecords(data) {
        const records = [], rookies = new Set((data.summary.drivers || []).filter(d => d.rookie).map(d => String(d.driverNumber)));
        const add = (entry, category, title, description, type = 'race') => records.push({ category, title, description, meeting: entry.meeting, date: entry.meeting.sessions?.find(s => s.sessionType === type)?.startTime || entry.meeting.endDate, href: `/results/${encodeURIComponent(entry.meeting.id)}/${type}?season=${driverPages.season}` });
        [...data.entries].sort((a, b) => (b.meeting.round || 0) - (a.meeting.round || 0)).forEach(entry => {
            const race = sessionRows(entry, 'race').filter(r => r.position > 0).sort((a, b) => a.position - b.position), winner = race.find(r => r.position === 1);
            if (!winner) return; const place = entry.meeting.location || entry.meeting.country;
            add(entry, 'Race', `${shortDriverName(winner)} wins in ${place}`, `${winner.driverName} took first place for ${winner.team}${winner.laps ? ` after ${winner.laps} laps` : ''}.`);
            const teams = new Map(); race.filter(r => r.position <= 3).forEach(r => { const key = r.constructorId || r.team; if (!teams.has(key)) teams.set(key, []); teams.get(key).push(r); });
            teams.forEach(rows => { if (rows.length > 1) add(entry, 'Team', `${cleanTeamName(rows[0].team)} takes a double podium`, `${rows.map(r => `${r.driverName} (P${r.position})`).join(' and ')} finished on the podium in ${place}.`); });
            const gain = race.filter(r => !retiredResult(r) && r.gridPosition > 0 && r.gridPosition > r.position).sort((a, b) => (b.gridPosition - b.position) - (a.gridPosition - a.position))[0];
            if (gain) add(entry, 'Driver', `${shortDriverName(gain)} gains ${gain.gridPosition - gain.position} places in ${place}`, `${gain.driverName} started P${gain.gridPosition} and finished P${gain.position} for ${gain.team}.`);
            const rookie = race.find(r => rookies.has(String(r.driverNumber))); if (rookie) add(entry, 'Rookie', `${shortDriverName(rookie)} finishes P${rookie.position}`, `${rookie.driverName}, listed as a rookie this season, finished P${rookie.position} in ${place}.`);
            const qualifying = sessionRows(entry, 'qualifying').flatMap(row => ['q1', 'q2', 'q3', 'bestLap'].filter(key => Number.isFinite(lapSeconds(row[key]))).map(key => ({ row, time: row[key], seconds: lapSeconds(row[key]) }))).sort((a, b) => a.seconds - b.seconds)[0];
            if (qualifying) add(entry, 'Track', `${shortDriverName(qualifying.row)} sets the fastest qualifying lap`, `${qualifying.time} at ${entry.meeting.circuit?.name || place}, the quickest time in the available qualifying results.`, 'qualifying');
        }); return records;
    }
    function homeMetric(title, value, href, icon, summary, negative = false) {
        const card = node(href ? 'a' : 'section', 'home-card home-metric'); if (href) card.href = href;
        const heading = node('div', 'home-metric-head'); heading.append(node('h2', '', title), svgIcon(icon, 'home-metric-icon')); card.append(heading);
        const main = node('div', 'home-metric-value'); main.append(node('strong', '', value));
        const difference = summary?.difference ?? summary?.lastRace;
        if (Number.isFinite(difference)) { const delta = node('span', `home-delta${negative ? ' is-cost' : ''}`, `${difference >= 0 ? '↗' : '↘'} ${negative ? crashMoney(difference) : pointsText(difference)}`); main.append(delta); }
        card.append(main);
        if (Number.isFinite(summary?.percentage) && Number.isFinite(difference)) card.append(node('p', 'home-metric-note', `${difference >= 0 ? '+' : ''}${summary.percentage}% vs prev. round`));
        else card.append(node('p', 'home-metric-note', value === '—' ? 'Data unavailable' : 'Season total'));
        return card;
    }
    function homeStandings(data, constructors, season) {
        const title = `${season} ${constructors ? 'Constructor' : 'Driver'} Standings`, card = node('section', 'home-card home-standings'), heading = node('h2', '', title); card.append(heading);
        const scroll = node('div', 'home-table-scroll'), table = node('table', 'home-standings-table'), head = table.createTHead().insertRow();['POS.', constructors ? 'CONSTRUCTOR' : 'DRIVER', 'POINTS', 'EVO.'].forEach(t => head.append(node('th', '', t))); const body = table.createTBody();
        const rows = [...(constructors ? data.constructors : data.drivers)].sort((a, b) => a.position - b.position).slice(0, 10), leader = rows[0]?.points || 0;
        rows.forEach(row => {
            const tr = body.insertRow(), who = node('td'), team = constructors ? row.name || row.constructorName || row.constructor : row.constructor, name = constructors ? cleanTeamName(team) : shortDriverName(row), identity = node('a', 'home-standing-name'); identity.href = constructors ? `/constructor-standings?season=${season}` : driverPageHref(`drivers/${encodeURIComponent(row.driverId)}`); const logo = manufacturerLogo(team); if (logo) identity.append(logo); identity.append(node('span', '', name)); who.append(identity);
            const score = node('td', 'home-standing-points'); score.append(node('b', '', pointsText(row.points))); if (row.position > 1) score.append(node('small', '', `-${pointsText(leader - row.points)}`));
            const evolution = row.evolution; tr.append(node('td', '', row.position), who, score, node('td', evolution > 0 ? 'home-up' : evolution < 0 ? 'home-down' : 'home-neutral', Number.isFinite(evolution) && evolution !== 0 ? `${evolution > 0 ? '↑' : '↓'} ${Math.abs(evolution)}` : '—'));
        }); scroll.append(table); card.append(scroll);
        if (!rows.length) card.append(node('p', 'empty', data.errors.includes(constructors ? 'constructors' : 'drivers') ? 'Standings could not be loaded.' : 'No standings available for this season.'));
        const more = node('a', 'home-full-link', `Full ${season} ${constructors ? 'Constructor' : 'Driver'} Standings →`); more.href = `/${constructors ? 'constructor' : 'driver'}-standings?season=${season}`; card.append(more); return card;
    }
    function homeRecordPanel(data, season) {
        const panel = node('section', 'home-card home-records'), header = node('header', 'home-records-head'), filters = node('div', 'home-record-filters'); filters.setAttribute('role', 'group'); filters.setAttribute('aria-label', 'Stats and records category'); header.append(node('h2', '', `${season} Stats & Records`), filters); panel.append(header);
        const list = node('div', 'home-record-list'); list.setAttribute('aria-live', 'polite'); const records = homeRecords(data);
        const render = () => {
            list.replaceChildren(); filters.querySelectorAll('button').forEach(button => button.setAttribute('aria-pressed', String(button.textContent === homePages.category)));
            records.filter(record => homePages.category === 'All' || record.category === homePages.category).forEach(record => {
                const item = node('a', 'home-record'); item.href = record.href; const tag = node('span', `home-record-tag home-record-${record.category.toLowerCase()}`, record.category.toUpperCase()); item.append(tag, node('h3', '', record.title), node('p', '', record.description));
                const footer = node('footer', 'home-record-meta'), where = node('span', ''); where.append(flatFlag(record.meeting), node('span', '', record.meeting.location || record.meeting.country)); const date = parseDate(record.date); footer.append(where, node('time', '', date ? new Intl.DateTimeFormat('en-GB', { day: '2-digit', month: 'short' }).format(date) : '')); item.append(footer); list.append(item);
            }); if (!list.childElementCount) list.append(node('p', 'empty', data.errors.includes('entries') ? 'Race results could not be loaded.' : 'No records in this category for the selected season.')); list.scrollTop = 0;
        };
        ['All', 'Team', 'Driver', 'Rookie', 'Race', 'Track'].forEach(category => { const button = node('button', '', category); button.type = 'button'; button.onclick = () => { homePages.category = category; render(); }; filters.append(button); }); panel.append(list); render(); return panel;
    }
    function homeTrackOutline(card, meeting, season) {
        if (!meeting) return; const key = `${season}:${meeting.id}`;
        const draw = body => {
            const coordinates = body?.geometry?.geometry?.coordinates; if (!Array.isArray(coordinates) || coordinates.length < 2 || !card.isConnected) return;
            const lat = coordinates.reduce((sum, p) => sum + p[1], 0) / coordinates.length, ratio = Math.cos(lat * Math.PI / 180), points = coordinates.map(p => [p[0] * ratio, -p[1]]), xs = points.map(p => p[0]), ys = points.map(p => p[1]), minX = Math.min(...xs), minY = Math.min(...ys), width = Math.max(...xs) - minX, height = Math.max(...ys) - minY, scale = Math.min(150 / Math.max(width, .00001), 95 / Math.max(height, .00001));
            const rotator = node('div', 'home-track-rotator');
            const svg = standingsSvg(180, 125, `${meeting.circuit?.name || meeting.country} circuit outline`); svg.classList.add('home-track-outline');
            const defs = chartShape(svg, 'defs', {}), gradient = chartShape(defs, 'linearGradient', { id: `track-gradient-${season}`, x1: '0%', y1: '0%', x2: '100%', y2: '0%' });
            chartShape(gradient, 'stop', { offset: '0%', 'stop-color': '#1dd6b2' }); chartShape(gradient, 'stop', { offset: '100%', 'stop-color': 'var(--red)' });
            // Center the scaled geometry, not its top-left padding, on the rotation axis.
            const offsetX = (180 - width * scale) / 2, offsetY = (125 - height * scale) / 2;
            const coords = points.map(p => [offsetX + (p[0] - minX) * scale, offsetY + (p[1] - minY) * scale]);
            const closed = Math.hypot(coords[0][0] - coords.at(-1)[0], coords[0][1] - coords.at(-1)[1]) < 2;
            const pathData = `M${coords.map(([x, y]) => `${x} ${y}`).join(' L')}${closed ? ' Z' : ''}`;
            chartShape(svg, 'path', { d: pathData, fill: 'none', 'stroke-width': 2.5, 'stroke-linecap': 'round', 'stroke-linejoin': 'round', class: 'home-track-base' });
            chartShape(svg, 'path', { d: pathData, pathLength: 1000, fill: 'none', stroke: `url(#track-gradient-${season})`, 'stroke-width': 3.5, 'stroke-linecap': 'round', 'stroke-linejoin': 'round', class: 'home-track-path' });
            svg.style.setProperty('--path-length', '1000'); rotator.append(svg); card.append(rotator);
        };
        if (homePages.geometry.has(key)) { queueMicrotask(() => draw(homePages.geometry.get(key))); return; }
        api(`/api/v1/meetings/${encodeURIComponent(meeting.id)}/geometry`).then(({ body }) => { homePages.geometry.set(key, body.data || body); draw(body.data || body); }).catch(() => { });
    }
    function updateHomeCountdown() {
        document.querySelectorAll('[data-home-countdown]').forEach(clock => {
            const target = Number(clock.dataset.homeCountdown); if (!Number.isFinite(target)) return; let remaining = Math.max(0, Math.floor((target - Date.now()) / 1000));
            const values = [Math.floor(remaining / 86400), Math.floor(remaining % 86400 / 3600), Math.floor(remaining % 3600 / 60), remaining % 60];
            clock.querySelectorAll('b').forEach((cell, i) => cell.textContent = String(values[i]).padStart(2, '0')); if (target <= Date.now() && !clock.dataset.expired) { clock.dataset.expired = '1'; renderDriverPages(); }
        });
    }
    function renderHome(root) {
        const season = driverPages.season, data = homeData(season), filters = engineeringHead(root, 'Home', 'home', season); filters.parentElement.classList.add('home-page-head');
        if (data.loading) { setLoading('Loading season overview…'); return; }
        const retry = () => { homePages.cache.delete(season); renderDriverPages(); };
        const unavailable = Object.entries(data.meta.summary?.sections || {}).filter(([, meta]) => meta.unavailable).map(([key]) => key), stale = Object.values(data.meta).some(meta => meta.stale);

        const schedule = homeSchedule(data.calendar, data.entries), cards = node('div', 'home-summary-grid'), summary = data.summary, unavailableSummary = key => data.errors.includes('summary') || data.meta.summary?.sections?.[key]?.unavailable;
        const counter = node('a', 'home-card home-countdown'), active = schedule.current || schedule.next; counter.href = schedule.display ? `/results/${encodeURIComponent(schedule.display.id)}/${active?.session.sessionType || 'race'}?season=${season}` : `/results?season=${season}`;
        if (active) {
            const heading = node('h2', ''); heading.append(node('span', 'home-round', `R${active.meeting.round}`), node('span', '', `${active.meeting.location || active.meeting.country}: ${{ fp1: 'Practice 1', fp2: 'Practice 2', fp3: 'Practice 3', qualifying: 'Qualifying', race: 'Race', sprint: 'Sprint', sprintQualifying: 'Sprint Qualifying' }[active.session.sessionType] || active.session.sessionType}`)); counter.append(heading);
            if (schedule.current) { counter.append(node('strong', 'home-session-live', 'Session underway'), node('p', '', new Intl.DateTimeFormat('en-GB', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(active.start)))); }
            else { const clock = node('div', 'home-countdown-clock'); clock.dataset.homeCountdown = String(active.start);['DAYS', 'HRS', 'MINS', 'SEC'].forEach(label => { const unit = node('span', ''); unit.append(node('b', '', '00'), node('small', '', label)); clock.append(unit); }); counter.append(clock); }
        } else { counter.append(node('h2', '', `${season} Season`), node('strong', 'home-session-live', schedule.total ? 'Season complete' : 'Schedule unavailable'), node('p', '', schedule.total ? 'Explore this season’s results and records.' : 'No sessions have been published.')); } cards.append(counter);
        const scheduleCard = node('section', 'home-card home-schedule'); scheduleCard.append(node('h2', '', `${season} Schedule`));
        const place = node('strong', 'home-schedule-place'); if (schedule.display) place.append(flatFlag(schedule.display), node('span', '', schedule.display.location || schedule.display.country)); else place.textContent = 'No schedule'; scheduleCard.append(place);
        const progress = node('div', 'home-progress'), segments = node('span', 'home-progress-segments'); for (let i = 0; i < schedule.total; i++) { const segment = node('i'); if (i < schedule.completed) segment.classList.add('is-complete'); segments.append(segment); } progress.append(segments, node('b', '', `${schedule.total ? Math.round(schedule.completed / schedule.total * 100) : 0}%`)); progress.setAttribute('aria-label', `${schedule.completed} of ${schedule.total} races with results`); scheduleCard.append(progress); cards.append(scheduleCard);
        const pit = Array.isArray(summary.pitStop) ? summary.pitStop[0] : null, pitCard = homeMetric(`${season} Fastest Pit Stop`, pit && !unavailableSummary('pitStop') ? `${Number(pit.time).toFixed(2)} s` : '—', null, 'M12 8v5l3 2M9 2h6M19 5l2 2M21 13a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z');
        pitCard.querySelector('.home-metric-note').replaceChildren(); if (pit) { const note = pitCard.querySelector('.home-metric-note'), logo = manufacturerLogo(pit.team); if (logo) note.append(logo); note.append(node('span', '', `${pit.driverName} · Round ${pit.round}`), flatFlag({ country: pit.country, countryCode: engineeringCountry(pit.country) }), node('span', '', pit.country)); } pitCard.tabIndex = 0; pitCard.dataset.popover = 'Fastest recorded stationary pit stop for the selected season. Source: PitPulse timing archive.'; cards.append(pitCard);
        cards.append(homeMetric(`${season} Crash Damage Total Costs`, !unavailableSummary('crashes') && Number.isFinite(summary.crashes?.seasonTotal) ? crashMoney(summary.crashes.seasonTotal) : '—', `/destructors-championship?season=${season}`, 'M15 6l3-3m-1-2c3 0 1 4 5 4M18 14a8 8 0 1 1-16 0 8 8 0 0 1 16 0Z', summary.crashes, true));
        const coverageNote = key => {
            const meta = data.meta.summary?.sections?.[key], rounds = meta?.coverage?.rounds || [];
            if (meta?.unavailable) return 'Data unavailable';
            if (!rounds.length) return 'Coverage unavailable';
            const latest = Math.max(...rounds);
            return meta.coverage.complete ? 'Complete season archive' : `Through Round ${latest} · partial season`;
        };
        const puMetric = homeMetric(`${season} Total PU Elements Used`, !unavailableSummary('pu') && Number.isFinite(summary.pu?.total) ? pointsText(summary.pu.total) : '—', `/pu-elements?season=${season}`, 'M9 3h6l1 3 3 1 2 5-2 5-3 1-1 3H9l-1-3-3-1-2-5 2-5 3-1 1-3ZM12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8Z', summary.pu);
        puMetric.querySelector('.home-metric-note').textContent = coverageNote('pu'); cards.append(puMetric);
        const techMetric = homeMetric(`${season} Total Tech Upgrades`, !unavailableSummary('tech') && Number.isFinite(summary.tech?.total) ? pointsText(summary.tech.total) : '—', `/tech-updates?season=${season}`, 'M14 6a5 5 0 0 0-6 6L2 18l4 4 6-6a5 5 0 0 0 6-6l-4 4-4-4 4-4Z', summary.tech);
        techMetric.querySelector('.home-metric-note').textContent = coverageNote('tech'); cards.append(techMetric);
        const social = node('section', 'home-card home-social'); social.append(node('p', '', 'Support PitPulse and help us build a better racing companion.')); const support = node('a', 'home-support-button', 'Support Us on GitHub'); support.href = 'https://github.com/aczeccssa/PitPulse'; support.target = '_blank'; support.rel = 'noopener noreferrer'; support.append(svgIcon('M14 5h5v5m0-5-7 7M5 7v12h12v-5')); social.append(support); cards.append(social);
        const promo = node('a', 'home-card home-app-promo'); promo.href = 'https://github.com/aczeccssa/PitPulse'; promo.target = '_blank'; promo.rel = 'noopener noreferrer';
        const appIcon = artImage('home-app-icon', mediaSrc('icon-192', '/icon-192.png')); appIcon.alt = ''; const promoCopy = node('div', 'home-app-copy'); promoCopy.append(node('span', 'home-app-platforms', 'macOS · iOS'), node('h2', '', 'PitPulse'), node('p', '', 'Your race. Always in reach.'), node('span', 'home-app-cta', 'Explore the App ↗')); promo.append(appIcon, promoCopy); cards.append(promo); root.append(cards);
        const lower = node('div', 'home-detail-grid'); lower.append(homeStandings(data, false, season), homeStandings(data, true, season), homeRecordPanel(data, season)); root.append(lower); homeTrackOutline(scheduleCard, schedule.display, season); updateHomeCountdown(); installSeasonPopovers(root);
    }

    function meetingFlag(meeting) {
        return /^[A-Z]{2}$/.test(meeting.countryCode || "") ? String.fromCodePoint(...[...meeting.countryCode].map(c => 127397 + c.charCodeAt(0))) : "";
    }

    function lapSeconds(value) {
        if (!/^\d+:\d{2}\.\d+$/.test(value || "")) return Infinity;
        return String(value).split(":").map(Number).reduce((a, b) => a * 60 + b, 0);
    }

    function grandPrixLabel(meeting) {
        const label = node("span", "gp-name");
        label.append(flatFlag(meeting), node("span", "round-badge", `R${meeting.round}`), node("span", "", resultsGpName(meeting.name)));
        return label;
    }

    function renderRecordChart(entries) {
        const section = seasonSection("Grand Prix Weekend Fastest Laps vs Track Records"); section.classList.add("record-section");
        const toolbar = node("div", "record-toolbar"); const label = node("label", "", "Sort by: "); const select = node("select", "");
        for (const [value, text] of [["round", "Grand Prix"], ["gap", "Gap to record"]]) { const option = node("option", "", text); option.value = value; select.append(option); }
        label.append(select); const download = node("button", "record-download", "⇩"); download.type = "button"; download.setAttribute("aria-label", "Download chart as SVG"); toolbar.append(label, download); const recordBar = node("div", "results-titlebar"); recordBar.append(section.querySelector("h2"), toolbar); section.append(recordBar);
        section.append(node("p", "record-description", `Each weekend’s fastest archived lap across all sessions, compared with the best lap from earlier weekends at the same circuit in the PitPulse archive (since ${seasonYears().at(-1) || defaultSeason()}).`));
        const scroll = node("div", "season-scroll record-scroll"); section.append(scroll);
        const rows = entries.map(({ meeting, fastestLaps }) => {
            const best = fastestLaps?.weekend, record = fastestLaps?.previous;
            return { meeting, best, record, gap: best && record ? (best.millis - record.millis) / 1000 : null };
        });
        if (!rows.length) {
            scroll.append(node("p", "empty", "No weekend lap times are available."));
            download.disabled = true;
            return section;
        }
        let drawnWidth = 0;
        function draw() {
            const data = [...rows].sort(select.value === "gap" ? (a, b) => (a.gap ?? Infinity) - (b.gap ?? Infinity) : (a, b) => a.meeting.round - b.meeting.round);
            const W = drawnWidth = Math.max(1080, scroll.clientWidth);
            const top = 56, rowHeight = 30, H = top + data.length * rowHeight;
            const plotLeft = 420, plotRight = W - 170;
            const zero = (plotLeft + plotRight) / 2, step = (plotRight - plotLeft) / 10;
            const tick = Math.max(1, Math.ceil(Math.max(...rows.map(row => Math.abs(row.gap ?? 0))) / 5));
            const svg = standingsSvg(W, H, "Weekend fastest laps compared with the earlier PitPulse archive best");
            const shape = (tag, attrs, value) => chartShape(svg, tag, attrs, value);
            const text = (x, y, value, extra = {}) => shape("text", { x, y, fill: "var(--text)", "font-size": 12, ...extra }, value);
            const signed = (n, digits) => `${n > 0 ? "+" : ""}${n.toFixed(digits)}`;
            const muted = { fill: "var(--muted)" };

            function lapLabel(x, y, anchor, lap, value, note) {
                const label = text(x, y, null, { "text-anchor": anchor, "font-weight": 650 });
                const color = lap.team ? standingsLineColor(lap.team) : "var(--text)";
                chartShape(label, "tspan", { fill: color }, driverCode(lap));
                chartShape(label, "tspan", {}, ` ${value}`);
                chartShape(label, "tspan", { ...muted, "font-weight": 500 }, ` ${note}`);
            }

            for (let i = 0; i < data.length; i++) {
                const y = top + i * rowHeight;
                if (i % 2 === 0) shape("rect", { x: 0, y, width: W, height: rowHeight, fill: "var(--tint-2)", class: "record-grid" });
                shape("line", { x1: 0, y1: y, x2: W, y2: y, stroke: "var(--line)", class: "record-grid" });
            }
            text(6, 43, "GRAND PRIX", { ...muted, "font-weight": 650 });
            text(zero, 18, "Gap to earlier archive best (seconds)", { ...muted, "text-anchor": "middle", "font-weight": 650 });
            for (let mark = -10; mark <= 10; mark++) {
                const x = zero + mark * step / 2;
                const minor = mark % 2 !== 0;
                shape("line", { x1: x, y1: 50, x2: x, y2: H, stroke: mark === 0 ? "var(--line-strong)" : "var(--line)", class: "record-grid", ...(minor ? { "stroke-dasharray": "4 3" } : {}) });
                if (!minor) text(x, 43, signed(mark * tick / 2, 1), { ...muted, "text-anchor": "middle", "font-weight": 650 });
            }
            for (const [i, { meeting, best, record, gap }] of data.entries()) {
                const rowTop = top + i * rowHeight;
                const y = rowTop + rowHeight / 2;
                const slot = shape("foreignObject", { x: 6, y: rowTop, width: 265, height: rowHeight });
                const label = node("div", "record-meeting-label");
                label.append(grandPrixLabel(meeting));
                slot.append(label);

                if (!best) {
                    text(zero + 16, y + 5, "No timed lap available", muted);
                    continue;
                }

                const detail = `${best.driverName} · ${best.time} · ${sessionTypeLabel(best.sessionType)}`;
                if (!record) {
                    lapLabel(zero - 14, y + 5, "end", best, best.time, `(${best.year})`);
                    chartTip(shape("circle", { cx: zero, cy: y, r: 4.5, fill: "var(--text)", stroke: "#0aad83", "stroke-width": 3 }), `${detail} · First archived benchmark for this circuit`);
                    text(zero + 15, y + 5, "First archived benchmark", muted);
                    continue;
                }

                const end = zero + gap / tick * step;
                const faster = gap < 0;
                const ring = faster ? "#0aad83" : gap > 0 ? "#ea4f71" : "var(--muted)";
                lapLabel(zero + (faster ? 14 : -14), y + 5, faster ? "start" : "end", record, record.time, `(${record.year})`);
                shape("line", { x1: zero, y1: y, x2: end, y2: y, stroke: "var(--text)", "stroke-opacity": .78, "stroke-width": 2.5, "stroke-linecap": "round" });
                shape("circle", { cx: zero, cy: y, r: 2.5, fill: "var(--text)" });
                const marker = shape("circle", { cx: end, cy: y, r: 4.5, fill: "var(--text)", stroke: ring, "stroke-width": 3 });
                const delta = `${signed(gap, 3)}s`;
                const percent = `(${signed((best.millis - record.millis) / record.millis * 100, 2)}%)`;
                chartTip(marker, `${detail} · ${delta} ${percent}`);
                lapLabel(end + (faster ? -16 : 16), y + 5, faster ? "end" : "start", best, delta, percent);
            }
            scroll.replaceChildren(svg);
            installSeasonPopovers(scroll);
        }
        select.onchange = draw;
        draw();
        const resize = new ResizeObserver(() => {
            if (!scroll.isConnected) resize.disconnect();
            else if (Math.max(1080, scroll.clientWidth) !== drawnWidth) draw();
        });
        resize.observe(scroll);
        download.onclick = () => {
            const chart = scroll.querySelector("svg");
            const copy = chart.cloneNode(true);
            const { width, height } = chart.viewBox.baseVal;
            copy.setAttribute("width", width);
            copy.setAttribute("height", height);
            copy.setAttribute("style", "--text:#080e1c;--muted:#64748b;--line:#e8edf3;--line-strong:#ccd5df;--tint-2:#f6f8fa;background:white;font-family:Arial,sans-serif");
            const styles = chartShape(copy, "style", {}, `
                .record-meeting-label { display: flex; align-items: center; height: 100%; font-size: 12px; }
                .gp-name { white-space: nowrap; font-weight: 600; }
                .flat-flag { display: inline-block; height: 1em; width: 1.5em; margin: 0 7px; vertical-align: -.1em; border-radius: 2px; }
                .round-badge { display: inline-block; border: 1px solid var(--line-strong); border-radius: 4px; padding: 2px 5px; margin-right: 10px; font-size: 10px; }
            `);
            copy.prepend(styles);
            const url = URL.createObjectURL(new Blob([new XMLSerializer().serializeToString(copy)], { type: "image/svg+xml" }));
            const link = node("a", "");
            link.href = url;
            link.download = "weekend-fastest-laps.svg";
            link.click();
            setTimeout(() => URL.revokeObjectURL(url), 1000);
        };
        section.append(node("div", "record-legend", "●  Earlier archive best     ◉  Weekend fastest lap · Green marks a faster lap or a first archived benchmark")); return section;
    }

    function describeMeta(meta) {
        if (!meta) return "";
        const parts = [];
        if (meta.source) parts.push(`Source: ${meta.source}`);
        if (meta.quality) parts.push(`Quality: ${QUALITY_LABELS[meta.quality] || meta.quality}`);
        if (meta.fetchedAt) parts.push(`Updated ${formatDateTime(meta.fetchedAt)}`);
        if (meta.stale) parts.push("Stale data");
        return parts.join(" · ");
    }

    function buildResultTable(rows, sessionType, meta) {
        const timing = sessionType === "qualifying" || sessionType === "sprintQualifying";
        const table = node("div", "dt");
        table.dataset.kind = "results";

        const columns = timing
            ? [
                ["Position", ""],
                ["", "col-code"],
                ["Driver", "col-team"],
                ["Q1", "num"],
                ["Q2", "num col-laps"],
                ["Q3", "num col-points"],
            ]
            : [
                ["Position", ""],
                ["", "col-code"],
                ["Driver", "col-team"],
                ["Time", "num"],
                ["Laps", "num col-laps"],
                ["Points", "num col-points"],
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
            const logo = teamLogoImage(artSeason(), row.team, row.constructorId);
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

        if (meta?.stale) table.title = "The server marked these results as stale.";
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

    function loadStandings(season) {
        if (standingsBySeason.has(season)) return standingsBySeason.get(season);
        const data = { drivers: [], constructors: [], loading: true, errors: [] };
        standingsBySeason.set(season, data);
        Promise.allSettled(['drivers', 'constructors'].map(async kind => {
            const { body } = await api(`/api/v1/standings/${kind}?season=${season}`);
            data[kind] = Array.isArray(body.data) ? body.data : [];
        })).then(results => {
            data.errors = ['drivers', 'constructors'].filter((_, index) => results[index].status === 'rejected');
            data.loading = false;
            renderStandingsPage();
        });
        return data;
    }

    /* ---------- routing ---------- */

    function navigate(href) {
        const target = String(href || "/").replace(/^#/, "");
        if (target === location.pathname + location.search) { applyRoute(); return; }
        history.pushState(null, "", target);
        applyRoute();
    }

    function currentRoute() {
        const parts = location.pathname.replace(/^\/+/, "").split("?")[0].split("/").filter(Boolean);
        if (parts[0] === "driver-standings" || parts[0] === "constructor-standings") return { view: "standings", parts: [parts[0] === "constructor-standings" ? "constructors" : "drivers"] };
        if (parts[0] === 'drivers' && parts[1]) return { view: 'driver-stats', parts: [decodeURIComponent(parts[1])] };
        const view = ROUTES.includes(parts[0]) ? parts[0] : "home";
        return { view, parts: parts.slice(1) };
    }

    function applyRoute() {
        const { view, parts } = currentRoute();
        setLoading(null);
        state.view = view;
        if (RACING_VIEWS.includes(view)) {
            const query = new URLSearchParams(location.search);
            driverPages.season = requestedSeason() || defaultSeason();
            driverPages.driver = view === 'driver-stats' ? parts[0] : null;
            driverPages.team = query.get('team') || '';
            driverPages.first = query.get('driver1') || '';
            driverPages.second = query.get('driver2') || '';
            if (view === 'consistency') driverPages.excludeDnf = query.get('excludeDnf') === '1';
            syncSectionNav(driverPages.season);
            // A section the server does not offer for this season is removed,
            // not shown empty: wait for the capability map, then fall back to a
            // sibling section of the same season.
            if (sectionFeature(view)) {
                const season = driverPages.season;
                const features = SEASON_FEATURES.get(Number(season));
                if (features?.[sectionFeature(view)] === false) {
                    navigate(`/tech-updates?season=${season}`);
                    return;
                }
            }
        }
        el("workspace-title").textContent = VIEW_TITLES[view];
        document.body.dataset.view = view;
        if (view === "standings") {
            state.standingsKind = parts[0] === "constructors" ? "constructors" : "drivers";
            driverPages.season = requestedSeason() || defaultSeason();
            syncSectionNav(driverPages.season);
        }
        if (view === "results") {
            state.results.detail = Boolean(parts[0]);
            state.results.meetingId = parts[0] ? decodeURIComponent(parts[0]) : null;
            state.results.sessionType = parts[1] || "race";
            driverPages.season = resultsSeason();
            syncSectionNav(driverPages.season);
        }
        for (const section of document.querySelectorAll(".view")) {
            section.hidden = section.dataset.view !== (view === 'driver-stats' ? 'drivers' : view);
        }
        for (const link of document.querySelectorAll("[data-route]")) {
            const active = link.dataset.route === (view === 'driver-stats' ? 'drivers' : view) && (!link.dataset.standingsNav || link.dataset.standingsNav === state.standingsKind);
            link.classList.toggle("is-active", active);
            const season = view === 'results' ? resultsSeason() : requestedSeason() || driverPages.season;
            if (link.dataset.route && !link.dataset.standingsNav && link.dataset.route !== "schedule") {
                const target = link.dataset.route === 'standings' ? 'driver-standings' : link.dataset.route;
                link.href = `/${target}${season ? `?season=${season}` : ''}`;
            }
            if (link.dataset.standingsNav) link.href = `/${link.dataset.standingsNav === 'constructors' ? 'constructor' : 'driver'}-standings${season ? `?season=${season}` : ''}`;
            if (active) link.setAttribute("aria-current", "page");
            else link.removeAttribute("aria-current");
        }
        document.title = `PitPulse · ${view === "standings" ? (state.standingsKind === "constructors" ? "Constructor Standings" : "Driver Standings") : VIEW_TITLES[view] || "F1 Live Timing"}`;
        document.querySelector(".app").scrollTo({ top: 0, behavior: "instant" });

        if (view === "standings") setStandingsKind(state.standingsKind);
        if (sectionFeature(view) && !SEASON_FEATURES.get(driverPages.season)) {
            el(`view-${view}`).querySelector('.racing-workspace').replaceChildren();
            setLoading('Loading season data…');
            return;
        }
        if (view === "results") renderResultsPage();
        if (view === "schedule") loadNextSeasonSchedule();
        if (RACING_VIEWS.includes(view)) renderDriverPages();
    }

    let displayedSchedule;
    const scheduleDates = new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", timeZone: "UTC" });

    async function loadNextSeasonSchedule() {
        if (state.view !== "schedule" || document.hidden) return;
        try {
            const { body: { data, meta } } = await api("/api/v1/schedule/next");
            const version = `${data.year}:${meta.revision}`;
            el("schedule-status").textContent = data.events.length ? "" : "Waiting for the official schedule.";
            if (version === displayedSchedule) return;
            el("schedule-title").textContent = `${data.year} F1 Schedule`;
            const source = el("schedule-source");
            source.href = data.sourceUrl;
            source.hidden = false;
            el("schedule-events").replaceChildren(...data.events.map(event => {
                const row = document.createElement("li");
                const detail = document.createElement("div");
                const round = document.createElement("span");
                round.textContent = event.round == null ? "Testing" : `Round ${event.round}`;
                const title = document.createElement("h2");
                title.textContent = event.location;
                const name = document.createElement("p");
                name.textContent = event.name;
                detail.append(round, title, name);
                const dates = document.createElement("span");
                dates.className = "schedule-dates";
                dates.textContent = scheduleDates.formatRange(new Date(event.startDate), new Date(event.endDate));
                row.append(detail, dates);
                return row;
            }));
            displayedSchedule = version;
        } catch {
            el("schedule-status").textContent = el("schedule-events").childElementCount
                ? "Refresh failed. Showing the last available schedule."
                : "Schedule unavailable. Retrying automatically.";
        }
    }

    /* ---------- wiring ---------- */

    function wireChrome() {
        el("navigation-toggle").addEventListener("click", () => {
            const expanded = document.body.classList.toggle("navigation-expanded");
            el("navigation-toggle").setAttribute("aria-expanded", String(expanded));
            el("navigation-toggle").setAttribute("aria-label", expanded ? "Collapse navigation" : "Expand navigation");
        });
        const density = el("density-toggle");
        try { document.body.classList.toggle("is-compact", localStorage.getItem("pitpulse-density") === "compact"); } catch { }
        const updateDensity = () => density.setAttribute("aria-pressed", String(document.body.classList.contains("is-compact")));
        updateDensity();
        density.addEventListener("click", () => {
            const compact = document.body.classList.toggle("is-compact");
            try { localStorage.setItem("pitpulse-density", compact ? "compact" : "comfortable"); } catch { }
            updateDensity();
        });
        const fullscreen = el("fullscreen-toggle");
        fullscreen.hidden = !document.fullscreenEnabled;
        const syncFullscreen = () => {
            const active = Boolean(document.fullscreenElement);
            fullscreen.setAttribute("aria-pressed", String(active));
            fullscreen.setAttribute("aria-label", active ? "Exit full screen" : "Enter full screen");
            fullscreen.title = active ? "Exit full screen" : "Full screen";
        };
        syncFullscreen();
        fullscreen.addEventListener("click", async () => {
            try {
                if (document.fullscreenElement) await document.exitFullscreen();
                else await document.documentElement.requestFullscreen();
            } catch { fullscreen.hidden = true; }
        });
        document.addEventListener("fullscreenchange", syncFullscreen);
        document.addEventListener("click", (event) => {
            const button = event.target.closest("[data-standings]");
            if (button) setStandingsKind(button.dataset.standings);
        });

        // Links are real paths now: intercept same-origin navigation so the
        // page renders in place, and let the server serve the shell on reload.
        document.addEventListener("click", (event) => {
            if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
            const link = event.target.closest && event.target.closest("a[href]");
            if (!link || link.target || link.hasAttribute("download")) return;
            const url = new URL(link.getAttribute("href"), location.origin);
            if (url.origin !== location.origin) return;
            if (url.pathname.startsWith("/api/") || url.pathname.startsWith("/motorsport/") || url.pathname.startsWith("/media/")) return;
            if (/\.(png|ico|css|js|webmanifest|svg|json)$/i.test(url.pathname)) return;
            event.preventDefault();
            navigate(url.pathname + url.search);
        });
        window.addEventListener("popstate", applyRoute);
    }

    async function init() {
        wireTheme();
        try {
            const { body } = await api("/api/v1/seasons");
            offeredSeasons = Array.isArray(body.data) ? body.data : [];
            for (const entry of offeredSeasons) SEASON_FEATURES.set(entry.year, entry.features);
        } catch { /* Data routes retain their own error state. */ }

        wireStandingsFilter();
        wireContentMotion();
        applyRoute();
        wireChrome();
        setInterval(updateHomeCountdown, 1000);
        setInterval(loadNextSeasonSchedule, 60_000);
        document.addEventListener("visibilitychange", loadNextSeasonSchedule);
    }

    init();
})();
