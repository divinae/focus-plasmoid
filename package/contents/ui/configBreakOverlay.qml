import QtQuick
import org.kde.kirigami as Kirigami
import QtQuick.Layouts
import org.kde.kcmutils as KCMUtils
import org.kde.kirigamiaddons.formcard as FormCard

// The fullscreen break overlay. Split out of the old General page, where it was the fourth
// unrelated subject on one scroll.
//
// Everything below the master switch is hidden rather than greyed when the overlay is off:
// the page is then as long as the configuration in force, not as long as every option that
// could apply.
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

    property int cfg_break_overlay_theme: 0
    property alias cfg_show_fullscreen_break: show_fullscreen_break.checked
    property alias cfg_break_overlay_blur: break_overlay_blur.checked
    property alias cfg_break_overlay_opacity: break_overlay_opacity.value
    property alias cfg_show_buttons_on_hover: show_buttons_on_hover.checked
    property alias cfg_fullscreen_buttons_postpone: fullscreen_buttons_postpone.checked
    property alias cfg_fullscreen_buttons_skip: fullscreen_buttons_skip.checked
    property alias cfg_fullscreen_buttons_close: fullscreen_buttons_close.checked
    property alias cfg_fullscreen_buttons_end: fullscreen_buttons_end.checked

    ColumnLayout {
        spacing: 0

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: show_fullscreen_break

                text: i18n("Cover the screen during a break")
            }

            // Only when it is actually missing: a standing notice about an optional
            // dependency is noise for everyone who already has it.
            FormCard.FormSectionText {
                visible: show_fullscreen_break.checked && !root.layerShellAvailable
                text: i18n("The overlay covers every screen but cannot follow a switch to another virtual desktop: that needs the optional LayerShellQt module. Install layer-shell-qt (qml6-module-org-kde-layershell on Debian and Ubuntu) and restart Plasma.")
            }
        }

        FormCard.FormHeader {
            title: i18n("Appearance")
            visible: show_fullscreen_break.checked
        }

        FormCard.FormCard {
            visible: show_fullscreen_break.checked

            FormCard.FormRadioSelectorDelegate {
                id: overlayThemeSelector

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
                // Same shape as the other selectors: a binding declared with the object,
                // which survives the control resetting its own index while it initialises.
                // An imperative write or a Binding element gets clobbered.
                selectedIndex: root.cfg_break_overlay_theme
                onSelectedIndexChanged: root.cfg_break_overlay_theme = selectedIndex
            }

            FormCard.FormSectionText {
                text: i18n("A dark overlay over a light desktop is much less of a jolt when a break starts.")
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSpinBoxDelegate {
                id: break_overlay_opacity

                label: i18n("Background opacity")
                // Down to 0: no tint at all, leaving just the dial and the buttons over the
                // desktop. The blur stays either way - it is enabled in C++ by the window
                // class and no QML binding can turn it off.
                from: 0
                to: 100
                stepSize: 5
                textFromValue: function(value, locale) {
                    return i18n("%1%", value);
                }
                valueFromText: function(text, locale) {
                    return parseInt(text) || from;
                }
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: break_overlay_blur

                text: i18n("Blur the desktop behind the overlay")
                description: i18n("Turn off if you see jagged shadows around the buttons: blur comes with Plasma's background-contrast effect, which frays soft edges at a low opacity.")
            }
        }

        FormCard.FormHeader {
            title: i18n("Buttons")
            visible: show_fullscreen_break.checked
        }

        FormCard.FormCard {
            visible: show_fullscreen_break.checked

            FormCard.FormSwitchDelegate {
                id: show_buttons_on_hover

                text: i18n("Reveal the buttons only on hover")
            }

            // Postpone shifts a fixed break; flowmodoro has none, so in that mode the option
            // is hidden rather than shown greyed out. The mode is chosen on the Timer page.
            FormCard.FormDelegateSeparator {
                visible: fullscreen_buttons_postpone.visible
            }

            FormCard.FormSwitchDelegate {
                id: fullscreen_buttons_postpone

                visible: !plasmoid.configuration.flowmodoro_mode_enabled
                text: i18n("Offer Postpone")
                description: i18n("Puts the break off by five minutes.")
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: fullscreen_buttons_skip

                text: i18n("Offer Skip")
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: fullscreen_buttons_close

                text: i18n("Offer Close")
                description: i18n("Dismisses the overlay without ending the break.")
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: fullscreen_buttons_end

                text: i18n("Offer End for today")
                description: i18n("Ends the break and starts nothing after it, where Skip carries on into the next session.")
            }
        }
    }
}
