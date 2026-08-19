import "./lib/timer.js" as TimerLogic
import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

// One day laid out on a clock: a block per recorded session at the position it happened,
// with hour ticks beneath. Replaces the bar chart for the Today period, where a chart of a
// single day is a single bar and says nothing about how the day went.
//
// Owns no state and reads no configuration; the caller supplies the day's timeline.
Item {
    id: root

    // As returned by TimerLogic.dayTimeline(): blocks plus the window they sit in.
    required property var timeline
    // Resolves a task name to its colour, so the timeline and the legend agree. Supplied
    // by the caller rather than duplicated here.
    required property var colorForTask

    // Colours come from the caller, not from Kirigami.Theme here: the applet reads the
    // theme in exactly one place, and the note above that palette in main.qml says why a
    // read per delegate used to take plasmashell down.
    required property color dimColor
    required property color textColor

    readonly property real windowMs: Math.max(1, timeline.windowEnd - timeline.windowStart)
    readonly property int hourCount: Math.round(windowMs / (60 * 60 * 1000))
    // A label every hour is unreadable much past a working day, so they thin out.
    readonly property int hourStep: hourCount <= 8 ? 1 : (hourCount <= 16 ? 2 : 3)
    readonly property real bandHeight: Math.max(Kirigami.Units.gridUnit,
                                                height - tickLabels.height - Kirigami.Units.smallSpacing)

    function xForTime(ms) {
        return band.width * (ms - timeline.windowStart) / windowMs;
    }

    implicitHeight: Kirigami.Units.gridUnit * 2.5

    Item {
        id: band

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: root.bandHeight

        // Bare track: the day's gaps are what is left showing through, so idle needs no
        // block of its own.
        Rectangle {
            anchors.fill: parent
            color: root.textColor
            opacity: 0.08
            radius: 2
        }

        // Hour gridlines, behind the blocks, so a block can be read against the clock.
        Repeater {
            model: root.hourCount + 1

            delegate: Rectangle {
                required property int index

                visible: index % root.hourStep === 0 && index > 0 && index < root.hourCount
                x: band.width * index / root.hourCount
                width: 1
                height: band.height
                color: root.textColor
                opacity: 0.12
            }
        }

        Repeater {
            model: root.timeline.blocks

            delegate: Rectangle {
                required property var modelData

                readonly property bool isBreak: TimerLogic.isBreakKind(modelData.kind)

                x: root.xForTime(modelData.startMs)
                // At least a pixel: a two minute session on an eight hour window rounds to
                // nothing otherwise, and a session that happened should be visible.
                width: Math.max(1, root.xForTime(modelData.endMs) - x)
                height: band.height
                radius: 2
                color: isBreak ? root.dimColor : root.colorForTask(modelData.task)
                opacity: isBreak ? 0.75 : 1

                HoverHandler {
                    id: blockHover
                }

                PlasmaComponents.ToolTip {
                    visible: blockHover.hovered
                    text: {
                        var from = Qt.formatTime(new Date(modelData.startMs), Qt.locale(), Locale.ShortFormat);
                        var to = Qt.formatTime(new Date(modelData.endMs), Qt.locale(), Locale.ShortFormat);
                        var length = TimerLogic.formatCounter(Math.round((modelData.endMs - modelData.startMs) / 1000));
                        if (isBreak)
                            return i18n("Break, %1 to %2 (%3)", from, to, length);
                        return i18n("%1, %2 to %3 (%4)",
                                    modelData.task || i18n("No task"), from, to, length);
                    }
                }
            }
        }
    }

    Item {
        id: tickLabels

        anchors {
            top: band.bottom
            left: parent.left
            right: parent.right
            topMargin: Kirigami.Units.smallSpacing / 2
        }
        height: Kirigami.Theme.smallFont.pixelSize > 0 ? Kirigami.Theme.smallFont.pixelSize + 2
                                                       : Kirigami.Units.gridUnit

        Repeater {
            model: root.hourCount + 1

            delegate: PlasmaComponents.Label {
                required property int index

                visible: index % root.hourStep === 0
                // Centred on its gridline, except at the ends where centring would push
                // the label outside the view and clip it.
                x: {
                    var at = band.width * index / root.hourCount;
                    if (index === 0)
                        return 0;
                    if (index === root.hourCount)
                        return band.width - width;
                    return at - width / 2;
                }
                // Qt.formatTime(date, locale, "HH") does not mean "the hour": with a
                // locale the third argument is a format enum, so a format string there
                // rendered the whole timezone name and the ticks became a smear.
                text: Qt.formatTime(new Date(root.timeline.windowStart + index * 60 * 60 * 1000), "HH")
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: root.dimColor
            }
        }
    }
}
