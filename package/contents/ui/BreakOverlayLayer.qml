import org.kde.layershell as LayerShell

// BreakOverlay plus the layer-shell properties, which are what keep the overlay up across
// virtual desktop switches: a Wayland client cannot ask to be on every desktop, but a layer
// surface is not assigned to one at all.
//
// Separate from BreakOverlay.qml so that the optional module is imported only by a file the
// applet loads when it has established the module is there (gitlab #58).
BreakOverlay {
    // Above panels and normal windows: a break the panel can cover is not a break.
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    // Anchored to all four edges, which is how a layer surface asks for the whole output
    // rather than a size of its own.
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.screenConfiguration: LayerShell.Window.ScreenFromQWindow
    // -1 ignores other surfaces' exclusive zones. Without it the panel's reserved strip is
    // subtracted from the anchored surface and the overlay comes up short of the output -
    // measured as 1888 of 1920 pixels wide with a panel present.
    LayerShell.Window.exclusionZone: -1
    // OnDemand rather than Exclusive: the overlay takes keyboard focus when clicked so
    // Escape works, without swallowing every keystroke on the machine.
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityOnDemand
}
