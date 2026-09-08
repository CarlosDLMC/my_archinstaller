import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Services.Pipewire
import ".."

Text {
    id: volumeWidget

    // Default sink straight from the PipeWire service. Tracking it keeps its
    // volume/mute properties live, so there is nothing to poll and no
    // `pactl subscribe` child to outlive the bar.
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool sinkReady: sink !== null && sink.audio !== null

    PwObjectTracker { objects: volumeWidget.sink ? [volumeWidget.sink] : [] }

    property int volumeLevel: sinkReady ? Math.round(sink.audio.volume * 100) : 0
    property bool volumeMuted: sinkReady ? sink.audio.muted : false

    // speaker, headphone, hdmi, bluetooth
    property string audioSink: {
        if (!sink) return "speaker"
        var s = ((sink.name || "") + " " + (sink.description || "") + " " + (sink.nickname || "")).toLowerCase()
        if (s.includes("headphone") || s.includes("headset")) return "headphone"
        if (s.includes("hdmi") || s.includes("displayport")) return "hdmi"
        if (s.includes("bluez") || s.includes("bluetooth")) return "bluetooth"
        return "speaker"
    }

    property string volumeIcon: {
        if (volumeMuted) return "󰖁"
        if (audioSink === "headphone") return ""
        if (audioSink === "bluetooth") return "󰂰"
        if (audioSink === "hdmi") return "󰡁"
        // Static speaker icon
        return "󰕾"
    }

    text: volumeIcon + " " + volumeLevel + "%"
    color: volumeMuted ? Theme.colMuted :
           audioSink === "headphone" ? "#f1fa8c" :
           audioSink === "bluetooth" ? Theme.colBluetooth :
           Theme.colVol
    font.pixelSize: Theme.fontSize
    font.family: Theme.fontFamily
    font.bold: true; style: Text.Outline; styleColor: Qt.rgba(color.r, color.g, color.b, 0.3)

    function adjustVolume(delta) {
        if (!sinkReady) return
        sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + delta))
    }

    function toggleMute() {
        if (!sinkReady) return
        sink.audio.muted = !sink.audio.muted
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) {
                volumeControlProc.running = true
            } else if (mouse.button === Qt.LeftButton) {
                volumeWidget.toggleMute()
            }
        }
        onWheel: function(wheel) {
            if (wheel.angleDelta.y > 0) {
                volumeWidget.adjustVolume(0.05)
            } else if (wheel.angleDelta.y < 0) {
                volumeWidget.adjustVolume(-0.05)
            }
        }
    }

    // Volume control launcher. One-shot: it exits on its own, so it cannot leak.
    Process {
        id: volumeControlProc
        command: ["pavucontrol"]
    }
}
