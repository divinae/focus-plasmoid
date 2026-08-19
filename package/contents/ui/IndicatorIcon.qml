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
    // Distinguishes a session stopped part-way from one not started, so the two
    // bare-ring styles can show which they are instead of looking identical.
    property bool paused: false
    property real progress: 1 // remaining fraction of the session, 0..1
    // No fraction to draw - a flowmodoro flow, or a break past its end. Without this
    // progress sits pinned at 1 and the ring reads as a full, definite session; the
    // sweep says "still going" instead, matching the dial in the popup.
    property bool indeterminate: false
    property color tint: Kirigami.Theme.textColor
    readonly property real shortestSide: Math.min(root.width, root.height)
    // The drawn diameter, not the box. pomodoro-frame-light.svg puts its body at
    // radius 9 in a 22 viewBox, so a bare circle filling the whole box would sit
    // noticeably larger than the icons either side of it in the panel.
    readonly property int iconExtent: Math.round(shortestSide * 18 / 22)
    // Hairline by intent: the point of these styles is to be lighter than the
    // tomato outline, so this stays 1px for every panel size up to a 32px box.
    // Rounded to whole pixels, because a fractional stroke is what made the
    // wedge's gap look uneven, with a 1px floor so it never vanishes.
    readonly property int thinStroke: Math.max(1, Math.round(iconExtent / 18))
    // Clearance between the wedge and the outline. Derived from the stroke but
    // floored separately: at a 1px stroke, half of it would be sub-pixel again.
    readonly property int wedgeGap: Math.max(1, Math.round(thinStroke / 2))

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
        indeterminate: root.running && root.indeterminate
        indeterminateOpacity: 0.8
    }

    // Ring and Wedge draw nothing in the middle, so when they are not counting
    // there is no way to tell a paused session from a stopped one. The TimerFrame
    // style needs none of this: its idle artwork already carries a play glyph.
    Kirigami.Icon {
        visible: !root.running && root.style !== IndicatorIcon.Style.TimerFrame
        // Half the dial so it clears the outline, forced even: at a 22 or 32 pixel
        // panel box the odd size this rounded to left the glyph on a half pixel,
        // which reads as off-centre.
        width: 2 * Math.round(root.iconExtent * 0.25)
        height: width
        // Positioned rather than anchored, so an odd box cannot reintroduce the
        // half pixel that centring would produce. No optical correction: measuring
        // the rendered pixels shows this glyph's mass centre and bounding-box centre
        // coincide, so the icon the theme serves here is symmetric and geometric
        // centring is correct. An earlier nudge for a bare triangle's mass simply
        // pushed it off centre.
        x: Math.round((root.width - width) / 2)
        y: Math.round((root.height - height) / 2)
        source: root.paused ? "media-playback-pause" : "media-playback-start"
        isMask: true
        color: root.tint
        smooth: true
    }

    // --- style: a bare thin ring, no frame and no knobs -----------------------

    ProgressCircle {
        anchors.centerIn: parent
        visible: root.style === IndicatorIcon.Style.Ring
        size: root.iconExtent
        lineWidth: root.thinStroke
        arcBegin: 0
        // Idle shows the empty track alone, so the panel is quiet when nothing
        // is running rather than showing a play glyph.
        arcEnd: root.running ? Math.ceil(root.progress * 360) : 0
        colorCircle: root.tint
        indeterminate: root.running && root.indeterminate
        // Stronger than the dial's default: there the arc is many pixels wide, here it
        // is a hairline, and at 0.55 over the track it all but disappears in the panel.
        indeterminateOpacity: 0.8
        showBackground: true
        colorBackground: Qt.alpha(root.tint, 0.25)
    }

    // --- style: a filled wedge inside a thin outline --------------------------

    ProgressCircle {
        anchors.centerIn: parent
        visible: root.style === IndicatorIcon.Style.Pie
        size: root.iconExtent
        lineWidth: root.thinStroke
        arcBegin: 0
        arcEnd: 0
        showBackground: true
        colorBackground: Qt.alpha(root.tint, 0.45)
    }

    ProgressCircle {
        anchors.centerIn: parent
        visible: root.style === IndicatorIcon.Style.Pie && root.running
        // The outline's stroke is centred on iconExtent, so its inner edge is one
        // stroke in on each side; wedgeGap keeps the wedge clear of it. Every term
        // is a whole pixel, so the gap cannot land on a half pixel.
        size: root.iconExtent - 2 * root.thinStroke - 2 * root.wedgeGap
        isPie: true
        arcBegin: 0
        arcEnd: Math.ceil(root.progress * 360)
        colorCircle: root.tint
        indeterminate: root.running && root.indeterminate
        indeterminateOpacity: 0.8
    }
}
