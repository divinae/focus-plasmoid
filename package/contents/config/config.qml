import org.kde.plasma.configuration

// Six pages rather than four. "General" had become twenty-four controls across four unrelated
// subjects, so it is split into the surfaces a user actually thinks about: the panel, the
// sessions themselves, and the break overlay.
//
// Every icon here is checked to exist in Breeze - preferences-desktop-notifications, used
// before, does not, so that category had been showing a blank.
ConfigModel {
    ConfigCategory {
        name: "Timer"
        icon: "preferences-system-time"
        source: "configTimer.qml"
    }

    ConfigCategory {
        name: "Panel"
        icon: "preferences-desktop-plasma"
        source: "configPanel.qml"
    }

    ConfigCategory {
        name: "Sessions"
        icon: "chronometer"
        source: "configSessions.qml"
    }

    ConfigCategory {
        name: "Break overlay"
        icon: "view-fullscreen"
        source: "configBreakOverlay.qml"
    }

    ConfigCategory {
        name: "Notifications"
        icon: "notification-active"
        source: "configNotifications.qml"
    }

    ConfigCategory {
        name: "Scripts"
        icon: "preferences-plugin"
        source: "configScripts.qml"
    }
}
