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

    function getToolTipText() {
        return timer.running ? stateHeadline() : "";
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
        if (plasmoid.configuration.timer_end_notification_enabled)
            notificationManager.notify(isBreak() ? i18n("End of break.") : i18n("End of focus time."), plasmoid.configuration.timer_stop_sfx_enabled ? plasmoid.configuration.timer_stop_sfx_filepath : "");
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
            if (counterMilliseconds <= 0)
                end();
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

    Plasmoid.status: PlasmaCore.Types.PassiveStatus
    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground
    toolTipMainText: timeText
    toolTipSubText: getToolTipText()
    switchWidth: Kirigami.Units.gridUnit * 12
    switchHeight: Kirigami.Units.gridUnit * 11

    Component.onCompleted: {
        if (plasmoid.configuration.autostart) {
            start();
        }
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
                        visible: !isBreak()
                        text: i18n("St&art")
                        icon.name: "media-playback-start"
                        onClicked: start()
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
            else if (timer.running) {
                if (flowmodoroModeEnabled) {
                    skip();
                } else {
                    pause();
                }
            } else
                start();
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
                onClicked: {
                    if (!timer.running)
                        start();
                    else if (flowmodoroModeEnabled) {
                        skip();
                    } else {
                        pause();
                    }
                }
            }

            PlasmaComponents.Button {
                text: flowmodoroModeEnabled ? i18n("Re&set") : i18n("St&op")
                icon.name: flowmodoroModeEnabled ? "chronometer-reset" : "media-playback-stop"
                onClicked: stop()
            }
        }
    }
}
