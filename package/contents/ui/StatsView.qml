import "./lib/timer.js" as TimerLogic
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

// Statistics page: finished focus sessions per day as a bar chart, plus the
// figures for today. Reads history, owns no state.
Item {
    id: root

    required property var entries
    required property string today

    property int dayCount: 14

    readonly property var buckets: TimerLogic.focusPerDay(entries, dayCount, new Date())
    readonly property int peak: TimerLogic.peakCount(buckets)
    readonly property int totalSessions: {
        var sum = 0;
        for (var i = 0; i < buckets.length; i++)
            sum += buckets[i].count;
        return sum;
    }
    readonly property int totalSeconds: {
        var sum = 0;
        for (var i = 0; i < buckets.length; i++)
            sum += buckets[i].seconds;
        return sum;
    }

    // Bars are drawn with Rectangles rather than a Canvas: there are at most a
    // few dozen, and this keeps the theme colours live without a repaint handler,
    // which is what ProgressCircle had to grow.
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: i18np("%1 focus session today", "%1 focus sessions today", TimerLogic.countFocusOn(root.entries, root.today))
            elide: Text.ElideRight
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: i18n("%1 focused today", TimerLogic.formatCounter(TimerLogic.focusSecondsOn(root.entries, root.today)))
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: Kirigami.Theme.disabledTextColor
            elide: Text.ElideRight
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            RowLayout {
                anchors.fill: parent
                spacing: 2

                Repeater {
                    model: root.buckets

                    delegate: Item {
                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        // Track, so an empty day still reads as a day rather than
                        // as a gap in the chart.
                        Rectangle {
                            anchors.fill: parent
                            color: Kirigami.Theme.textColor
                            opacity: 0.08
                            radius: 2
                        }

                        Rectangle {
                            anchors {
                                left: parent.left
                                right: parent.right
                                bottom: parent.bottom
                            }
                            height: modelData.count > 0 ? Math.max(2, parent.height * modelData.count / root.peak) : 0
                            radius: 2
                            color: Kirigami.Theme.highlightColor
                            // Today stands out from the rest of the window.
                            opacity: index === root.buckets.length - 1 ? 1 : 0.65

                            Behavior on height {
                                NumberAnimation {
                                    duration: 150
                                }
                            }
                        }

                        PlasmaComponents.ToolTip {
                            text: i18np("%2: %1 session", "%2: %1 sessions", modelData.count, modelData.day)
                        }

                        HoverHandler {
                            id: barHover
                        }
                    }
                }
            }
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: i18np("%1 session over the last %2 days, %3 focused", "%1 sessions over the last %2 days, %3 focused", root.totalSessions, root.dayCount, TimerLogic.formatCounter(root.totalSeconds))
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: Kirigami.Theme.disabledTextColor
            wrapMode: Text.Wrap
        }
    }
}
