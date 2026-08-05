import QtQuick
import QtQuick.Layouts
import org.kde.kcmutils as KCMUtils
import org.kde.kirigamiaddons.formcard as FormCard

// How sessions begin and end, and what counts as one worth recording. Split out of the old
// General page.
KCMUtils.SimpleKCM {
    id: root

    property alias cfg_autostart: autostart.checked
    property alias cfg_do_not_disturb_enabled: do_not_disturb_enabled.checked
    property alias cfg_timer_auto_focus_enabled: timer_auto_focus_enabled.checked
    property alias cfg_timer_auto_pause_enabled: timer_auto_pause_enabled.checked
    property alias cfg_min_session_minutes: min_session_minutes.value
    property alias cfg_workday_hours: workday_hours.value

    ColumnLayout {
        spacing: 0

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }

        FormCard.FormHeader {
            title: i18n("Starting and stopping")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: autostart

                text: i18n("Start the timer when Plasma starts")
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: timer_auto_focus_enabled

                text: i18n("Start the next focus session automatically")
                description: i18n("When off, a break that runs out keeps counting past its end.")
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: timer_auto_pause_enabled

                text: i18n("Start breaks automatically")
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: do_not_disturb_enabled

                text: i18n("Silence notifications while focusing")
                description: i18n("Suppresses other applications' notifications for the length of a focus session.")
            }
        }

        FormCard.FormHeader {
            title: i18n("What gets recorded")
        }

        FormCard.FormCard {
            FormCard.FormSpinBoxDelegate {
                id: min_session_minutes

                label: i18n("Ignore sessions shorter than")
                from: 0
                to: 120
                textFromValue: function(value, locale) {
                    return value === 0 ? i18n("Record everything") : i18n("%1 min", value);
                }
                valueFromText: function(text, locale) {
                    return parseInt(text) || from;
                }
            }

            FormCard.FormSectionText {
                text: i18n("Keeps the totals free of fragments left by switching task or skipping. Breaks are always recorded.")
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSpinBoxDelegate {
                id: workday_hours

                label: i18n("Working day")
                from: 0
                to: 24
                textFromValue: function(value, locale) {
                    return value === 0 ? i18n("No target") : i18n("%1 h", value);
                }
                valueFromText: function(text, locale) {
                    return parseInt(text) || from;
                }
            }

            FormCard.FormSectionText {
                text: i18n("Used on the Stats page, to say how much of a working day the timer accounted for.")
            }
        }
    }
}
