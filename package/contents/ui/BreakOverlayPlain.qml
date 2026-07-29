import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.layershell as LayerShell

// One fullscreen break overlay. Instantiated once per screen, because a single
// window only covers the display it is on, which left every other monitor
// uncovered during a break (gitlab #19).
//
// A layer-shell surface, because a Wayland client cannot put itself on every
// virtual desktop - there is no protocol for asking. Layer surfaces are not
// assigned to a desktop at all, so the compositor keeps them up across desktop
// switches, which is what a break overlay has to do. On a compositor without
// layer shell the attached properties do nothing and this stays a plain
// fullscreen window.
//
// The unblurred flavour. DashboardWindow enables blur AND Plasma's background
// contrast effect in C++, and neither can be turned off from QML. Contrast takes
// its region from the window's alpha mask, so at a low background opacity the only
// alpha left is the buttons' own drop shadows - whose soft gradients it quantises
// into jagged halos. An ordinary Window asks the compositor for nothing, so the
// overlay is exactly what it draws.
//
// Takes the applet root rather than a dozen individual properties: it is an
// internal part of the applet, and the alternative was mirroring most of the
// root's state through this file.
Window {
    id: overlay

    property var applet
    // Where this overlay belongs, in virtual desktop coordinates. Setting the
    // geometry is also what picks the output: it decides which screen the window
    // is on, and ScreenFromQWindow below tells the compositor to use that one.
    property rect screenGeometry

    signal closeRequested()

    function showOnItsScreen() {
        overlay.x = screenGeometry.x;
        overlay.y = screenGeometry.y;
        overlay.width = screenGeometry.width;
        overlay.height = screenGeometry.height;
        overlay.showFullScreen();
        overlay.raise();
    }

    flags: Qt.WindowStaysOnTopHint | Qt.FramelessWindowHint
    // Transparent window plus a Rectangle for the tint: a plain Window has no
    // backgroundColor of its own.
    color: "transparent"

    // Above panels and normal windows: a break the panel can cover is not a break.
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    // Anchored to all four edges, which is how a layer surface asks for the whole
    // output rather than a size of its own.
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.screenConfiguration: LayerShell.Window.ScreenFromQWindow
    // -1 ignores other surfaces' exclusive zones. Without it the panel's reserved
    // strip is subtracted from the anchored surface and the overlay comes up short
    // of the output - measured as 1888 of 1920 pixels wide with a panel present.
    LayerShell.Window.exclusionZone: -1
    // OnDemand rather than Exclusive: the overlay takes keyboard focus when clicked
    // so Escape works, without swallowing every keystroke on the machine.
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityOnDemand

    Rectangle {
        anchors.fill: parent
        color: Qt.hsla(Kirigami.Theme.backgroundColor.hslHue,
                       Kirigami.Theme.backgroundColor.hslSaturation,
                       Kirigami.Theme.backgroundColor.hslLightness,
                       plasmoid.configuration.break_overlay_opacity / 100)
    }

    BreakOverlayContent {
        anchors.fill: parent
        applet: overlay.applet
        onCloseRequested: overlay.closeRequested()
    }
}
