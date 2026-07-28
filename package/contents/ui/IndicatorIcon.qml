import QtQuick
import org.kde.kirigami as Kirigami

// Panel/tray indicator. Three styles, because the original tomato-timer frame is
// heavy at panel sizes: its outline and knobs are thick strokes that crowd a
// 22px icon. The other two are drawn entirely with ProgressCircle, so nothing
// extra is shipped.
Item {
    id: root

    enum Style {
        TimerFrame,
        Ring,
        Pie
    }

    property int style: IndicatorIcon.Style.TimerFrame
    property bool running: false
    property real progress: 1 // remaining fraction of the session, 0..1
    property color tint: Kirigami.Theme.textColor

    readonly property real shortestSide: Math.min(root.width, root.height)
    // Thin enough to read as a line at panel sizes, but never sub-pixel.
    readonly property real thinStroke: Math.max(1.5, shortestSide / 11)

    // --- style: the original tomato-timer frame with a filled wedge inside ----

    Kirigami.Icon {
        anchors.fill: parent
        visible: root.style === IndicatorIcon.Style.TimerFrame
        source: Qt.resolvedUrl(root.running ? "../icons/pomodoro-frame-light.svg" : "../icons/pomodoro-start-light.svg")
        isMask: true
        color: root.tint
        smooth: true
    }

    ProgressCircle {
        anchors.centerIn: parent
        visible: root.style === IndicatorIcon.Style.TimerFrame && root.running
        // The frame SVG has a 22x22 viewBox whose inner dial has radius 6.
        size: Math.round(root.shortestSide * 12 / 22)
        isPie: true
        arcBegin: 0
        arcEnd: Math.ceil(root.progress * 360)
        colorCircle: root.tint
    }

    // --- style: a bare thin ring, no frame and no knobs -----------------------

    ProgressCircle {
        anchors.centerIn: parent
        visible: root.style === IndicatorIcon.Style.Ring
        size: root.shortestSide
        lineWidth: root.thinStroke
        arcBegin: 0
        // Idle shows the empty track alone, so the panel is quiet when nothing
        // is running rather than showing a play glyph.
        arcEnd: root.running ? Math.ceil(root.progress * 360) : 0
        colorCircle: root.tint
        showBackground: true
        colorBackground: Qt.alpha(root.tint, 0.25)
    }

    // --- style: a filled wedge inside a thin outline --------------------------

    ProgressCircle {
        anchors.centerIn: parent
        visible: root.style === IndicatorIcon.Style.Pie
        size: root.shortestSide
        lineWidth: root.thinStroke
        arcBegin: 0
        arcEnd: 0
        showBackground: true
        colorBackground: Qt.alpha(root.tint, 0.45)
    }

    ProgressCircle {
        anchors.centerIn: parent
        visible: root.style === IndicatorIcon.Style.Pie && root.running
        // Inset so the wedge sits inside the outline rather than over it.
        size: root.shortestSide - root.thinStroke * 2.5
        isPie: true
        arcBegin: 0
        arcEnd: Math.ceil(root.progress * 360)
        colorCircle: root.tint
    }
}
