// Deliberately not ".pragma library": these helpers are shared by QML files
// that also need their own component context.

// Turn a file:// url into a plain filesystem path. The url form percent-encodes
// anything special, so a path containing a space arrives as %20 and has to be
// decoded or the stored path will not resolve.
function getPath(fileUrl) {
    var path = fileUrl.toString().replace(/^file:\/\//, "");
    try {
        return decodeURIComponent(path);
    } catch (e) {
        // Already a plain path containing a stray '%'; leave it alone.
        return path;
    }
}

// The file name alone, for a button that has room for "bell.oga" but not for the whole
// path. The full path goes in that button's tooltip.
function baseName(path) {
    var text = "" + (path || "");
    var cut = text.lastIndexOf("/");
    return cut >= 0 ? text.substring(cut + 1) : text;
}
