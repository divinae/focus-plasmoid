import QtQuick
import org.kde.notification

// Sends the applet's notifications. Deciding *what* to say is the caller's job;
// this only knows how to deliver it.
QtObject {
    id: notificationManager

    // What the notification's buttons should do, for the lifetime of one
    // notification. Held here because the action objects are reused.
    property var pendingAction: null
    property var pendingSecondaryAction: null

    property NotificationAction primaryAction: NotificationAction {
        onActivated: {
            if (notificationManager.pendingAction)
                notificationManager.pendingAction();
        }
    }

    // Two slots, because the flow reminder offers a choice - take the break, or carry
    // on - rather than a single next step. KNotification takes any number of actions;
    // two is where the popup stops being readable.
    property NotificationAction secondaryAction: NotificationAction {
        onActivated: {
            if (notificationManager.pendingSecondaryAction)
                notificationManager.pendingSecondaryAction();
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
        notifyActions(summary, actionLabel ? [{ "label": actionLabel, "action": action }] : []);
    }

    // The general form: a list of { label, action }, at most two of which are shown.
    // Anything past the second is dropped rather than silently reusing a slot, which
    // would attach the wrong callback to a button.
    function notifyActions(summary, actions) {
        var list = actions || [];
        pendingAction = list.length > 0 ? (list[0].action || null) : null;
        pendingSecondaryAction = list.length > 1 ? (list[1].action || null) : null;
        var buttons = [];
        if (list.length > 0) {
            primaryAction.label = list[0].label;
            buttons.push(primaryAction);
        }
        if (list.length > 1) {
            secondaryAction.label = list[1].label;
            buttons.push(secondaryAction);
        }
        note.actions = buttons;
        note.text = summary;
        note.sendEvent();
    }
}
