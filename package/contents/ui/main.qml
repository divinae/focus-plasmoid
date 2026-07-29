import "./lib"
import "./lib/tasks.js" as Tasks
import "./lib/timer.js" as TimerLogic
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.private.kicker as Kicker

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
        sfx.play(plasmoid.configuration.timer_tick_sfx_filepath, TimerLogic.tickVolume(counterSeconds, tickingSeconds));
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
        if (plasmoid.configuration.timer_start_notification_enabled)
            notificationManager.notify(stateHeadline(), plasmoid.configuration.timer_start_sfx_enabled ? plasmoid.configuration.timer_start_sfx_filepath : "");
        if (!isBreak())
            doNotDisturbEnable();
        previousTime = new Date();
        executeScript(1);
        timer.start();
        if (flowmodoroModeEnabled) {
            sessionBtnText = i18n("St&op");
            sessionBtnIconSource = "media-playback-stop";
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
        if (plasmoid.configuration.timer_end_notification_enabled) {
            // The state has not advanced yet, so isBreak() still describes the
            // session that just finished and the button names the next one. The
            // guard matters because auto-start may have begun it already by the
            // time the button is pressed.
            notificationManager.notify(isBreak() ? i18n("End of break.") : i18n("End of focus time."), plasmoid.configuration.timer_stop_sfx_enabled ? plasmoid.configuration.timer_stop_sfx_filepath : "", isBreak() ? i18n("Start focus") : i18n("Start break"), function() {
                if (!timer.running)
                    start();
            });
        }
        executeScript(2);
        timer.stop();
        // Recorded before nextState()/resetTime() overwrite the lengths. Reaching
        // zero means it ran its full planned length.
        recordSession(currentKind(), initialSeconds, initialSeconds);
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
        if (plasmoid.configuration.timer_end_notification_enabled) {
            // The overrun keeps running until the user acts, so the button is the
            // way out of it.
            notificationManager.notify(i18n("End of break."), plasmoid.configuration.timer_stop_sfx_enabled ? plasmoid.configuration.timer_stop_sfx_filepath : "", i18n("Start focus"), finishBreak);
        }
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
            recordSession("flow", 0, counterSeconds);
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
            sessionBtnText = i18n("St&op");
            sessionBtnIconSource = "media-playback-stop";
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
        statusText = breakOvertime ? i18n("break overrun") : captionFor(TimerLogic.sessionKind(stateVal, numberOfSessions, flowmodoroModeEnabled));
        previousTime = new Date();
        counterMilliseconds = TimerLogic.restoredCounterMs(session, now);
        if (!session.running)
            return true;
        // Deliberately not start(): resuming must not re-fire the start
        // notification or the start script, which already ran before the restart.
        timer.start();
        if (flowmodoroModeEnabled) {
            sessionBtnText = i18n("St&op");
            sessionBtnIconSource = "media-playback-stop";
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
    function recordSession(kind, plannedSeconds, actualSeconds) {
        var now = new Date();
        var entry = TimerLogic.makeEntry(kind, plannedSeconds, actualSeconds, now, plasmoid.configuration.task_label);
        plasmoid.configuration.session_history = TimerLogic.appendHistory(plasmoid.configuration.session_history, entry, now);
        historyRevision++;
    }

    // Todo list, read through the same revision trick as history.
    property int taskListRevision: 0

    readonly property var taskList: {
        taskListRevision;
        return Tasks.parseTasks(plasmoid.configuration.task_list);
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

    function getCircleColor() {
        return isBreak() ? Kirigami.Theme.disabledTextColor : Kirigami.Theme.highlightColor;
    }

    function getTextColor() {
        return isBreak() ? Kirigami.Theme.disabledTextColor : Kirigami.Theme.textColor;
    }

    // Single entry point for the fullscreen overlay: every state transition calls
    // this, so the overlay can never be left up after the break it belongs to.
    function syncBreakDialog() {
        if (plasmoid.configuration.show_fullscreen_break && isBreak() && timer.running)
            breakDialog.showFullScreen();
        else
            breakDialog.hide();
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
            text: flowmodoroModeEnabled ? i18n("Reset") : i18n("Stop")
            icon.name: flowmodoroModeEnabled ? "chronometer-reset" : "media-playback-stop"
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

    Component.onCompleted: {
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

    Kicker.DashboardWindow {
        id: breakDialog

        flags: Qt.WindowStaysOnTopHint
        backgroundColor: Qt.hsla(Kirigami.Theme.backgroundColor.hslHue, Kirigami.Theme.backgroundColor.hslSaturation, Kirigami.Theme.backgroundColor.hslLightness, 0.85)

        Item {
            anchors.fill: parent

            TimerFace {
                id: overlayFace

                anchors.fill: parent

                sizeDivisor: 2.4
                progress: progressFraction()
                showProgress: !(flowmodoroModeEnabled && !isBreak())
                timeText: root.timeText
                showTime: plasmoid.configuration.show_dial_time
                statusText: root.statusText
                sessionCount: numberOfSessions
                sessionIndex: (stateVal - 1) / 2
                showSessionDots: !flowmodoroModeEnabled && numberOfSessions > 1
                fontFamily: clock_fontfamily
                circleColor: getCircleColor()
                captionColor: getTextColor()
            }

            // flash_on_end animates the compact representation, which this window
            // covers - panel included. So the overlay needs its own cue, or the
            // setting does nothing in the one case it matters most.
            readonly property int pulse: root.endPulse

            onPulseChanged: {
                if (plasmoid.configuration.flash_on_end)
                    overlayEndPulse.restart();
            }

            // The moment the break runs out.
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

            // And for as long as it keeps overrunning, since a single pulse is easy
            // to look away from. Slower and shallower, so it reads as a state rather
            // than an alarm. Stops by itself: every way out of the overrun clears
            // breakOvertime.
            SequentialAnimation {
                id: overlayOverrunBlink

                running: breakOvertime && plasmoid.configuration.flash_on_end && !overlayEndPulse.running
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
                    id: breakDialogMouse
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    cursorShape: Qt.PointingHandCursor
                }

                RowLayout {
                    spacing: 10
                    visible: !plasmoid.configuration.show_buttons_on_hover || breakDialogMouse.hovered
                    Layout.alignment: Qt.AlignHCenter

                    PlasmaComponents.Button {
                        visible: isBreak() && !flowmodoroModeEnabled && plasmoid.configuration.fullscreen_buttons_postpone
                        text: i18n("&Postpone")
                        icon.name: "circular-arrow-shape"
                        onClicked: postpone()
                    }

                    PlasmaComponents.Button {
                        visible: isBreak() && plasmoid.configuration.fullscreen_buttons_skip
                        text: i18n("Sk&ip")
                        icon.name: "go-next-skip"
                        onClicked: skip()
                    }

                    PlasmaComponents.Button {
                        visible: isBreak() && plasmoid.configuration.fullscreen_buttons_close
                        text: i18n("&Close")
                        icon.name: "dialog-close"
                        onClicked: {
                            breakDialog.close();
                        }
                    }

                    PlasmaComponents.Button {
                        // The overlay is only up while a break is running, so
                        // this is reachable exactly during a break overrun: it is
                        // how the user says the break is finished.
                        visible: breakOvertime || !isBreak()
                        text: i18n("St&art")
                        icon.name: "media-playback-start"
                        onClicked: toggleSession()
                    }
                }
            }
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

        function getFontSize() {
            if (isVertical) {
                return Math.floor(Math.min(Kirigami.Units.iconSizes.large * 0.4, root.width * 0.4));
            } else {
                if (timeLabel.text.length > 5) {
                    return Math.floor(baseHorizontalFontSize * 0.8);
                }
                return baseHorizontalFontSize;
            }
        }

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
                return Math.max(baseIconSize, timeLabel.height);
            return wantTime ? baseIconSize + timeLabel.height : baseIconSize;
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
                font.pixelSize: getFontSize()
                fontSizeMode: Text.FixedSize
                font.family: clock_fontfamily
                text: timeText
                minimumPixelSize: 1
                color: getTextColor()
                smooth: true
                Layout.alignment: Qt.AlignCenter
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

            anchors {
                top: fullRoot.top
                left: fullRoot.left
                right: fullRoot.right
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

        QQC2.SwipeView {
            id: pages

            currentIndex: tabBar.currentIndex
            clip: true
            // Interactive swiping would fight the scroll-to-adjust gesture on the
            // timer page, so pages change only through the tab bar.
            interactive: false

            anchors {
                top: tabBar.bottom
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
                plasmoid.configuration.task_label = root.taskChoices[index].value;
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
                top: taskPicker.bottom
                left: timerPage.left
                right: timerPage.right
                bottom: dailyLabel.top
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

                sizeDivisor: 1.4
                progress: progressFraction()
                showProgress: !(flowmodoroModeEnabled && !isBreak())
                timeText: root.timeText
                showTime: plasmoid.configuration.show_dial_time
                statusText: root.statusText
                sessionCount: numberOfSessions
                sessionIndex: (stateVal - 1) / 2
                showSessionDots: !flowmodoroModeEnabled && numberOfSessions > 1
                fontFamily: clock_fontfamily
                circleColor: getCircleColor()
                captionColor: getTextColor()
            }
        }

        RowLayout {
            id: buttonsRow
            spacing: 10
            height: Kirigami.Units.gridUnit * 2
            visible: !plasmoid.configuration.show_buttons_on_hover || fullRepMouse.hovered

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
                text: flowmodoroModeEnabled ? i18n("Re&set") : i18n("St&op")
                icon.name: flowmodoroModeEnabled ? "chronometer-reset" : "media-playback-stop"
                onClicked: stop()
            }
        }

            }

            TaskListView {
                tasksJson: plasmoid.configuration.task_list
                activeTask: plasmoid.configuration.task_label
                onSaveRequested: json => writeTaskList(json)
                // Picking a task names the session and puts it on the dial.
                onTaskPicked: title => plasmoid.configuration.task_label = title
            }

            StatsView {
                entries: root.historyEntries
                today: root.today
            }
        }
    }
}
