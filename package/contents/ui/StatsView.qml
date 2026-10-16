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
    // A working day in seconds, for accounting the period against it. 0 leaves that out.
    // Passed in rather than read here, so this view still touches no configuration.
    property int workdaySeconds: 0

    // Colours come from the caller, not from Kirigami.Theme here: the applet reads the
    // theme in exactly one place, and the note above that palette in main.qml says why a
    // read per delegate used to take plasmashell down.
    required property color accentColor
    required property color dimColor
    required property color textColor
    required property color surfaceColor

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

    // Each of these counts back from now; naming today makes them recount when the day
    // turns over, not only when the history changes. A fresh Date rather than one built
    // from the key: midnight minus whole days drifts across a DST change.
    readonly property var buckets: {
        today; // establish the dependency
        return TimerLogic.focusPerDay(entries, dayCount, new Date());
    }
    // Bars are scaled by time, not by session count: every other figure on this page is
    // time, and a bar height that meant "sessions" was read as time anyway. Floored by the
    // working day so its reference line stays inside the plot.
    readonly property int peak: TimerLogic.peakSeconds(buckets, workdaySeconds)
    readonly property var timeline: TimerLogic.dayTimeline(entries, today)
    // Task rows past this get folded into a "+N more" line, which returns height to the
    // chart. Three covers most days without the list taking over the page.
    readonly property int visibleTaskRows: 3
    readonly property int totalSessions: {
        var sum = 0;
        for (var i = 0; i < buckets.length; i++)
            sum += buckets[i].count;
        return sum;
    }
    readonly property var taskRows: {
        today; // establish the dependency
        return TimerLogic.focusByTask(entries, dayCount, new Date());
    }
    readonly property int totalSeconds: {
        var sum = 0;
        for (var i = 0; i < buckets.length; i++)
            sum += buckets[i].seconds;
        return sum;
    }

    // How the selected period was spent: focus, breaks, and the gaps between sessions.
    readonly property var breakdown: {
        today; // establish the dependency
        return TimerLogic.periodBreakdown(entries, dayCount, new Date());
    }
    readonly property int accountedSeconds: breakdown.focusSeconds + breakdown.breakSeconds
    // Scaled per day worked, so a week containing days off is not held to a full day each.
    readonly property int targetSeconds: workdaySeconds * breakdown.daysWorked

    function clockTime(ms) {
        return Qt.formatTime(new Date(ms), Qt.locale(), Locale.ShortFormat);
    }

    readonly property bool darkTheme: root.surfaceColor.hslLightness < 0.5

    // The colour for a task, shared by the stacked bars and the list below them so the
    // list doubles as the legend.
    //
    // Pastel and deliberately narrow: rather than spending the whole colour wheel, the
    // hue is spread across a band centred on the theme's own highlight, so the chart
    // stays in the desktop's family and no block shouts over its neighbours. Tasks are
    // still told apart, just not by maximum contrast. Saturation is low and lightness
    // follows the theme, so the same band works on either background.
    readonly property real taskHueBand: 110

    // Called once per bar segment, timeline block and legend row, so it reads the cached
    // accent rather than the theme - see the palette note above.
    function taskColor(task) {
        var hue = TimerLogic.taskHue(task);
        if (hue < 0)
            return root.accentColor; // sessions run with no task
        var centre = root.accentColor.hslHue * 360;
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

        // One figure with weight, rather than four lines of equal quietness. The session
        // count rides along as a suffix: it was a line of its own saying what this line
        // and the chart already say.
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignBaseline
                text: i18n("%1 focused", TimerLogic.formatDurationCompact(root.breakdown.focusSeconds))
                font.pointSize: Math.round(Kirigami.Theme.defaultFont.pointSize * 1.6)
                elide: Text.ElideRight
            }

            PlasmaComponents.Label {
                Layout.alignment: Qt.AlignBaseline
                text: i18np("%1 session", "%1 sessions", root.totalSessions)
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: root.dimColor
            }

            PlasmaComponents.ComboBox {
                id: periodPicker

                Layout.alignment: Qt.AlignVCenter
                model: root.periods
                textRole: "label"
                // Set once rather than bound to dayCount: binding currentIndex to a
                // value the control itself writes is the recursion hazard the task
                // picker in main.qml documents, and one segfault was seen with it.
                Component.onCompleted: currentIndex = root.periodIndexOf(root.dayCount)
                onActivated: index => root.dayCount = root.periods[index].days
            }
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
                    color: root.accentColor
                    radius: 2
                }

                Rectangle {
                    width: parent.width * root.breakdown.breakSeconds / parent.usable
                    height: parent.height
                    color: root.dimColor
                    opacity: 0.75
                }

                Rectangle {
                    width: parent.width * root.breakdown.idleSeconds / parent.usable
                    height: parent.height
                    // The same faint wash the chart uses for a day with nothing in it.
                    color: root.textColor
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

        // Each figure carries the colour it has in the strip above, which is what makes
        // the strip readable without a caption explaining it.
        RowLayout {
            Layout.fillWidth: true
            visible: root.breakdown.sessions > 0
            spacing: Kirigami.Units.largeSpacing

            Repeater {
                model: [
                    { "label": i18n("focus"), "seconds": root.breakdown.focusSeconds, "swatch": root.accentColor, "swatchOpacity": 1 },
                    { "label": i18n("breaks"), "seconds": root.breakdown.breakSeconds, "swatch": root.dimColor, "swatchOpacity": 0.75 },
                    { "label": i18n("idle"), "seconds": root.breakdown.idleSeconds, "swatch": root.textColor, "swatchOpacity": 0.12 }
                ]

                delegate: RowLayout {
                    required property var modelData

                    spacing: Kirigami.Units.smallSpacing

                    Rectangle {
                        implicitWidth: Kirigami.Units.smallSpacing * 2
                        implicitHeight: implicitWidth
                        radius: 2
                        color: modelData.swatch
                        opacity: modelData.swatchOpacity
                    }

                    PlasmaComponents.Label {
                        text: i18nc("focus 5h20", "%1 %2", modelData.label,
                                    TimerLogic.formatDurationCompact(modelData.seconds))
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        color: root.dimColor
                    }
                }
            }

            Item {
                Layout.fillWidth: true
            }
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            visible: root.breakdown.sessions > 0 && root.targetSeconds > 0
            text: i18n("%1 of %2 accounted for",
                       TimerLogic.formatDurationCompact(root.accountedSeconds),
                       TimerLogic.formatDurationCompact(root.targetSeconds))
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: root.dimColor
            elide: Text.ElideRight
        }

        // Today gets a clock, everything else gets bars: a single day drawn as one bar
        // says nothing, which is what it was doing since Today became the default period.
        DayTimeline {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.maximumHeight: Kirigami.Units.gridUnit * 3.5
            visible: root.dayCount === 1 && root.timeline.blocks.length > 0
            timeline: root.timeline
            colorForTask: root.taskColor
            dimColor: root.dimColor
            textColor: root.textColor
        }

        Item {
            Layout.fillWidth: true
            // Takes whatever the task list below does not need.
            Layout.fillHeight: true
            visible: root.dayCount > 1

            // Where the plot ends and the weekday initials begin.
            readonly property real labelsHeight: Kirigami.Theme.smallFont.pixelSize > 0
                ? Kirigami.Theme.smallFont.pixelSize + 2
                : Kirigami.Units.gridUnit

            Item {
                id: plot

                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    bottomMargin: parent.labelsHeight
                }

                // The working day, so a bar can be read as "most of a day" or "an hour"
                // without counting pixels. Drawn behind the bars.
                Item {
                    visible: root.workdaySeconds > 0 && root.workdaySeconds <= root.peak
                    y: plot.height * (1 - root.workdaySeconds / root.peak)
                    width: plot.width
                    height: 1

                    Row {
                        width: parent.width
                        spacing: 3

                        Repeater {
                            // A dashed line, drawn as dashes: a 1px Rectangle cannot be
                            // dashed and a Canvas here would need its own repaint handling.
                            model: Math.max(1, Math.floor(plot.width / 6))

                            delegate: Rectangle {
                                width: 3
                                height: 1
                                color: root.textColor
                                opacity: 0.35
                            }
                        }
                    }

                    PlasmaComponents.Label {
                        anchors {
                            right: parent.right
                            bottom: parent.top
                        }
                        text: i18nc("8 hours, the working day", "%1h", Math.round(root.workdaySeconds / 3600))
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        color: root.dimColor
                        opacity: 0.8
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    spacing: 2

                    Repeater {
                        model: root.buckets

                        delegate: Item {
                            id: bar

                            required property var modelData
                            required property int index

                            readonly property int total: modelData.seconds + modelData.breakSeconds
                            readonly property real fullHeight: total > 0
                                ? Math.max(2, height * total / root.peak)
                                : 0

                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            // Track, so an empty day still reads as a day rather than as a
                            // gap in the chart.
                            Rectangle {
                                anchors.fill: parent
                                color: root.textColor
                                opacity: 0.08
                                radius: 2
                            }

                            // Focus at the base, break stacked above it. Two segments
                            // rather than one per task: at thirty days a task split turns
                            // into slivers, and the names live in the legend below.
                            Column {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    bottom: parent.bottom
                                }

                                Rectangle {
                                    width: parent.width
                                    height: bar.total > 0 ? bar.fullHeight * bar.modelData.breakSeconds / bar.total : 0
                                    color: root.dimColor
                                    opacity: (bar.index === root.buckets.length - 1 ? 1 : 0.65) * 0.75
                                    radius: 2

                                    Behavior on height {
                                        NumberAnimation {
                                            duration: 150
                                        }
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: bar.total > 0 ? bar.fullHeight * bar.modelData.seconds / bar.total : 0
                                    color: root.accentColor
                                    // Today stands out from the rest of the window.
                                    opacity: bar.index === root.buckets.length - 1 ? 1 : 0.65

                                    Behavior on height {
                                        NumberAnimation {
                                            duration: 150
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

            // Weekday initials, so a bar is identifiable without hovering it. Every bar up
            // to a fortnight; past that they would collide, so only every fifth.
            RowLayout {
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                height: parent.labelsHeight
                spacing: 2

                Repeater {
                    model: root.buckets

                    delegate: PlasmaComponents.Label {
                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        // Blanked rather than hidden: a hidden item leaves the RowLayout,
                        // so the remaining labels spread evenly and stop lining up with
                        // the bars they name. Counted back from today, so today is always
                        // labelled.
                        text: root.buckets.length <= 14
                              || (root.buckets.length - 1 - index) % 5 === 0
                            ? Qt.locale().dayName(TimerLogic.dateFromDayKey(modelData.day).getDay(),
                                                  Locale.NarrowFormat)
                            : ""
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        font.bold: index === root.buckets.length - 1
                        color: root.dimColor
                        elide: Text.ElideNone
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

        // The legend for the timeline's colours, and the period's split by task. Capped:
        // the list used to be allowed 40% of the height, which it spent on rows nobody
        // scrolled to while the chart was squeezed above it.
        Repeater {
            model: root.taskRows.slice(0, root.visibleTaskRows)

            delegate: RowLayout {
                required property var modelData

                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                // A solid chip, not a wash behind the text: at 0.3 alpha the old bar was
                // too faint to match a block in the chart, which is the one job it had.
                Rectangle {
                    implicitWidth: Kirigami.Units.smallSpacing * 2
                    implicitHeight: implicitWidth
                    radius: 2
                    color: root.taskColor(modelData.task)
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    // Sessions run without a task are grouped, not dropped, so they need
                    // a name here.
                    text: modelData.task === "" ? i18n("No task") : modelData.task
                    font.italic: modelData.task === ""
                    elide: Text.ElideRight
                }

                PlasmaComponents.Label {
                    text: TimerLogic.formatDurationCompact(modelData.seconds)
                    color: root.dimColor
                }

                // Share of the period's focus, which is the comparison the old proportion
                // bar was reaching for - and it was scaled to the heaviest task, not to the
                // total, so it answered a question nobody asked.
                PlasmaComponents.Label {
                    Layout.minimumWidth: Kirigami.Units.gridUnit * 2
                    horizontalAlignment: Text.AlignRight
                    visible: root.breakdown.focusSeconds > 0
                    text: i18nc("percentage of focus time", "%1%",
                                Math.round(100 * modelData.seconds / root.breakdown.focusSeconds))
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    color: root.dimColor
                }
            }
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            visible: root.taskRows.length > root.visibleTaskRows
            text: i18np("+%1 more task", "+%1 more tasks",
                        root.taskRows.length - root.visibleTaskRows)
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: root.dimColor
            elide: Text.ElideRight
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            visible: root.breakdown.sessions === 0
            text: i18n("Nothing recorded in this period yet.")
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: root.dimColor
            wrapMode: Text.Wrap
        }

        // Soaks up the slack when the lists are short, so nothing stretches oddly.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: root.dayCount === 1
        }
    }
}
