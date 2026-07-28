import "./lib/Utils.js" as Utils
import QtQuick
import org.kde.kirigamiaddons.formcard as FormCard

// FormFileDelegate speaks file:// urls, while the applet's config keys hold plain
// filesystem paths. This keeps the two in sync in one place rather than at each
// of the eight call sites across the Notifications and Scripts pages.
FormCard.FormFileDelegate {
    id: root

    // The plain path, for binding a cfg_* alias to.
    property string path: ""

    // Both handlers guard on equality, so the pair settles instead of looping.
    onSelectedFileChanged: {
        var selected = Utils.getPath(selectedFile);
        if (selected !== root.path)
            root.path = selected;
    }

    onPathChanged: {
        var wanted = root.path ? "file://" + root.path : "";
        if (selectedFile.toString() !== wanted)
            selectedFile = wanted;
    }
}
