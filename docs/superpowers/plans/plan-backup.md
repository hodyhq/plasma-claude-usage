# Claude Usage Widget v2.0 UI Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild both representations of the Plasma 6 widget: card-based popup (account, progress rings, dynamic model breakdown incl. Fable 5, 7-day trend, update chip) and a Mini Rings panel style replacing Text/Circular/Bar.

**Architecture:** Pure QML plasmoid. `main.qml` keeps all data/logic (DataSources, timers, XHR fetch); UI moves to new components in `contents/ui/`: `UsageRing.qml`, `ModelRow.qml`, `TrendChart.qml`, `CompactView.qml`, `FullView.qml`. Rings use `QtQuick.Shapes` for anti-aliasing. Spec: `docs/superpowers/specs/2026-06-09-ui-redesign-design.md`.

**Tech Stack:** QML (Qt 6), Plasma 6 / Kirigami, Plasma5Support DataSource (executable engine), XMLHttpRequest.

**Testing reality:** No automated test framework exists for plasmoids (project convention is manual testing, per `.claude/CLAUDE.md`). Each task verifies with `qmllint` (syntax; *import warnings for org.kde.* modules are expected noise — only fail on syntax errors*) and the final task does a real install on this CachyOS laptop (Plasma 6.6.5): `./install.sh`, restart plasmashell, check `journalctl`.

**Verify command used throughout:**
```bash
cd /home/hody/.dev/Projects/plasma-claude-usage && qmllint contents/ui/*.qml 2>&1 | grep -v "Warnings occurred" | grep -iv "failed to import" | grep -v "import org.kde" | grep -v "QML module" || true
```
Expected: no `Error:` lines (warnings about unresolved org.kde imports are OK).

**Commit identity:** repo-local git config is already `Hody <hody@hody.dev>`. NO `Co-Authored-By` trailers.

---

### Task 1: Pure UI components — UsageRing, ModelRow, TrendChart

**Files:**
- Create: `contents/ui/UsageRing.qml`
- Create: `contents/ui/ModelRow.qml`
- Create: `contents/ui/TrendChart.qml`

- [ ] **Step 1: Create `contents/ui/UsageRing.qml`**

```qml
/*
    SPDX-FileCopyrightText: 2026 Hody
    SPDX-License-Identifier: GPL-3.0-or-later
*/

import QtQuick
import QtQuick.Shapes
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// Anti-aliased progress ring with the percentage centered.
Item {
    id: ring

    property real percent: 0
    property real lineWidth: 4
    property color ringColor: Kirigami.Theme.positiveTextColor
    property color trackColor: Qt.alpha(Kirigami.Theme.textColor, 0.15)
    property bool showPercentSign: false
    property real fontScale: 0.3

    readonly property real arcRadius: Math.min(width, height) / 2 - lineWidth / 2

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        // Track
        ShapePath {
            strokeColor: ring.trackColor
            strokeWidth: ring.lineWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: ring.width / 2
                centerY: ring.height / 2
                radiusX: ring.arcRadius
                radiusY: ring.arcRadius
                startAngle: 0
                sweepAngle: 360
            }
        }

        // Progress
        ShapePath {
            strokeColor: ring.ringColor
            strokeWidth: ring.lineWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: ring.width / 2
                centerY: ring.height / 2
                radiusX: ring.arcRadius
                radiusY: ring.arcRadius
                startAngle: -90
                sweepAngle: 360 * Math.max(0, Math.min(ring.percent, 100)) / 100
            }
        }
    }

    PlasmaComponents.Label {
        anchors.centerIn: parent
        text: Math.round(ring.percent) + (ring.showPercentSign ? "%" : "")
        font.pixelSize: Math.max(8, ring.height * ring.fontScale)
        font.bold: true
    }
}
```

- [ ] **Step 2: Create `contents/ui/ModelRow.qml`**

