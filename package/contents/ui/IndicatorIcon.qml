import QtQuick
import org.kde.kirigami as Kirigami

// Panel/tray indicator: a static tomato-timer frame with a pie wedge drawn
// inside it for the remaining time. Replaces the 62 pre-rendered
// pomodoro-indicator-light-NN.svg frames this applet used to ship.
Item {
    id: root

    property bool running: false
    property real progress: 1 // remaining fraction of the session, 0..1
    property color tint: Kirigami.Theme.textColor

    Kirigami.Icon {
        anchors.fill: parent
        source: Qt.resolvedUrl(root.running ? "../icons/pomodoro-frame-light.svg" : "../icons/pomodoro-start-light.svg")
        isMask: true
        color: root.tint
        smooth: true
    }

    ProgressCircle {
        anchors.centerIn: parent
        visible: root.running
        // The frame SVG has a 22x22 viewBox whose inner dial has radius 6.
        size: Math.round(Math.min(root.width, root.height) * 12 / 22)
        isPie: true
        arcBegin: 0
        arcEnd: Math.ceil(root.progress * 360)
        colorCircle: root.tint
    }
}
