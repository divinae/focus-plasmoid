import QtQuick

QtObject {
    id: notificationManager

    // Supplied by the parent. Instantiating a second ExecUtil here would open a
    // redundant Plasma5Support DataSource for no reason.
    required property var executable

    function isBreakState(stateVal) {
        return stateVal % 2 == 0;
    }

    function isLongBreakState(stateVal) {
        return stateVal == 2 * plasmoid.configuration.number_of_sessions;
    }

    function start(stateVal) {
        var summary;
        if (!isBreakState(stateVal))
            summary = "Focus on your work!";
        else if (isLongBreakState(stateVal))
            summary = "Take a long break!";
        else
            summary = "Go for a walk.";
        createNotification(summary, plasmoid.configuration.timer_start_sfx_enabled ? plasmoid.configuration.timer_start_sfx_filepath : "");
    }

    function end(stateVal) {
        createNotification(isBreakState(stateVal) ? "End of break." : "End of focus time.", plasmoid.configuration.timer_stop_sfx_enabled ? plasmoid.configuration.timer_stop_sfx_filepath : "");
    }

    function getPath(fileUrl) {
        // remove prefixed "file://"
        return fileUrl.toString().replace(/^file:\/\//, "");
    }

    function createNotification(summary, soundFile) {
        var cmd = ['python3', getPath(Qt.resolvedUrl("../scripts/notification.py"))];
        cmd.push('--app-name', 'fokus');
        if (soundFile)
            cmd.push('--sound', soundFile);

        // ExecUtil keys its DataSource by the full command string, so two identical
        // notifications would collide. The timestamp keeps every command unique.
        cmd.push('--metadata', '' + Date.now());
        cmd.push(executable.sanitizeString(summary));
        cmd.push(""); // notification.py takes the body as a positional argument
        executable.exec(cmd);
    }
}