```qml
/*
    SPDX-FileCopyrightText: 2026 Hody
    SPDX-License-Identifier: GPL-3.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// One "name | bar | percent" row for the model breakdown card.
RowLayout {
    id: row

    property string label: ""
    property real percent: 0
    property color barColor: Kirigami.Theme.positiveTextColor

    spacing: Kirigami.Units.smallSpacing
    Layout.fillWidth: true

    PlasmaComponents.Label {
        text: row.label
        Layout.preferredWidth: Kirigami.Units.gridUnit * 3.5
        elide: Text.ElideRight
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 6
        radius: 3
        color: Qt.alpha(Kirigami.Theme.textColor, 0.15)

        Rectangle {
            width: parent.width * Math.min(row.percent / 100, 1)
            height: parent.height
            radius: 3
            color: row.barColor
        }
    }

    PlasmaComponents.Label {
        text: Math.round(row.percent) + "%"
        font.bold: true
        Layout.preferredWidth: Kirigami.Units.gridUnit * 2
        horizontalAlignment: Text.AlignRight
    }
}
```

- [ ] **Step 3: Create `contents/ui/TrendChart.qml`**

```qml
/*
    SPDX-FileCopyrightText: 2026 Hody
    SPDX-License-Identifier: GPL-3.0-or-later
*/

import QtQuick

// Sparkline (line + soft area fill) of session-usage samples.
// samples: array of {t: ms-epoch, session: percent, weekly: percent}
Canvas {
    id: chart

    property var samples: []
    property color lineColor: "#D97757"

    onSamplesChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        if (!samples || samples.length < 2) {
            return
        }

        var pad = 2
        var t0 = samples[0].t
        var span = Math.max(samples[samples.length - 1].t - t0, 1)

        function px(s) { return pad + (width - 2 * pad) * (s.t - t0) / span }
        function py(s) { return height - pad - (height - 2 * pad) * Math.min(s.session, 100) / 100 }

        // Area fill
        ctx.beginPath()
        ctx.moveTo(px(samples[0]), height)
        for (var i = 0; i < samples.length; i++) {
            ctx.lineTo(px(samples[i]), py(samples[i]))
        }
        ctx.lineTo(px(samples[samples.length - 1]), height)
        ctx.closePath()
        ctx.fillStyle = Qt.alpha(chart.lineColor, 0.15)
        ctx.fill()

        // Line
        ctx.beginPath()
        ctx.moveTo(px(samples[0]), py(samples[0]))
        for (var j = 1; j < samples.length; j++) {
            ctx.lineTo(px(samples[j]), py(samples[j]))
        }
        ctx.strokeStyle = chart.lineColor
        ctx.lineWidth = 2
        ctx.lineJoin = "round"
        ctx.stroke()
    }
}
```

- [ ] **Step 4: Verify syntax**

Run the verify command from the header. Expected: no `Error:` lines.

- [ ] **Step 5: Commit**

```bash
git add contents/ui/UsageRing.qml contents/ui/ModelRow.qml contents/ui/TrendChart.qml
git commit -m "feat: add UsageRing, ModelRow, TrendChart components"
```

---

### Task 2: Data layer — dynamic models, trend samples, email, update checker

**Files:**
- Modify: `contents/ui/main.qml` (property block ~line 18–46, cache reader/writer ~49–112, fetch success handler ~301–338, `Component.onCompleted` ~1125, tooltip ~1153)

- [ ] **Step 1: Add new properties** — in `main.qml`, after the existing property block (after the `staleThresholdMs` property, ~line 46), add:

```qml
    // v2.0: dynamic model breakdown, trend history, account email, update check
    property var modelUsage: []          // [{key, name, percent}] from seven_day_* API keys
    property var usageSamples: []        // [{t, session, weekly}] for the trend chart
    property string accountEmail: ""
    property string latestVersion: ""
    readonly property bool updateAvailable: root.claudeVersion !== "" && root.latestVersion !== ""
        && isNewerVersion(root.latestVersion, root.claudeVersion)
    // Shared by both views: metrics render normally during token/rate-limit errors
    readonly property bool metricsVisible: root.errorMsg === "" || root.hasTokenError || root.hasRateLimitError
```

- [ ] **Step 2: Add helper functions** — next to `getUsageColor()` (~line 1091), add:

```qml
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
```

- [ ] **Step 3: Replace hardcoded sonnet/opus parsing with a dynamic loop** — in the `xhr.status === 200` success block of `fetchUsageFromApi()` (~lines 310–313), replace:

