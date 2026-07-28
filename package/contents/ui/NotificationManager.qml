import QtMultimedia
import QtQuick
import org.kde.notification

// Sends the applet's notifications. Deciding *what* to say is the caller's job;
// this only knows how to deliver it.
QtObject {
    id: notificationManager

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

    function notify(summary, soundFile) {
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
