import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.core as PlasmaCore

PlasmoidItem {
    id: root

    // Translations
    Translations {
        id: i18n
        currentLanguage: Plasmoid.configuration.language || "system"
    }

    property real sessionUsagePercent: 0
    property real weeklyUsagePercent: 0
    property real sonnetWeeklyPercent: 0
    property real opusWeeklyPercent: 0
    property string lastUpdate: ""
    property string planName: ""
    property string sessionReset: ""
    property string weeklyReset: ""
    property string errorMsg: ""
    property string accessToken: ""
    property string apiKey: ""
    property string baseUrl: ""
    property bool isLoading: false
    property var sessionResetTime: null
    property var weeklyResetTime: null
    property bool hasSonnetData: false
    property bool hasOpusData: false
    property bool hasTokenError: false
    property bool hasRateLimitError: false
    property int rateLimitRetryCount: 0
    property int rateLimitRetryMs: 0  // from retry-after header
    property double lastFetchTime: 0
    property double lastSuccessTime: 0
    property bool isStale: false
    readonly property int minFetchIntervalMs: 55000  // just under 1 minute
    // Stale threshold: if rate limited, use retry-after + buffer; otherwise 3x refresh interval
    readonly property int staleThresholdMs: root.hasRateLimitError && root.rateLimitRetryMs > 0
        ? root.rateLimitRetryMs + 60000
        : Math.max(Plasmoid.configuration.refreshInterval || 1, 1) * 60000 * 3

    // v2.0: dynamic model breakdown, trend history, account email, update check
    property var modelUsage: []          // [{key, name, percent}] from seven_day_* API keys
    property var usageSamples: []        // [{t, session, weekly}] for the trend chart
    property string accountEmail: ""
    property string latestVersion: ""
    readonly property bool updateAvailable: root.claudeVersion !== "" && root.latestVersion !== ""
        && isNewerVersion(root.latestVersion, root.claudeVersion)
    // Shared by both views: metrics render normally during token/rate-limit errors
    readonly property bool metricsVisible: root.errorMsg === "" || root.hasTokenError || root.hasRateLimitError

    // Plan-name sources, most authoritative first (see updatePlanName)
    property string accountTier: ""   // user/org rateLimitTier from ~/.claude.json (most current)
    property string credsTier: ""     // rateLimitTier from credentials file
    property string credsSub: ""      // subscriptionType from credentials file (may be stale)

    // Today's per-model token usage parsed from local transcripts
    property var tokenStats: []       // [{model, name, total, output}] sorted by total desc

    // v2.1: time-aware coloring, extra usage, installations, notifications
    property double nowTick: Date.now()   // refreshed every 30s so elapsed-time bindings update
    readonly property real sessionTimePct: elapsedPct(root.sessionResetTime, 18000000)       // 5h period
    readonly property real weeklyTimePct: elapsedPct(root.weeklyResetTime, 604800000)        // 7d period
    property bool extraEnabled: false
    property real extraUsedCents: 0
    property real extraLimitCents: 0
    readonly property real extraPercent: root.extraLimitCents > 0 ? root.extraUsedCents / root.extraLimitCents * 100 : 0
    property var installations: []    // [{name, version}] incl. CLI and IDE extensions
    property var alertedThresholds: ({})  // field -> highest threshold already notified

    // Cache writer - saves last successful data to file
    Plasma5Support.DataSource {
        id: cacheWriter
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) { disconnectSource(sourceName) }
    }

    // Cache reader - loads cached data on startup
    Plasma5Support.DataSource {
        id: cacheReader
        engine: "executable"
        connectedSources: []

        onNewData: function(sourceName, data) {
            var stdout = (data["stdout"] || "").trim()
            disconnectSource(sourceName)
            if (stdout.length > 10) {
                try {
                    var cache = JSON.parse(stdout)
                    var age = Date.now() - (cache.timestamp || 0)
                    if (age < 86400000) { // less than 24 hours old
                        root.sessionUsagePercent = cache.session || 0
                        root.weeklyUsagePercent = cache.weekly || 0
                        root.sonnetWeeklyPercent = cache.sonnet || 0
                        root.opusWeeklyPercent = cache.opus || 0
                        root.hasSonnetData = cache.hasSonnet || false
                        root.hasOpusData = cache.hasOpus || false
                        root.modelUsage = cache.models || []
                        root.usageSamples = cache.samples || []
                        root.extraEnabled = cache.extraEnabled || false
                        root.extraUsedCents = cache.extraUsed || 0
                        root.extraLimitCents = cache.extraLimit || 0
                        root.planName = cache.plan || ""
                        root.sessionReset = cache.sessionReset || ""
                        root.weeklyReset = cache.weeklyReset || ""
                        root.sessionResetTime = cache.sessionResetTs ? new Date(cache.sessionResetTs) : null
                        root.weeklyResetTime = cache.weeklyResetTs ? new Date(cache.weeklyResetTs) : null
                        root.lastSuccessTime = cache.timestamp
                        root.lastUpdate = Qt.formatTime(new Date(cache.timestamp), "hh:mm:ss") + " *"
                        root.isStale = age > root.staleThresholdMs
                        console.log("Claude Usage: Loaded cache, age:", Math.round(age/60000), "min, stale:", root.isStale)
                    } else {
                        console.log("Claude Usage: Cache too old, ignoring")
                    }
                } catch (e) {
                    console.log("Claude Usage: Cache parse error:", e)
                }
            }
        }
    }

    function saveCache() {
        var cache = {
            session: root.sessionUsagePercent,
            weekly: root.weeklyUsagePercent,
            sonnet: root.sonnetWeeklyPercent,
            opus: root.opusWeeklyPercent,
            hasSonnet: root.hasSonnetData,
            hasOpus: root.hasOpusData,
            plan: root.planName,
            sessionReset: root.sessionReset,
            weeklyReset: root.weeklyReset,
            sessionResetTs: root.sessionResetTime ? root.sessionResetTime.getTime() : null,
            weeklyResetTs: root.weeklyResetTime ? root.weeklyResetTime.getTime() : null,
            models: root.modelUsage,
            samples: root.usageSamples,
            extraEnabled: root.extraEnabled,
            extraUsed: root.extraUsedCents,
            extraLimit: root.extraLimitCents,
            timestamp: Date.now()
        }
        var json = JSON.stringify(cache)
        cacheWriter.connectSource("echo '" + json.replace(/'/g, "'\\''") + "' > $HOME/.local/share/claude-usage-cache.json")
    }

    // Stale checker - updates isStale flag periodically
    Timer {
        id: staleTimer
        interval: 60000
        running: true
        repeat: true
        onTriggered: {
            if (root.lastSuccessTime > 0) {
                root.isStale = (Date.now() - root.lastSuccessTime) > root.staleThresholdMs
            }
        }
    }

    // Token watcher - polls credentials file during rate limit to detect token refresh
    Plasma5Support.DataSource {
        id: tokenWatcher
        engine: "executable"
        connectedSources: []

        onNewData: function(sourceName, data) {
            var stdout = (data["stdout"] || "").trim()
            disconnectSource(sourceName)
            if (stdout.length > 10) {
                try {
                    var creds = JSON.parse(stdout)
                    var newToken = (creds.claudeAiOauth || {}).accessToken || ""
                    if (newToken && newToken !== root.accessToken) {
                        console.log("Claude Usage: New token detected! Resetting rate limit state.")
                        root.accessToken = newToken
                        root.hasRateLimitError = false
                        root.rateLimitRetryCount = 0
                        root.lastFetchTime = 0
                        fetchUsageFromApi(true)
                    }
                } catch (e) {
                    console.log("Claude Usage: Token watcher parse error:", e)
                }
            }
        }
    }

    Timer {
        id: tokenWatchTimer
        interval: 30000  // check every 30 seconds
        running: root.hasRateLimitError && !root.baseUrl
        repeat: true
        onTriggered: {
            tokenWatcher.connectSource("cat $HOME/.claude/.credentials.json 2>/dev/null")
        }
    }

    // Data source for reading credentials file
    Plasma5Support.DataSource {
        id: fileReader
        engine: "executable"
        connectedSources: []

        onNewData: function(sourceName, data) {
            var stdout = data["stdout"] || ""
            disconnectSource(sourceName)

            console.log("Claude Usage: Got credentials, length:", stdout.length)

            if (stdout.length > 10) {
                try {
                    var creds = JSON.parse(stdout)
                    var oauth = creds.claudeAiOauth || {}
                    root.accessToken = oauth.accessToken || ""

                    root.credsTier = oauth.rateLimitTier || ""
                    root.credsSub = oauth.subscriptionType || ""
                    updatePlanName()

                    console.log("Claude Usage: Token found, plan:", root.planName)

                    if (root.accessToken) {
                        fetchUsageFromApi()
                    } else {
                        root.errorMsg = i18n.tr("Not logged in")
                        root.isLoading = false
                    }
                } catch (e) {
                    console.log("Claude Usage: Failed to parse credentials:", e)
                    root.errorMsg = "Not logged in"
                    root.isLoading = false
                }
            } else {
                console.log("Claude Usage: No credentials file found")
                root.errorMsg = "Not logged in"
                root.isLoading = false
            }
        }
    }

    // Data source for detecting Claude Code version
    property string claudeVersion: ""
    property string userAgent: "claude-code/" + Qt.formatDateTime(new Date(), "yyyy.M.d")

    Plasma5Support.DataSource {
        id: versionReader
        engine: "executable"
        connectedSources: []

        onNewData: function(sourceName, data) {
            var stdout = (data["stdout"] || "").trim()
            disconnectSource(sourceName)
            // Output format: "2.1.81 (Claude Code)"
            var match = stdout.match(/^(\d+\.\d+\.\d+)/)
            if (match) {
                root.claudeVersion = match[1]
                root.userAgent = "claude-code/" + match[1]
                console.log("Claude Usage: Detected version:", root.claudeVersion)
                refreshInstallations()
            }
        }
    }

    // Reads account email from Claude Code's config
    Plasma5Support.DataSource {
        id: emailReader
        engine: "executable"
        connectedSources: []

        onNewData: function(sourceName, data) {
            var stdout = (data["stdout"] || "").trim()
            disconnectSource(sourceName)
            if (stdout.length > 2) {
                try {
                    var acct = JSON.parse(stdout).oauthAccount || {}
                    root.accountEmail = acct.emailAddress || ""
                    // These tier fields are fresher than the credentials file
                    root.accountTier = acct.userRateLimitTier || acct.organizationRateLimitTier || ""
                    updatePlanName()
                } catch (e) {
                    console.log("Claude Usage: account info parse error:", e)
                }
            }
        }
    }

    Timer {
        id: updateCheckTimer
        interval: 21600000  // 6 hours
        running: true
        repeat: true
        onTriggered: checkForUpdate()
    }

    // Local token stats: parses ~/.claude/projects/*.jsonl via bundled python script
    Plasma5Support.DataSource {
        id: tokenStatsReader
        engine: "executable"
        connectedSources: []

        onNewData: function(sourceName, data) {
            var stdout = (data["stdout"] || "").trim()
            disconnectSource(sourceName)
            if (stdout.length < 2) return
            try {
                var result = JSON.parse(stdout)
                var stats = []
                for (var model in (result.models || {})) {
                    var u = result.models[model]
                    stats.push({
                        model: model,
                        name: prettyModelName(model),
                        total: (u.input || 0) + (u.output || 0) + (u.cacheRead || 0) + (u.cacheWrite || 0),
                        output: u.output || 0
                    })
                }
                root.tokenStats = sortModels(stats, "model")
            } catch (e) {
                console.log("Claude Usage: token stats parse error:", e)
            }
        }
    }

    Timer {
        id: tokenStatsTimer
        interval: 900000  // 15 minutes
        running: true
        repeat: true
        onTriggered: refreshTokenStats()
    }

    Timer {
        id: clockTimer
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.nowTick = Date.now()
    }

    // Detects Claude Code IDE extensions (VS Code, Cursor, Windsurf)
    Plasma5Support.DataSource {
        id: installsReader
        engine: "executable"
        connectedSources: []

        onNewData: function(sourceName, data) {
            var stdout = (data["stdout"] || "").trim()
            disconnectSource(sourceName)
            var found = []
            if (root.claudeVersion !== "") {
                found.push({ name: "CLI", version: root.claudeVersion })
            }
            if (stdout.length > 0) {
                var lines = stdout.split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var parts = lines[i].split("|")
                    if (parts.length === 2 && parts[1]) {
                        found.push({ name: parts[0], version: parts[1] })
                    }
                }
            }
            root.installations = found
        }
    }

    function refreshInstallations() {
        installsReader.connectSource("bash -c 'for p in \"VS Code:.vscode\" \"Cursor:.cursor\" \"Windsurf:.windsurf\"; do n=\"${p%%:*}\"; d=\"$HOME/${p#*:}/extensions\"; v=$(ls -d \"$d\"/anthropic.claude-code-* 2>/dev/null | sed -e \"s/.*claude-code-//\" -e \"s/-[a-z].*//\" | sort -V | tail -n1); [ -n \"$v\" ] && printf \"%s|%s\\n\" \"$n\" \"$v\"; done; true'")
    }

    // Desktop notifications via notify-send (libnotify -> KDE notifications)
    Plasma5Support.DataSource {
        id: notifier
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) { disconnectSource(sourceName) }
    }

    function sendNotification(title, body) {
        if (Plasmoid.configuration.enableNotifications === false) return
        var esc = function(s) { return String(s).replace(/'/g, "'\\''") }
        notifier.connectSource("notify-send -a 'Claude Usage' -i claude-usage-widget '" + esc(title) + "' '" + esc(body) + "'")
    }

    function refreshTokenStats() {
        var script = Qt.resolvedUrl("../scripts/token-stats.py").toString().replace("file://", "")
        tokenStatsReader.connectSource("python3 '" + script + "' 2>/dev/null")
    }

    // Data source for launching claude in terminal
    Plasma5Support.DataSource {
        id: claudeLauncher
        engine: "executable"
        connectedSources: []

        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)
            console.log("Claude Usage: Terminal launched")
        }
    }

    function loadCredentials() {
        root.isLoading = true
        root.errorMsg = ""
        var configBaseUrl = (Plasmoid.configuration.baseUrl || "").trim()
        if (configBaseUrl) {
            root.baseUrl = configBaseUrl.replace(/\/$/, "")
            root.apiKey = (Plasmoid.configuration.apiKey || "").trim()
            root.planName = "API Key"
            console.log("Claude Usage: Using configured base URL:", root.baseUrl)
            if (root.apiKey) {
                fetchUsageFromApi()
            } else {
                root.errorMsg = "API key not configured"
                root.isLoading = false
            }
        } else {
            root.baseUrl = ""
            root.apiKey = ""
            console.log("Claude Usage: No base URL configured, reading credentials file")
            fileReader.connectSource("cat $HOME/.claude/.credentials.json 2>/dev/null")
        }
    }

    function fetchUsageFromApi(force) {
        var now = Date.now()
        if (!force && root.lastFetchTime > 0 && (now - root.lastFetchTime) < root.minFetchIntervalMs) {
            console.log("Claude Usage: Skipping fetch, too soon since last request")
            root.isLoading = false
            return
        }
        root.lastFetchTime = now

        var url = root.baseUrl
            ? root.baseUrl + "/api/oauth/usage"
            : "https://api.anthropic.com/api/oauth/usage"

        var xhr = new XMLHttpRequest()
        xhr.open("GET", url)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.setRequestHeader("User-Agent", root.userAgent)
        xhr.setRequestHeader("anthropic-beta", "oauth-2025-04-20")

        if (root.baseUrl) {
            // Custom base URL: authenticate with API key
            xhr.setRequestHeader("x-api-key", root.apiKey)
        } else {
            // Default: OAuth token from credentials file
            xhr.setRequestHeader("Authorization", "Bearer " + root.accessToken)
        }

        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                root.isLoading = false

                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText)

                        var fiveHour = data.five_hour || {}
                        var sevenDay = data.seven_day || {}

                        root.sessionUsagePercent = fiveHour.utilization || 0
                        root.weeklyUsagePercent = sevenDay.utilization || 0
                        // Collect every per-model seven_day_* key dynamically.
                        // Some seven_day_* keys are features, not models — exclude them.
                        var nonModelKeys = ["oauth_apps", "cowork", "omelette"]
                        var models = []
                        for (var key in data) {
                            var m = key.match(/^seven_day_(.+)$/)
                            if (m && nonModelKeys.indexOf(m[1]) !== -1) continue
                            if (m && data[key] && typeof data[key] === "object") {
                                models.push({
                                    key: m[1],
                                    name: modelDisplayName(m[1]),
                                    percent: data[key].utilization || 0
                                })
                            }
                        }
                        root.modelUsage = sortModels(models, "key")
                        // Legacy properties kept for the panel sonnet toggle + cache compat
                        root.hasSonnetData = models.some(function(x) { return x.key === "sonnet" })
                        root.hasOpusData = models.some(function(x) { return x.key === "opus" })
                        root.sonnetWeeklyPercent = (models.find(function(x) { return x.key === "sonnet" }) || {percent: 0}).percent
                        root.opusWeeklyPercent = (models.find(function(x) { return x.key === "opus" }) || {percent: 0}).percent

                        // Extra usage (paid overage budget)
                        var extra = data.extra_usage || {}
                        root.extraEnabled = !!extra.is_enabled && (extra.monthly_limit || 0) > 0
                        root.extraUsedCents = extra.used_credits || 0
                        root.extraLimitCents = extra.monthly_limit || 0

                        if (fiveHour.resets_at) {
                            root.sessionResetTime = new Date(fiveHour.resets_at)
                            root.sessionReset = Qt.formatTime(root.sessionResetTime, "hh:mm")
                        }
                        if (sevenDay.resets_at) {
                            root.weeklyResetTime = new Date(sevenDay.resets_at)
                            root.weeklyReset = Qt.formatDateTime(root.weeklyResetTime, "MMM d, hh:mm")
                        }

                        root.lastUpdate = Qt.formatTime(new Date(), "hh:mm:ss")
                        root.lastSuccessTime = Date.now()
                        root.isStale = false
                        root.errorMsg = ""
                        root.hasTokenError = false
                        root.hasRateLimitError = false
                        root.rateLimitRetryCount = 0
                        root.rateLimitRetryMs = 0

                        // Trend history: one sample per >=15 min, pruned to 7 days
                        var samples = root.usageSamples.slice()
                        var nowTs = Date.now()
                        if (samples.length === 0 || nowTs - samples[samples.length - 1].t >= 900000) {
                            samples.push({ t: nowTs, session: root.sessionUsagePercent, weekly: root.weeklyUsagePercent })
                        }
                        root.usageSamples = samples.filter(function(s) { return nowTs - s.t < 604800000 })

                        root.nowTick = Date.now()
                        checkAlerts()
                        saveCache()

                        console.log("Claude Usage: API success - session:", root.sessionUsagePercent, "weekly:", root.weeklyUsagePercent)
                    } catch (e) {
                        console.log("Claude Usage: JSON parse error:", e)
                        root.errorMsg = "Parse error"
                    }
                } else if (xhr.status === 401) {
                    if (root.baseUrl) {
                        root.errorMsg = i18n.tr("Invalid API key")
                        console.log("Claude Usage: 401 Unauthorized - invalid API key")
                    } else {
                        console.log("Claude Usage: 401 Unauthorized - token expired")
                        root.hasTokenError = true
                        root.errorMsg = ""
                    }
                } else if (xhr.status === 404) {
                    root.errorMsg = root.baseUrl
                        ? i18n.tr("Endpoint not found")
                        : i18n.tr("API error") + " (404)"
                    console.log("Claude Usage: 404 Not Found:", url)
                } else if (xhr.status === 429) {
                    var retryAfter = parseInt(xhr.getResponseHeader("retry-after") || "0")
                    if (retryAfter > 0) {
                        root.rateLimitRetryMs = retryAfter * 1000
                    }
                    root.rateLimitRetryCount++
                    console.log("Claude Usage: 429 Rate limited (retry #" + root.rateLimitRetryCount + ", retry-after: " + retryAfter + "s, waiting: " + root.rateLimitBackoffMs/1000 + "s)")
                    root.hasRateLimitError = true
                    root.lastFetchTime = 0  // allow retry timer to work
                    root.errorMsg = ""
                } else {
                    root.errorMsg = i18n.tr("API error") + " (" + xhr.status + ")"
                    console.log("Claude Usage: API error:", xhr.status, xhr.statusText)
                }
            }
        }

        xhr.send()
    }

    // Opens a terminal running the given claude command (konsole > gnome-terminal > xfce4-terminal > xterm)
    function launchInTerminal(cmd) {
        claudeLauncher.connectSource("bash -c 'cd $HOME && if command -v konsole >/dev/null; then konsole --hold -e env -u CLAUDECODE bash -lc \"" + cmd + "\"; elif command -v gnome-terminal >/dev/null; then gnome-terminal -- env -u CLAUDECODE bash -lc \"" + cmd + "; exec bash\"; elif command -v xfce4-terminal >/dev/null; then xfce4-terminal --hold -e \"env -u CLAUDECODE bash -lc \\\"" + cmd + "\\\"\"; elif command -v xterm >/dev/null; then xterm -hold -e env -u CLAUDECODE bash -lc \"" + cmd + "\"; fi &'")
    }

    function refresh() {
        root.hasTokenError = false
        root.hasRateLimitError = false
        root.rateLimitRetryCount = 0
        root.rateLimitRetryMs = 0
        loadCredentials()
    }

    // Compact representation (panel)
    readonly property bool isVerticalLayout: Plasmoid.configuration.panelLayout === "vertical"

    compactRepresentation: CompactView {}

    // Full representation (popup)
    fullRepresentation: FullView {}

    Timer {
        id: rateLimitRetryTimer
        interval: root.rateLimitBackoffMs
        running: root.hasRateLimitError
        repeat: true
        onTriggered: {
            console.log("Claude Usage: Backoff retry, interval:", interval/1000, "s")
            loadCredentials()
        }
    }

    // Use retry-after header if available, otherwise fallback to 5min steps (capped at 15min)
    readonly property int rateLimitBackoffMs: root.rateLimitRetryMs > 0
        ? root.rateLimitRetryMs + 10000  // retry-after + 10s buffer
        : Math.min((root.rateLimitRetryCount + 1) * 300000, 900000)

    Timer {
        id: refreshTimer
        interval: Math.max(Plasmoid.configuration.refreshInterval || 5, 1) * 60000
        running: !root.hasRateLimitError
        repeat: true
        onTriggered: loadCredentials()
    }

    // Elapsed fraction of a usage period as 0-100, or -1 when unknown
    function elapsedPct(resetTime, periodMs) {
        if (!resetTime) return -1
        var remaining = resetTime.getTime() - root.nowTick
        if (remaining <= 0 || remaining > periodMs) return -1
        return Math.max(0, Math.min(100, (periodMs - remaining) / periodMs * 100))
    }

    // Time-aware when timePct is known: red = usage outpaces elapsed time
    // (you may hit the limit before reset), yellow = close to pace, green = on pace.
    // Falls back to fixed thresholds when no period information exists.
    function getUsageColor(percent, timePct) {
        if (timePct === undefined || timePct === null || timePct < 0) {
            if (percent < 50) return Kirigami.Theme.positiveTextColor
            if (percent < 80) return Kirigami.Theme.neutralTextColor
            return Kirigami.Theme.negativeTextColor
        }
        if (percent >= 100 || percent > timePct) return Kirigami.Theme.negativeTextColor
        if (percent > timePct * 0.75) return Kirigami.Theme.neutralTextColor
        return Kirigami.Theme.positiveTextColor
    }

    function formatDollars(cents) {
        return "$" + (cents / 100).toFixed(2)
    }

    // Threshold + reset notifications, mirroring the Windows app's smart alerts:
    // below 90% a threshold only fires when usage outpaces elapsed time.
    function checkFieldAlert(field, label, percent, timePct, thresholds) {
        var last = root.alertedThresholds[field] || 0

        if (percent < thresholds[0]) {
            if (last !== 0) {
                var updated = root.alertedThresholds
                updated[field] = 0
                root.alertedThresholds = updated
                if (last >= 95 && percent < 20) {
                    sendNotification(i18n.tr("Quota Reset"), label + ": " + i18n.tr("quota has been reset. Claude is ready to use again."))
                }
            }
            return
        }

        var crossed = 0
        for (var i = 0; i < thresholds.length; i++) {
            if (percent >= thresholds[i]) crossed = thresholds[i]
        }
        if (crossed <= last) return

        var updatedUp = root.alertedThresholds
        updatedUp[field] = crossed
        root.alertedThresholds = updatedUp

        // Time-aware suppression: on pace and below 90% -> stay quiet
        if (crossed < 90 && timePct >= 0 && percent <= timePct) return

        sendNotification(i18n.tr("Usage Notice"), label + " " + i18n.tr("usage has reached") + " " + Math.round(percent) + "%")
    }

    function checkAlerts() {
        checkFieldAlert("session", i18n.tr("Session (5hr)"), root.sessionUsagePercent, root.sessionTimePct, [50, 80, 95])
        checkFieldAlert("weekly", i18n.tr("Weekly (7day)"), root.weeklyUsagePercent, root.weeklyTimePct, [95])
        if (root.extraEnabled) {
            checkFieldAlert("extra", i18n.tr("Extra Usage"), root.extraPercent, -1, [50, 80, 95])
        }
    }

    // Plan name resolution: known tier (account file first, then credentials),
    // then subscriptionType, then a prettified tier string.
    function updatePlanName() {
        if (root.baseUrl) return  // "API Key" mode keeps its label
        var planMap = {
            "default_claude_pro": "Pro",
            "default_claude_max_5x": "Max 5x",
            "default_claude_max_20x": "Max 20x"
        }
        var tier = root.accountTier || root.credsTier
        if (planMap[tier]) {
            root.planName = planMap[tier]
        } else if (root.credsSub) {
            root.planName = root.credsSub.charAt(0).toUpperCase() + root.credsSub.slice(1)
        } else if (tier) {
            root.planName = tier.replace(/^default_/, "").replace(/_/g, " ")
                .replace(/\b\w/g, function(c) { return c.toUpperCase() })
        }
        console.log("Claude Usage: plan resolved:", root.planName, "(tier:", tier + ", sub:", root.credsSub + ")")
    }

    // Canonical model ordering: Fable > Opus > Sonnet > Haiku, newer versions first
    function modelRank(id) {
        var families = ["fable", "opus", "sonnet", "haiku"]
        var lower = id.toLowerCase()
        for (var i = 0; i < families.length; i++) {
            if (lower.indexOf(families[i]) !== -1) return i
        }
        return families.length
    }

    function modelVersion(id) {
        var m = id.toLowerCase().match(/(?:fable|opus|sonnet|haiku)[-_ ]?(\d+(?:[.-]\d+)?)/)
        return m ? parseFloat(m[1].replace("-", ".")) : 0
    }

    function sortModels(list, idField) {
        list.sort(function(a, b) {
            var ra = modelRank(a[idField]), rb = modelRank(b[idField])
            if (ra !== rb) return ra - rb
            return modelVersion(b[idField]) - modelVersion(a[idField])
        })
        return list
    }

    // "claude-fable-5" -> "Fable 5", "claude-haiku-4-5-20251001" -> "Haiku 4.5"
    function prettyModelName(id) {
        var m = id.match(/(fable|opus|sonnet|haiku)[-_ ]?(\d+(?:[.-]\d+)?)?/i)
        if (!m) return id
        var family = m[1].charAt(0).toUpperCase() + m[1].slice(1).toLowerCase()
        var version = (m[2] || "").replace("-", ".")
        return version ? family + " " + version : family
    }

    function formatTokens(n) {
        if (n >= 1e9) return (n / 1e9).toFixed(1) + "B"
        if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
        if (n >= 1e3) return (n / 1e3).toFixed(1) + "k"
        return "" + n
    }

    function modelDisplayName(key) {
        if (key === "fable") return "Fable 5"
        if (key === "sonnet") return i18n.tr("Sonnet")
        if (key === "opus") return i18n.tr("Opus")
        return key.charAt(0).toUpperCase() + key.slice(1)
    }

    function modelBarColor(key, percent) {
        return key === "fable" ? "#D97757" : getUsageColor(percent)
    }

    // true if version a is newer than b ("2.1.85" vs "2.1.81")
    function isNewerVersion(a, b) {
        var pa = a.split(".").map(Number)
        var pb = b.split(".").map(Number)
        for (var i = 0; i < 3; i++) {
            if ((pa[i] || 0) > (pb[i] || 0)) return true
            if ((pa[i] || 0) < (pb[i] || 0)) return false
        }
        return false
    }

    function checkForUpdate() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "https://registry.npmjs.org/@anthropic-ai/claude-code/latest")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    root.latestVersion = JSON.parse(xhr.responseText).version || ""
                    console.log("Claude Usage: latest version:", root.latestVersion)
                } catch (e) { /* silent — indicator simply doesn't show */ }
            }
        }
        xhr.send()
    }

    function formatTimeRemaining(resetTime) {
        if (!resetTime) return ""
        var now = new Date()
        var diff = resetTime.getTime() - now.getTime()
        if (diff <= 0) return ""

        var hours = Math.floor(diff / (1000 * 60 * 60))
        var minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60))

        if (hours > 24) {
            var days = Math.floor(hours / 24)
            hours = hours % 24
            return days + i18n.tr("d") + " " + hours + i18n.tr("h")
        } else if (hours > 0) {
            return hours + i18n.tr("h") + " " + minutes + i18n.tr("m")
        } else {
            return minutes + i18n.tr("m")
        }
    }

    // Install icon to system theme for about page
    Plasma5Support.DataSource {
        id: iconInstaller
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) { disconnectSource(sourceName) }
    }

    Component.onCompleted: {
        console.log("Claude Usage: Widget loaded")
        var iconSource = Qt.resolvedUrl("../icons/claude-usage-widget.svg").toString().replace("file://", "")
        iconInstaller.connectSource("bash -c 'ICON_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps && mkdir -p $ICON_DIR && cp \"" + iconSource + "\" $ICON_DIR/claude-usage-widget.svg && chmod 644 $ICON_DIR/claude-usage-widget.svg 2>/dev/null'")
        cacheReader.connectSource("cat $HOME/.local/share/claude-usage-cache.json 2>/dev/null")
        versionReader.connectSource("claude --version 2>/dev/null")
        emailReader.connectSource("cat $HOME/.claude.json 2>/dev/null")
        checkForUpdate()
        refreshTokenStats()
        refreshInstallations()
        loadCredentials()
    }

    // Only use custom background on desktop, panel keeps default Plasma background
    readonly property bool isOnPanel: Plasmoid.location === PlasmaCore.Types.TopEdge
        || Plasmoid.location === PlasmaCore.Types.BottomEdge
        || Plasmoid.location === PlasmaCore.Types.LeftEdge
        || Plasmoid.location === PlasmaCore.Types.RightEdge

    Plasmoid.backgroundHints: isOnPanel ? PlasmaCore.Types.DefaultBackground : PlasmaCore.Types.NoBackground

    // Custom background with configurable opacity (desktop only)
    Rectangle {
        visible: !root.isOnPanel
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
        opacity: Plasmoid.configuration.backgroundOpacity
        radius: Kirigami.Units.cornerRadius
    }

    Plasmoid.icon: "claude-usage-widget"
    toolTipMainText: i18n.tr("Claude Usage")
    toolTipSubText: {
        var parts = []
        if (Plasmoid.configuration.showSession !== false)
            parts.push(i18n.tr("Session (5hr)") + ": " + Math.round(root.sessionUsagePercent) + "%")
        if (Plasmoid.configuration.showWeekly !== false)
            parts.push(i18n.tr("Weekly (7day)") + ": " + Math.round(root.weeklyUsagePercent) + "%")
        if (Plasmoid.configuration.showSonnet === true)
            parts.push(i18n.tr("Sonnet") + ": " + Math.round(root.sonnetWeeklyPercent) + "%")
        return parts.join(" | ")
    }
}
