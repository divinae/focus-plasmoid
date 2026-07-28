import QtMultimedia
import QtQuick
import org.kde.notification

// Sends the applet's notifications. Deciding *what* to say is the caller's job;
// this only knows how to deliver it.
QtObject {
    id: notificationManager

    // What the notification's button should do, for the lifetime of one
    // notification. Held here because the action object is reused.
    property var pendingAction: null

    property NotificationAction primaryAction: NotificationAction {
        onActivated: {
            if (notificationManager.pendingAction)
                notificationManager.pendingAction();
        }
    }

    property MediaPlayer sfx: MediaPlayer {
        audioOutput: AudioOutput {}
    }

    property Notification note: Notification {
        // This applet ships no .notifyrc, and KNotification silently sends
        // nothing at all for a componentName it cannot resolve, so it borrows
        // the generic workspace event. The cost is that the notification is
        // attributed to "System Notifications" rather than to Fokus, which is
        // why the title carries the name instead.
        componentName: "plasma_workspace"
        eventId: "notification"
        title: "Fokus"
        iconName: "chronometer"
        autoDelete: false
    }

    // actionLabel and action are optional: pass them to put a button on the
    // notification, so the next session can be started without going to the panel.
    function notify(summary, soundFile, actionLabel, action) {
        pendingAction = action || null;
        if (actionLabel) {
            primaryAction.label = actionLabel;
            note.actions = [primaryAction];
        } else {
            note.actions = [];
        }
        note.text = summary;
        note.sendEvent();
        // KNotification takes its sound from the .notifyrc too, so the sound is
        // played here rather than left to the notification server.
        if (soundFile) {
            sfx.source = soundFile;
            sfx.play();
        }
    }
}
