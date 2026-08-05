import QtQuick
import QtTest
import "../package/contents/ui/lib/Utils.js" as Utils

TestCase {
    name: "Utils"

    function test_getPath_data() {
        return [
            { tag: "plain path", url: "file:///usr/share/sounds/x.oga", expected: "/usr/share/sounds/x.oga" },
            // The url form percent-encodes, so a space arrives as %20. Storing it
            // undecoded means the path never resolves.
            { tag: "space", url: "file:///home/dv/My%20Scripts/hook.sh", expected: "/home/dv/My Scripts/hook.sh" },
            { tag: "several spaces", url: "file:///a%20b%20c/d.sh", expected: "/a b c/d.sh" },
            { tag: "non-ascii", url: "file:///home/dv/Muzyka/d%C5%BAwi%C4%99k.oga", expected: "/home/dv/Muzyka/dźwięk.oga" },
            { tag: "no scheme", url: "/already/plain.sh", expected: "/already/plain.sh" },
            { tag: "empty", url: "", expected: "" },
            // A bare '%' is not valid percent-encoding; decoding throws, and the
            // input has to survive rather than take the whole picker down.
            { tag: "literal percent", url: "/tmp/100%/x.sh", expected: "/tmp/100%/x.sh" },
            { tag: "trailing percent", url: "/tmp/x%", expected: "/tmp/x%" }
        ];
    }

    function test_getPath(data) {
        compare(Utils.getPath(data.url), data.expected);
    }

    function test_getPath_acceptsUrlObjects() {
        // FormFileDelegate hands over a url, not a string.
        compare(Utils.getPath(Qt.resolvedUrl("/tmp/plain.sh")), "/tmp/plain.sh");
    }

    function test_baseName() {
        compare(Utils.baseName("/usr/share/sounds/ocean/stereo/dialog-information.oga"), "dialog-information.oga");
        compare(Utils.baseName("bell.oga"), "bell.oga");
        // A path with no file part, and the empty cases the table will hand it.
        compare(Utils.baseName("/usr/share/sounds/"), "");
        compare(Utils.baseName(""), "");
        compare(Utils.baseName(undefined), "");
        // Spaces survive: getPath() has already decoded them by this point.
        compare(Utils.baseName("/home/dv/my sounds/ding.wav"), "ding.wav");
    }
}
