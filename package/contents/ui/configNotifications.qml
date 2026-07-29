import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard

KCMUtils.SimpleKCM {
    id: root

    readonly property var soundFilters: [i18n("Sound files (*.wav *.mp3 *.oga *.ogg)"), i18n("All files (*)")]
    readonly property url soundFolder: "file:///usr/share/sounds"

    // The existing timer_start_* and timer_stop_* keys are the focus ones: they kept
    // their names so a customised setup survives the split into four events.
    property alias cfg_timer_start_notification_enabled: focusStartNotify.checked
    property alias cfg_timer_start_sfx_enabled: focusStartSound.checked
    property alias cfg_timer_start_sfx_filepath: focusStartFile.path
    property alias cfg_timer_end_notification_enabled: focusEndNotify.checked
    property alias cfg_timer_stop_sfx_enabled: focusEndSound.checked
    property alias cfg_timer_stop_sfx_filepath: focusEndFile.path

    property alias cfg_break_start_notification_enabled: breakStartNotify.checked
    property alias cfg_break_start_sfx_enabled: breakStartSound.checked
    property alias cfg_break_start_sfx_filepath: breakStartFile.path
    property alias cfg_break_end_notification_enabled: breakEndNotify.checked
    property alias cfg_break_end_sfx_enabled: breakEndSound.checked
    property alias cfg_break_end_sfx_filepath: breakEndFile.path

    property alias cfg_timer_tick_sfx_enabled: tickSound.checked
    property alias cfg_timer_tick_sfx_filepath: tickFile.path

    property alias cfg_break_overrun_repeat_enabled: overrunRepeat.checked
    property alias cfg_break_overrun_repeat_seconds: overrunEvery.value

    property alias cfg_sound_volume: volume.value

    function preview(path) {
        sfx.play(path, volume.value / 100);
    }

    Sfx {
        id: sfx
    }

    ColumnLayout {
        spacing: 0

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }

        FormCard.FormHeader {
            title: i18n("Sound")
        }

        FormCard.FormCard {
            FormCard.AbstractFormDelegate {
                background: null
                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing

                    QQC2.Label {
                        text: i18n("Volume")
                    }

                    QQC2.Slider {
                        id: volume

                        Layout.fillWidth: true
                        from: 0
                        to: 100
                        stepSize: 5
                        snapMode: QQC2.Slider.SnapAlways
                    }

                    QQC2.Label {
                        // Fixed width, so dragging the slider does not shift it.
                        Layout.minimumWidth: Kirigami.Units.gridUnit * 2
                        horizontalAlignment: Text.AlignRight
                        text: i18n("%1%", Math.round(volume.value))
                    }
                }
            }
        }

        FormCard.FormSectionText {
            text: i18n("Applies to every sound below. The notification and the sound are independent for each event, so either can be used on its own.")
        }

        FormCard.FormHeader {
            title: i18n("Focus session starts")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: focusStartNotify

                text: i18n("Show a notification")
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: focusStartSound

                text: i18n("Play a sound")
            }

            FormCard.FormDelegateSeparator {}

            FormPathDelegate {
                id: focusStartFile

                label: i18n("Sound file")
                currentFolder: root.soundFolder
                nameFilters: root.soundFilters
                enabled: focusStartSound.checked
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormButtonDelegate {
                text: i18n("Preview")
                icon.name: "media-playback-start"
                enabled: focusStartSound.checked
                onClicked: root.preview(focusStartFile.path)
            }
        }

        FormCard.FormHeader {
            title: i18n("Focus session ends")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: focusEndNotify

                text: i18n("Show a notification")
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: focusEndSound

                text: i18n("Play a sound")
            }

            FormCard.FormDelegateSeparator {}

            FormPathDelegate {
                id: focusEndFile

                label: i18n("Sound file")
                currentFolder: root.soundFolder
                nameFilters: root.soundFilters
                enabled: focusEndSound.checked
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormButtonDelegate {
                text: i18n("Preview")
                icon.name: "media-playback-start"
                enabled: focusEndSound.checked
                onClicked: root.preview(focusEndFile.path)
            }
        }

        FormCard.FormHeader {
            title: i18n("Break starts")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: breakStartNotify

                text: i18n("Show a notification")
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: breakStartSound

                text: i18n("Play a sound")
            }

            FormCard.FormDelegateSeparator {}

            FormPathDelegate {
                id: breakStartFile

                label: i18n("Sound file")
                currentFolder: root.soundFolder
                nameFilters: root.soundFilters
                enabled: breakStartSound.checked
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormButtonDelegate {
                text: i18n("Preview")
                icon.name: "media-playback-start"
                enabled: breakStartSound.checked
                onClicked: root.preview(breakStartFile.path)
            }
        }

        FormCard.FormHeader {
            title: i18n("Break ends")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: breakEndNotify

                text: i18n("Show a notification")
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: breakEndSound

                text: i18n("Play a sound")
            }

            FormCard.FormDelegateSeparator {}

            FormPathDelegate {
                id: breakEndFile

                label: i18n("Sound file")
                currentFolder: root.soundFolder
                nameFilters: root.soundFilters
                enabled: breakEndSound.checked
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormButtonDelegate {
                text: i18n("Preview")
                icon.name: "media-playback-start"
                enabled: breakEndSound.checked
                onClicked: root.preview(breakEndFile.path)
            }
        }

        FormCard.FormSectionText {
            text: i18n("A break that runs past its end uses these too.")
        }

        FormCard.FormHeader {
            title: i18n("Break overrun")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: overrunRepeat

                text: i18n("Repeat the sound while a break runs over")
                description: i18n("One sound at the moment a break ends is easy to miss. This keeps reminding you until you start the next focus session.")
                enabled: breakEndSound.checked
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSpinBoxDelegate {
                id: overrunEvery

                label: i18n("Repeat every")
                from: 10
                to: 3600
                stepSize: 10
                textFromValue: function(value, locale) {
                    return i18np("%1 second", "%1 seconds", value);
                }
                // Paired with textFromValue, as on the Timer page: without it the
                // suffixed text cannot be parsed back and typing a value breaks.
                valueFromText: function(text, locale) {
                    return parseInt(text) || from;
                }
                enabled: breakEndSound.checked && overrunRepeat.checked
            }
        }

        FormCard.FormHeader {
            title: i18n("Ticking")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: tickSound

                text: i18n("Tick as a focus session runs out")
                description: i18n("Begins at the point set on the Timer page and grows louder as the end approaches.")
            }

            FormCard.FormDelegateSeparator {}

            FormPathDelegate {
                id: tickFile

                label: i18n("Sound file")
                currentFolder: root.soundFolder
                nameFilters: root.soundFilters
                enabled: tickSound.checked
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormButtonDelegate {
                text: i18n("Preview")
                icon.name: "media-playback-start"
                enabled: tickSound.checked
                onClicked: root.preview(tickFile.path)
            }
        }
    }
}
