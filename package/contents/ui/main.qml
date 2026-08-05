import "./lib"
import "./lib/tasks.js" as Tasks
import "./lib/timer.js" as TimerLogic
import QtQml
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    property ExecUtil executable
    property string clock_fontfamily: plasmoid.configuration.clock_fontfamily || "Noto Sans"
    property int stateVal: 1
    property int initialSeconds: setInitialSeconds()

    // counterMilliseconds is the only stored countdown value; everything the UI
    // shows is derived from it. Keeping a second copy in seconds is what let
    // postpone() set the two to different lengths.
    property real counterMilliseconds: initialSeconds * 1000
    readonly property int counterSeconds: Math.ceil(counterMilliseconds / 1000)
    readonly property string timeText: TimerLogic.formatCounter(counterSeconds)
    // A panel column has room for about five glyphs, which the hours field breaks, so the
    // panel gets its own format. The popup and the tooltip keep timeText.
    readonly property string panelTimeText: TimerLogic.formatCounterPanel(counterSeconds)

    // Set while a break has run past its end and is counting the overrun. It has
    // to be a latched flag rather than a derived binding, because the
    // end-of-break notification and script must fire exactly once.
    property bool breakOvertime: false

    property int tickingSeconds: plasmoid.configuration.ticking_time
    property string sessionBtnText: i18n("St&art")
    property string sessionBtnIconSource: "media-playback-start"
    property string statusText: i18n("focus")
    property date previousTime: new Date()
    property int numberOfSessions: plasmoid.configuration.number_of_sessions
    readonly property string inhibitCmd: "kde-inhibit --notifications sleep 99999"
    readonly property bool flowmodoroModeEnabled: plasmoid.configuration.flowmodoro_mode_enabled // to update counter seconds when flowmode is enabled
    readonly property int focusTime: plasmoid.configuration.focus_time

    // The countdown crossing a second boundary is the only trigger for the
    // ticking sound; it used to be driven by an explicit updateTime() call that
    // every state transition had to remember to make.
    onCounterSecondsChanged: {
        if (!timer.running || !plasmoid.configuration.timer_tick_sfx_enabled)
            return;
        if (!TimerLogic.shouldTick(counterSeconds, initialSeconds, tickingSeconds, isBreak()))
            return;
        // Volume lives on the AudioOutput in Qt6, not on MediaPlayer; Sfx.play
        // takes it so callers cannot reintroduce the throw that once stopped the
        // ticking sound from playing at all.
        playSound(plasmoid.configuration.timer_tick_sfx_filepath, TimerLogic.tickVolume(counterSeconds, tickingSeconds));
    }

    onFlowmodoroModeEnabledChanged: {
        stop();
    }
    onFocusTimeChanged: {
        stop();
    }

    function setInitialSeconds() {
        // sets default value for counter
        if (flowmodoroModeEnabled && !isBreak()) {
            return 0;
        } else {
            return plasmoid.configuration.focus_time * 60;
        }
    }

    function shiftCounter(seconds) {
        if (counterSeconds + seconds > 0) {
            counterMilliseconds += seconds * 1000;
            initialSeconds += seconds;
        }
    }

    // Scroll wheel adds or removes whole minutes. Takes the caller's leftover
    // delta, returns the new leftover.
    // magic number 120 for common "one click"
    // See: http://qt-project.org/doc/qt-5/qml-qtquick-wheelevent.html#angleDelta-prop
    function scrollByWheel(wheelDelta, eventDelta) {
        wheelDelta += eventDelta;
        while (wheelDelta >= 120) {
            wheelDelta -= 120;
            shiftCounter(60);
        }
        while (wheelDelta <= -120) {
            wheelDelta += 120;
            shiftCounter(-60);
        }
        return wheelDelta;
    }

    readonly property real soundVolume: plasmoid.configuration.sound_volume / 100

    function playSound(path, factor) {
        if (path)
            sfx.play(path, soundVolume * (factor === undefined ? 1 : factor));
    }

    // Whether this event should show a popup. Focus and breaks are configured
    // separately; the existing timer_* keys are the focus ones.
    function wantsNotification(breakEvent, atEnd) {
        if (breakEvent)
            return atEnd ? plasmoid.configuration.break_end_notification_enabled : plasmoid.configuration.break_start_notification_enabled;
        return atEnd ? plasmoid.configuration.timer_end_notification_enabled : plasmoid.configuration.timer_start_notification_enabled;
    }

    // The sound file for this event, or "" for silence.
    function soundFor(breakEvent, atEnd) {
        if (breakEvent) {
            if (atEnd)
                return plasmoid.configuration.break_end_sfx_enabled ? plasmoid.configuration.break_end_sfx_filepath : "";
            return plasmoid.configuration.break_start_sfx_enabled ? plasmoid.configuration.break_start_sfx_filepath : "";
        }
        if (atEnd)
            return plasmoid.configuration.timer_stop_sfx_enabled ? plasmoid.configuration.timer_stop_sfx_filepath : "";
        return plasmoid.configuration.timer_start_sfx_enabled ? plasmoid.configuration.timer_start_sfx_filepath : "";
    }

    // The popup and the sound are independent: either, both or neither. Previously
    // the sound rode along inside the notification, so it could not play alone.
    function announce(breakEvent, atEnd, summary, actionLabel, action) {
        if (wantsNotification(breakEvent, atEnd))
            notificationManager.notify(summary, actionLabel, action);
        playSound(soundFor(breakEvent, atEnd));
    }

    // Caption for the state that is about to run, shared by the tooltip and the
    // start notification.
    function stateHeadline() {
        if (!isBreak())
            return i18n("Focus on your work!");
        if (isLongBreak())
            return i18n("Take a long break!");
        return i18n("Go for a walk.");
    }

    // The tooltip is the one place the whole state is visible at a glance, so it
    // reports where in the cycle the session is rather than a fixed sentence.
    function doneTodayText() {
        if (focusDoneToday === 0)
            return i18n("Nothing finished today yet.");
        return i18np("%1 focus session today, %2 in total", "%1 focus sessions today, %2 in total", focusDoneToday, TimerLogic.formatCounter(focusSecondsToday));
    }

    function getToolTipText() {
        if (breakOvertime)
            return i18n("Break ended %1 ago.", TimerLogic.formatCounter(-counterSeconds)) + "\n" + doneTodayText();
        if (!timer.running)
            return doneTodayText();
        if (flowmodoroModeEnabled)
            return isBreak() ? i18n("Flow break, %1 left", timeText) : i18n("Flow, %1 so far", timeText);
        if (isLongBreak())
            return i18n("Long break, %1 left", timeText);
        if (isBreak())
            return i18n("Short break, %1 left", timeText);
        if (numberOfSessions > 1)
            return i18n("Focus, session %1 of %2, %3 left", TimerLogic.sessionNumber(stateVal), numberOfSessions, timeText) + "\n" + doneTodayText();
        return i18n("Focus, %1 left", timeText) + "\n" + doneTodayText();
    }

    // The primary action, shared by the popup button and the compact
    // middle-click. During a break overrun it means "I am done, start focus".
    function toggleSession() {
        if (breakOvertime)
            finishBreak();
        else if (!timer.running)
            start();
        else if (flowmodoroModeEnabled)
            skip();
        else
            pause();
    }

    function start() {
        announce(isBreak(), false, stateHeadline());
        if (!isBreak())
            doNotDisturbEnable();
        previousTime = new Date();
        executeScript(1);
        timer.start();
        if (flowmodoroModeEnabled) {
            // "Break", not "Stop": in flowmodoro this button ends the flow and begins
            // the break it earned. It was labelled Stop while calling skip(), which is
            // the opposite of stopping.
            sessionBtnText = i18n("&Break");
            sessionBtnIconSource = "chronometer-pause";
        } else {
            sessionBtnText = i18n("Pa&use");
            sessionBtnIconSource = "media-playback-pause";
        }
        Plasmoid.status = PlasmaCore.Types.ActiveStatus;
        syncBreakDialog();
        saveSession();
    }

    function pause() {
        doNotDisturbDisable();
        timer.stop();
        sessionBtnText = i18n("St&art");
        sessionBtnIconSource = "media-playback-start";
        syncBreakDialog();
        saveSession();
    }

    function end() {
        doNotDisturbDisable();
        // The state has not advanced yet, so isBreak() still describes the session
        // that just finished and the button names the next one. The guard matters
        // because auto-start may have begun it already by the time it is pressed.
        announce(isBreak(), true, isBreak() ? i18n("End of break.") : i18n("End of focus time."), isBreak() ? i18n("Start focus") : i18n("Start break"), function() {
            if (!timer.running)
                start();
        });
        executeScript(2);
        timer.stop();
        // Recorded before nextState()/resetTime() overwrite the lengths. Reaching
        // zero means it ran its full planned length - unless the task was switched
        // part-way, in which case the earlier stretches are already recorded and
        // only the last one is left to file.
        var wholeSession = isBreak() || taskSegmentStartSeconds === 0;
        var actual = wholeSession ? initialSeconds : initialSeconds - taskSegmentStartSeconds;
        recordSession(currentKind(), wholeSession ? initialSeconds : actual, actual);
        pulseOnEnd();
        sessionBtnText = i18n("St&art");
        sessionBtnIconSource = "media-playback-start";
        nextState();
        resetTime();
        if ((isBreak() && plasmoid.configuration.timer_auto_pause_enabled) || (!isBreak() && plasmoid.configuration.timer_auto_focus_enabled)) {
            start();
        } else {
            syncBreakDialog();
        saveSession();
            Plasmoid.status = PlasmaCore.Types.PassiveStatus;
        }
    }

    // A break that runs out with auto-start-focus off keeps counting, so the
    // overrun stays visible as a negative time until focus is started by hand.
    // The break is genuinely over, so everything that normally happens at the end
    // of one happens now; only the state change waits for the user. Staying on
    // the break state is what keeps the overlay up and the break colours in use.
    function beginBreakOvertime() {
        breakOvertime = true;
        pulseOnEnd();
        // The overrun keeps running until the user acts, so the button is the way
        // out of it. This is a break ending, so it uses the break keys.
        announce(true, true, i18n("End of break."), i18n("Start focus"), finishBreak);
        executeScript(2);
        statusText = i18n("break overrun");
        sessionBtnText = i18n("St&art");
        sessionBtnIconSource = "media-playback-start";
        saveSession();
    }

    // Leaving an overrun: advance out of the break the user has been sitting in,
    // then begin the focus session.
    function finishBreak() {
        // An overrunning break is not finished until now, so this is where its
        // real length is known: the planned length plus however far it ran over.
        // counterSeconds is negative during an overrun.
        recordSession(currentKind(), initialSeconds, initialSeconds - counterSeconds);
        nextState();
        resetTime();
        start();
    }

    function skip() {
        // A flow session counts up and never reaches zero, so skipping out of it
        // is the only point its length is known. It has no planned length.
        if (timer.running && flowmodoroModeEnabled && !isBreak())
            recordSession("flow", 0, TimerLogic.segmentSeconds(counterSeconds, taskSegmentStartSeconds));
        nextState();
        resetTime();
        syncBreakDialog();
        saveSession();
        if (!isBreak()) {
            doNotDisturbEnable();
        } else {
            doNotDisturbDisable();
        }
        if (flowmodoroModeEnabled && !isBreak()) {
            sessionBtnText = i18n("&Break");
            sessionBtnIconSource = "chronometer-pause";
        } else if (flowmodoroModeEnabled && isBreak()) {
            sessionBtnText = i18n("Sk&ip");
            sessionBtnIconSource = "media-skip-forward";
        }
    }

    function postpone() {
        breakOvertime = false;
        prevState();
        statusText = i18n("focus");
        initialSeconds = 60 * 5;
        previousTime = new Date();
        counterMilliseconds = initialSeconds * 1000;
        syncBreakDialog();
        saveSession();
        if (!isBreak()) {
            doNotDisturbEnable();
        } else {
            doNotDisturbDisable();
        }
    }

    function stop() {
        doNotDisturbDisable();
        executeScript(0);
        timer.stop();
        stateVal = 1;
        resetTime();
        sessionBtnText = i18n("St&art");
        sessionBtnIconSource = "media-playback-start";
        Plasmoid.status = PlasmaCore.Types.PassiveStatus;
        syncBreakDialog();
        saveSession();
    }

    // Caption for a session kind. Shared so the restore path does not need its own
    // copy of this mapping, which would be one more thing to keep in step.
    function captionFor(kind) {
        switch (kind) {
        case "flow":
            return i18n("flow");
        case "flowBreak":
            return i18n("flow break");
        case "longBreak":
            return i18n("long break");
        case "shortBreak":
            return i18n("short break");
        default:
            return i18n("focus");
        }
    }

    // Written down on every transition, so a plasmashell restart - an update, a
    // crash - does not discard a session in progress.
    function saveSession() {
        // Nothing is written until startup has settled. The config-change handlers
        // for focus_time and flowmodoro fire stop() while the applet is still being
        // built, and that stop() would otherwise save a fresh, stopped session over
        // the one being restored - which is exactly the state this feature exists to
        // keep.
        if (!sessionReady)
            return;
        var now = new Date().getTime();
        var countingUp = flowmodoroModeEnabled && !isBreak();
        plasmoid.configuration.session_state = TimerLogic.serializeSession({
            "stateVal": stateVal,
            "initialSeconds": initialSeconds,
            "running": timer.running,
            "breakOvertime": breakOvertime,
            "countingUp": countingUp,
            // A deadline rather than a remaining time, so the seconds Plasma was
            // down are counted the same way a suspend already is.
            "deadline": timer.running && !countingUp ? now + counterMilliseconds : 0,
            "remainingMs": timer.running ? 0 : counterMilliseconds,
            "startedAt": countingUp ? now - counterMilliseconds : 0,
            "taskSegmentStart": taskSegmentStartSeconds,
            "savedAt": now
        });
    }

    // Returns whether a session was picked up, so the caller knows not to autostart
    // a fresh one on top of it.
    function restoreSession() {
        var session = TimerLogic.parseSession(plasmoid.configuration.session_state);
        var now = new Date().getTime();
        if (!session || TimerLogic.sessionIsStale(session, now))
            return false;
        stateVal = session.stateVal;
        initialSeconds = session.initialSeconds;
        breakOvertime = session.breakOvertime === true;
        taskSegmentStartSeconds = session.taskSegmentStart || 0;
        statusText = breakOvertime ? i18n("break overrun") : captionFor(TimerLogic.sessionKind(stateVal, numberOfSessions, flowmodoroModeEnabled));
        previousTime = new Date();
        counterMilliseconds = TimerLogic.restoredCounterMs(session, now);
        if (!session.running)
            return true;
        // Deliberately not start(): resuming must not re-fire the start
        // notification or the start script, which already ran before the restart.
        timer.start();
        if (flowmodoroModeEnabled) {
            // "Break", not "Stop": in flowmodoro this button ends the flow and begins
            // the break it earned. It was labelled Stop while calling skip(), which is
            // the opposite of stopping.
            sessionBtnText = i18n("&Break");
            sessionBtnIconSource = "chronometer-pause";
        } else {
            sessionBtnText = i18n("Pa&use");
            sessionBtnIconSource = "media-playback-pause";
        }
        if (!isBreak())
            doNotDisturbEnable();
        Plasmoid.status = PlasmaCore.Types.ActiveStatus;
        syncBreakDialog();
        saveSession();
        return true;
    }

    function resetTime() {
        // Every transition ends up here, so this is the one place an overrun can
        // be cleared - except postpone(), which sets its own time.
        breakOvertime = false;
        // A new session starts a new stretch, whatever the task was before.
        taskSegmentStartSeconds = 0;
        var kind = TimerLogic.sessionKind(stateVal, numberOfSessions, flowmodoroModeEnabled);
        switch (kind) {
        case "flow":
            // A flow session counts up, so it has no length to run down.
            initialSeconds = 0;
            break;
        case "flowBreak":
            initialSeconds = Math.max(1, Math.floor(counterSeconds / plasmoid.configuration.flow_divisor));
            break;
        case "longBreak":
            initialSeconds = plasmoid.configuration.long_break_time * 60;
            break;
        case "shortBreak":
            initialSeconds = plasmoid.configuration.short_break_time * 60;
            break;
        default:
            initialSeconds = plasmoid.configuration.focus_time * 60;
            break;
        }
        statusText = captionFor(kind);
        previousTime = new Date();
        counterMilliseconds = initialSeconds * 1000;
    }

    // Driven by wall clock rather than by the tick count, so the countdown stays
    // correct if the timer fires late or the machine suspends.
    function setTime() {
        var currentTime = new Date();
        var timeDiff = currentTime.getTime() - previousTime.getTime();
        previousTime = currentTime;
        if (flowmodoroModeEnabled && !isBreak()) {
            counterMilliseconds += timeDiff;
        } else {
            counterMilliseconds -= timeDiff;
            if (counterMilliseconds <= 0 && !breakOvertime) {
                if (isBreak() && !plasmoid.configuration.timer_auto_focus_enabled)
                    beginBreakOvertime();
                else
                    end();
            }
        }
    }

    function doNotDisturbEnable() {
        if (plasmoid.configuration.do_not_disturb_enabled)
            executable.exec(inhibitCmd);
    }

    function doNotDisturbDisable() {
        // Unconditional: the inhibitor must be released even if the setting was
        // turned off while a session was already running.
        executable.stopExec(inhibitCmd);
    }

    // --- session history ---------------------------------------------------
    //
    // False until Component.onCompleted has finished, so startup churn cannot
    // overwrite the stored session. See saveSession().
    property bool sessionReady: false

    // Strips the popup back to the dial alone: no tabs, no task picker, no buttons, no
    // daily line. Runtime only rather than a config key - it is a way to look at the
    // timer for a moment, not a setting to carry across restarts.
    property bool focusMode: false

    // Bumped when a session finishes, to flash the panel icon for people who run
    // without notification sound and miss the moment (gitlab #17).
    property int endPulse: 0

    function pulseOnEnd() {
        if (plasmoid.configuration.flash_on_end)
            endPulse++;
    }

    // Bumped whenever the stored history changes, so the counts below recompute.
    // plasmoid.configuration is not itself a notifying source for this purpose.
    property int historyRevision: 0

    readonly property var historyEntries: {
        historyRevision; // establish the dependency
        return TimerLogic.parseHistory(plasmoid.configuration.session_history);
    }
    readonly property string today: TimerLogic.dayKey(new Date())
    readonly property int focusDoneToday: TimerLogic.countFocusOn(historyEntries, today)
    readonly property int focusSecondsToday: TimerLogic.focusSecondsOn(historyEntries, today)

    // Called at the point a session is known to have finished. plannedSeconds is
    // what it was set to run for; actualSeconds is what it really took, which
    // differ after a break overrun or a scroll adjustment.
    // task defaults to the current one; a task switch passes the outgoing task, so
    // the stretch is filed under the task it was actually worked on.
    // Where the current task's stretch began, as elapsed seconds into this session.
    // Non-zero only after a mid-session task switch.
    property int taskSegmentStartSeconds: 0

    function elapsedSeconds() {
        return TimerLogic.elapsedSeconds(initialSeconds, counterSeconds,
                                         flowmodoroModeEnabled && !isBreak());
    }

    // The single way the task changes, so switching it can never silently
    // re-attribute time already worked. Changing task mid-session closes the stretch
    // that ran under the old task as a finished session, then starts counting the
    // new one from here - the session itself keeps running.
    function setTask(title) {
        if (title === plasmoid.configuration.task_label)
            return;
        // Breaks are not filed against a task, and a session that has not started
        // has nothing to close: both fall out of the segment being zero.
        if (!isBreak()) {
            var elapsed = elapsedSeconds();
            var segment = TimerLogic.segmentSeconds(elapsed, taskSegmentStartSeconds);
            // The base advances only when the stretch was actually recorded. A stretch
            // too short to record leaves it where it is, so those minutes carry into the
            // next task's stretch rather than being lost - they end up filed under
            // whichever task is current once the total clears the minimum.
            if (segment > 0 && recordSession(currentKind(), segment, segment, plasmoid.configuration.task_label))
                taskSegmentStartSeconds = elapsed;
        }
        plasmoid.configuration.task_label = title;
        saveSession();
    }

    // Returns whether the stretch was recorded, so a task switch knows whether the
    // time has been accounted for or still needs carrying.
    function recordSession(kind, plannedSeconds, actualSeconds, task) {
        // A focus stretch shorter than the configured minimum is not recorded, so the
        // totals and the per-task breakdown are not littered with two-minute fragments.
        if (!TimerLogic.countsAsSession(kind, actualSeconds, plasmoid.configuration.min_session_minutes * 60))
            return false;
        var now = new Date();
        var entry = TimerLogic.makeEntry(kind, plannedSeconds, actualSeconds, now,
                                         task === undefined ? plasmoid.configuration.task_label : task);
        plasmoid.configuration.session_history = TimerLogic.appendHistory(plasmoid.configuration.session_history, entry, now);
        historyRevision++;
        return true;
    }

    // Todo list, read through the same revision trick as history.
    property int taskListRevision: 0

    // Visible tasks only: deleting a task archives it, so that the sessions recorded
    // against its name keep that name on the stats page. Nothing user-facing should
    // see an archived row.
    readonly property var taskList: {
        taskListRevision;
        return Tasks.visibleTasks(Tasks.parseTasks(plasmoid.configuration.task_list));
    }

    // Options for the timer page's task dropdown: no task, then every open task.
    readonly property var taskChoices: {
        var choices = [{ "text": i18n("No task"), "value": "" }];
        for (var i = 0; i < taskList.length; i++) {
            if (!taskList[i].done)
                choices.push({ "text": taskList[i].title, "value": taskList[i].title });
        }
        return choices;
    }

    function writeTaskList(json) {
        plasmoid.configuration.task_list = json;
        taskListRevision++;
    }

    // Renaming carries the recorded sessions with it, because history names its task
    // by title rather than by id: without the rewrite, a rename would leave every past
    // session under the old name and split one task's work in two on the stats page.
    function renameTask(id, newTitle) {
        var title = ("" + newTitle).trim();
        if (!title)
            return;
        var all = Tasks.parseTasks(plasmoid.configuration.task_list);
        var index = Tasks.indexOfTask(all, id);
        if (index < 0)
            return;
        var oldTitle = all[index].title;
        if (oldTitle === title)
            return;

        writeTaskList(Tasks.renameTask(plasmoid.configuration.task_list, id, title));
        plasmoid.configuration.session_history =
            TimerLogic.renameTaskInHistory(plasmoid.configuration.session_history, oldTitle, title);
        historyRevision++;

        // Deliberately not setTask(): that closes the current stretch and records a
        // session, which is right for switching task and wrong for renaming one. The
        // session carries on untouched under its new name.
        if (plasmoid.configuration.task_label === oldTitle)
            plasmoid.configuration.task_label = title;
    }

    // The kind of the session that is finishing right now, before nextState().
    function currentKind() {
        return TimerLogic.sessionKind(stateVal, numberOfSessions, flowmodoroModeEnabled);
    }

    // Stopped part-way rather than not started: stop() resets the counter to the
    // full session length, pause() leaves it where it was. A flow counts up, so
    // for it any progress at all means paused.
    readonly property bool sessionPaused: {
        if (timer.running || breakOvertime)
            return false;
        return initialSeconds > 0 ? counterSeconds < initialSeconds : counterSeconds > 0;
    }

    function progressFraction() {
        return TimerLogic.progressFraction(counterSeconds, initialSeconds);
    }

    function nextState() {
        stateVal = TimerLogic.nextState(stateVal, numberOfSessions, {
            "flowmodoro": flowmodoroModeEnabled,
            "skipShortBreak": plasmoid.configuration.short_break_time === 0,
            "skipLongBreak": plasmoid.configuration.long_break_time === 0
        });
    }

    function prevState() {
        stateVal = TimerLogic.prevState(stateVal);
    }

    // --- break overlay palette -------------------------------------------
    //
    // The overlay can keep its own light or dark palette regardless of the desktop
    // scheme: a dark overlay over a light desktop is much less of a jolt when a
    // break starts, which is the whole point of the thing. 0 follows Plasma.
    readonly property bool overlayThemeForced: plasmoid.configuration.break_overlay_theme !== 0
    readonly property bool overlayThemeDark: plasmoid.configuration.break_overlay_theme === 1

    // Read out of Breeze's own scheme files rather than guessed, so a forced palette
    // looks like the desktop it sits on. The dim colour is Breeze's ForegroundInactive:
    // an earlier guess of #7f8c8d was far too dark against the dark background, which
    // left the caption and the break ring muddy.
    readonly property color overlayBackgroundColor: overlayThemeForced
        ? (overlayThemeDark ? "#202326" : "#eff0f1")
        : Kirigami.Theme.backgroundColor
    readonly property color overlayTextColor: overlayThemeForced
        ? (overlayThemeDark ? "#fcfcfc" : "#232629")
        : Kirigami.Theme.textColor
    readonly property color overlayDimColor: overlayThemeForced
        ? (overlayThemeDark ? "#a1a9b1" : "#707d8a")
        : Kirigami.Theme.disabledTextColor
    readonly property color overlayHighlightColor: overlayThemeForced
        ? "#3daee9"
        : Kirigami.Theme.highlightColor

    // The overlay's equivalents of getCircleColor()/getTextColor(), which stay as
    // they are for the popup - only the overlay takes a palette of its own.
    function overlayCircleColor() {
        return isBreak() ? overlayDimColor : overlayHighlightColor;
    }

    function overlayCaptionColor() {
        return isBreak() ? overlayDimColor : overlayTextColor;
    }

    // Nothing to fill: a flow counts up with no target, and an overrunning break has
    // already spent its length, which the fraction reports as an empty ring. Both are
    // still actively running, so the ring sweeps instead of sitting at 0 or 100%.
    readonly property bool progressIndeterminate: timer.running
        && ((flowmodoroModeEnabled && !isBreak()) || breakOvertime)

    function getCircleColor() {
        return isBreak() ? Kirigami.Theme.disabledTextColor : Kirigami.Theme.highlightColor;
    }

    function getTextColor() {
        return isBreak() ? Kirigami.Theme.disabledTextColor : Kirigami.Theme.textColor;
    }

    // Walks whichever set of overlays exists. Only one Instantiator is active at a
    // time, but iterating both means no caller has to know which.
    function forEachOverlay(fn) {
        var sets = [breakOverlays, breakOverlaysLayer, breakOverlaysPlain, breakOverlaysPlainLayer];
        for (var s = 0; s < sets.length; s++) {
            for (var i = 0; i < sets[s].count; i++) {
                var overlay = sets[s].objectAt(i);
                if (overlay)
                    fn(overlay);
            }
        }
    }

    function hideBreakOverlays() {
        forEachOverlay(function(overlay) {
            overlay.hide();
        });
    }

    // Single entry point for the fullscreen overlay: every state transition calls
    // this, so the overlay can never be left up after the break it belongs to.
    function syncBreakDialog() {
        var wanted = breakOverlayWanted;
        forEachOverlay(function(overlay) {
            if (wanted)
                overlay.showOnItsScreen();
            else
                overlay.hide();
        });
    }

    function executeScript(state) {
        switch (state) {
        case 0:
            if (plasmoid.configuration.stop_script_enabled)
                executable.exec(["sh", plasmoid.configuration.stop_script_filepath]);
            break;
        case 1:
            if (isBreak()) {
                if (plasmoid.configuration.start_break_script_enabled)
                    executable.exec(["sh", plasmoid.configuration.start_break_script_filepath]);
            } else if (plasmoid.configuration.start_focus_script_enabled) {
                executable.exec(["sh", plasmoid.configuration.start_focus_script_filepath]);
            }
            break;
        case 2:
            if (isBreak()) {
                if (plasmoid.configuration.end_break_script_enabled)
                    executable.exec(["sh", plasmoid.configuration.end_break_script_filepath]);
            } else if (plasmoid.configuration.end_focus_script_enabled) {
                executable.exec(["sh", plasmoid.configuration.end_focus_script_filepath]);
            }
            break;
        }
    }

    function isBreak() {
        return TimerLogic.isBreak(stateVal);
    }

    function isLongBreak() {
        return TimerLogic.isLongBreak(stateVal, numberOfSessions);
    }

    // Which of the shared presets the configured durations amount to, or
    // presetCount() for a custom set. Same derivation the config page uses.
    readonly property int currentPreset: TimerLogic.matchPreset(plasmoid.configuration.focus_time, plasmoid.configuration.short_break_time, plasmoid.configuration.long_break_time)

    function applyPreset(index) {
        var preset = TimerLogic.presetAt(index);
        plasmoid.configuration.focus_time = preset.focus;
        plasmoid.configuration.short_break_time = preset.shortBreak;
        plasmoid.configuration.long_break_time = preset.longBreak;
        // focus_time changing already routes through onFocusTimeChanged -> stop(),
        // so the timer restarts on the new durations rather than finishing the old.
    }

    function presetLabel(index) {
        var preset = TimerLogic.presetAt(index);
        return i18n("%1 / %2 min", preset.focus, preset.shortBreak);
    }

    Plasmoid.status: PlasmaCore.Types.PassiveStatus
    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground
    toolTipMainText: timeText
    toolTipSubText: getToolTipText()
    switchWidth: Kirigami.Units.gridUnit * 12
    switchHeight: Kirigami.Units.gridUnit * 11

    // Right-clicking the panel icon previously offered nothing but Configure and
    // Remove. These drive exactly the same functions as the popup buttons.
    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: sessionBtnText.replace("&", "")
            icon.name: sessionBtnIconSource
            onTriggered: toggleSession()
        },
        PlasmaCore.Action {
            text: i18n("Skip")
            icon.name: "media-skip-forward"
            visible: !flowmodoroModeEnabled
            onTriggered: skip()
        },
        PlasmaCore.Action {
            // Stop in both modes, matching the popup button it drives: stop() halts and
            // zeroes the counter either way. This still said Reset in flowmodoro after
            // the buttons were renamed, so the menu and the popup disagreed.
            text: i18n("Stop")
            icon.name: "media-playback-stop"
            onTriggered: stop()
        },
        PlasmaCore.Action {
            // The property is isSeparator, not separator; the latter silently
            // fails to load the whole applet.
            isSeparator: true
        },
        // Switching mode goes through onFlowmodoroModeEnabledChanged -> stop(),
        // so the timer resets onto the other mode's rules.
        PlasmaCore.Action {
            text: i18n("Pomodoro")
            checkable: true
            checked: !flowmodoroModeEnabled
            onTriggered: plasmoid.configuration.flowmodoro_mode_enabled = false
        },
        PlasmaCore.Action {
            text: i18n("Flowmodoro")
            checkable: true
            checked: flowmodoroModeEnabled
            onTriggered: plasmoid.configuration.flowmodoro_mode_enabled = true
        },
        PlasmaCore.Action {
            isSeparator: true
            visible: !flowmodoroModeEnabled
        },
        // Presets are pomodoro-only: flowmodoro derives its break from the flow.
        // Checkable so the menu shows which set is in use, including when the
        // durations match none of them.
        PlasmaCore.Action {
            text: presetLabel(0)
            checkable: true
            checked: currentPreset === 0
            visible: !flowmodoroModeEnabled
            onTriggered: applyPreset(0)
        },
        PlasmaCore.Action {
            text: presetLabel(1)
            checkable: true
            checked: currentPreset === 1
            visible: !flowmodoroModeEnabled
            onTriggered: applyPreset(1)
        },
        PlasmaCore.Action {
            text: presetLabel(2)
            checkable: true
            checked: currentPreset === 2
            visible: !flowmodoroModeEnabled
            onTriggered: applyPreset(2)
        },
        PlasmaCore.Action {
            // Shown only when the durations match no preset, purely so the menu
            // does not look as though nothing is selected.
            text: i18n("Custom")
            checkable: true
            checked: currentPreset >= TimerLogic.presetCount()
            enabled: false
            visible: !flowmodoroModeEnabled && currentPreset >= TimerLogic.presetCount()
        }
    ]

    // Deferred rather than run from Component.onCompleted. Restoring can start a timer, show
    // fullscreen overlays, fire a notification and spawn the do-not-disturb inhibitor - all
    // while the applet is still being constructed and, at login, while plasmashell itself is
    // still coming up. That is the moment the shell was reported to crash on Fedora 44
    // (gitlab #59). A short wait costs an idle dial for half a second and takes the whole
    // sequence off the startup path.
    Timer {
        id: startupRestore

        interval: 600
        repeat: false
        onTriggered: {
            // A picked-up session wins over autostart: replacing it with a fresh one
            // would be exactly the loss this is meant to prevent.
            var resumed = restoreSession();
            // Only now may anything be written back.
            sessionReady = true;
            if (resumed)
                return;
            if (plasmoid.configuration.autostart) {
                start();
            }
        }
    }

    Component.onCompleted: startupRestore.start()

    // Removing the applet mid-session would otherwise leave the kde-inhibit child
    // holding notifications suppressed: nothing else on this path releases it.
    Component.onDestruction: {
        saveSession();
        doNotDisturbDisable();
    }

    NotificationManager {
        id: notificationManager
    }

    Sfx {
        id: sfx
    }

    // A break that has run out keeps counting, but the single sound at the moment it
    // ended is the easiest one to miss - that moment is usually the one spent away
    // from the desk. The reminder repeats the break-end sound until the overrun is
    // ended by hand, and respects the break-end sound setting: turning that off
    // means silence here too.
    Timer {
        id: overrunReminder

        interval: TimerLogic.overrunReminderMs(plasmoid.configuration.break_overrun_repeat_seconds)
        repeat: true
        running: root.breakOvertime && plasmoid.configuration.break_overrun_repeat_enabled
        onTriggered: root.playSound(root.soundFor(true, true))
    }

    // A session saves only on transitions, so its stored savedAt would age for as long
    // as the session runs - and staleness is judged by it for every running state.
    // Writing the state periodically keeps it recent, which is what tells a restart
    // apart from a reboot: an applet that stopped reporting in for longer than
    // SESSION_RUNNING_GRACE_MS was not running, so its session is not resumed. The
    // interval has to stay well under that grace window.
    Timer {
        id: sessionKeepalive

        interval: 10 * 1000
        repeat: true
        running: root.sessionReady && timer.running
        onTriggered: root.saveSession()
    }

    Timer {
        id: timer

        // The counter reads the wall clock, so the tick rate only bounds how
        // stale the display can be, not how accurate the countdown is.
        interval: 250
        repeat: true
        running: false
        triggeredOnStart: false
        onTriggered: setTime()
    }

    // org.kde.layershell is optional: layer-shell-qt is not installed on every
    // distribution, and importing a missing module from a file the applet loads takes the
    // whole applet down - which is exactly what happened on Kubuntu 25.10 (gitlab #58).
    //
    // Created dynamically instead, so a missing module is a component status this can read
    // rather than a fatal load error. Without it the overlay is an ordinary window: it still
    // covers every screen, it just does not follow a virtual desktop switch.
    readonly property bool layerShellAvailable: {
        var probe = Qt.createComponent(Qt.resolvedUrl("LayerShellProbe.qml"), Component.PreferSynchronous);
        var ready = probe.status === Component.Ready;
        probe.destroy();
        return ready;
    }

    // One overlay per screen. A single window covers only its own display, so a
    // break left every other monitor visible (gitlab #19).
    //
    // Two Instantiators rather than one, because the blurred and plain overlays are
    // different window types and a QML root type cannot be switched at runtime. Only
    // one is ever active, so the loops below still see exactly one overlay per screen.
    readonly property bool blurredOverlay: plasmoid.configuration.break_overlay_blur

    // Whether an overlay belongs on screen at all. The Instantiators below key off this, so
    // the windows exist only during a break rather than from the moment the applet loads.
    //
    // They used to be built as soon as the applet did: one fullscreen window per screen,
    // created while plasmashell was still starting, hidden and waiting. That is a poor trade
    // at the best of times and a plausible cause of the shell crashing at login on Fedora 44
    // when a session was restored mid-startup (gitlab #59).
    readonly property bool breakOverlayWanted: plasmoid.configuration.show_fullscreen_break
                                               && isBreak()
                                               && timer.running

    Instantiator {
        id: breakOverlays

        active: breakOverlayWanted && blurredOverlay && !layerShellAvailable
        model: Qt.application.screens
        onObjectAdded: (index, object) => syncBreakDialog()

        delegate: BreakOverlay {
            applet: root
            screenGeometry: Qt.rect(modelData.virtualX, modelData.virtualY, modelData.width, modelData.height)
            onCloseRequested: root.hideBreakOverlays()
        }
    }

    Instantiator {
        id: breakOverlaysLayer

        active: breakOverlayWanted && blurredOverlay && layerShellAvailable
        model: Qt.application.screens
        onObjectAdded: (index, object) => syncBreakDialog()

        delegate: BreakOverlayLayer {
            applet: root
            screenGeometry: Qt.rect(modelData.virtualX, modelData.virtualY, modelData.width, modelData.height)
            onCloseRequested: root.hideBreakOverlays()
        }
    }

    Instantiator {
        id: breakOverlaysPlain

        active: breakOverlayWanted && !blurredOverlay && !layerShellAvailable
        model: Qt.application.screens
        onObjectAdded: (index, object) => syncBreakDialog()

        delegate: BreakOverlayPlain {
            applet: root
            screenGeometry: Qt.rect(modelData.virtualX, modelData.virtualY, modelData.width, modelData.height)
            onCloseRequested: root.hideBreakOverlays()
        }
    }

    Instantiator {
        id: breakOverlaysPlainLayer

        active: breakOverlayWanted && !blurredOverlay && layerShellAvailable
        model: Qt.application.screens
        onObjectAdded: (index, object) => syncBreakDialog()

        delegate: BreakOverlayPlainLayer {
            applet: root
            screenGeometry: Qt.rect(modelData.virtualX, modelData.virtualY, modelData.width, modelData.height)
            onCloseRequested: root.hideBreakOverlays()
        }
    }

    executable: ExecUtil {
        id: executable
    }

    compactRepresentation: MouseArea {
        id: compactRoot

        property int wheelDelta: 0

        property bool isVertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        property bool showIcon: plasmoid.configuration.show_icon_in_compact_mode
        property bool showTime: plasmoid.configuration.show_time_in_compact_mode
        // With swap_icon_for_time the panel carries the icon while idle and the
        // countdown while running, rather than both at once. Everything below reads
        // wantIcon/wantTime so the two settings resolve in one place.
        readonly property bool swapWhenRunning: plasmoid.configuration.swap_icon_for_time && showIcon
        readonly property bool wantIcon: showIcon && !(swapWhenRunning && timer.running)
        readonly property bool wantTime: swapWhenRunning ? timer.running : showTime

        property int baseIconSize: Math.min(Kirigami.Units.iconSizes.large, isVertical ? root.width : root.height)
        property int baseHorizontalFontSize: Math.floor(Math.min(Kirigami.Units.iconSizes.large, root.height) * 0.6)

        // Horizontal only. The vertical case used to return
        // min(iconSizes.large * 0.4, width * 0.4), which capped the countdown at about
        // 17px however wide the panel was, and still overflowed once the string grew an
        // hours field. Vertically the label is fitted by Qt instead, see below.
        function getFontSize() {
            if (timeLabel.text.length > 5) {
                return Math.floor(baseHorizontalFontSize * 0.8);
            }
            return baseHorizontalFontSize;
        }

        // The row the countdown gets on a vertical panel. Explicit, so the applet's own
        // height stays bounded rather than following the text - which is the shape of the
        // vertical ballooning in gitlab #16.
        readonly property int verticalTimeHeight: Math.round(baseIconSize * 0.6)

        // In swap mode the footprint must not depend on which of the two is
        // currently showing, or the applet resizes every time a session starts or
        // stops and the whole panel shifts around it. Both states reserve the
        // larger box and the content is centred inside it.
        readonly property real timeExtent: baseHorizontalFontSize * 2.5
        readonly property real swapWidth: Math.max(baseIconSize, timeExtent)

        Layout.preferredHeight: {
            if (!isVertical)
                return baseIconSize;
            if (swapWhenRunning)
                return Math.max(baseIconSize, verticalTimeHeight);
            return wantTime ? baseIconSize + verticalTimeHeight : baseIconSize;
        }
        Layout.preferredWidth: {
            if (isVertical)
                return baseIconSize;
            if (swapWhenRunning)
                return swapWidth;
            return wantTime ? baseIconSize + timeExtent : baseIconSize;
        }

        Layout.minimumWidth: Kirigami.Units.iconSizes.small
        Layout.minimumHeight: Kirigami.Units.iconSizes.small
        Layout.maximumHeight: Layout.preferredHeight
        Layout.maximumWidth: Layout.preferredWidth

        // The flash lives here rather than on the icon: the panel may be showing the
        // icon, the countdown, or both, and animating the icon alone meant nothing
        // happened at all for anyone running with the countdown only.
        readonly property int pulse: root.endPulse

        onPulseChanged: endPulseAnimation.restart()

        SequentialAnimation {
            id: endPulseAnimation

            loops: 3

            NumberAnimation {
                target: compactRoot
                property: "opacity"
                to: 0.25
                duration: 160
                easing.type: Easing.InOutQuad
            }

            NumberAnimation {
                target: compactRoot
                property: "opacity"
                to: 1
                duration: 160
                easing.type: Easing.InOutQuad
            }
        }

        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton)
                root.expanded = !root.expanded;
            else
                toggleSession();
        }
        onWheel: wheel => {
            if (flowmodoroModeEnabled) {
                return;
            }

            wheelDelta = scrollByWheel(wheelDelta, wheel.angleDelta.y);
        }

        GridLayout {
            columns: isVertical ? 1 : 2
            rows: isVertical ? 2 : 1
            rowSpacing: 0
            columnSpacing: 0

            anchors.fill: parent
            visible: wantTime

            IndicatorIcon {
                visible: wantIcon

                // Centred in swap mode: it is the only thing in the box, so the
                // left-aligned position it uses beside the countdown would put it
                // somewhere the countdown never appears.
                Layout.alignment: (swapWhenRunning || isVertical) ? Qt.AlignCenter : Qt.AlignLeft | Qt.AlignVCenter
                Layout.preferredWidth: baseIconSize
                Layout.preferredHeight: baseIconSize

                style: plasmoid.configuration.panel_icon_style
                running: timer.running
                paused: root.sessionPaused
                progress: progressFraction()
                tint: getTextColor()
            }

            PlasmaComponents.Label {
                id: timeLabel

                font.pointSize: -1
                // Vertically the size is an upper bound and Text.Fit does the work, so the
                // countdown uses the whole column for two-digit minutes and shrinks only
                // when the string is genuinely longer. Horizontally the fixed size that
                // already worked is left alone.
                font.pixelSize: isVertical ? Math.round(baseIconSize * 0.75) : getFontSize()
                fontSizeMode: isVertical ? Text.Fit : Text.FixedSize
                minimumPixelSize: isVertical ? 6 : 1
                font.family: clock_fontfamily
                font.bold: plasmoid.configuration.clock_bold
                text: isVertical ? panelTimeText : timeText
                color: getTextColor()
                smooth: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter

                Layout.alignment: Qt.AlignCenter
                // Fitting needs a box to fit into: without a width the text would size
                // itself and Text.Fit would have nothing to work against.
                Layout.fillWidth: isVertical
                Layout.preferredHeight: isVertical ? verticalTimeHeight : implicitHeight
            }
        }

        IndicatorIcon {
            // Sized and centred to the same box the countdown uses, so swapping
            // between them does not move anything.
            anchors.centerIn: parent
            width: swapWhenRunning ? Math.min(parent.width, parent.height, baseIconSize) : parent.width
            height: width
            visible: !wantTime && wantIcon

            style: plasmoid.configuration.panel_icon_style
            running: timer.running
            paused: root.sessionPaused
            progress: progressFraction()
            tint: getTextColor()
        }
    }

    fullRepresentation: Item {
        id: fullRoot

        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.maximumWidth: Kirigami.Units.gridUnit * 24
        // Roomier than a bare dial: the popup now has tabs, a task list and a
        // chart to fit.
        Layout.minimumHeight: Kirigami.Units.gridUnit * 20
        Layout.maximumHeight: Kirigami.Units.gridUnit * 28

        HoverHandler {
            id: fullRepMouse
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            cursorShape: Qt.PointingHandCursor
        }

        PlasmaComponents.TabBar {
            id: tabBar

            visible: !root.focusMode

            anchors {
                top: fullRoot.top
                left: fullRoot.left
                right: fullRoot.right
                // Room for the toggle, which would otherwise sit on top of the last tab.
                rightMargin: focusModeButton.width
            }

            PlasmaComponents.TabButton {
                text: i18n("Timer")
                icon.name: "chronometer"
            }

            PlasmaComponents.TabButton {
                text: i18n("Tasks")
                icon.name: "view-task"
            }

            PlasmaComponents.TabButton {
                text: i18n("Stats")
                icon.name: "office-chart-bar"
            }
        }

        PlasmaComponents.ToolButton {
            id: focusModeButton

            // Above the pages, so it stays reachable as the way back out.
            z: 10
            flat: true
            display: QQC2.AbstractButton.IconOnly
            icon.name: root.focusMode ? "view-restore" : "view-fullscreen"
            text: root.focusMode ? i18n("Show the full popup") : i18n("Focus mode")
            onClicked: root.focusMode = !root.focusMode

            anchors {
                top: fullRoot.top
                right: fullRoot.right
            }

            PlasmaComponents.ToolTip {
                text: focusModeButton.text
                visible: focusModeHover.hovered
            }

            HoverHandler {
                id: focusModeHover
            }
        }

        QQC2.SwipeView {
            id: pages

            // Focus mode is the timer, whichever tab was last open.
            currentIndex: root.focusMode ? 0 : tabBar.currentIndex
            clip: true
            // Interactive swiping would fight the scroll-to-adjust gesture on the
            // timer page, so pages change only through the tab bar.
            interactive: false

            anchors {
                top: root.focusMode ? fullRoot.top : tabBar.bottom
                left: fullRoot.left
                right: fullRoot.right
                bottom: fullRoot.bottom
                topMargin: Kirigami.Units.smallSpacing
            }

            Item {
                id: timerPage

        // Chosen, not typed: tasks are created on the Tasks page, and this only
        // picks which of them the session is for.
        PlasmaComponents.ComboBox {
            id: taskPicker

            visible: !root.focusMode
            model: root.taskChoices
            textRole: "text"
            // displayText rather than a currentIndex binding. Binding currentIndex
            // to a value derived from the model means a model rebuild re-enters
            // the control's own index handling, which is a known recursion hazard
            // - one segfault was seen with that shape before this was changed.
            displayText: plasmoid.configuration.task_label || i18n("No task")
            // onActivated fires only on a real choice, so rebuilding the model
            // when the task list changes cannot overwrite the current task.
            onActivated: index => {
                root.setTask(root.taskChoices[index].value);
            }

            anchors {
                top: timerPage.top
                left: timerPage.left
                right: timerPage.right
                margins: Kirigami.Units.smallSpacing
            }
        }

        PlasmaComponents.Label {
            id: dailyLabel

            visible: !root.focusMode
            text: doneTodayText()
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: Kirigami.Theme.disabledTextColor
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter

            anchors {
                bottom: buttonsRow.top
                left: timerPage.left
                right: timerPage.right
                bottomMargin: Kirigami.Units.smallSpacing
            }
        }

        Item {
            anchors {
                // Anchoring to a hidden item still uses its geometry, so focus mode has
                // to re-anchor rather than rely on the chrome being invisible.
                top: root.focusMode ? timerPage.top : taskPicker.bottom
                left: timerPage.left
                right: timerPage.right
                bottom: root.focusMode ? timerPage.bottom : dailyLabel.top
            }

            MouseArea {
                property int wheelDelta: 0

                anchors.fill: parent
                onWheel: wheel => {
                    if (flowmodoroModeEnabled) {
                        return;
                    }
                    wheelDelta = scrollByWheel(wheelDelta, wheel.angleDelta.y);
                }
            }

            TimerFace {
                anchors.fill: parent

                // Larger with the chrome gone, which is the point of the mode.
                sizeDivisor: root.focusMode ? 1.15 : 1.4
                progress: progressFraction()
                // The ring used to be hidden during a flow for want of anything to
                // draw; the sweep is what to draw instead.
                showProgress: true
                indeterminate: progressIndeterminate
                timeText: root.timeText
                showTime: plasmoid.configuration.show_dial_time
                statusText: root.statusText
                sessionCount: numberOfSessions
                sessionIndex: (stateVal - 1) / 2
                showSessionDots: !flowmodoroModeEnabled && numberOfSessions > 1
                fontFamily: clock_fontfamily
                fontBold: plasmoid.configuration.clock_bold
                circleColor: getCircleColor()
                captionColor: getTextColor()
            }
        }

        RowLayout {
            id: buttonsRow
            spacing: 10
            height: Kirigami.Units.gridUnit * 2
            visible: !root.focusMode
                     && (!plasmoid.configuration.show_buttons_on_hover || fullRepMouse.hovered)

            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
            }

            PlasmaComponents.Button {
                text: i18n("Sk&ip")
                icon.name: "media-skip-forward"
                visible: !flowmodoroModeEnabled
                onClicked: skip()
            }

            PlasmaComponents.Button {
                id: sessionBtn
                text: sessionBtnText
                icon.name: sessionBtnIconSource
                onClicked: toggleSession()
            }

            PlasmaComponents.Button {
                // stop() halts the timer and resets the counter to zero in both modes,
                // so it is Stop in both. Calling it Reset in flowmodoro only made sense
                // while the other button was misnamed Stop.
                text: i18n("St&op")
                icon.name: "media-playback-stop"
                onClicked: stop()
            }
        }

            }

            TaskListView {
                tasksJson: plasmoid.configuration.task_list
                activeTask: plasmoid.configuration.task_label
                onSaveRequested: json => writeTaskList(json)
                onRenameRequested: (id, title) => renameTask(id, title)
                // Picking a task names the session and puts it on the dial.
                onTaskPicked: title => root.setTask(title)
            }

            StatsView {
                entries: root.historyEntries
                today: root.today
                workdaySeconds: plasmoid.configuration.workday_hours * 3600
            }
        }
    }
}
