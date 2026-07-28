import "./lib"
import "./lib/Utils.js" as Utils
import QtQuick

// Thin wrapper around scripts/notification.py. Deciding *what* to say is the
// caller's job; this only knows how to deliver it.
QtObject {
    id: notificationManager

    // Supplied by the parent. Instantiating a second ExecUtil here would open a
    // redundant Plasma5Support DataSource for no reason.
    required property ExecUtil executable

    function notify(summary, soundFile) {
        var cmd = ['python3', Utils.getPath(Qt.resolvedUrl("../scripts/notification.py"))];
        cmd.push('--app-name', 'fokus');
        if (soundFile)
            cmd.push('--sound', soundFile);

        // ExecUtil keys its DataSource by the full command string, so two
        // identical notifications would collide. The timestamp keeps them apart.
        cmd.push('--metadata', '' + Date.now());
        cmd.push(executable.sanitizeString(summary));
        cmd.push(""); // notification.py takes the body as a positional argument
        executable.exec(cmd);
    }
}
