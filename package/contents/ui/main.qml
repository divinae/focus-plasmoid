import "./lib"
import "./lib/timer.js" as TimerLogic
import QtMultimedia
import QtQuick
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
        sfx.source = plasmoid.configuration.timer_tick_sfx_filepath;
        // Qt6 moved volume off MediaPlayer onto AudioOutput. Writing sfx.volume
        // throws, which aborted this handler before play() and meant the ticking
        // sound never played at all.
        sfxOutput.volume = TimerLogic.tickVolume(counterSeconds, tickingSeconds);
        sfx.play();
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
    function getToolTipText() {
        if (breakOvertime)
            return i18n("Break ended %1 ago.", TimerLogic.formatCounter(-counterSeconds));
        if (!timer.running)
            return "";
        if (flowmodoroModeEnabled)
            return isBreak() ? i18n("Flow break, %1 left", timeText) : i18n("Flow, %1 so far", timeText);
        if (isLongBreak())
            return i18n("Long break, %1 left", timeText);
        if (isBreak())
            return i18n("Short break, %1 left", timeText);
        if (numberOfSessions > 1)
            return i18n("Focus, session %1 of %2, %3 left", TimerLogic.sessionNumber(stateVal), numberOfSessions, timeText);
        return i18n("Focus, %1 left", timeText);
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
    }

    function pause() {
        doNotDisturbDisable();
        timer.stop();
        sessionBtnText = i18n("St&art");
        sessionBtnIconSource = "media-playback-start";
        syncBreakDialog();
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
        sessionBtnText = i18n("St&art");
        sessionBtnIconSource = "media-playback-start";
        nextState();
        resetTime();
        if ((isBreak() && plasmoid.configuration.timer_auto_pause_enabled) || (!isBreak() && plasmoid.configuration.timer_auto_focus_enabled)) {
            start();
        } else {
            syncBreakDialog();
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
        if (plasmoid.configuration.timer_end_notification_enabled) {
            // The overrun keeps running until the user acts, so the button is the
            // way out of it.
            notificationManager.notify(i18n("End of break."), plasmoid.configuration.timer_stop_sfx_enabled ? plasmoid.configuration.timer_stop_sfx_filepath : "", i18n("Start focus"), finishBreak);
        }
        executeScript(2);
        statusText = i18n("break overrun");
        sessionBtnText = i18n("St&art");
        sessionBtnIconSource = "media-playback-start";
    }

    // Leaving an overrun: advance out of the break the user has been sitting in,
    // then begin the focus session.
    function finishBreak() {
        nextState();
        resetTime();
        start();
    }

    function skip() {
        nextState();
        resetTime();
        syncBreakDialog();
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
    }

    function resetTime() {
        // Every transition ends up here, so this is the one place an overrun can
        // be cleared - except postpone(), which sets its own time.
        breakOvertime = false;
        switch (TimerLogic.sessionKind(stateVal, numberOfSessions, flowmodoroModeEnabled)) {
        case "flow":
            // A flow session counts up, so it has no length to run down.
            initialSeconds = 0;
            statusText = i18n("flow");
            break;
        case "flowBreak":
            initialSeconds = Math.max(1, Math.floor(counterSeconds / plasmoid.configuration.flow_divisor));
            statusText = i18n("flow break");
            break;
        case "longBreak":
            initialSeconds = plasmoid.configuration.long_break_time * 60;
            statusText = i18n("long break");
            break;
        case "shortBreak":
            initialSeconds = plasmoid.configuration.short_break_time * 60;
            statusText = i18n("short break");
            break;
        default:
            initialSeconds = plasmoid.configuration.focus_time * 60;
            statusText = i18n("focus");
            break;
        }
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
        if (plasmoid.configuration.autostart) {
            start();
        }
    }

    // Removing the applet mid-session would otherwise leave the kde-inhibit child
    // holding notifications suppressed: nothing else on this path releases it.
    Component.onDestruction: {
        doNotDisturbDisable();
    }

    NotificationManager {
        id: notificationManager
    }

    MediaPlayer {
        id: sfx

        audioOutput: AudioOutput {
            id: sfxOutput
        }
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
                anchors.fill: parent

                sizeDivisor: 2.4
                progress: progressFraction()
                showProgress: !(flowmodoroModeEnabled && !isBreak())
                timeText: root.timeText
                statusText: root.statusText
                sessionCount: numberOfSessions
                sessionIndex: (stateVal - 1) / 2
                showSessionDots: !flowmodoroModeEnabled && numberOfSessions > 1
                fontFamily: clock_fontfamily
                circleColor: getCircleColor()
                captionColor: getTextColor()
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

        Layout.preferredHeight: (!showTime || !isVertical) ? baseIconSize : (baseIconSize + timeLabel.height)
        Layout.preferredWidth: (!showTime || isVertical) ? baseIconSize : baseIconSize + baseHorizontalFontSize * 2.5

        Layout.minimumWidth: Kirigami.Units.iconSizes.small
        Layout.minimumHeight: Kirigami.Units.iconSizes.small
        Layout.maximumHeight: Layout.preferredHeight
        Layout.maximumWidth: Layout.preferredWidth

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
            visible: showTime

            IndicatorIcon {
                visible: showIcon

                Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignLeft | Qt.AlignVCenter
                Layout.preferredWidth: baseIconSize
                Layout.preferredHeight: baseIconSize

                running: timer.running
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
            anchors.fill: parent
            visible: !showTime && showIcon

            running: timer.running
            progress: progressFraction()
            tint: getTextColor()
        }
    }

    fullRepresentation: Item {
        id: fullRoot

        Layout.minimumWidth: Kirigami.Units.gridUnit * 12
        Layout.maximumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 11
        Layout.maximumHeight: Kirigami.Units.gridUnit * 18

        HoverHandler {
            id: fullRepMouse
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            cursorShape: Qt.PointingHandCursor
        }

        Item {
            anchors {
                top: fullRoot.top
                left: fullRoot.left
                right: fullRoot.right
                bottom: buttonsRow.top
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
}
