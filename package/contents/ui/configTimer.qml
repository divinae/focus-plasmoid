import "./lib/timer.js" as TimerLogic
import QtQuick
import QtQuick.Layouts
import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard

KCMUtils.SimpleKCM {
    id: root

    property alias cfg_focus_time: focus_time.value
    property alias cfg_short_break_time: short_break_time.value
    property alias cfg_long_break_time: long_break_time.value
    property alias cfg_scroll_adjusts_time_enabled: scroll_adjusts_time_enabled.checked
    property alias cfg_ticking_time: ticking_time.value
    property alias cfg_number_of_sessions: number_of_sessions.value
    property alias cfg_flow_divisor: flow_divisor.value
    property alias cfg_flow_reminder_enabled: flow_reminder_enabled.checked
    property alias cfg_flow_reminder_minutes: flow_reminder_minutes.value
    property bool cfg_flowmodoro_mode_enabled: false

    // The two modes have almost nothing in common, so only the settings that
    // belong to the selected one are shown at all.
    readonly property bool flowmodoro: cfg_flowmodoro_mode_enabled

    // Which preset the current durations amount to, or presets.length for Custom.
    // Derived rather than stored, so editing any duration moves the selector to
    // Custom on its own and no config key is needed.
    readonly property int currentPreset: TimerLogic.matchPreset(cfg_focus_time, cfg_short_break_time, cfg_long_break_time)

    function applyPreset(index) {
        var preset = TimerLogic.presetAt(index);
        cfg_focus_time = preset.focus;
        cfg_short_break_time = preset.shortBreak;
        cfg_long_break_time = preset.longBreak;
    }

    ColumnLayout {
        spacing: 0

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }

        FormCard.FormHeader {
            title: i18n("Timer mode")
        }

        FormCard.FormCard {
            FormCard.FormRadioSelectorDelegate {
                id: modeSelector

                consistentWidth: true
                actions: [
                    Kirigami.Action {
                        text: i18n("Pomodoro")
                        icon.name: "chronometer"
                    },
                    Kirigami.Action {
                        text: i18n("Flowmodoro")
                        icon.name: "chronometer-lap"
                    }
                ]
                // A binding rather than an assignment on completion: the internal
                // selector settles its actions after Component.onCompleted runs,
                // which resets the index and loses an assignment made there.
                selectedIndex: root.cfg_flowmodoro_mode_enabled ? 1 : 0
                onSelectedIndexChanged: root.cfg_flowmodoro_mode_enabled = (selectedIndex === 1)
            }
        }

        // FormSectionText wraps; FormTextDelegate's title elides instead.
        FormCard.FormSectionText {
            text: root.flowmodoro ? i18n("Focus for as long as you like. The timer counts up, and the break you earn is worked out from how long you focused.") : i18n("Fixed focus sessions separated by short breaks, with a long break at the end of each cycle.")
        }

        FormCard.FormHeader {
            title: i18n("Pomodoro")
            visible: !root.flowmodoro
        }

        FormCard.FormCard {
            visible: !root.flowmodoro

            FormCard.FormRadioSelectorDelegate {
                id: presetSelector

                consistentWidth: false
                // Each action only sets the durations. The highlight comes from
                // the Binding below, so editing a duration by hand moves the
                // selector to Custom on its own.
                actions: [
                    Kirigami.Action {
                        text: i18n("Classic")
                        onTriggered: root.applyPreset(0)
                    },
                    Kirigami.Action {
                        text: i18n("Deep work")
                        onTriggered: root.applyPreset(1)
                    },
                    Kirigami.Action {
                        text: i18n("90/20")
                        onTriggered: root.applyPreset(2)
                    },
                    Kirigami.Action {
                        text: i18n("Custom")
                    }
                ]
            }

            // A Binding element rather than a plain binding on selectedIndex: the
            // selector writes that property itself when clicked, which would
            // break an ordinary binding and leave the highlight stuck. This
            // re-asserts afterwards, and settles late enough to survive the
            // control's own initialisation.
            Binding {
                target: presetSelector
                property: "selectedIndex"
                value: root.currentPreset
                restoreMode: Binding.RestoreBindingOrValue
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSpinBoxDelegate {
                id: number_of_sessions

                label: i18n("Focus sessions per cycle")
                description: i18n("How many focus sessions to run before the long break.")
                from: 1
                to: 10
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSpinBoxDelegate {
                id: focus_time

                label: i18n("Focus session")
                from: 1
                to: 9999
                textFromValue: function(value, locale) {
                    return i18n("%1 min", value);
                }
                valueFromText: function(text, locale) {
                    return parseInt(text) || from;
                }
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSpinBoxDelegate {
                id: short_break_time

                label: i18n("Short break")
                description: i18n("Set to zero to skip short breaks entirely.")
                from: 0
                to: 9999
                textFromValue: function(value, locale) {
                    // Zero is a mode rather than a duration: the break is skipped.
                    return value === 0 ? i18n("Skipped") : i18n("%1 min", value);
                }
                valueFromText: function(text, locale) {
                    return parseInt(text) || 0;
                }
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSpinBoxDelegate {
                id: long_break_time

                label: i18n("Long break")
                description: i18n("Runs after the last focus session of a cycle. Set to zero to skip it.")
                from: 0
                to: 9999
                textFromValue: function(value, locale) {
                    return value === 0 ? i18n("Skipped") : i18n("%1 min", value);
                }
                valueFromText: function(text, locale) {
                    return parseInt(text) || 0;
                }
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: scroll_adjusts_time_enabled

                text: i18n("Change the time with the scroll wheel")
                description: i18n("Scrolling over the timer adds or removes minutes. Turn it off if the wheel is meant for something else there, such as switching desktops.")
            }
        }

        FormCard.FormHeader {
            title: i18n("Flowmodoro")
            visible: root.flowmodoro
        }

        FormCard.FormCard {
            visible: root.flowmodoro

            FormCard.FormSpinBoxDelegate {
                id: flow_divisor

                label: i18n("Break divisor")
                description: i18n("The break is the length of the flow divided by this. At 5, a 50 minute flow earns a 10 minute break.")
                from: 1
                to: 9999
                valueFromText: function(text, locale) {
                    return parseInt(text) || from;
                }
            }

            FormCard.FormDelegateSeparator {}

            // A flow has no end to run into, so nothing otherwise notices that the work
            // stopped hours ago. The reminder asks, and offers the break as its answer.
            FormCard.FormSwitchDelegate {
                id: flow_reminder_enabled

                text: i18n("Ask if the flow is still going")
                description: i18n("A notification offering the break, so a flow left running is not counted as work.")
            }

            FormCard.FormDelegateSeparator {
                visible: flow_reminder_minutes.visible
            }

            FormCard.FormSpinBoxDelegate {
                id: flow_reminder_minutes

                visible: flow_reminder_enabled.checked
                label: i18n("Ask every")
                from: 1
                to: 9999
                textFromValue: function(value, locale) {
                    return i18n("%1 min", value);
                }
                valueFromText: function(text, locale) {
                    return parseInt(text) || from;
                }
            }
        }

        // Ticking warns that a deadline is approaching, and a flow session has
        // none, so the setting has nothing to act on in flowmodoro mode.
        FormCard.FormHeader {
            title: i18n("Sound")
            visible: !root.flowmodoro
        }

        FormCard.FormCard {
            visible: !root.flowmodoro

            FormCard.FormSpinBoxDelegate {
                id: ticking_time

                label: i18n("Ticking starts at")
                description: i18n("Plays the ticking sound over the final seconds of a focus session.")
                from: 0
                to: 60
                textFromValue: function(value, locale) {
                    return value === 0 ? i18n("Never") : i18n("%1 s", value);
                }
                valueFromText: function(text, locale) {
                    return parseInt(text) || 0;
                }
            }
        }
    }
}