```qml
                        root.hasSonnetData = !!data.seven_day_sonnet
                        root.hasOpusData = !!data.seven_day_opus
                        root.sonnetWeeklyPercent = root.hasSonnetData ? (data.seven_day_sonnet.utilization || 0) : 0
                        root.opusWeeklyPercent = root.hasOpusData ? (data.seven_day_opus.utilization || 0) : 0
```

with:

```qml
                        // Collect every per-model seven_day_* key dynamically
                        var models = []
                        for (var key in data) {
                            var m = key.match(/^seven_day_(.+)$/)
                            if (m && data[key] && typeof data[key] === "object") {
                                models.push({
                                    key: m[1],
                                    name: modelDisplayName(m[1]),
                                    percent: data[key].utilization || 0
                                })
                            }
                        }
                        root.modelUsage = models
                        // Legacy properties kept for the panel sonnet toggle + cache compat
                        root.hasSonnetData = models.some(function(x) { return x.key === "sonnet" })
                        root.hasOpusData = models.some(function(x) { return x.key === "opus" })
                        root.sonnetWeeklyPercent = (models.find(function(x) { return x.key === "sonnet" }) || {percent: 0}).percent
                        root.opusWeeklyPercent = (models.find(function(x) { return x.key === "opus" }) || {percent: 0}).percent
```

- [ ] **Step 4: Append trend samples on success** — in the same success block, right before `saveCache()` (~line 332), add:

```qml
                        // Trend history: one sample per >=15 min, pruned to 7 days
                        var samples = root.usageSamples.slice()
                        var nowTs = Date.now()
                        if (samples.length === 0 || nowTs - samples[samples.length - 1].t >= 900000) {
                            samples.push({ t: nowTs, session: root.sessionUsagePercent, weekly: root.weeklyUsagePercent })
                        }
                        root.usageSamples = samples.filter(function(s) { return nowTs - s.t < 604800000 })
```

- [ ] **Step 5: Extend the cache** — in `saveCache()` (~line 95) add two keys to the `cache` object:

```qml
            models: root.modelUsage,
            samples: root.usageSamples,
```

In the `cacheReader.onNewData` handler (~line 70, inside the `age < 86400000` branch), after `root.hasOpusData = cache.hasOpus || false` add:

```qml
                        root.modelUsage = cache.models || []
                        root.usageSamples = cache.samples || []
```

- [ ] **Step 6: Email reader + update timer** — after the `versionReader` DataSource (~line 233), add:

```qml
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
                    var cfg = JSON.parse(stdout)
                    root.accountEmail = (cfg.oauthAccount || {}).emailAddress || ""
                } catch (e) {
                    console.log("Claude Usage: email parse error:", e)
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
```

In `Component.onCompleted` (~line 1125), after `versionReader.connectSource(...)` add:

```qml
        emailReader.connectSource("cat $HOME/.claude.json 2>/dev/null")
        checkForUpdate()
```

- [ ] **Step 7: Verify syntax** — run the header verify command. Expected: no `Error:` lines.

- [ ] **Step 8: Commit**

```bash
git add contents/ui/main.qml
git commit -m "feat: dynamic model parsing, trend samples, account email, update checker"
```

---

### Task 3: CompactView — Mini Rings panel

**Files:**
- Create: `contents/ui/CompactView.qml`
- Modify: `contents/ui/main.qml` — replace the entire `compactRepresentation: Item { ... }` block (~lines 384–699) and delete `drawCircularProgress()` (~lines 1061–1089)

- [ ] **Step 1: Create `contents/ui/CompactView.qml`**

