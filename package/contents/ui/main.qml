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
    // Every MPRIS player on the session bus is told to pause; one that is not playing
    // ignores it, so there is nothing to check first. dbus-send rather than the
    // private Plasma MPRIS module, which has no stable API. KDE Connect players are
    // somebody's phone, not this desk, and are left alone.
    readonly property string pauseMediaCmd: "for p in $(dbus-send --session --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ListNames | grep -o 'org\\.mpris\\.MediaPlayer2\\.[^\"]*' | grep -v '\\.kdeconnect\\.'); do dbus-send --session --type=method_call --dest=\"$p\" /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.Pause; done"
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
        claimStartup();
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
        // Focus is what just finished, so a break is what comes next.
        if (!isBreak())
            pauseMedia();
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
        claimStartup();
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
            pauseMedia();
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
        claimStartup();
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
        claimStartup();
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
            "savedAt": now,
            // Which boot this belongs to, so the restore can refuse a session the
            // machine was rebooted out of. See sessionIsStale().
            "bootId": bootId
        });
    }

    // Returns whether a RUNNING session was picked up, so the caller knows not to autostart
    // on top of one already counting. A stopped session is still restored - its state and
    // what was left on the clock - but it does not count as picked up: nothing is running,
    // so autostart has nothing to overwrite and every reason to fire.
    function restoreSession() {
        var session = TimerLogic.parseSession(plasmoid.configuration.session_state);
        var now = new Date().getTime();
        if (!session || TimerLogic.sessionIsStale(session, now, bootId))
            return false;
        stateVal = session.stateVal;
        initialSeconds = session.initialSeconds;
        breakOvertime = session.breakOvertime === true;
        taskSegmentStartSeconds = session.taskSegmentStart || 0;
        statusText = breakOvertime ? i18n("break overrun") : captionFor(TimerLogic.sessionKind(stateVal, numberOfSessions, flowmodoroModeEnabled));
        previousTime = new Date();
        counterMilliseconds = TimerLogic.restoredCounterMs(session, now);
        // Restored, but not running: "Start the timer when Plasma starts" is what autostart
        // promises, and a stopped session left over from the last login is not a running
        // timer. Reporting it as picked up is why autostart did nothing whenever anything at
        // all was stored - which is most logins (gitlab #47).
        if (!session.running)
            return false;
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
    // Ends a session early, keeping the part that really ran. Two callers: a gap the
    // machine slept through, and the Stop the user pressed. Either way the time before
    // it was worked, so it is recorded; the gap itself is not, which is the whole point.
    //
    // From setTime() this runs before the counter has seen the gap, so the elapsed figure
    // here is the state as at the last tick.
    function interruptSession() {
        if (!isBreak()) {
            var segment = TimerLogic.segmentSeconds(elapsedSeconds(), taskSegmentStartSeconds);
            // A flow has no length to plan, so it is filed with a planned zero - the same
            // shape skip() writes, which is the other way out of one.
            var planned = (flowmodoroModeEnabled && !isBreak()) ? 0 : segment;
            if (segment > 0)
                recordSession(currentKind(), planned, segment);
        }
        // stop() resets to the first focus session and leaves the panel showing Start, so the
        // interruption is visible rather than silently rolled into the next session.
        stop();
    }

    // Ends the day rather than the session: the break stops and nothing follows it, so
    // the flowmodoro chain is broken instead of advanced the way skip() advances it. The
    // work already done is filed; a break that has not run its length is not, which is
    // interruptSession()'s existing rule.
    //
    // A thin wrapper on purpose: the two buttons that call it read as what they do, and
    // stop() alone - which is what they used to call - would have dropped the flow.
    function endForToday() {
        interruptSession();
    }

    function setTime() {
        var currentTime = new Date();
        var timeDiff = currentTime.getTime() - previousTime.getTime();
        previousTime = currentTime;
        // A jump this large is the machine having been away, not time spent working.
        if (TimerLogic.isTimeGap(timeDiff)) {
            interruptSession();
            return;
        }
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

    function pauseMedia() {
        if (plasmoid.configuration.break_pause_media_enabled)
            executable.exec(pauseMediaCmd);
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
    // Kept current by dayTurnover below: a binding on new Date() is evaluated once
    // and would hold the day the applet loaded on until the next restart (#67).
    property string today: TimerLogic.dayKey(new Date())
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

    // --- the palette, read once ---------------------------------------------------
    //
    // The applet root is never in a window itself; only its representations are. A theme
    // read here therefore drives libplasma's Kirigami style - PlasmaTheme::syncColors() -
    // with no on-screen item owning the result, and that path took plasmashell down with
    // a SIGSEGV, notifying a change event to a null receiver:
    //
    //   QCoreApplication::notifyInternal2 (receiver=0x0)
    //   Kirigami::Platform::PlatformTheme::setHighlightColor
    //   PlasmaTheme::syncColors  (libplasma 6.7.4, plasmatheme.cpp:150)
    //
    // So the theme is read once, a pass after construction, and every caller takes the
    // cached value. A plasmoid has no sandbox - it runs inside plasmashell - so staying
    // off that path is the applet's own responsibility.
    property bool paletteReady: false
    readonly property color themeTextColor: paletteReady ? Kirigami.Theme.textColor : "transparent"
    readonly property color themeDimColor: paletteReady ? Kirigami.Theme.disabledTextColor : "transparent"
    readonly property color themeAccentColor: paletteReady ? Kirigami.Theme.highlightColor : "transparent"
    readonly property color themeSurfaceColor: paletteReady ? Kirigami.Theme.backgroundColor : "transparent"

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
        : root.themeSurfaceColor
    readonly property color overlayTextColor: overlayThemeForced
        ? (overlayThemeDark ? "#fcfcfc" : "#232629")
        : root.themeTextColor
    readonly property color overlayDimColor: overlayThemeForced
        ? (overlayThemeDark ? "#a1a9b1" : "#707d8a")
        : root.themeDimColor
    readonly property color overlayHighlightColor: overlayThemeForced
        ? "#3daee9"
        : root.themeAccentColor

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
        return isBreak() ? themeDimColor : themeAccentColor;
    }

    function getTextColor() {
        return isBreak() ? themeDimColor : themeTextColor;
    }

    // Walks whichever set of overlays exists. Only one Instantiator is active at a
    // time, but iterating both means no caller has to know which.
    function forEachOverlay(fn) {
        // The layer sets live behind Loaders, so their item is null until loaded.
        var sets = [breakOverlays, breakOverlaysPlain,
                    breakOverlaysLayer.item, breakOverlaysPlainLayer.item];
        for (var s = 0; s < sets.length; s++) {
            if (!sets[s])
                continue;
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
            // Stop in both modes, matching the popup button it drives: it halts and
            // zeroes the counter either way, and takes the popup's break-time name too so
            // the menu and the popup cannot disagree - which they did while this still
            // said Reset in flowmodoro.
            text: (isBreak() || breakOvertime) ? i18n("End for today") : i18n("Stop")
            icon.name: "media-playback-stop"
            onTriggered: endForToday()
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

    // Startup runs once both of these are true: the short deferral below has elapsed, and
    // the boot id has either arrived or been given up on. Restoring before the id is known
    // would resume a session the machine was rebooted out of.
    // False until Component.onCompleted has run. Everything that happens before that is the
    // applet building itself, not the user doing something.
    property bool constructed: false
    property bool startupDelayed: false
    property bool bootIdSettled: false
    property bool startupDone: false

    // The kernel boot id, empty until read. Identifies the boot the machine is on, which is
    // how a plasmashell restart is told apart from a reboot without the session having to
    // write itself down every few seconds to prove the machine stayed up.
    property string bootId: ""
    readonly property string bootIdCmd: "cat /proc/sys/kernel/random/boot_id"

    // The read is asynchronous, and a click in the moment before it answers saves a session
    // stamped with no boot id at all - which sessionIsStale() can only read as "cannot tell",
    // so that session would survive a reboot and be resumed on the other side. The state the
    // user was found with had exactly that: an empty bootId. Stamping it as soon as the id
    // arrives closes the window.
    onBootIdChanged: {
        if (sessionReady && bootId !== "")
            saveSession();
    }

    // Startup is deferred by a moment and by the boot id read, and the applet is live in the
    // meantime. Anyone who starts or stops a session inside that window has said what they
    // want, so the pending startup must not act on top of it: without this, restoreSession()
    // could replace the session just started, or autostart could start a second one - firing
    // the start notification and the start script twice and inhibiting do-not-disturb again.
    function claimStartup() {
        // Only a real interaction may claim startup. stop() is also called from the config
        // handlers - onFocusTimeChanged and onFlowmodoroModeEnabledChanged both fire while the
        // configuration loads - and those calls used to mark startup as spent before it had
        // run, so autostart never started anything. Nobody can click before construction ends,
        // so that is the line between the two (gitlab #47).
        if (!constructed)
            return;
        if (startupDone)
            return;
        startupDone = true;
        // The user's session is worth writing down; nothing else has been restored over it.
        sessionReady = true;
    }

    function beginStartup() {
        if (startupDone || !startupDelayed || !bootIdSettled)
            return;
        startupDone = true;
        // A picked-up session wins over autostart: replacing it with a fresh one
        // would be exactly the loss this is meant to prevent.
        var resumed = restoreSession();
        // Only now may anything be written back.
        sessionReady = true;
        if (resumed)
            return;
        if (plasmoid.configuration.autostart)
            start();
    }

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
            root.startupDelayed = true;
            root.beginStartup();
        }
    }

    // The boot id read is a few milliseconds, but the session must still come back if it
    // never answers at all: without an id the age of the state is the only test left.
    Timer {
        id: bootIdTimeout

        interval: 2500
        repeat: false
        onTriggered: {
            root.bootIdSettled = true;
            root.beginStartup();
        }
    }

    Component.onCompleted: {
        // A pass later, so nothing reads the theme while the shell is still building and
        // attaching the representations - which is when the null-receiver crash happened.
        Qt.callLater(function() {
            root.paletteReady = true;
        });
        constructed = true;
        executable.exec(bootIdCmd, function(cmd, exitCode, exitStatus, stdout) {
            if (exitCode === 0)
                root.bootId = ("" + stdout).trim();
            root.bootIdSettled = true;
            root.beginStartup();
        });
        bootIdTimeout.start();
        startupRestore.start();
    }

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
    // Polled rather than aimed at midnight, so a machine that slept through it still
    // turns the day over within a minute of waking.
    Timer {
        id: dayTurnover

        interval: 60 * 1000
        repeat: true
        running: true
        onTriggered: {
            var day = TimerLogic.dayKey(new Date());
            if (day !== root.today)
                root.today = day;
        }
    }

    Timer {
        id: overrunReminder

        interval: TimerLogic.overrunReminderMs(plasmoid.configuration.break_overrun_repeat_seconds)
        repeat: true
        running: root.breakOvertime && plasmoid.configuration.break_overrun_repeat_enabled
        onTriggered: root.playSound(root.soundFor(true, true))
    }

    // A flow counts up with no end, so there is nothing to stop it being left running
    // after the work stopped - a walk away with the timer still going is the failure mode
    // this mode has and the countdown does not. The reminder asks, and carries the way out
    // with it, so the flow can be ended from the notification instead of the panel.
    //
    // No sound, deliberately: this is a question, not a deadline, and the break-end sound
    // would announce something that has not happened.
    Timer {
        id: flowReminder

        interval: TimerLogic.flowReminderMs(plasmoid.configuration.flow_reminder_minutes)
        repeat: true
        running: timer.running && root.flowmodoroModeEnabled && !root.isBreak()
                 && plasmoid.configuration.flow_reminder_enabled
        // The interval counts from when the timer started running, so a flow picked up
        // after a plasmashell restart is asked about a full interval later rather than
        // immediately.
        onTriggered: notificationManager.notifyActions(i18n("Still in flow? %1 so far.", root.timeText),
                                                       [{
                                                           "label": i18n("Take a break"),
                                                           "action": root.skip
                                                       }, {
                                                           // Restarts the wait, so carrying on
                                                           // buys a full interval rather than
                                                           // leaving the original cadence to
                                                           // ask again moments later.
                                                           "label": i18n("Keep going"),
                                                           "action": function() {
                                                               flowReminder.restart();
                                                           }
                                                       }])
    }

    // Every running session, not only a flow. saveSession() is otherwise called at
    // transitions alone, so savedAt ages with the session and sessionIsStale() cannot tell a
    // session that has been running for an hour from one that was written an hour ago and
    // then abandoned - plasmashell gone, or the machine asleep. A write a minute is what lets
    // the age test stand on its own, without exemptions that invent time.
    Timer {
        id: sessionKeepalive

        interval: 60 * 1000
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
            screen: modelData
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
            screen: modelData
            screenGeometry: Qt.rect(modelData.virtualX, modelData.virtualY, modelData.width, modelData.height)
            onCloseRequested: root.hideBreakOverlays()
        }
    }

    // The layer-shell variants are reached by URL, never by type name. A static type
    // reference is an eager dependency - QML resolves every composite type a document names,
    // including in an inactive delegate - so naming them here made this file fail to load
    // wherever org.kde.layershell is absent, which is the failure #58 reported. The probe
    // above never got the chance to matter.
    //
    // A Loader source is resolved at runtime, so on a machine without the module these files
    // are never opened. Clearing the source unloads them, which also keeps the windows tied
    // to a break actually being on screen (gitlab #59).
    Loader {
        id: breakOverlaysLayer

        // No `active:` here. It is evaluated at completion, which would force the
        // layerShellAvailable probe - and with it the org.kde.layershell import - onto
        // plasmashell's startup path, which is what #59 was about. The source expression
        // below is false at startup, so the probe stays lazy until the first break.
        source: (breakOverlayWanted && blurredOverlay && layerShellAvailable)
            ? Qt.resolvedUrl("BreakOverlaySetLayer.qml") : ""
        onLoaded: {
            item.applet = root;
            item.closeRequested.connect(root.hideBreakOverlays);
            root.syncBreakDialog();
        }
    }

    Loader {
        id: breakOverlaysPlainLayer

        source: (breakOverlayWanted && !blurredOverlay && layerShellAvailable)
            ? Qt.resolvedUrl("BreakOverlaySetLayerPlain.qml") : ""
        onLoaded: {
            item.applet = root;
            item.closeRequested.connect(root.hideBreakOverlays);
            root.syncBreakDialog();
        }
    }

    executable: ExecUtil {
        id: executable
    }

    compactRepresentation: MouseArea {
        id: compactRoot

        // Nothing here may paint outside the box the panel gave us. The icon overflowing its
        // box is what #60 reported - drawn over the neighbouring plasmoid - and a clip is the
        // difference between a sizing mistake looking cramped and it vandalising the panel.
        clip: true

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
                indeterminate: progressIndeterminate
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
            //
            // Bounded by the box in BOTH dimensions, always. Taking parent.width alone, as the
            // non-swap case used to, made the icon as tall as the panel is thick - while the
            // applet had only asked for iconSizes.large of height - so on any vertical panel
            // thicker than 48px it drew over the plasmoid below it. Measured: 8px over on a
            // 56px panel, 52px on a 100px one (gitlab #60).
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height, baseIconSize)
            height: width
            visible: !wantTime && wantIcon

            style: plasmoid.configuration.panel_icon_style
            running: timer.running
            paused: root.sessionPaused
            progress: progressFraction()
            indeterminate: progressIndeterminate
            tint: getTextColor()
        }
    }

    fullRepresentation: Item {
        id: fullRoot

        // Whether the stats page has been asked for. A latch rather than a live test of
        // the tab index: unloading the page on every tab change would rebuild the chart
        // from scratch each time it is opened.
        property bool statsRequested: false

        // The popup is what makes the tab reachable, so an index left on Stats from the
        // last time cannot load the page while the applet is still collapsed.
        readonly property bool statsTabOpen: root.expanded && !root.focusMode && tabBar.currentIndex === 2

        onStatsTabOpenChanged: if (statsTabOpen)
            statsRequested = true

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
            color: root.themeDimColor
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
                // Halts the timer and resets the counter to zero in both modes, so it is
                // Stop in both. Calling it Reset in flowmodoro only made sense while the
                // other button was misnamed Stop.
                //
                // During a break it is renamed rather than joined by a second button:
                // ending a break is the point at which "stop" means "that is me done",
                // since the alternative - Skip - carries on into the next session.
                //
                // endForToday() wraps interruptSession(), not stop(): what was worked
                // before the press is still worked, and in flowmodoro this is the only way
                // out of a flow besides Break, so a bare stop() dropped whole flows on the
                // floor. stop() itself stays silent because the config handlers call it
                // while the applet is still loading.
                text: (isBreak() || breakOvertime) ? i18n("&End for today") : i18n("St&op")
                icon.name: "media-playback-stop"
                onClicked: endForToday()
            }
        }

            }

            TaskListView {
                dimColor: root.themeDimColor
                textColor: root.themeTextColor
                tasksJson: plasmoid.configuration.task_list
                activeTask: plasmoid.configuration.task_label
                onSaveRequested: json => writeTaskList(json)
                onRenameRequested: (id, title) => renameTask(id, title)
                // Picking a task names the session and puts it on the dial.
                onTaskPicked: title => root.setTask(title)
            }

            // Behind a Loader, and built only once the tab is actually opened. The stats
            // page is by far the largest tree the applet makes - a bar per day, a legend
            // row per task, and a block with a tooltip per recorded session - and
            // SwipeView builds every page eagerly, so it used to be constructed while the
            // popup was being reparented into its window. plasmashell died there: a
            // SIGSEGV inside KirigamiPlasmaStyle, pushing a highlight colour through
            // Kirigami's PlatformTheme as the tree attached to the window, with no frame
            // of this applet's own in the backtrace. An empty history never crashed; a
            // real one crashed every time.
            //
            // Same lesson as the overlay windows in #59: keep the heavy tree off the path
            // that runs while the shell is still assembling things.
            Loader {
                id: statsPage

                // Not just currentIndex: once the page has been opened it stays loaded, so
                // switching tabs back and forth does not rebuild the chart every time.
                active: fullRoot.statsRequested
                // Off the reparenting path entirely - the tree is built after the window
                // exists, not during the property write that attaches it.
                asynchronous: true

                sourceComponent: StatsView {
                    entries: root.historyEntries
                    today: root.today
                    workdaySeconds: plasmoid.configuration.workday_hours * 3600
                    accentColor: root.themeAccentColor
                    dimColor: root.themeDimColor
                    textColor: root.themeTextColor
                    surfaceColor: root.themeSurfaceColor
                }
            }
        }
    }
}
