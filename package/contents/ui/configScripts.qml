import QtCore
import QtQuick
import QtQuick.Layouts
import org.kde.kcmutils as KCMUtils
import org.kde.kirigamiaddons.formcard as FormCard

KCMUtils.SimpleKCM {
    id: root

    readonly property var scriptFilters: [i18n("Shell script (*.sh)"), i18n("All files (*)")]
    // currentFolder is a url and Qt does not expand "~", which is why the old
    // '~/' never opened the home directory.
    readonly property url scriptFolder: StandardPaths.writableLocation(StandardPaths.HomeLocation)

    property alias cfg_start_focus_script_filepath: start_focus_script_filepath.path
    property alias cfg_start_focus_script_enabled: start_focus_script_enabled.checked
    property alias cfg_start_break_script_filepath: start_break_script_filepath.path
    property alias cfg_start_break_script_enabled: start_break_script_enabled.checked
    property alias cfg_end_focus_script_filepath: end_focus_script_filepath.path
    property alias cfg_end_focus_script_enabled: end_focus_script_enabled.checked
    property alias cfg_end_break_script_filepath: end_break_script_filepath.path
    property alias cfg_end_break_script_enabled: end_break_script_enabled.checked
    property alias cfg_stop_script_filepath: stop_script_filepath.path
    property alias cfg_stop_script_enabled: stop_script_enabled.checked

    ColumnLayout {
        spacing: 0

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }

        FormCard.FormHeader {
            title: i18n("Focus sessions")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: start_focus_script_enabled

                text: i18n("Run a script when focus starts")
            }

            FormCard.FormDelegateSeparator {}

            FormPathDelegate {
                id: start_focus_script_filepath

                label: i18n("Script")
                currentFolder: root.scriptFolder
                nameFilters: root.scriptFilters
                enabled: start_focus_script_enabled.checked
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: end_focus_script_enabled

                text: i18n("Run a script when focus ends")
            }

            FormCard.FormDelegateSeparator {}

            FormPathDelegate {
                id: end_focus_script_filepath

                label: i18n("Script")
                currentFolder: root.scriptFolder
                nameFilters: root.scriptFilters
                enabled: end_focus_script_enabled.checked
            }
        }

        FormCard.FormHeader {
            title: i18n("Breaks")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: start_break_script_enabled

                text: i18n("Run a script when a break starts")
            }

            FormCard.FormDelegateSeparator {}

            FormPathDelegate {
                id: start_break_script_filepath

                label: i18n("Script")
                currentFolder: root.scriptFolder
                nameFilters: root.scriptFilters
                enabled: start_break_script_enabled.checked
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: end_break_script_enabled

                text: i18n("Run a script when a break ends")
            }

            FormCard.FormDelegateSeparator {}

            FormPathDelegate {
                id: end_break_script_filepath

                label: i18n("Script")
                currentFolder: root.scriptFolder
                nameFilters: root.scriptFilters
                enabled: end_break_script_enabled.checked
            }
        }

        FormCard.FormHeader {
            title: i18n("Stopping the timer")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: stop_script_enabled

                text: i18n("Run a script when the timer is stopped")
            }

            FormCard.FormDelegateSeparator {}

            FormPathDelegate {
                id: stop_script_filepath

                label: i18n("Script")
                currentFolder: root.scriptFolder
                nameFilters: root.scriptFilters
                enabled: stop_script_enabled.checked
            }
        }

        FormCard.FormSectionText {
            text: i18n("Each script is run with sh. Paths containing spaces are handled, so no quoting is needed.")
        }
    }
}