```qml
/*
    SPDX-FileCopyrightText: 2026 Hody
    SPDX-License-Identifier: GPL-3.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// Panel representation: Claude icon + one mini ring per enabled metric.
// Reads data from the `root` PlasmoidItem context (main.qml).
Item {
    id: compact

    readonly property bool vertical: root.isVerticalLayout
    readonly property real ringSize: vertical
        ? Math.max(20, Math.min(width - Kirigami.Units.smallSpacing * 2, 30))
        : Math.max(20, Math.min(height - Kirigami.Units.smallSpacing, 30))
    readonly property real dimOpacity: (root.hasTokenError || root.hasRateLimitError)
        ? 0.5 : root.isStale ? 0.6 : 1.0

    Layout.minimumWidth: grid.implicitWidth + Kirigami.Units.largeSpacing * 2
    Layout.minimumHeight: vertical
        ? grid.implicitHeight + Kirigami.Units.largeSpacing * 2
        : Kirigami.Units.iconSizes.medium
    Layout.preferredWidth: grid.implicitWidth + Kirigami.Units.largeSpacing * 2
    Layout.preferredHeight: vertical
        ? grid.implicitHeight + Kirigami.Units.largeSpacing * 2
        : -1

    MouseArea {
        anchors.fill: parent
        onClicked: root.expanded = !root.expanded
    }

    GridLayout {
        id: grid
        anchors.centerIn: parent
        columns: compact.vertical ? 1 : -1
        rows: compact.vertical ? -1 : 1
        flow: compact.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        columnSpacing: Kirigami.Units.smallSpacing
        rowSpacing: Kirigami.Units.smallSpacing / 2

        // Claude icon with status dot (red = error, orange = update available)
        Item {
            visible: Plasmoid.configuration.showIcon !== false
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium

            Kirigami.Icon {
                anchors.fill: parent
                source: Qt.resolvedUrl("../icons/claude.svg")
            }

            Rectangle {
                visible: root.hasTokenError || root.hasRateLimitError || root.updateAvailable
                width: 8
                height: 8
                radius: 4
                color: (root.hasTokenError || root.hasRateLimitError)
                    ? Kirigami.Theme.negativeTextColor
                    : "#D97757"
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: -2
                anchors.bottomMargin: -2
            }
        }

        UsageRing {
            visible: Plasmoid.configuration.showSession !== false && root.metricsVisible
            Layout.preferredWidth: compact.ringSize
            Layout.preferredHeight: compact.ringSize
            percent: root.sessionUsagePercent
            ringColor: root.getUsageColor(root.sessionUsagePercent)
            lineWidth: Math.max(2.5, compact.ringSize / 9)
            opacity: compact.dimOpacity
        }

        UsageRing {
            visible: Plasmoid.configuration.showWeekly !== false && root.metricsVisible
            Layout.preferredWidth: compact.ringSize
            Layout.preferredHeight: compact.ringSize
            percent: root.weeklyUsagePercent
            ringColor: root.getUsageColor(root.weeklyUsagePercent)
            lineWidth: Math.max(2.5, compact.ringSize / 9)
            opacity: compact.dimOpacity
        }

        UsageRing {
            visible: Plasmoid.configuration.showSonnet === true && root.metricsVisible
            Layout.preferredWidth: compact.ringSize
            Layout.preferredHeight: compact.ringSize
            percent: root.sonnetWeeklyPercent
            ringColor: root.getUsageColor(root.sonnetWeeklyPercent)
            lineWidth: Math.max(2.5, compact.ringSize / 9)
            opacity: compact.dimOpacity
        }

        // Generic (non-token, non-rate-limit) errors
        PlasmaComponents.Label {
            visible: !root.metricsVisible
            text: "⚠ " + root.errorMsg
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            color: Kirigami.Theme.negativeTextColor
        }
    }
}
```

- [ ] **Step 2: Wire it up** — in `main.qml`, replace the whole `compactRepresentation: Item { ... }` block (from `compactRepresentation: Item {` ~line 384 down to its closing brace ~line 699) with:

```qml
    compactRepresentation: CompactView {}
```

Keep the `readonly property bool isVerticalLayout` line (~382) above it.

- [ ] **Step 3: Delete `drawCircularProgress()`** — remove the entire function (~lines 1061–1089 in the original file); nothing references it anymore.

- [ ] **Step 4: Verify syntax** — run the header verify command. Expected: no `Error:` lines.

- [ ] **Step 5: Commit**

```bash
git add contents/ui/CompactView.qml contents/ui/main.qml
git commit -m "feat: Mini Rings panel view replacing Text/Circular/Bar styles"
```

---

### Task 4: FullView — card-based popup

**Files:**
- Create: `contents/ui/FullView.qml`
- Modify: `contents/ui/main.qml` — replace the entire `fullRepresentation: Item { ... }` block (~lines 702–1035)

- [ ] **Step 1: Create `contents/ui/FullView.qml`**

