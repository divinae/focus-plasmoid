import QtMultimedia
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

QQC2.Pane {
    id: root

    property alias cfg_timer_start_sfx_enabled: timer_start_sfx_enabled.checked
    property alias cfg_timer_start_sfx_filepath: timer_start_sfx_filepath.text
    property alias cfg_timer_stop_sfx_enabled: timer_stop_sfx_enabled.checked
    property alias cfg_timer_stop_sfx_filepath: timer_stop_sfx_filepath.text
    property alias cfg_timer_tick_sfx_enabled: timer_tick_sfx_enabled.checked
    property alias cfg_timer_tick_sfx_filepath: timer_tick_sfx_filepath.text

    function getPath(fileUrl) {
        // remove prefixed "file://"
        return fileUrl.toString().replace(/^file:\/\//, "");
    }

    MediaPlayer {
        id: sfx

        audioOutput: AudioOutput {
        }

    }

    Kirigami.FormLayout {
        anchors.fill: parent

        RowLayout {
            Kirigami.FormData.label: i18n("Start:")

            QQC2.CheckBox {
                id: timer_start_sfx_enabled
            }

            QQC2.TextField {
                id: timer_start_sfx_filepath

                Layout.fillWidth: true
                enabled: cfg_timer_start_sfx_enabled
                placeholderText: "/usr/share/sounds/ocean/stereo/dialog-information.oga"
            }

            QQC2.Button {
                icon.name: "quickopen-file"
                onClicked: timer_start_sfx_filepathDialog.visible = true
                enabled: cfg_timer_start_sfx_enabled
            }

            QQC2.Button {
                icon.name: "media-playback-start"
                onClicked: {
                    sfx.source = timer_start_sfx_filepath.text;
                    sfx.play();
                }
            }

        }

        RowLayout {
            Kirigami.FormData.label: i18n("End:")

            QQC2.CheckBox {
                id: timer_stop_sfx_enabled
            }

            QQC2.TextField {
                id: timer_stop_sfx_filepath

                Layout.fillWidth: true
                enabled: cfg_timer_stop_sfx_enabled
                placeholderText: "/usr/share/sounds/ocean/stereo/dialog-question.oga"
            }

            QQC2.Button {
                icon.name: "quickopen-file"
                onClicked: timer_stop_sfx_filepathDialog.visible = true
                enabled: cfg_timer_stop_sfx_enabled
            }

            QQC2.Button {
                icon.name: "media-playback-start"
                onClicked: {
                    sfx.source = timer_stop_sfx_filepath.text;
                    sfx.play();
                }
            }

        }

        RowLayout {
            Kirigami.FormData.label: i18n("Countdown tick:")

            QQC2.CheckBox {
                id: timer_tick_sfx_enabled
            }

            QQC2.TextField {
                id: timer_tick_sfx_filepath

                Layout.fillWidth: true
                enabled: cfg_timer_tick_sfx_enabled
                placeholderText: "/usr/share/sounds/ocean/stereo/dialog-warning.oga"
            }

            QQC2.Button {
                icon.name: "quickopen-file"
                onClicked: timer_tick_sfx_filepathDialog.visible = true
                enabled: cfg_timer_tick_sfx_enabled
            }

            QQC2.Button {
                icon.name: "media-playback-start"
                onClicked: {
                    sfx.source = timer_tick_sfx_filepath.text;
                    sfx.play();
                }
            }

        }

    }

    FileDialog {
        id: timer_start_sfx_filepathDialog

        title: i18n("Choose a sound effect")
        currentFolder: "file:///usr/share/sounds"
        nameFilters: ["Sound files (*.wav *.mp3 *.oga *.ogg)", "All files (*)"]
        onAccepted: {
            cfg_timer_start_sfx_filepath = getPath(timer_start_sfx_filepathDialog.currentFile);
        }
    }

    FileDialog {
        id: timer_stop_sfx_filepathDialog

        title: i18n("Choose a sound effect")
        currentFolder: "file:///usr/share/sounds"
        nameFilters: ["Sound files (*.wav *.mp3 *.oga *.ogg)", "All files (*)"]
        onAccepted: {
            cfg_timer_stop_sfx_filepath = getPath(timer_stop_sfx_filepathDialog.currentFile);
        }
    }

    FileDialog {
        id: timer_tick_sfx_filepathDialog

        title: i18n("Choose a sound effect")
        currentFolder: "file:///usr/share/sounds"
        nameFilters: ["Sound files (*.wav *.mp3 *.oga *.ogg)", "All files (*)"]
        onAccepted: {
            cfg_timer_tick_sfx_filepath = getPath(timer_tick_sfx_filepathDialog.currentFile);
        }
    }

}
