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
    property string timeText: ""
    property string statusText: ""
    // What this session is for. Empty hides the line rather than leaving a gap.
    property string taskText: ""
    property int sessionCount: 1
    property int sessionIndex: 0
    property bool showSessionDots: true
    property string fontFamily: ""
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
        lineWidth: size / 30
    }

    Item {
        anchors.centerIn: parent
        height: timeLabel.height

        PlasmaComponents.Label {
            id: timeLabel

            text: root.timeText
            font.pointSize: Math.max(progressCircle.width / 8, 1)
            font.family: root.fontFamily
            anchors.horizontalCenter: parent.horizontalCenter
        }

        PlasmaComponents.Label {
            id: taskLabel

            visible: root.taskText !== ""
            text: root.taskText
            font.pointSize: Math.max(progressCircle.width / 26, 1)
            color: root.captionColor
            opacity: 0.85
            horizontalAlignment: Text.AlignHCenter
            // Wraps to two lines before eliding: a long task cut at one line loses
            // most of its words, and two lines still clear the ring.
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            // The circle is narrower at the height this sits at than across its
            // middle, so the usable width is well under the diameter.
            width: progressCircle.width * 0.6

            anchors {
                bottom: pageIndicator.visible ? pageIndicator.top : timeLabel.top
                horizontalCenter: parent.horizontalCenter
                bottomMargin: progressCircle.width / 30
            }
        }

        Controls.PageIndicator {
            id: pageIndicator

            visible: root.showSessionDots
            count: root.sessionCount
            currentIndex: root.sessionIndex
            spacing: progressCircle.width / 25

            anchors {
                bottom: timeLabel.top
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
            text: root.statusText
            font.pointSize: Math.max(progressCircle.width / 24, 1)
            color: root.captionColor

            anchors {
                top: timeLabel.bottom
                horizontalCenter: parent.horizontalCenter
                topMargin: progressCircle.width / 20
            }
        }
    }
}