```qml
/*
    SPDX-FileCopyrightText: 2026 Hody
    SPDX-License-Identifier: GPL-3.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// Popup representation: card-based layout.
// Reads data from the `root` PlasmoidItem context (main.qml).
Item {
    id: full

    readonly property color accent: "#D97757"
    readonly property color cardColor: Qt.alpha(Kirigami.Theme.textColor, 0.07)

    Layout.minimumWidth: Kirigami.Units.gridUnit * 16
    Layout.preferredWidth: Kirigami.Units.gridUnit * 17
    Layout.minimumHeight: mainColumn.implicitHeight + Kirigami.Units.largeSpacing * 2
    Layout.preferredHeight: mainColumn.implicitHeight + Kirigami.Units.largeSpacing * 2

    // Rounded card with column content
    component Card: Rectangle {
        id: card
        default property alias content: inner.data
        Layout.fillWidth: true
        radius: Kirigami.Units.cornerRadius
        color: full.cardColor
        implicitHeight: inner.implicitHeight + Kirigami.Units.largeSpacing * 2

        ColumnLayout {
            id: inner
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing
        }
    }

    // Small uppercase section label
    component SectionLabel: PlasmaComponents.Label {
        font.pixelSize: Kirigami.Theme.smallFont.pixelSize - 1
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1.2
        font.bold: true
        opacity: 0.55
    }

    ColumnLayout {
        id: mainColumn
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.mediumSpacing

        // ===== Header =====
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: Qt.resolvedUrl("../icons/claude.svg")
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
            }

            PlasmaComponents.Label {
                text: i18n.tr("Claude Usage")
                font.bold: true
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.25
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                visible: root.planName !== ""
                Layout.preferredWidth: planLabel.implicitWidth + Kirigami.Units.largeSpacing
                Layout.preferredHeight: planLabel.implicitHeight + Kirigami.Units.smallSpacing
                radius: height / 2
                color: Qt.alpha(full.accent, 0.18)

                PlasmaComponents.Label {
                    id: planLabel
                    anchors.centerIn: parent
                    text: root.planName
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    font.bold: true
                    color: full.accent
                }
            }
        }

        // ===== Error cards =====
        Rectangle {
            visible: root.errorMsg !== "" && !root.hasTokenError && !root.hasRateLimitError
            Layout.fillWidth: true
            radius: Kirigami.Units.cornerRadius
            color: Qt.alpha(Kirigami.Theme.negativeTextColor, 0.12)
            implicitHeight: errorColumn.implicitHeight + Kirigami.Units.largeSpacing * 2

            ColumnLayout {
                id: errorColumn
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    text: "⚠ " + root.errorMsg
                    color: Kirigami.Theme.negativeTextColor
                    font.bold: true
                }
                PlasmaComponents.Label {
                    text: root.baseUrl
                        ? i18n.tr("Check base URL and API key in widget settings")
                        : i18n.tr("Run 'claude' to log in")
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    color: Kirigami.Theme.negativeTextColor
                }
            }
        }

        Rectangle {
            visible: root.hasTokenError
            Layout.fillWidth: true
            radius: Kirigami.Units.cornerRadius
            color: Qt.alpha(Kirigami.Theme.negativeTextColor, 0.12)
            implicitHeight: tokenErrorColumn.implicitHeight + Kirigami.Units.largeSpacing * 2

            ColumnLayout {
                id: tokenErrorColumn
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    text: "⚠ " + i18n.tr("Token expired")
                    color: Kirigami.Theme.negativeTextColor
                    font.bold: true
                }

                PlasmaComponents.Button {
                    text: i18n.tr("Open Claude")
                    icon.name: "utilities-terminal"
                    onClicked: root.launchInTerminal("claude")
                }
            }
        }

        Rectangle {
            visible: root.hasRateLimitError
            Layout.fillWidth: true
            radius: Kirigami.Units.cornerRadius
            color: Qt.alpha(Kirigami.Theme.negativeTextColor, 0.12)
            implicitHeight: rateLimitColumn.implicitHeight + Kirigami.Units.largeSpacing * 2

            ColumnLayout {
                id: rateLimitColumn
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    text: "⚠ " + i18n.tr("Rate limited")
                    color: Kirigami.Theme.negativeTextColor
                    font.bold: true
                }
                PlasmaComponents.Label {
                    text: i18n.tr("Auto-retry in") + " " + Math.round(root.rateLimitBackoffMs / 60000) + " min"
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    color: Kirigami.Theme.negativeTextColor
                }
            }
        }

        // ===== Account card =====
        Card {
            visible: root.accountEmail !== "" || root.planName !== ""

            SectionLabel { text: i18n.tr("Account") }

            RowLayout {
                visible: root.accountEmail !== ""
                Layout.fillWidth: true
                PlasmaComponents.Label {
                    text: i18n.tr("Email")
                    opacity: 0.65
                }
                Item { Layout.fillWidth: true }
                PlasmaComponents.Label { text: root.accountEmail }
            }

            RowLayout {
                visible: root.planName !== ""
                Layout.fillWidth: true
                PlasmaComponents.Label {
                    text: i18n.tr("Plan")
                    opacity: 0.65
                }
                Item { Layout.fillWidth: true }
                PlasmaComponents.Label { text: root.planName }
            }
        }

        // ===== Ring cards =====
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.mediumSpacing

            Rectangle {
                Layout.fillWidth: true
                radius: Kirigami.Units.cornerRadius
                color: full.cardColor
                implicitHeight: sessionCol.implicitHeight + Kirigami.Units.largeSpacing * 2

                ColumnLayout {
                    id: sessionCol
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    UsageRing {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 64
                        percent: root.sessionUsagePercent
                        ringColor: root.getUsageColor(root.sessionUsagePercent)
                        lineWidth: 5
                        showPercentSign: true
                        fontScale: 0.22
                    }
                    PlasmaComponents.Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: i18n.tr("Session (5hr)")
                        font.bold: true
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    }
                    PlasmaComponents.Label {
                        Layout.alignment: Qt.AlignHCenter
                        visible: root.sessionResetTime !== null && root.formatTimeRemaining(root.sessionResetTime) !== ""
                        text: i18n.tr("resets in") + " " + root.formatTimeRemaining(root.sessionResetTime)
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        opacity: 0.65
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: Kirigami.Units.cornerRadius
                color: full.cardColor
                implicitHeight: weeklyCol.implicitHeight + Kirigami.Units.largeSpacing * 2

                ColumnLayout {
                    id: weeklyCol
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    UsageRing {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 64
                        percent: root.weeklyUsagePercent
                        ringColor: root.getUsageColor(root.weeklyUsagePercent)
                        lineWidth: 5
                        showPercentSign: true
                        fontScale: 0.22
                    }
                    PlasmaComponents.Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: i18n.tr("Weekly (7day)")
                        font.bold: true
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    }
                    PlasmaComponents.Label {
                        Layout.alignment: Qt.AlignHCenter
                        visible: root.weeklyResetTime !== null && root.formatTimeRemaining(root.weeklyResetTime) !== ""
                        text: i18n.tr("resets in") + " " + root.formatTimeRemaining(root.weeklyResetTime)
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        opacity: 0.65
                    }
                }
            }
        }

        // ===== Model breakdown card =====
        Card {
            visible: root.modelUsage.length > 0

            SectionLabel { text: i18n.tr("By Model (Weekly)") }

            Repeater {
                model: root.modelUsage
                delegate: ModelRow {
                    required property var modelData
                    label: modelData.name
                    percent: modelData.percent
                    barColor: root.modelBarColor(modelData.key, modelData.percent)
                }
            }
        }

        // ===== Trend card =====
        Card {
            visible: root.usageSamples.length >= 2

            RowLayout {
                Layout.fillWidth: true
                SectionLabel { text: i18n.tr("7-day trend") }
                Item { Layout.fillWidth: true }
                PlasmaComponents.Label {
                    text: i18n.tr("session usage")
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    opacity: 0.55
                }
            }

            TrendChart {
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 2.2
                samples: root.usageSamples
                lineColor: full.accent
            }
        }

        // Refresh-interval warning (unchanged behavior)
        PlasmaComponents.Label {
            visible: (Plasmoid.configuration.refreshInterval || 5) < 5
            text: "⚠ " + i18n.tr("Values under 5 min may cause rate limiting")
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            color: Kirigami.Theme.neutralTextColor
            font.italic: true
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        // ===== Footer =====
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            // Update chip (click = run `claude update` in a terminal)
            Rectangle {
                visible: root.updateAvailable
                Layout.preferredWidth: updateLabel.implicitWidth + Kirigami.Units.largeSpacing
                Layout.preferredHeight: updateLabel.implicitHeight + Kirigami.Units.smallSpacing
                radius: height / 2
                color: Qt.alpha(full.accent, 0.18)

                PlasmaComponents.Label {
                    id: updateLabel
                    anchors.centerIn: parent
                    text: "⬆ " + root.latestVersion + " " + i18n.tr("available")
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    font.bold: true
                    color: full.accent
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.launchInTerminal("claude update")
                }
            }

            PlasmaComponents.Label {
                visible: !root.updateAvailable && root.claudeVersion !== ""
                text: "CLI " + root.claudeVersion
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                opacity: 0.65
            }

            PlasmaComponents.Label {
                text: root.lastUpdate !== ""
                    ? "· " + i18n.tr("Updated:") + " " + root.lastUpdate
                    : i18n.tr("Loading...")
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                opacity: 0.65
            }

            Item { Layout.fillWidth: true }

            PlasmaComponents.ToolButton {
                icon.name: "view-refresh"
                text: i18n.tr("Refresh")
                onClicked: root.refresh()
            }
        }
    }
}
```

