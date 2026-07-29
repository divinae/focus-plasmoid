import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

// Everything drawn on a break overlay. Split out of BreakOverlay.qml because the
// overlay comes in two window flavours - blurred and plain - and a QML root type
// cannot be switched at runtime, so the two wrappers share this instead of
// duplicating the dial, the animations and the buttons.
Item {
    id: content

    // The applet root, not a dozen mirrored properties: this is an internal part of
    // the applet and the alternative was restating most of the root's state here.
    property var applet

    signal closeRequested()

    focus: true

    // Children inherit these, so the dial's digits, the session dots and the Plasma
    // buttons all follow the overlay's palette rather than the desktop's. inherit
    // must be false or the attached values are ignored.
    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.backgroundColor: content.applet.overlayBackgroundColor
    Kirigami.Theme.textColor: content.applet.overlayTextColor
    Kirigami.Theme.disabledTextColor: content.applet.overlayDimColor
    Kirigami.Theme.highlightColor: content.applet.overlayHighlightColor

        // Escape matches the Close button, so it is offered on the same terms: a
        // user who turned Close off does not get a back door out of the break.
        Keys.onEscapePressed: {
            if (plasmoid.configuration.fullscreen_buttons_close)
                content.closeRequested();
        }

        readonly property int pulse: content.applet.endPulse

        onPulseChanged: {
            if (plasmoid.configuration.flash_on_end)
                overlayEndPulse.restart();
        }

        TimerFace {
            id: overlayFace

            anchors.fill: parent

            sizeDivisor: 2.4
            progress: content.applet.progressFraction()
            showProgress: true
            indeterminate: content.applet.progressIndeterminate
            timeText: content.applet.timeText
            showTime: plasmoid.configuration.show_dial_time
            statusText: content.applet.statusText
            sessionCount: content.applet.numberOfSessions
            sessionIndex: (content.applet.stateVal - 1) / 2
            showSessionDots: !content.applet.flowmodoroModeEnabled && content.applet.numberOfSessions > 1
            fontFamily: content.applet.clock_fontfamily
            fontBold: plasmoid.configuration.clock_bold
            circleColor: content.applet.overlayCircleColor()
            captionColor: content.applet.overlayCaptionColor()
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

            running: content.applet.breakOvertime && plasmoid.configuration.flash_on_end && !overlayEndPulse.running
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
                    visible: content.applet.isBreak() && !content.applet.flowmodoroModeEnabled && plasmoid.configuration.fullscreen_buttons_postpone
                    text: i18n("&Postpone")
                    icon.name: "circular-arrow-shape"
                    onClicked: content.applet.postpone()
                }

                PlasmaComponents.Button {
                    visible: content.applet.isBreak() && plasmoid.configuration.fullscreen_buttons_skip
                    text: i18n("Sk&ip")
                    icon.name: "go-next-skip"
                    onClicked: content.applet.skip()
                }

                PlasmaComponents.Button {
                    // Closes every overlay, not just this one: dismissing the break
                    // on one screen while it stayed up on the others would be worse
                    // than not offering the button.
                    visible: content.applet.isBreak() && plasmoid.configuration.fullscreen_buttons_close
                    text: i18n("&Close")
                    icon.name: "dialog-close"
                    onClicked: content.closeRequested()
                }

                PlasmaComponents.Button {
                    // The overlay is only up while a break is running, so this is
                    // reachable exactly during a break overrun.
                    visible: content.applet.breakOvertime || !content.applet.isBreak()
                    text: i18n("St&art")
                    icon.name: "media-playback-start"
                    onClicked: content.applet.toggleSession()
                }
            }
        }
    }
