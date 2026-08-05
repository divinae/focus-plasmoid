import "./lib/Utils.js" as Utils
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard

KCMUtils.SimpleKCM {
    id: root

    // Explicit column widths, shared by the header and the rows. Binding a checkbox to its
    // header label's width instead looked fine in English and collapsed the control to a
    // sliver as soon as the header was short - or, in an offscreen render without i18n,
    // empty.
    readonly property int checkColumn: Kirigami.Units.gridUnit * 4
    readonly property int fileColumn: Kirigami.Units.gridUnit * 8
    readonly property int previewColumn: Kirigami.Units.gridUnit * 2

    readonly property var soundFilters: [i18n("Sound files (*.wav *.mp3 *.oga *.ogg)"), i18n("All files (*)")]
    readonly property url soundFolder: "file:///usr/share/sounds"

    // The existing timer_start_* and timer_stop_* keys are the focus ones: they kept
    // their names so a customised setup survives the split into four events.
    property alias cfg_timer_start_notification_enabled: focusStart.notifyChecked
    property alias cfg_timer_start_sfx_enabled: focusStart.soundChecked
    property alias cfg_timer_start_sfx_filepath: focusStart.path
    property alias cfg_timer_end_notification_enabled: focusEnd.notifyChecked
    property alias cfg_timer_stop_sfx_enabled: focusEnd.soundChecked
    property alias cfg_timer_stop_sfx_filepath: focusEnd.path

    property alias cfg_break_start_notification_enabled: breakStart.notifyChecked
    property alias cfg_break_start_sfx_enabled: breakStart.soundChecked
    property alias cfg_break_start_sfx_filepath: breakStart.path
    property alias cfg_break_end_notification_enabled: breakEnd.notifyChecked
    property alias cfg_break_end_sfx_enabled: breakEnd.soundChecked
    property alias cfg_break_end_sfx_filepath: breakEnd.path

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

    // One dialog for all four rows rather than one each: it is opened by whichever row
    // asked, and hands the result back to it.
    FileDialog {
        id: soundDialog

        property var target: null

        title: i18n("Choose a sound file")
        currentFolder: root.soundFolder
        nameFilters: root.soundFilters
        onAccepted: {
            if (target)
                target.path = Utils.getPath(selectedFile);
        }
    }

    // One event per row. The four events used to be four near-identical cards, sixteen
    // controls over a hundred-odd lines, so comparing two of them meant scrolling between
    // them. As rows they line up under their columns and fit on one screen.
    //
    // Plain properties rather than aliases: an alias cannot be passed into a component, but
    // the page's cfg_ aliases can point into one, which is what binds these to the config.
    component EventRow: RowLayout {
        id: row

        property string label: ""
        property bool notifyChecked: false
        property bool soundChecked: false
        property string path: ""

        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label {
            Layout.fillWidth: true
            Layout.minimumWidth: Kirigami.Units.gridUnit * 6
            text: row.label
            elide: Text.ElideRight
        }

        QQC2.CheckBox {
            Layout.preferredWidth: root.checkColumn
            Layout.alignment: Qt.AlignHCenter
            // The indicator sits at the control's left edge, so centring the control is not
            // the same as centring the tick under its heading.
            leftPadding: (width - implicitIndicatorWidth) / 2
            checked: row.notifyChecked
            onToggled: row.notifyChecked = checked
        }

        QQC2.CheckBox {
            Layout.preferredWidth: root.checkColumn
            Layout.alignment: Qt.AlignHCenter
            leftPadding: (width - implicitIndicatorWidth) / 2
            checked: row.soundChecked
            onToggled: row.soundChecked = checked
        }

        // Greyed rather than hidden with the sound off: hiding would break the column
        // alignment that makes the table readable in the first place.
        QQC2.Button {
            Layout.preferredWidth: root.fileColumn
            enabled: row.soundChecked
            text: row.path ? Utils.baseName(row.path) : i18n("Choose…")
            icon.name: "document-open"
            display: QQC2.AbstractButton.TextBesideIcon
            onClicked: {
                soundDialog.target = row;
                soundDialog.open();
            }

            // Attached rather than a child ToolTip object: a child's own `hovered` is the
            // tooltip's, not the button's, so every row showed its tooltip at rest.
            QQC2.ToolTip.text: row.path ? row.path : i18n("Choose a sound file")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }

        QQC2.ToolButton {
            Layout.preferredWidth: root.previewColumn
            enabled: row.soundChecked && row.path !== ""
            icon.name: "media-playback-start"
            display: QQC2.AbstractButton.IconOnly
            text: i18n("Preview")
            onClicked: root.preview(row.path)

            QQC2.ToolTip.text: text
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
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
            title: i18n("Events")
        }

        FormCard.FormCard {
            FormCard.AbstractFormDelegate {
                Layout.fillWidth: true
                background: null

                contentItem: ColumnLayout {
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            Layout.fillWidth: true
                            Layout.minimumWidth: Kirigami.Units.gridUnit * 6
                            text: ""
                        }

                        QQC2.Label {
                            Layout.preferredWidth: root.checkColumn
                            horizontalAlignment: Text.AlignHCenter
                            text: i18n("Popup")
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            color: Kirigami.Theme.disabledTextColor
                        }

                        QQC2.Label {
                            Layout.preferredWidth: root.checkColumn
                            horizontalAlignment: Text.AlignHCenter
                            text: i18n("Sound")
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            color: Kirigami.Theme.disabledTextColor
                        }

                        QQC2.Label {
                            Layout.preferredWidth: root.fileColumn
                            horizontalAlignment: Text.AlignHCenter
                            text: i18n("File")
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            color: Kirigami.Theme.disabledTextColor
                        }

                        // Keeps the header aligned over the preview column.
                        Item {
                            Layout.preferredWidth: root.previewColumn
                        }
                    }

                    EventRow {
                        id: focusStart

                        label: i18n("Focus starts")
                    }

                    EventRow {
                        id: focusEnd

                        label: i18n("Focus ends")
                    }

                    EventRow {
                        id: breakStart

                        label: i18n("Break starts")
                    }

                    EventRow {
                        id: breakEnd

                        label: i18n("Break ends")
                    }
                }
            }
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
                        text: i18n("%1%", volume.value)
                    }
                }
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: overrunRepeat

                text: i18n("Repeat the sound while a break runs over")
                description: i18n("One sound at the moment a break ends is easy to miss.")
                enabled: breakEnd.soundChecked
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
                enabled: breakEnd.soundChecked && overrunRepeat.checked
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
