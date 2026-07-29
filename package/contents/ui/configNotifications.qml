import QtQuick
import QtQuick.Layouts
import org.kde.kcmutils as KCMUtils
import org.kde.kirigamiaddons.formcard as FormCard

KCMUtils.SimpleKCM {
    id: root

    readonly property var soundFilters: [i18n("Sound files (*.wav *.mp3 *.oga *.ogg)"), i18n("All files (*)")]
    readonly property url soundFolder: "file:///usr/share/sounds"

    property alias cfg_timer_start_notification_enabled: timer_start_notification_enabled.checked
    property alias cfg_timer_end_notification_enabled: timer_end_notification_enabled.checked
    property alias cfg_timer_start_sfx_enabled: timer_start_sfx_enabled.checked
    property alias cfg_timer_start_sfx_filepath: timer_start_sfx_filepath.path
    property alias cfg_timer_stop_sfx_enabled: timer_stop_sfx_enabled.checked
    property alias cfg_timer_stop_sfx_filepath: timer_stop_sfx_filepath.path
    property alias cfg_timer_tick_sfx_enabled: timer_tick_sfx_enabled.checked
    property alias cfg_timer_tick_sfx_filepath: timer_tick_sfx_filepath.path

    function preview(path) {
        sfx.play(path);
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
            title: i18n("When a session starts")
        }

        FormCard.FormSectionText {
            text: i18n("Applies to focus sessions and to breaks alike.")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: timer_start_notification_enabled

                text: i18n("Show a notification")
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: timer_start_sfx_enabled

                text: i18n("Play a sound")
            }

            FormCard.FormDelegateSeparator {}

            FormPathDelegate {
                id: timer_start_sfx_filepath

                label: i18n("Sound file")
                currentFolder: root.soundFolder
                nameFilters: root.soundFilters
                enabled: timer_start_sfx_enabled.checked
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormButtonDelegate {
                text: i18n("Preview")
                icon.name: "media-playback-start"
                enabled: timer_start_sfx_enabled.checked
                onClicked: root.preview(timer_start_sfx_filepath.path)
            }
        }

        FormCard.FormHeader {
            title: i18n("When a session ends")
        }

        FormCard.FormSectionText {
            text: i18n("Applies to the end of a focus session and to the end of a break, including a break that has run over.")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: timer_end_notification_enabled

                text: i18n("Show a notification")
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: timer_stop_sfx_enabled

                text: i18n("Play a sound")
            }

            FormCard.FormDelegateSeparator {}

            FormPathDelegate {
                id: timer_stop_sfx_filepath

                label: i18n("Sound file")
                currentFolder: root.soundFolder
                nameFilters: root.soundFilters
                enabled: timer_stop_sfx_enabled.checked
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormButtonDelegate {
                text: i18n("Preview")
                icon.name: "media-playback-start"
                enabled: timer_stop_sfx_enabled.checked
                onClicked: root.preview(timer_stop_sfx_filepath.path)
            }
        }

        FormCard.FormHeader {
            title: i18n("Ticking")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: timer_tick_sfx_enabled

                text: i18n("Tick as a focus session runs out")
                description: i18n("Begins at the point set on the Timer page and grows louder as the end approaches.")
            }

            FormCard.FormDelegateSeparator {}

            FormPathDelegate {
                id: timer_tick_sfx_filepath

                label: i18n("Sound file")
                currentFolder: root.soundFolder
                nameFilters: root.soundFilters
                enabled: timer_tick_sfx_enabled.checked
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormButtonDelegate {
                text: i18n("Preview")
                icon.name: "media-playback-start"
                enabled: timer_tick_sfx_enabled.checked
                onClicked: root.preview(timer_tick_sfx_filepath.path)
            }
        }
    }
}
