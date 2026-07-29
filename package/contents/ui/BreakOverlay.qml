import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.private.kicker as Kicker

// One fullscreen break overlay. Instantiated once per screen, because a single
// window only covers the display it is on, which left every other monitor
// uncovered during a break (gitlab #19).
//
// Takes the applet root rather than a dozen individual properties: it is an
// internal part of the applet, and the alternative was mirroring most of the
// root's state through this file.
Kicker.DashboardWindow {
    id: overlay

    property var applet
    // Where this overlay belongs, in virtual desktop coordinates. DashboardWindow
    // has no assignable screen property, so the geometry is set explicitly.
    property rect screenGeometry

    signal closeRequested()

    // Placed before being shown, then fullscreened: showFullScreen() targets the
    // screen the window's geometry sits on, so moving it first is what puts each
    // overlay on its own display. Calling showFullScreen() straight away would put
    // every overlay on whichever screen Qt happened to create the window on.
    // Assigning screen directly is not an option - DashboardWindow exposes no
    // writable screen property.
    function showOnItsScreen() {
        overlay.x = screenGeometry.x;
        overlay.y = screenGeometry.y;
        overlay.width = screenGeometry.width;
        overlay.height = screenGeometry.height;
        overlay.showFullScreen();
        overlay.raise();
    }

    flags: Qt.WindowStaysOnTopHint
    backgroundColor: Qt.hsla(Kirigami.Theme.backgroundColor.hslHue, Kirigami.Theme.backgroundColor.hslSaturation, Kirigami.Theme.backgroundColor.hslLightness, 0.85)

    Item {
        anchors.fill: parent

        readonly property int pulse: overlay.applet.endPulse

        onPulseChanged: {
            if (plasmoid.configuration.flash_on_end)
                overlayEndPulse.restart();
        }

        TimerFace {
            id: overlayFace

            anchors.fill: parent

            sizeDivisor: 2.4
            progress: overlay.applet.progressFraction()
            showProgress: !(overlay.applet.flowmodoroModeEnabled && !overlay.applet.isBreak())
            timeText: overlay.applet.timeText
            showTime: plasmoid.configuration.show_dial_time
            statusText: overlay.applet.statusText
            sessionCount: overlay.applet.numberOfSessions
            sessionIndex: (overlay.applet.stateVal - 1) / 2
            showSessionDots: !overlay.applet.flowmodoroModeEnabled && overlay.applet.numberOfSessions > 1
            fontFamily: overlay.applet.clock_fontfamily
            circleColor: overlay.applet.getCircleColor()
            captionColor: overlay.applet.getTextColor()
        }

        SequentialAnimation {
            id: overlayEndPulse

            loops: 3

            NumberAnimation {
                target: overlayFace
                property: "opacity"
                to: 0.2
                duration: 180
                easing.type: Easing.InOutQuad
            }

            NumberAnimation {
                target: overlayFace
                property: "opacity"
                to: 1
                duration: 180
                easing.type: Easing.InOutQuad
            }
        }

        SequentialAnimation {
            id: overlayOverrunBlink

            running: overlay.applet.breakOvertime && plasmoid.configuration.flash_on_end && !overlayEndPulse.running
            loops: Animation.Infinite
            alwaysRunToEnd: true

            NumberAnimation {
                target: overlayFace
                property: "opacity"
                to: 0.55
                duration: 700
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                target: overlayFace
                property: "opacity"
                to: 1
                duration: 700
                easing.type: Easing.InOutSine
            }
        }

        RowLayout {
            height: Kirigami.Units.gridUnit * 6
            width: parent.width

            anchors {
                bottom: parent.bottom
                bottomMargin: Kirigami.Units.gridUnit * 3
            }

            HoverHandler {
                id: overlayMouse

                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                cursorShape: Qt.PointingHandCursor
            }

            RowLayout {
                spacing: 10
                visible: !plasmoid.configuration.show_buttons_on_hover || overlayMouse.hovered
                Layout.alignment: Qt.AlignHCenter

                PlasmaComponents.Button {
                    visible: overlay.applet.isBreak() && !overlay.applet.flowmodoroModeEnabled && plasmoid.configuration.fullscreen_buttons_postpone
                    text: i18n("&Postpone")
                    icon.name: "circular-arrow-shape"
                    onClicked: overlay.applet.postpone()
                }

                PlasmaComponents.Button {
                    visible: overlay.applet.isBreak() && plasmoid.configuration.fullscreen_buttons_skip
                    text: i18n("Sk&ip")
                    icon.name: "go-next-skip"
                    onClicked: overlay.applet.skip()
                }

                PlasmaComponents.Button {
                    // Closes every overlay, not just this one: dismissing the break
                    // on one screen while it stayed up on the others would be worse
                    // than not offering the button.
                    visible: overlay.applet.isBreak() && plasmoid.configuration.fullscreen_buttons_close
                    text: i18n("&Close")
                    icon.name: "dialog-close"
                    onClicked: overlay.closeRequested()
                }

                PlasmaComponents.Button {
                    // The overlay is only up while a break is running, so this is
                    // reachable exactly during a break overrun.
                    visible: overlay.applet.breakOvertime || !overlay.applet.isBreak()
                    text: i18n("St&art")
                    icon.name: "media-playback-start"
                    onClicked: overlay.applet.toggleSession()
                }
            }
        }
    }
}
