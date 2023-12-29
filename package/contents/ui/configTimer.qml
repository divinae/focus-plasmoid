import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

QQC2.Pane {
    id: root

    property alias cfg_focus_time: focus_time.value
    property alias cfg_short_break_time: short_break_time.value
    property alias cfg_long_break_time: long_break_time.value
    property alias cfg_ticking_time: ticking_time.value
    property alias cfg_number_of_sessions: number_of_sessions.value

    Kirigami.FormLayout {
        anchors.fill: parent

        RowLayout {
            Kirigami.FormData.label: i18n("Number of sessions:")

            QQC2.SpinBox {
                id: number_of_sessions

                to: 10
                from: 1
            }

        }

        RowLayout {
            Kirigami.FormData.label: i18n("Focus:")

            QQC2.SpinBox {
                id: focus_time

                to: 9999
                from: 1
                textFromValue: function(value, locale) {
                    return qsTr("%1 min").arg(value);
                }
            }

        }

        RowLayout {
            Kirigami.FormData.label: i18n("Short break:")

            QQC2.SpinBox {
                id: short_break_time

                to: 9999
                textFromValue: function(value, locale) {
                    return qsTr("%1 min").arg(value);
                }
            }

        }

        RowLayout {
            Kirigami.FormData.label: i18n("Long break:")

            QQC2.SpinBox {
                id: long_break_time

                to: 9999
                textFromValue: function(value, locale) {
                    return qsTr("%1 min").arg(value);
                }
            }

        }

        RowLayout {
            Kirigami.FormData.label: i18n("Ticking time:")

            QQC2.SpinBox {
                id: ticking_time

                to: 60
                textFromValue: function(value, locale) {
                    return qsTr("%1 s").arg(value);
                }
            }

        }

    }

}