- [ ] **Step 2: Generalize the terminal launcher** — in `main.qml`, the token-error button used an inline konsole command. Add this function next to `refresh()` (~line 373):

```qml
    // Opens a terminal running the given claude command (konsole > gnome-terminal > xfce4-terminal > xterm)
    function launchInTerminal(cmd) {
        claudeLauncher.connectSource("bash -c 'cd $HOME && if command -v konsole >/dev/null; then konsole --hold -e env -u CLAUDECODE bash -lc \"" + cmd + "\"; elif command -v gnome-terminal >/dev/null; then gnome-terminal -- env -u CLAUDECODE bash -lc \"" + cmd + "; exec bash\"; elif command -v xfce4-terminal >/dev/null; then xfce4-terminal --hold -e \"env -u CLAUDECODE bash -lc \\\"" + cmd + "\\\"\"; elif command -v xterm >/dev/null; then xterm -hold -e env -u CLAUDECODE bash -lc \"" + cmd + "\"; fi &'")
    }
```

- [ ] **Step 3: Wire it up** — replace the whole `fullRepresentation: Item { ... }` block (from `fullRepresentation: Item {` down to its closing brace, originally lines 702–1035) with:

```qml
    fullRepresentation: FullView {}
```

- [ ] **Step 4: Verify syntax** — run the header verify command. Expected: no `Error:` lines.

