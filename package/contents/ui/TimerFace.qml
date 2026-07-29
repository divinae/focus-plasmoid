import QtQuick
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

// The dial shown both in the popup and in the fullscreen break overlay:
// progress ring, remaining time, session dots and the state caption.
Item {
    id: root

    // The ring takes up 1/sizeDivisor of the smaller parent dimension.
    property real sizeDivisor: 1.4
    property real progress: 1 // remaining fraction of the session, 0..1
    property bool showProgress: true
    // For sessions with no fraction to show: a flowmodoro flow counts up with no end,
    // and a break past its end has already run its length out.
    property bool indeterminate: false
    property string timeText: ""
    // The ring already carries the progress, so the digits can be turned off for
    // people who find a visible countdown distracting.
    property bool showTime: true
    property string statusText: ""
    property int sessionCount: 1
    property int sessionIndex: 0
    property bool showSessionDots: true
    property string fontFamily: ""
    property bool fontBold: false
    property color circleColor: Kirigami.Theme.highlightColor
    property color captionColor: Kirigami.Theme.textColor
    // Faint guide ring behind the arc. Without it a finished session - or the
    // whole of a break overrun, where progress is pinned at 0 - drew no circle at
    // all and the time text was left floating.
    property color trackColor: Qt.alpha(root.captionColor, 0.12)

    ProgressCircle {
        id: progressCircle

        anchors.centerIn: parent
        size: Math.min(root.width, root.height) / root.sizeDivisor
        colorCircle: root.circleColor
        showBackground: true
        colorBackground: root.trackColor
        arcBegin: 0
        arcEnd: root.showProgress ? Math.ceil(root.progress * 360) : 0
        indeterminate: root.indeterminate
        lineWidth: size / 30
    }

    Item {
        anchors.centerIn: parent
        height: timeLabel.height

        PlasmaComponents.Label {
            id: timeLabel

            text: root.timeText
            visible: root.showTime
            // Collapsed rather than merely hidden: the dots anchor to its top and
            // the caption to its bottom, so leaving its height would leave a gap
            // where the digits used to be.
            height: root.showTime ? implicitHeight : 0
            font.pointSize: Math.max(progressCircle.width / 8, 1)
            font.family: root.fontFamily
            font.bold: root.fontBold
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Controls.PageIndicator {
            id: pageIndicator

            visible: root.showSessionDots
            count: root.sessionCount
            currentIndex: root.sessionIndex
            spacing: progressCircle.width / 25

            anchors {
                bottom: root.showTime ? timeLabel.top : statusLabel.top
                horizontalCenter: parent.horizontalCenter
                bottomMargin: progressCircle.width / 15
            }

            delegate: Rectangle {
                implicitWidth: progressCircle.width / 34
                implicitHeight: width
                radius: width / 2
                color: root.captionColor
                opacity: index === pageIndicator.currentIndex ? 0.95 : 0.45

                Behavior on opacity {
                    OpacityAnimator {
                        duration: 100
                    }
                }
            }
        }

        PlasmaComponents.Label {
            id: statusLabel

            text: root.statusText
            // With the digits hidden this is the only text in the ring, so it takes
            // the centre and grows to suit rather than sitting small and off-centre
            // under a collapsed label.
            font.pointSize: Math.max(progressCircle.width / (root.showTime ? 24 : 11), 1)
            color: root.captionColor
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            // At the larger size a long caption would otherwise reach past the ring.
            width: progressCircle.width * 0.72

            anchors {
                // One anchor, not two: setting top and verticalCenter together is a
                // conflict QML resolves by dropping one, which made this caption
                // disappear entirely whenever the countdown was shown.
                //
                // timeLabel collapses to zero height when the countdown is hidden,
                // so its bottom edge is the centre of the ring. Offsetting by half
                // this label's height therefore centres it, while the normal case
                // just sits below the digits.
                top: timeLabel.bottom
                topMargin: root.showTime ? progressCircle.width / 20 : -implicitHeight / 2
                horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
