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
    // A working day in seconds, for accounting the period against it. 0 leaves that out.
    // Passed in rather than read here, so this view still touches no configuration.
    property int workdaySeconds: 0

    // Selected period. Today by default: it is the figure people check most, and the
    // fortnight it replaced buried it in a row of bars.
    property int dayCount: 1

    // Which entry of periods matches a day count, so the picker can start on the
    // current one without binding its index.
    function periodIndexOf(days) {
        for (var i = 0; i < periods.length; i++) {
            if (periods[i].days === days)
                return i;
        }
        return 0;
    }

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

    // How the selected period was spent: focus, breaks, and the gaps between sessions.
    readonly property var breakdown: TimerLogic.periodBreakdown(entries, dayCount, new Date())
    readonly property int accountedSeconds: breakdown.focusSeconds + breakdown.breakSeconds
    // Scaled per day worked, so a week containing days off is not held to a full day each.
    readonly property int targetSeconds: workdaySeconds * breakdown.daysWorked

    function clockTime(ms) {
        return Qt.formatTime(new Date(ms), Qt.locale(), Locale.ShortFormat);
    }

    readonly property bool darkTheme: Kirigami.Theme.backgroundColor.hslLightness < 0.5

    // The colour for a task, shared by the stacked bars and the list below them so the
    // list doubles as the legend.
    //
    // Pastel and deliberately narrow: rather than spending the whole colour wheel, the
    // hue is spread across a band centred on the theme's own highlight, so the chart
    // stays in the desktop's family and no block shouts over its neighbours. Tasks are
    // still told apart, just not by maximum contrast. Saturation is low and lightness
    // follows the theme, so the same band works on either background.
    readonly property real taskHueBand: 110

    function taskColor(task) {
        var hue = TimerLogic.taskHue(task);
        if (hue < 0)
            return Kirigami.Theme.highlightColor; // sessions run with no task
        var centre = Kirigami.Theme.highlightColor.hslHue * 360;
        var spread = (hue / 360) * root.taskHueBand - root.taskHueBand / 2;
        return Qt.hsla((((centre + spread) % 360) + 360) % 360 / 360,
                       0.32,
                       root.darkTheme ? 0.68 : 0.58,
                       1);
    }

    // Tooltip body for a day: the per-task split, so the colours have names.
    function bucketText(bucket) {
        if (!bucket.count)
            return i18n("%1: nothing", bucket.day);
        var breakSeconds = TimerLogic.breakSecondsOn(root.entries, bucket.day);
        var lines = [breakSeconds > 0
            ? i18n("%1 - breaks %2", bucket.day, TimerLogic.formatCounter(breakSeconds))
            : bucket.day];
        for (var i = 0; i < bucket.segments.length; i++) {
            var segment = bucket.segments[i];
            lines.push(i18nc("task: 2 sessions, 50m", "%1: %2 (%3)",
                             segment.task || i18n("No task"),
                             i18np("%1 session", "%1 sessions", segment.count),
                             TimerLogic.formatCounter(segment.seconds)));
        }
        return lines.join("\n");
    }

    // Bars are drawn with Rectangles rather than a Canvas: there are at most a
    // few dozen, and this keeps the theme colours live without a repaint handler,
    // which is what ProgressCircle had to grow.
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        // The period shares a row with today's count rather than taking one of its
        // own: a tab bar across the full width cost more space than the figures it
        // was filtering, in a popup that has little to spare.
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: i18np("%1 focus session today", "%1 focus sessions today", TimerLogic.countFocusOn(root.entries, root.today))
                elide: Text.ElideRight
            }

            PlasmaComponents.ComboBox {
                id: periodPicker

                model: root.periods
                textRole: "label"
                // Set once rather than bound to dayCount: binding currentIndex to a
                // value the control itself writes is the recursion hazard the task
                // picker in main.qml documents, and one segfault was seen with it.
                Component.onCompleted: currentIndex = root.periodIndexOf(root.dayCount)
                onActivated: index => root.dayCount = root.periods[index].days
            }
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: i18n("%1 focused today", TimerLogic.formatCounter(TimerLogic.focusSecondsOn(root.entries, root.today)))
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: Kirigami.Theme.disabledTextColor
            elide: Text.ElideRight
        }

        // Focus against breaks against idle. The bar chart below answers "how many
        // sessions"; this answers "where did the day go", which is a different question
        // and the one an eight-hour day raises.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 0.6
            visible: root.breakdown.sessions > 0

            Row {
                anchors.fill: parent

                // Widths come from the span, so the three together fill the strip exactly.
                readonly property real usable: root.breakdown.spanSeconds > 0
                    ? root.breakdown.spanSeconds
                    : Math.max(1, root.accountedSeconds)

                Rectangle {
                    width: parent.width * root.breakdown.focusSeconds / parent.usable
                    height: parent.height
                    color: Kirigami.Theme.highlightColor
                    radius: 2
                }

                Rectangle {
                    width: parent.width * root.breakdown.breakSeconds / parent.usable
                    height: parent.height
                    color: Kirigami.Theme.disabledTextColor
                    opacity: 0.75
                }

                Rectangle {
                    width: parent.width * root.breakdown.idleSeconds / parent.usable
                    height: parent.height
                    // The same faint wash the chart uses for a day with nothing in it.
                    color: Kirigami.Theme.textColor
                    opacity: 0.12
                    radius: 2
                }
            }

            HoverHandler {
                id: stripHover
            }

            PlasmaComponents.ToolTip {
                visible: stripHover.hovered
                text: root.dayCount === 1 && root.breakdown.sessions > 0
                    ? i18n("Working window %1 to %2.\nIdle is the time between recorded sessions. Sessions you skip, and focus stretches below the minimum length, are not recorded and count as idle.",
                           root.clockTime(TimerLogic.dayBreakdown(root.entries, root.today).firstStart),
                           root.clockTime(TimerLogic.dayBreakdown(root.entries, root.today).lastEnd))
                    : i18n("Idle is the time between recorded sessions, counted within each day. Sessions you skip, and focus stretches below the minimum length, are not recorded and count as idle.")
            }
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            visible: root.breakdown.sessions > 0
            text: i18nc("focus 5:20 - breaks 1:05 - idle 2:10",
                        "focus %1 \u00b7 breaks %2 \u00b7 idle %3",
                        TimerLogic.formatCounter(root.breakdown.focusSeconds),
                        TimerLogic.formatCounter(root.breakdown.breakSeconds),
                        TimerLogic.formatCounter(root.breakdown.idleSeconds))
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: Kirigami.Theme.disabledTextColor
            elide: Text.ElideRight
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            visible: root.breakdown.sessions > 0 && root.targetSeconds > 0
            text: i18n("%1 of %2 accounted for",
                       TimerLogic.formatCounter(root.accountedSeconds),
                       TimerLogic.formatCounter(root.targetSeconds))
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
                        id: bar

                        required property var modelData
                        required property int index

                        // Lightest first, because a Column fills downwards and the bar
                        // grows from the bottom: this puts the heaviest task at the base.
                        readonly property var stack: modelData.segments.slice().reverse()
                        readonly property real fullHeight: modelData.count > 0
                            ? Math.max(2, height * modelData.count / root.peak)
                            : 0

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

                        // One block per task rather than one per day: four tasks in an
                        // afternoon used to look the same as one.
                        Column {
                            anchors {
                                left: parent.left
                                right: parent.right
                                bottom: parent.bottom
                            }

                            Repeater {
                                model: bar.stack

                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index

                                    readonly property var segment: modelData

                                    width: parent.width
                                    height: bar.modelData.count > 0
                                        ? bar.fullHeight * segment.count / bar.modelData.count
                                        : 0
                                    color: root.taskColor(segment.task)
                                    // Only the top block is rounded; rounding every one
                                    // would draw seams through the middle of the bar.
                                    radius: index === 0 ? 2 : 0
                                    // Today stands out from the rest of the window.
                                    opacity: bar.index === root.buckets.length - 1 ? 1 : 0.65

                                    Behavior on height {
                                        NumberAnimation {
                                            duration: 150
                                        }
                                    }
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
                            text: root.bucketText(bar.modelData)
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
                        // Same colour as the task's blocks in the chart, so this list
                        // reads as the legend for it.
                        color: root.taskColor(modelData.task)
                        opacity: 0.3
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