- [ ] **Step 5: Commit**

```bash
git add contents/ui/FullView.qml contents/ui/main.qml
git commit -m "feat: card-based popup with rings, dynamic models, trend, update chip"
```

---

### Task 5: Config cleanup + translations

**Files:**
- Modify: `contents/config/main.xml` — remove `panelStyle` entry
- Modify: `contents/ui/configGeneral.qml` — remove `cfg_panelStyle` + Style combo
- Modify: `contents/ui/Translations.qml` — add new en_US keys

- [ ] **Step 1: Remove `panelStyle` from `main.xml`** — delete this entry (lines 25–28):

```xml
        <entry name="panelStyle" type="String">
            <label>Panel display style (text or circular)</label>
            <default>text</default>
        </entry>
```

- [ ] **Step 2: Remove from `configGeneral.qml`** — delete the property (line 19):

```qml
    property string cfg_panelStyle
```

and the Style combo (lines 108–116):

```qml
        QQC2.ComboBox {
            Kirigami.FormData.label: tr("Style:")
            model: [tr("Text"), tr("Circular"), tr("Bar")]
            currentIndex: cfg_panelStyle === "circular" ? 1 : cfg_panelStyle === "bar" ? 2 : 0
            onCurrentIndexChanged: {
                var styles = ["text", "circular", "bar"]
                cfg_panelStyle = styles[currentIndex]
            }
        }
```

- [ ] **Step 3: Add new en_US strings** — in `Translations.qml`, inside the `"en_US"` map (after the `"Background opacity (desktop):"` line, ~line 66), add:

