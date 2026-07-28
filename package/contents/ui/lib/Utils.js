// Deliberately not ".pragma library": these helpers are shared by QML files
// that also need their own component context.

// remove prefixed "file://"
function getPath(fileUrl) {
    return fileUrl.toString().replace(/^file:\/\//, "");
}
