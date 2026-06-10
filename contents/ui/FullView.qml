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

    // Live status footer ("Updated 23s ago · Next update in 4m")
    property double footerNow: Date.now()

    Timer {
        interval: 1000
        running: full.visible
        repeat: true
        onTriggered: full.footerNow = Date.now()
    }

    readonly property string statusText: {
        if (root.lastSuccessTime <= 0) return i18n.tr("Loading...")
        var ago = Math.max(0, Math.floor((full.footerNow - root.lastSuccessTime) / 1000))
        var duration
        if (ago < 60) duration = ago + "s"
        else if (ago < 3600) duration = Math.floor(ago / 60) + "m"
        else duration = Math.floor(ago / 3600) + "h " + Math.floor((ago % 3600) / 60) + "m"
        var text = i18n.tr("Updated {duration} ago").replace("{duration}", duration)
        var nextPoll = root.lastFetchTime + Math.max(Plasmoid.configuration.refreshInterval || 5, 1) * 60000
        if (ago >= 60 && nextPoll > full.footerNow && !root.hasRateLimitError) {
            var untilMin = Math.ceil((nextPoll - full.footerNow) / 60000)
            text += " · " + i18n.tr("Next update in {duration}").replace("{duration}", untilMin + "m")
        }
        return text
    }

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
        implicitHeight: inner.implicitHeight + Kirigami.Units.mediumSpacing * 2

        ColumnLayout {
            id: inner
            anchors.fill: parent
            anchors.margins: Kirigami.Units.mediumSpacing
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
        spacing: Kirigami.Units.smallSpacing

        // ===== Header =====
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: Qt.resolvedUrl("../icons/claude-tile.svg")
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
                implicitHeight: sessionCol.implicitHeight + Kirigami.Units.mediumSpacing * 2

                ColumnLayout {
                    id: sessionCol
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.mediumSpacing
                    spacing: Kirigami.Units.smallSpacing

                    UsageRing {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 56
                        Layout.preferredHeight: 56
                        percent: root.sessionUsagePercent
                        ringColor: root.getUsageColor(root.sessionUsagePercent, root.sessionTimePct)
                        markerRel: root.sessionTimePct >= 0 ? root.sessionTimePct / 100 : -1
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
                implicitHeight: weeklyCol.implicitHeight + Kirigami.Units.mediumSpacing * 2

                ColumnLayout {
                    id: weeklyCol
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.mediumSpacing
                    spacing: Kirigami.Units.smallSpacing

                    UsageRing {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 56
                        Layout.preferredHeight: 56
                        percent: root.weeklyUsagePercent
                        ringColor: root.getUsageColor(root.weeklyUsagePercent, root.weeklyTimePct)
                        markerRel: root.weeklyTimePct >= 0 ? root.weeklyTimePct / 100 : -1
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
                    barColor: modelData.key === "fable" ? "#D97757" : root.getUsageColor(modelData.percent, root.weeklyTimePct)
                }
            }

            PlasmaComponents.Label {
                text: i18n.tr("Other models aren't reported by the API yet")
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize - 1
                font.italic: true
                opacity: 0.45
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
        }

        // ===== Extra usage card (paid overage budget) =====
        Card {
            visible: root.extraEnabled

            SectionLabel { text: i18n.tr("Extra Usage") }

            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents.Label {
                    text: root.formatDollars(root.extraUsedCents) + " / " + root.formatDollars(root.extraLimitCents) + " " + i18n.tr("spent")
                }
                Item { Layout.fillWidth: true }
                PlasmaComponents.Label {
                    text: Math.round(root.extraPercent) + "%"
                    font.bold: true
                    color: root.getUsageColor(root.extraPercent)
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 6
                radius: 3
                color: Qt.alpha(Kirigami.Theme.textColor, 0.15)

                Rectangle {
                    width: parent.width * Math.min(root.extraPercent / 100, 1)
                    height: parent.height
                    radius: 3
                    color: root.getUsageColor(root.extraPercent)
                }
            }
        }

        // ===== Today's tokens card (local transcripts, incl. models the API omits) =====
        Card {
            visible: root.tokenStats.length > 0

            RowLayout {
                Layout.fillWidth: true
                SectionLabel { text: i18n.tr("Today's Tokens") }
                Item { Layout.fillWidth: true }
                PlasmaComponents.Label {
                    text: i18n.tr("local logs")
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    opacity: 0.55
                }
            }

            Repeater {
                model: root.tokenStats
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents.Label {
                        text: modelData.name
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                        elide: Text.ElideRight
                    }
                    Item { Layout.fillWidth: true }
                    PlasmaComponents.Label {
                        text: root.formatTokens(modelData.output) + " " + i18n.tr("out")
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        opacity: 0.55
                    }
                    PlasmaComponents.Label {
                        text: root.formatTokens(modelData.total)
                        font.bold: true
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                        horizontalAlignment: Text.AlignRight
                    }
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

        // ===== Claude Code installations (CLI + IDE extensions) =====
        Card {
            visible: root.installations.length > 0

            SectionLabel { text: "Claude Code" }

            Repeater {
                model: root.installations
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    PlasmaComponents.Label {
                        text: modelData.name
                        opacity: 0.65
                    }
                    Item { Layout.fillWidth: true }
                    PlasmaComponents.Label { text: modelData.version }
                }
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
                text: full.statusText
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                opacity: 0.65
                elide: Text.ElideRight
                Layout.fillWidth: false
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
