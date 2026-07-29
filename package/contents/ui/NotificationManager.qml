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
    //
    // Sound is deliberately not handled here. It used to be an argument, which meant
    // a sound could only play as part of a notification - turning the popup off
    // silenced it too. The caller now plays sound separately.
    function notify(summary, actionLabel, action) {
        pendingAction = action || null;
        if (actionLabel) {
            primaryAction.label = actionLabel;
            note.actions = [primaryAction];
        } else {
            note.actions = [];
        }
        note.text = summary;
        note.sendEvent();
    }
}
