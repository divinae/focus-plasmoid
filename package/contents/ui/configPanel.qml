import QtQuick
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami
import QtQuick.Layouts
import org.kde.kcmutils as KCMUtils
import org.kde.kirigamiaddons.formcard as FormCard

// Everything drawn in the panel, plus the two settings that decide what the dial shows.
// Split out of the old General page, which had grown to twenty-four controls across four
// unrelated subjects.
KCMUtils.SimpleKCM {
    id: root

    property string cfg_clock_fontfamily: ""
    property int cfg_panel_icon_style: 0
    // Plasma uses cfg_<key>Default to initialise and to offer "reset to default".
    property string cfg_clock_fontfamilyDefault: ""
    property alias cfg_clock_bold: clock_bold.checked
    property alias cfg_show_time_in_compact_mode: show_time_in_compact_mode.checked
    property alias cfg_swap_icon_for_time: swap_icon_for_time.checked
    property alias cfg_show_icon_in_compact_mode: show_icon_in_compact_mode.checked
    property alias cfg_show_dial_time: show_dial_time.checked
    property alias cfg_flash_on_end: flash_on_end.checked

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
            title: i18n("Icon")
        }

        FormCard.FormCard {
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
                text: i18n("Ring and Wedge are thinner than the tomato outline, which reads better in a slim panel.")
            }
        }

        FormCard.FormHeader {
            title: i18n("Countdown")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: show_time_in_compact_mode

                text: i18n("Show the remaining time")
                // With the swap below, the countdown appears on its own while
                // running, so this setting no longer decides anything.
                enabled: !swap_icon_for_time.checked
            }

            FormCard.FormDelegateSeparator {
                visible: show_icon_in_compact_mode.checked
            }

            FormCard.FormSwitchDelegate {
                id: swap_icon_for_time

                visible: show_icon_in_compact_mode.checked
                text: i18n("Replace the icon with the countdown while running")
            }


            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: clock_bold

                text: i18n("Bold countdown")
            }

        }

        FormCard.FormHeader {
            title: i18n("Dial")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: show_dial_time

                text: i18n("Show the countdown in the dial")
                description: i18n("Off leaves only the ring. Applies to the popup and the break overlay.")
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: flash_on_end

                text: i18n("Flash when a session ends")
                description: i18n("Fades the panel and the overlay as a session finishes, and keeps pulsing while a break runs over.")
            }
        }

        FormCard.FormHeader {
            title: i18n("Font")
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
        }
    }
}
