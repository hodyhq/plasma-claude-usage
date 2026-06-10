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
                source: Qt.resolvedUrl("../icons/claude-tile.svg")
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
