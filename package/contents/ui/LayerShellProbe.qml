import QtQml
import org.kde.layershell as LayerShell

// Nothing but the import. main.qml creates this with Qt.createComponent() and reads the
// component's status: a dynamic creation reports a missing module as an error it can act
// on, where a static import in a file the applet loads takes the whole applet down.
//
// org.kde.layershell comes from layer-shell-qt, which is not installed everywhere - on
// Kubuntu 25.10 its absence made the applet fail to load entirely (gitlab #58).
QtObject {
}
