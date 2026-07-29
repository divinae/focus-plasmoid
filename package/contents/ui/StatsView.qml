import "./lib/timer.js" as TimerLogic
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

// Statistics page: finished focus sessions per day as a bar chart, plus the
// figures for today. Reads history, owns no state.
Item {
    id: root

    required property var entries
    required property string today

    // Selected period. 1 is today alone, which is the figure people check most and
    // which the chart's 14-day default buried.
    property int dayCount: 14

    readonly property var periods: [
        { "label": i18n("Today"), "days": 1 },
        { "label": i18n("7 days"), "days": 7 },
        { "label": i18n("14 days"), "days": 14 },
        { "label": i18n("30 days"), "days": 30 }
    ]

    readonly property var buckets: TimerLogic.focusPerDay(entries, dayCount, new Date())
    readonly property int peak: TimerLogic.peakCount(buckets)
    readonly property int totalSessions: {
        var sum = 0;
        for (var i = 0; i < buckets.length; i++)
            sum += buckets[i].count;
        return sum;
    }
    readonly property var taskRows: TimerLogic.focusByTask(entries, dayCount, new Date())
    // Never zero: it divides the proportion bars below.
    readonly property real peakTaskSeconds: {
        var peak = 0;
        for (var i = 0; i < taskRows.length; i++) {
            if (taskRows[i].seconds > peak)
                peak = taskRows[i].seconds;
        }
        return Math.max(1, peak);
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

        PlasmaComponents.TabBar {
            id: periodBar

            Layout.fillWidth: true

            Repeater {
                model: root.periods

                PlasmaComponents.TabButton {
                    required property var modelData
                    required property int index

                    text: modelData.label
                    // The period drives dayCount rather than being bound from it, so
                    // the bar stays the single source of what is shown.
                    onClicked: root.dayCount = modelData.days
                }
            }
        }

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
            // Takes whatever the task list below does not need.
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

                        HoverHandler {
                            id: barHover
                        }

                        // A ToolTip shows nothing unless something drives visible.
                        // Without this the handler above was dead and no bar ever
                        // had a tooltip, despite one being declared.
                        PlasmaComponents.ToolTip {
                            text: i18np("%2: %1 session", "%2: %1 sessions", modelData.count, modelData.day)
                            visible: barHover.hovered
                        }
                    }
                }
            }
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            visible: root.taskRows.length > 0
            text: i18n("By task")
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            font.bold: true
            elide: Text.ElideRight
        }

        QQC2.ScrollView {
            Layout.fillWidth: true
            // Sized to its rows rather than filling: sharing the slack with the
            // chart left the list padded out with blank space below its last row.
            // Capped so a long task list scrolls instead of squeezing the chart out.
            Layout.preferredHeight: Math.min(taskList.contentHeight, root.height * 0.4)
            Layout.maximumHeight: root.height * 0.4
            visible: root.taskRows.length > 0
            clip: true

            ListView {
                id: taskList

                model: root.taskRows
                spacing: 1

                delegate: Item {
                    required property var modelData

                    width: taskList.width
                    height: taskName.implicitHeight + Kirigami.Units.smallSpacing

                    // Proportion of the heaviest task, drawn behind the text so a
                    // glance shows the split without a second chart.
                    Rectangle {
                        anchors {
                            left: parent.left
                            top: parent.top
                            bottom: parent.bottom
                        }
                        width: parent.width * modelData.seconds / root.peakTaskSeconds
                        color: Kirigami.Theme.highlightColor
                        opacity: 0.18
                        radius: 2
                    }

                    RowLayout {
                        anchors.fill: parent
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents.Label {
                            id: taskName

                            Layout.fillWidth: true
                            Layout.leftMargin: Kirigami.Units.smallSpacing
                            // Sessions run without a task are grouped, not dropped,
                            // so they need a name here.
                            text: modelData.task === "" ? i18n("No task") : modelData.task
                            font.italic: modelData.task === ""
                            elide: Text.ElideRight
                        }

                        PlasmaComponents.Label {
                            Layout.rightMargin: Kirigami.Units.smallSpacing
                            text: TimerLogic.formatCounter(modelData.seconds)
                            color: Kirigami.Theme.disabledTextColor
                        }
                    }
                }
            }
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            // "over the last 1 days" would be wrong, so today gets its own wording.
            text: root.dayCount === 1
                ? i18np("%1 session today, %2 focused", "%1 sessions today, %2 focused", root.totalSessions, TimerLogic.formatCounter(root.totalSeconds))
                : i18np("%1 session over the last %2 days, %3 focused", "%1 sessions over the last %2 days, %3 focused", root.totalSessions, root.dayCount, TimerLogic.formatCounter(root.totalSeconds))
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: Kirigami.Theme.disabledTextColor
            wrapMode: Text.Wrap
        }
    }
}
