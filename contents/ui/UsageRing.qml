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
