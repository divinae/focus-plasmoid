import QtQuick
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami
import QtQuick.Layouts
import org.kde.kcmutils as KCMUtils
import org.kde.kirigamiaddons.formcard as FormCard

KCMUtils.SimpleKCM {
    id: root

    // The same runtime probe main.qml uses: a config page cannot see the applet root, and a
    // static import of an optional module would take this page down with it (gitlab #58).
    readonly property bool layerShellAvailable: {
        var probe = Qt.createComponent(Qt.resolvedUrl("LayerShellProbe.qml"), Component.PreferSynchronous);
        var ready = probe.status === Component.Ready;
        probe.destroy();
        return ready;
    }

    property string cfg_clock_fontfamily: ""
    property int cfg_panel_icon_style: 0
    // Plasma uses cfg_<key>Default to initialise and to offer "reset to default".
    property string cfg_clock_fontfamilyDefault: ""
    property alias cfg_clock_bold: clock_bold.checked
    property alias cfg_show_time_in_compact_mode: show_time_in_compact_mode.checked
    property alias cfg_show_dial_time: show_dial_time.checked
    property alias cfg_flash_on_end: flash_on_end.checked
    property alias cfg_swap_icon_for_time: swap_icon_for_time.checked
    property alias cfg_show_icon_in_compact_mode: show_icon_in_compact_mode.checked
    property alias cfg_show_fullscreen_break: show_fullscreen_break.checked
    property alias cfg_fullscreen_buttons_postpone: fullscreen_buttons_postpone.checked
    property alias cfg_fullscreen_buttons_skip: fullscreen_buttons_skip.checked
    property alias cfg_fullscreen_buttons_close: fullscreen_buttons_close.checked
    property alias cfg_timer_auto_pause_enabled: timer_auto_pause_enabled.checked
    property alias cfg_timer_auto_focus_enabled: timer_auto_focus_enabled.checked
    property alias cfg_autostart: autostart.checked
    property alias cfg_do_not_disturb_enabled: do_not_disturb_enabled.checked
    property alias cfg_min_session_minutes: min_session_minutes.value
    property alias cfg_workday_hours: workday_hours.value
    property alias cfg_show_buttons_on_hover: show_buttons_on_hover.checked
    property alias cfg_break_overlay_opacity: break_overlay_opacity.value
    property alias cfg_break_overlay_blur: break_overlay_blur.checked
    property int cfg_break_overlay_theme: 0

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
                id: clock_bold

                text: i18n("Bold countdown")
                description: i18n("Applies to the panel and to the dial. Worth having on a narrow vertical panel, where the digits cannot grow much.")
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
                description: i18n("The panel shows the icon when idle and the remaining time while a session runs, instead of both together.")
            }
        }

        FormCard.FormHeader {
            title: i18n("Timer view")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: show_dial_time

                text: i18n("Show the countdown in the dial")
                description: i18n("Turn this off to leave only the ring, in the popup and on the break overlay. The ring still shows how much is left.")
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: flash_on_end

                text: i18n("Flash when a session ends")
                description: i18n("Fades the panel icon, and the break overlay, as a session finishes. The overlay keeps pulsing while a break is running over. Useful if you run without a notification sound and miss the moment.")
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
                text: i18n("Only used on the Stats page, to say how much of a working day the timer accounted for. Set it to zero to leave that out.")
            }

            FormCard.FormDelegateSeparator {}

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
                text: i18n("Focus sessions this short are not recorded, so the totals are not littered with fragments left by switching task or skipping. Breaks are always recorded.")
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

            // Only when it is actually missing: a permanent notice about an optional
            // dependency is noise for everyone who already has it.
            FormCard.FormSectionText {
                visible: show_fullscreen_break.checked && !root.layerShellAvailable
                text: i18n("The overlay covers every screen, but cannot follow a switch to another virtual desktop: that needs the optional LayerShellQt module, which is not installed. Install layer-shell-qt (qml6-module-org-kde-layershell on Debian and Ubuntu) and restart Plasma to enable it.")
            }

            FormCard.FormDelegateSeparator {
                visible: show_fullscreen_break.checked
            }

            FormCard.FormSectionText {
                visible: show_fullscreen_break.checked
                text: i18n("Colours for the overlay only. A dark overlay over a light desktop is much less of a jolt when a break starts.")
            }

            FormCard.FormRadioSelectorDelegate {
                id: overlayThemeSelector

                visible: show_fullscreen_break.checked
                consistentWidth: true
                actions: [
                    Kirigami.Action {
                        text: i18n("Follow Plasma")
                    },
                    Kirigami.Action {
                        text: i18n("Dark")
                    },
                    Kirigami.Action {
                        text: i18n("Light")
                    }
                ]
                // Same shape as the other selectors here: a binding declared with the
                // object, which survives the control resetting its own index while it
                // initialises. An imperative write or a Binding element gets clobbered.
                selectedIndex: root.cfg_break_overlay_theme
                onSelectedIndexChanged: root.cfg_break_overlay_theme = selectedIndex
            }

            FormCard.FormDelegateSeparator {
                visible: show_fullscreen_break.checked
            }

            FormCard.FormSwitchDelegate {
                id: break_overlay_blur

                text: i18n("Blur the desktop behind the overlay")
                description: i18n("Turn this off if you see jagged shadows around the buttons: blur comes with Plasma's background-contrast effect, which cannot be separated from it and which frays soft edges at a low opacity.")
                visible: show_fullscreen_break.checked
            }

            FormCard.FormDelegateSeparator {
                visible: show_fullscreen_break.checked
            }

            FormCard.FormSpinBoxDelegate {
                id: break_overlay_opacity

                label: i18n("Background opacity")
                // Down to 0: no tint at all, leaving just the dial and the buttons
                // over the desktop. The blur stays either way - it is enabled in C++
                // by the window class and no QML binding can turn it off.
                from: 0
                to: 100
                stepSize: 5
                visible: show_fullscreen_break.checked
                textFromValue: function(value, locale) {
                    return i18n("%1%", value);
                }
                valueFromText: function(text, locale) {
                    return parseInt(text) || from;
                }
            }

            FormCard.FormSectionText {
                visible: show_fullscreen_break.checked
                text: i18n("Below 100% the desktop stays visible through the break, so the overlay interrupts without hiding what you were doing. At 0% only the timer and the buttons are drawn, over a blurred desktop.")
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
