import QtQuick
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami
import QtQuick.Layouts
import org.kde.kcmutils as KCMUtils
import org.kde.kirigamiaddons.formcard as FormCard

KCMUtils.SimpleKCM {
    id: root

    property string cfg_clock_fontfamily: ""
    property int cfg_panel_icon_style: 0
    // Plasma uses cfg_<key>Default to initialise and to offer "reset to default".
    property string cfg_clock_fontfamilyDefault: ""
    property alias cfg_show_time_in_compact_mode: show_time_in_compact_mode.checked
    property alias cfg_show_icon_in_compact_mode: show_icon_in_compact_mode.checked
    property alias cfg_show_fullscreen_break: show_fullscreen_break.checked
    property alias cfg_fullscreen_buttons_postpone: fullscreen_buttons_postpone.checked
    property alias cfg_fullscreen_buttons_skip: fullscreen_buttons_skip.checked
    property alias cfg_fullscreen_buttons_close: fullscreen_buttons_close.checked
    property alias cfg_timer_auto_pause_enabled: timer_auto_pause_enabled.checked
    property alias cfg_timer_auto_focus_enabled: timer_auto_focus_enabled.checked
    property alias cfg_autostart: autostart.checked
    property alias cfg_do_not_disturb_enabled: do_not_disturb_enabled.checked
    property alias cfg_show_buttons_on_hover: show_buttons_on_hover.checked

    // Qt's own font dialog does the browsing, so the settings page never builds a
    // model over Qt.fontFamilies() - nearly 2000 entries on this machine - inside
    // plasmashell, and the config value is only written on an explicit choice.
    FontDialog {
        id: fontDialog

        title: i18n("Choose the timer font")
        currentFont.family: root.cfg_clock_fontfamily || "Noto Sans"
        onAccepted: {
            root.cfg_clock_fontfamily = selectedFont.family;
            fontField.text = selectedFont.family;
        }
    }

    ColumnLayout {
        spacing: 0

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }

        FormCard.FormHeader {
            title: i18n("Panel")
        }

        FormCard.FormCard {
            FormCard.FormTextFieldDelegate {
                id: fontField

                label: i18n("Timer font")
                text: root.cfg_clock_fontfamily
                placeholderText: i18n("Default")
                // Committed rather than written per keystroke, so a half-typed
                // family name never reaches the config.
                onEditingFinished: root.cfg_clock_fontfamily = text
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormButtonDelegate {
                text: i18n("Choose from installed fonts…")
                icon.name: "preferences-desktop-font"
                onClicked: fontDialog.open()
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormButtonDelegate {
                text: i18n("Use the default font")
                icon.name: "edit-clear"
                enabled: root.cfg_clock_fontfamily !== ""
                onClicked: {
                    root.cfg_clock_fontfamily = "";
                    // Typing breaks the field's binding, so it is reset explicitly.
                    fontField.text = "";
                }
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: show_icon_in_compact_mode

                text: i18n("Show the icon")
            }

            FormCard.FormDelegateSeparator {
                visible: show_icon_in_compact_mode.checked
            }

            FormCard.FormRadioSelectorDelegate {
                id: iconStyleSelector

                visible: show_icon_in_compact_mode.checked
                consistentWidth: true
                actions: [
                    Kirigami.Action {
                        text: i18n("Timer")
                    },
                    Kirigami.Action {
                        text: i18n("Ring")
                    },
                    Kirigami.Action {
                        text: i18n("Wedge")
                    }
                ]
                // Same shape as the mode selector on the Timer page: a binding
                // declared with the object, which survives the control resetting
                // its own index during initialisation.
                selectedIndex: root.cfg_panel_icon_style
                onSelectedIndexChanged: root.cfg_panel_icon_style = selectedIndex
            }

            FormCard.FormSectionText {
                visible: show_icon_in_compact_mode.checked
                text: i18n("The Timer style is the original tomato outline. Ring and Wedge are drawn thinner, which reads better in a slim panel.")
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: show_time_in_compact_mode

                text: i18n("Show the remaining time")
                description: i18n("Displays the countdown next to the icon in the panel.")
            }
        }

        FormCard.FormHeader {
            title: i18n("Sessions")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: autostart

                text: i18n("Start the timer when Plasma starts")
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: do_not_disturb_enabled

                text: i18n("Silence notifications while focusing")
                description: i18n("Suppresses other applications' notifications for the length of a focus session.")
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: timer_auto_focus_enabled

                text: i18n("Start the next focus session automatically")
                description: i18n("When off, a break that runs out keeps counting and shows how far past its end it went.")
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: timer_auto_pause_enabled

                text: i18n("Start breaks automatically")
            }
        }

        FormCard.FormHeader {
            title: i18n("Break overlay")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: show_fullscreen_break

                text: i18n("Cover the screen during a break")
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: show_buttons_on_hover

                text: i18n("Reveal the buttons only on hover")
                enabled: show_fullscreen_break.checked
            }

            // Postpone shifts a fixed break; flowmodoro has none, so in that mode
            // the option is hidden rather than shown greyed out. The mode itself
            // is selected on the Timer page.
            FormCard.FormDelegateSeparator {
                visible: fullscreen_buttons_postpone.visible
            }

            FormCard.FormSwitchDelegate {
                id: fullscreen_buttons_postpone

                text: i18n("Offer Postpone")
                description: i18n("Puts the break off by five minutes.")
                visible: !plasmoid.configuration.flowmodoro_mode_enabled
                enabled: show_fullscreen_break.checked
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: fullscreen_buttons_skip

                text: i18n("Offer Skip")
                enabled: show_fullscreen_break.checked
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: fullscreen_buttons_close

                text: i18n("Offer Close")
                description: i18n("Dismisses the overlay without ending the break.")
                enabled: show_fullscreen_break.checked
            }
        }
    }
}
