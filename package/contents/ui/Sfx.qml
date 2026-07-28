import QtMultimedia
import QtQuick

// Sound effects, with the MediaPlayer created only on first use.
//
// Merely constructing a MediaPlayer makes QtMultimedia probe hardware video
// decode. On a machine with the NVIDIA driver that loads libvdpau_nvidia.so,
// which opens /dev/nvidia* and holds it, so the dGPU never reaches D3cold - the
// applet kept the card awake just by sitting in the panel (gitlab #45).
//
// Verified with a pair of minimal QML files: no MediaPlayer produces no VDPAU
// probe at all, one constructed and never played produces it. So nothing here
// touches QtMultimedia until a sound is actually asked for, and a user who never
// enables a sound never pays for it.
Item {
    id: root

    function play(path, volume) {
        if (!path)
            return;
        // First call is what brings QtMultimedia in.
        player.active = true;
        var media = player.item;
        media.audioOutput.volume = volume === undefined ? 1 : volume;
        media.source = path;
        media.play();
    }

    Loader {
        id: player

        active: false

        sourceComponent: Component {
            MediaPlayer {
                audioOutput: AudioOutput {}
            }
        }
    }
}