```js
            "Account": "Account",
            "Email": "Email",
            "Plan": "Plan",
            "resets in": "resets in",
            "7-day trend": "7-day trend",
            "session usage": "session usage",
            "available": "available",
            "Auto-retry in": "Auto-retry in"
```

(Other languages fall back to English keys via `tr()`'s fallback chain — acceptable per spec. Note: `main.qml` line 816 used the key `"Auto-retry in"` which was never in the map; this fixes that too.)

- [ ] **Step 4: Verify syntax** — run the header verify command, plus `qmllint contents/config/config.qml`. Expected: no `Error:` lines.

- [ ] **Step 5: Commit**

```bash
git add contents/config/main.xml contents/ui/configGeneral.qml contents/ui/Translations.qml
git commit -m "feat: drop panelStyle setting, add v2.0 translation keys"
```

---

### Task 6: Version bump, docs, install & verify on CachyOS

**Files:**
- Modify: `metadata.json` — version 2.0.0
- Modify: `README.md` — features + version history
- Modify: `.claude/CLAUDE.md` — note component split

- [ ] **Step 1: Bump version** — in `metadata.json` change `"Version": "1.3.6"` to `"Version": "2.0.0"`.

- [ ] **Step 2: Update README** — in `README.md`: update the features list to describe the ring-based panel (remove Text/Circular/Bar style mentions), the card popup (account / rings / dynamic per-model breakdown incl. Fable 5 / 7-day trend), and the Claude Code update indicator. Add a version-history entry:

```markdown
### 2.0.0
- Complete UI redesign: card-based popup with progress rings, account info, 7-day usage trend
- Dynamic per-model breakdown (Fable 5, Opus, Sonnet, and future models automatically)
- New Mini Rings panel style (replaces Text/Circular/Bar styles)
- Claude Code update indicator with one-click `claude update`
```

- [ ] **Step 3: Update `.claude/CLAUDE.md`** — in the Key Files section, replace the `main.qml` line with:

```markdown
- `contents/ui/main.qml` - Data layer: credentials, API fetch, cache, timers
- `contents/ui/CompactView.qml` / `FullView.qml` - Panel and popup UI
- `contents/ui/UsageRing.qml`, `ModelRow.qml`, `TrendChart.qml` - Reusable components
```

- [ ] **Step 4: Install on this laptop**

```bash
cd /home/hody/.dev/Projects/plasma-claude-usage && ./install.sh
```

Expected: installs to `~/.local/share/plasma/plasmoids/org.kde.plasma.claudeusage/` without errors.

- [ ] **Step 5: Restart plasmashell and verify visually**

```bash
systemctl --user restart plasma-plasmashell.service 2>/dev/null || (kquitapp6 plasmashell; kstart plasmashell >/dev/null 2>&1 &)
sleep 8 && journalctl --user --since "1 min ago" | grep -i "claude" | head -40
```

Expected log lines: `Widget loaded`, `Token found`, `API success`, `latest version:`. **No** `qml: ... error` / `TypeError` / `ReferenceError` lines.

Manual checks (ask Hody to confirm):
1. Panel shows Claude icon + mini rings with percentages.
2. Popup shows: header + plan chip, Account card with email, two rings with countdowns, By Model card (incl. Fable 5 if API reports it), footer with CLI version + Refresh.
3. Trend card appears after 2+ samples (≥15 min apart — may need a later check).
4. Widget settings page no longer shows the Style dropdown.

- [ ] **Step 6: Commit**

```bash
git add metadata.json README.md .claude/CLAUDE.md
git commit -m "chore: bump to 2.0.0, update README and dev guide for redesign"
```

---

## Self-review notes

- Spec coverage: popup (Task 4), panel (Task 3), update checker + email + models + samples (Task 2), components (Task 1), config (Task 5), version/docs/testing (Task 6). ✓
- `metricsVisible`, `modelUsage`, `usageSamples`, `launchInTerminal`, `modelBarColor`, `isNewerVersion` defined in Task 2/4 before use. ✓
- `panelLayout`/vertical support preserved via `isVerticalLayout` + CompactView GridLayout flow. ✓
- Old cache files load fine (new keys optional). ✓
