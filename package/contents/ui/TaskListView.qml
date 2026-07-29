import "./lib/tasks.js" as Tasks
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

// Todo list page. Owns no state: it reads and writes the task_list config key
// through the pure helpers in lib/tasks.js.
Item {
    id: root

    // The stored JSON, and a way to write it back.
    required property string tasksJson
    // Currently selected task title, so the active one can be marked.
    property string activeTask: ""

    signal saveRequested(string json)
    signal taskPicked(string title)

    // Archived tasks are the ones the user deleted: hidden here, but kept in the
    // stored list so the stats page can still name their past sessions.
    readonly property var tasks: Tasks.visibleTasks(Tasks.parseTasks(tasksJson))

    function add() {
        var title = newTask.text;
        if (!title.trim())
            return;
        root.saveRequested(Tasks.addTask(root.tasksJson, title));
        newTask.text = "";
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.TextField {
                id: newTask

                Layout.fillWidth: true
                placeholderText: i18n("Add a task…")
                onAccepted: root.add()
            }

            PlasmaComponents.Button {
                icon.name: "list-add"
                enabled: newTask.text.trim() !== ""
                onClicked: root.add()
            }
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.tasks.length === 0
            text: i18n("No tasks yet. Add one above, then pick it to focus on.")
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: Kirigami.Theme.disabledTextColor
        }

        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.tasks.length > 0
            clip: true

            ListView {
                id: list

                model: root.tasks
                spacing: 0

                delegate: RowLayout {
                    required property var modelData
                    required property int index

                    width: list.width
                    spacing: 0

                    PlasmaComponents.CheckBox {
                        checked: modelData.done
                        onToggled: root.saveRequested(Tasks.setDone(root.tasksJson, modelData.id, checked))
                    }

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.smallSpacing
                        text: modelData.title
                        elide: Text.ElideRight
                        font.strikeout: modelData.done
                        // The task being focused on is called out rather than
                        // relying on the dial alone.
                        font.bold: !modelData.done && modelData.title === root.activeTask
                        color: modelData.done ? Kirigami.Theme.disabledTextColor : Kirigami.Theme.textColor

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (!modelData.done)
                                root.taskPicked(modelData.title)
                        }
                    }

                    // Reordering is a swap in the stored list. Buttons rather than
                    // drag and drop: the list is short, and a drag would fight the
                    // ScrollView it sits in.
                    PlasmaComponents.ToolButton {
                        icon.name: "arrow-up"
                        display: QQC2.AbstractButton.IconOnly
                        text: i18n("Move up")
                        flat: true
                        enabled: index > 0
                        implicitWidth: Kirigami.Units.iconSizes.smallMedium + Kirigami.Units.smallSpacing
                        implicitHeight: implicitWidth
                        icon.width: Kirigami.Units.iconSizes.small
                        icon.height: Kirigami.Units.iconSizes.small
                        onClicked: root.saveRequested(Tasks.moveTask(root.tasksJson, modelData.id, -1))
                    }

                    PlasmaComponents.ToolButton {
                        icon.name: "arrow-down"
                        display: QQC2.AbstractButton.IconOnly
                        text: i18n("Move down")
                        flat: true
                        enabled: index < root.tasks.length - 1
                        implicitWidth: Kirigami.Units.iconSizes.smallMedium + Kirigami.Units.smallSpacing
                        implicitHeight: implicitWidth
                        icon.width: Kirigami.Units.iconSizes.small
                        icon.height: Kirigami.Units.iconSizes.small
                        onClicked: root.saveRequested(Tasks.moveTask(root.tasksJson, modelData.id, 1))
                    }

                    PlasmaComponents.ToolButton {
                        icon.name: "edit-delete-remove"
                        display: QQC2.AbstractButton.IconOnly
                        text: i18n("Remove")
                        flat: true
                        // Sized explicitly: the default ToolButton icon is far
                        // larger than a list row wants.
                        implicitWidth: Kirigami.Units.iconSizes.smallMedium + Kirigami.Units.smallSpacing
                        implicitHeight: implicitWidth
                        icon.width: Kirigami.Units.iconSizes.small
                        icon.height: Kirigami.Units.iconSizes.small
                        onClicked: root.saveRequested(Tasks.removeTask(root.tasksJson, modelData.id))
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.tasks.length > 0

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: i18np("%1 task open", "%1 tasks open", Tasks.countOpen(root.tasks))
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: Kirigami.Theme.disabledTextColor
                elide: Text.ElideRight
            }

            PlasmaComponents.Button {
                text: i18n("Clear finished")
                icon.name: "edit-clear-history"
                enabled: Tasks.countOpen(root.tasks) < root.tasks.length
                onClicked: root.saveRequested(Tasks.removeDone(root.tasksJson))
            }
        }
    }
}
