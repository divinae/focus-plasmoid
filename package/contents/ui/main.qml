import QtQuick 2.2
import QtQuick.Layouts 1.1
import QtQuick.Controls 2.0 as Controls
import QtQuick.Window 2.0
import QtGraphicalEffects 1.0

import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 2.0 as PlasmaComponents

Item {
    id: root

    Plasmoid.switchWidth: units.gridUnit * 11
    Plasmoid.switchHeight: units.gridUnit * 11

    property string clock_fontfamily: plasmoid.configuration.clock_fontfamily || "Noto Mono"

    property var stateVal: 1
    property var isRunning: false
    property var maxSeconds: plasmoid.configuration.focus_time * 60
    property var countdownSeconds: maxSeconds
    property var countdownMilliseconds: countdownSeconds * 1000
    property var customIconSource: plasmoid.file(
                                       "", "icons/pomodoro-start-light.svg")
    property var previousTime: new Date()

    Plasmoid.status: PlasmaCore.Types.PassiveStatus
    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground

    function formatNumberLength(num, length) {
        var r = "" + num
        while (r.length < length) {
            r = "0" + r
        }

        return r
    }

    function shiftCountdown(seconds) {
        if (countdownSeconds + seconds > 0) {
            countdownMilliseconds += seconds * 1000
            countdownSeconds += seconds
            maxSeconds += seconds
        }
    }

    function formatCountdown() {
        var sec = countdownSeconds % 60
        var min = Math.floor(countdownSeconds / 60)

        return formatNumberLength(min, 2) + ":" + formatNumberLength(sec, 2)
    }

    function getToolTipText() {
        var text = ""

        if (isRunning) {
            switch (stateVal) {
                case 1:
                case 3:
                case 5:
                case 7:
                    text = "Focus on your work!"
                    break
                case 2:
                case 4:
                case 6:
                    text = "Go for a walk."
                    break
                case 8:
                    text = "Take a long break!"
                    break
            }
        }

        return text
    }

    NotificationManager {
        id: notificationManager
    }

    PlasmaCore.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        property var callbacks: ({})
        onNewData: {
            var stdout = data["stdout"]

            if (callbacks[sourceName] !== undefined) {
                callbacks[sourceName](stdout);
            }

            exited(sourceName, stdout)
            disconnectSource(sourceName) // cmd finished
        }

        function exec(cmd, onNewDataCallback) {
            if (onNewDataCallback !== undefined){
                callbacks[cmd] = onNewDataCallback
            }
            connectSource(cmd)

        }
        signal exited(string sourceName, string stdout)
    }

    Plasmoid.toolTipMainText: formatCountdown()
    Plasmoid.toolTipSubText: getToolTipText()

    Plasmoid.compactRepresentation: MouseArea {
        id: compactRoot

        Layout.minimumWidth: units.iconSizes.small
        Layout.minimumHeight: units.iconSizes.small
        Layout.preferredHeight: Layout.minimumHeight
        Layout.maximumHeight: Layout.minimumHeight

        Layout.preferredWidth: plasmoid.configuration.show_time_in_compact_mode ? row.width : root.width
 
        property int wheelDelta: 0

        onClicked: plasmoid.expanded = !plasmoid.expanded

        onWheel: {
            wheelDelta = scrollByWheel(wheelDelta, wheel.angleDelta.y);
        }

        RowLayout {
            id: row
            spacing: units.smallSpacing
            Layout.margins: units.smallSpacing
            visible: plasmoid.configuration.show_time_in_compact_mode ? true : false

            Item {
                Layout.preferredHeight: compactRoot.height
                Layout.preferredWidth: compactRoot.height

                PlasmaCore.IconItem {
                    id: trayIcon2
                    height: parent.height
                    width: parent.width
                    source: customIconSource
                    smooth: true
                }

                ColorOverlay {
                    anchors.fill: trayIcon2
                    source: trayIcon2
                    color: getTextColor()
                }
            }

            PlasmaComponents.Label {
                id: time
                font.pointSize: -1
                font.pixelSize: compactRoot.height * 0.6
                fontSizeMode: Text.FixedSize
                font.family: clock_fontfamily
                text: formatCountdown()
                minimumPixelSize: 1
                anchors.verticalCenter: row.verticalCenter
                color: getTextColor()
                smooth: true
            }
        }

        Item {
            visible: plasmoid.configuration.show_time_in_compact_mode ? false : true

            PlasmaCore.IconItem {
                id: trayIcon
                width: compactRoot.width
                height: compactRoot.height
                Layout.preferredWidth: height
                source: customIconSource
                smooth: true
            }

            ColorOverlay {
                anchors.fill: trayIcon
                source: trayIcon
                color: getTextColor()
            }
        }

        function scrollByWheel(wheelDelta, eventDelta) {
            // magic number 120 for common "one click"
            // See: http://qt-project.org/doc/qt-5/qml-qtquick-wheelevent.html#angleDelta-prop
            wheelDelta += eventDelta;

            var increment = 0;

            while (wheelDelta >= 120) {
                wheelDelta -= 120;
                increment++;
            }

            while (wheelDelta <= -120) {
                wheelDelta += 120;
                increment--;
            }

            while (increment != 0) {
                if(increment > 0) {
                    shiftCountdown(60)
                } else {
                    shiftCountdown(-60)
                }

                time.update()
                increment += (increment < 0) ? 1 : -1;
            }

            return wheelDelta;
        }
    }

    Plasmoid.fullRepresentation: Item {
        id: fullRoot

        Layout.minimumWidth: units.gridUnit * 12
        Layout.maximumWidth: units.gridUnit * 18
        Layout.minimumHeight: units.gridUnit * 11
        Layout.maximumHeight: units.gridUnit * 18

        Timer {
            id: textTimer
            interval: 100
            repeat: true
            running: false
            triggeredOnStart: false
            onTriggered: time.set()
        }

        Column {
            anchors {
                top: fullRoot.top
                left: fullRoot.left
                right: fullRoot.right
                bottom: buttonsRow.top
            }

            MouseArea {
                anchors.fill: parent
                property int wheelDelta: 0

                function scrollByWheel(wheelDelta, eventDelta) {
                    // magic number 120 for common "one click"
                    // See: http://qt-project.org/doc/qt-5/qml-qtquick-wheelevent.html#angleDelta-prop
                    wheelDelta += eventDelta;

                    var increment = 0;

                    while (wheelDelta >= 120) {
                        wheelDelta -= 120;
                        increment++;
                    }

                    while (wheelDelta <= -120) {
                        wheelDelta += 120;
                        increment--;
                    }

                    while (increment != 0) {
                        if(increment > 0) {
                            shiftCountdown(60)
                        } else {
                            shiftCountdown(-60)
                        }

                        time.update()
                        increment += (increment < 0) ? 1 : -1;
                    }

                    return wheelDelta;
                }

                onWheel: {
                    wheelDelta = scrollByWheel(wheelDelta, wheel.angleDelta.y);
                }
            }

            ProgressCircle {
                id: progressCircle
                anchors.centerIn: parent
                size: Math.min(parent.width / 1.4, parent.height / 1.4)
                colorCircle: getCircleColor()
                arcBegin: 0
                arcEnd: Math.ceil((countdownSeconds / maxSeconds) * 360)
                lineWidth: size / 30
            }

            Column {
                anchors.centerIn: parent
                height: time.height

                PlasmaComponents.Label {
                    id: time
                    text: formatCountdown()
                    font.pointSize: progressCircle.width / 8
                    font.family: clock_fontfamily
                    anchors.horizontalCenter: parent.horizontalCenter

                    function set() {
                        var currentTime = new Date()
                        var timeDiff = currentTime.getTime() - previousTime.getTime()
                        previousTime = currentTime

                        var oldCountdownSeconds = Math.ceil(countdownMilliseconds / 1000)
                        countdownMilliseconds -= timeDiff
                        var newCountdownSeconds = Math.ceil(countdownMilliseconds / 1000)

                        // Avoid too fast countdown when relying solely on QML's Timer
                        if (newCountdownSeconds === oldCountdownSeconds) {
                            return;
                        }
                        countdownSeconds--

                        if (countdownSeconds <= 0) {
                            end()
                        }

                        time.update()
                    }

                    function update() {
                        time.text = formatCountdown()

                        if (textTimer.running) {
                            customIconSource = plasmoid.file(
                                        "",
                                        "icons/pomodoro-indicator-light-" + formatNumberLength(
                                            Math.ceil(
                                                (countdownSeconds / maxSeconds) * 61),
                                            2) + ".svg")
                        }
                    }
                }

                Controls.PageIndicator {
                    id: pageIndicator
                    count: 4
                    currentIndex: (stateVal - 1) / 2

                    anchors {
                        bottom: time.top
                        horizontalCenter: parent.horizontalCenter
                        bottomMargin: progressCircle.width / 15
                    }

                    spacing: progressCircle.width / 25
                    delegate: Rectangle {
                        implicitWidth: progressCircle.width / 34
                        implicitHeight: width
                        radius: width / 2
                        color: theme.textColor

                        opacity: index === pageIndicator.currentIndex ? 0.95 : 0.45

                        Behavior on opacity {
                            OpacityAnimator {
                                duration: 100
                            }
                        }
                    }
                }

                PlasmaComponents.Label {
                    id: status
                    text: "focus"
                    font.pointSize: progressCircle.width / 24
                    color: getTextColor()

                    anchors {
                        top: time.bottom
                        horizontalCenter: parent.horizontalCenter
                        topMargin: progressCircle.width / 20
                    }

                }
            }
        }

        RowLayout {
            id: buttonsRow
            spacing: 10

            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
            }

            PlasmaComponents.Button {
                id: skipBtn
                text: "Skip"
                implicitWidth: minimumWidth
                iconSource: "media-skip-forward"
                onClicked: skip()
            }

            PlasmaComponents.Button {
                id: sessionBtn
                text: "Start"
                implicitWidth: minimumWidth
                iconSource: "media-playback-start"
                onClicked: {
                    if (sessionBtn.text == "Start") {
                        start()
                    } else {
                        pause()
                    }
                }
            }

            PlasmaComponents.Button {
                id: breakBtn
                text: "Stop"
                implicitWidth: minimumWidth
                iconSource: "media-playback-stop"
                onClicked: stop()
            }
        }

        function start() {
//             notificationManager.start(stateVal)
            previousTime = new Date()
            executeScript(1)
            textTimer.start()
            isRunning = true
            sessionBtn.text = "Pause"
            sessionBtn.iconSource = "media-playback-pause"
            customIconSource = plasmoid.file(
                        "", "icons/pomodoro-indicator-light-61.svg")
            Plasmoid.status = PlasmaCore.Types.ActiveStatus
        }

        function pause() {
            textTimer.stop()
            isRunning = false
            sessionBtn.text = "Start"
            sessionBtn.iconSource = "media-playback-start"
            customIconSource = plasmoid.file("",
                                             "icons/pomodoro-start-light.svg")
        }

        function end() {
            notificationManager.end(stateVal)
            executeScript(2)
            textTimer.stop()
            isRunning = false
            sessionBtn.text = "Start"
            sessionBtn.iconSource = "media-playback-start"
            customIconSource = plasmoid.file("",
                                             "icons/pomodoro-start-light.svg")
            nextState()
            resetTime()

            if (plasmoid.configuration.timer_auto_next_enabled) {
                start()
            } else {
                Plasmoid.status = PlasmaCore.Types.PassiveStatus
            }
        }

        function skip() {
            nextState()
            resetTime()
        }

        function stop() {
//             notificationManager.stop()
            executeScript(0)
            textTimer.stop()
            isRunning = false
            stateVal = 1
            resetTime()
            sessionBtn.text = "Start"
            sessionBtn.iconSource = "media-playback-start"
            customIconSource = plasmoid.file("",
                                             "icons/pomodoro-start-light.svg")
            Plasmoid.status = PlasmaCore.Types.PassiveStatus
        }

        function executeScript(state) {
            switch (state) {
                case 0:
                    if (plasmoid.configuration.stop_script_enabled) {
                        executable.exec("sh " + plasmoid.configuration.stop_script_filepath);
                    }
                    break
                case 1:
                    switch (stateVal) {
                        case 1:
                        case 3:
                        case 5:
                        case 7:
                            if (plasmoid.configuration.start_focus_script_enabled) {
                                executable.exec("sh " + plasmoid.configuration.start_focus_script_filepath);
                            }
                            break
                        case 2:
                        case 4:
                        case 6:
                        case 8:
                            if (plasmoid.configuration.start_break_script_enabled) {
                                executable.exec("sh " + plasmoid.configuration.start_break_script_filepath);
                            }
                            break
                    }
                    break
                case 2:
                    switch (stateVal) {
                        case 1:
                        case 3:
                        case 5:
                        case 7:
                            if (plasmoid.configuration.end_focus_script_enabled) {
                                executable.exec("sh " + plasmoid.configuration.end_focus_script_filepath);
                            }
                            break
                        case 2:
                        case 4:
                        case 6:
                        case 8:
                            if (plasmoid.configuration.end_break_script_enabled) {
                                executable.exec("sh " + plasmoid.configuration.end_break_script_filepath);
                            }
                            break
                    }
                    break
            }
        }

        function resetTime() {
            switch (stateVal) {
                case 1:
                case 3:
                case 5:
                case 7:
                    maxSeconds = plasmoid.configuration.focus_time * 60
                    status.text = "focus"
                    break
                case 2:
                case 4:
                case 6:
                    maxSeconds = plasmoid.configuration.short_break_time * 60
                    status.text = "short break"
                    break
                case 8:
                    maxSeconds = plasmoid.configuration.long_break_time * 60
                    status.text = "long break"
                    break
            }

            previousTime = new Date()
            countdownSeconds = maxSeconds
            countdownMilliseconds = countdownSeconds * 1000
            time.update()
            progressCircle.requestPaint()
        }

        function getCircleColor() {
            var color

            switch (stateVal) {
                case 1:
                case 3:
                case 5:
                case 7:
                    color = theme.buttonFocusColor
                    break
                case 2:
                case 4:
                case 6:
                case 8:
                    color = theme.disabledTextColor
                    break
            }

            return color
        }

        function nextState() {
            if (stateVal < 8) {
                stateVal++
            } else {
                stateVal = 1
            }
        }
    }

    function getTextColor() {
        var color

        switch (stateVal) {
            case 1:
            case 3:
            case 5:
            case 7:
                color = theme.textColor
                break
            case 2:
            case 4:
            case 6:
            case 8:
                color = theme.disabledTextColor
                break
        }

        return color
    }
}
