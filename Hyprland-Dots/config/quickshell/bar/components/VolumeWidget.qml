import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import ".."

// Volume readout in the bar, and the audio card behind it.
//
// Gestures on the bar item are unchanged: left-click mutes, wheel adjusts.
// Right-click used to launch pavucontrol; it now opens a card with the three
// things that launch was ever used for - pick an output, pick an input, set a
// level per running application - without a second window to find and close.
//
// Everything here reads the PipeWire service directly, so there are no
// subprocesses and nothing to poll: volume, mute and the device lists are
// live properties.
DropdownWidget {
    id: volumeWidget

    // Right-click opens the card. Left-click is already mute, and muting is
    // the gesture worth keeping on the shortest path.
    triggerButton: Qt.RightButton
    stemAlignment: "center"
    popupWidth: 330
    popupHeight: cardHeight

    // ------------------------------------------------------------------
    //  Default sink / source
    // ------------------------------------------------------------------

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool sinkReady: sink !== null && sink.audio !== null
    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool sourceReady: source !== null && source.audio !== null

    property int volumeLevel: sinkReady ? Math.round(sink.audio.volume * 100) : 0
    property bool volumeMuted: sinkReady ? sink.audio.muted : false
    property bool sourceMuted: sourceReady ? source.audio.muted : false

    PwObjectTracker { objects: volumeWidget.sink ? [volumeWidget.sink] : [] }
    PwObjectTracker { objects: volumeWidget.source ? [volumeWidget.source] : [] }

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

    function adjustVolume(delta) {
        if (!sinkReady) return
        sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + delta))
    }

    function setSinkVolume(v) {
        if (!sinkReady) return
        sink.audio.volume = Math.max(0, Math.min(1, v))
    }

    function toggleMute() {
        if (!sinkReady) return
        sink.audio.muted = !sink.audio.muted
    }

    function setSourceVolume(v) {
        if (!sourceReady) return
        source.audio.volume = Math.max(0, Math.min(1, v))
    }

    function toggleSourceMute() {
        if (!sourceReady) return
        source.audio.muted = !source.audio.muted
    }

    function setStreamVolume(node, v) {
        if (!node || !node.audio) return
        node.audio.volume = Math.max(0, Math.min(1.5, v))
    }

    function toggleStreamMute(node) {
        if (!node || !node.audio) return
        node.audio.muted = !node.audio.muted
    }

    function setDefaultSink(node) {
        if (!node) return
        Pipewire.preferredDefaultAudioSink = node
    }

    function setDefaultSource(node) {
        if (!node) return
        Pipewire.preferredDefaultAudioSource = node
    }

    // ------------------------------------------------------------------
    //  Node classification
    // ------------------------------------------------------------------
    //  Read `properties` only once a node reports `ready`. PwNode.properties is
    //  not valid before the node is bound, and touching it while capture
    //  streams are appearing or disappearing is a known way to destabilise
    //  Quickshell's PipeWire service.
    function nodeProps(node) {
        return node && node.ready && node.properties ? node.properties : ({})
    }

    // Quickshell versions differ in how a stream's direction is exposed, so
    // test the reliable signal first: a playback stream accepts audio from a
    // client and therefore publishes isSink, and only fall back to matching
    // the media class by name.
    function isPlaybackStream(node) {
        if (!node || !node.isStream) return false
        if (node.isSink === true) return true
        var cls = String(node.type || "")
        return cls.indexOf("Stream/Output/Audio") !== -1
            || cls.indexOf("AudioOutStream") !== -1
            || cls.indexOf("Output") !== -1
    }

    function isAudioSource(node) {
        if (!node) return false
        if (node.audio) return true
        var cls = String(node.type || "")
        return cls.indexOf("Audio/Source") !== -1
            || cls.indexOf("AudioSource") !== -1
            || cls.indexOf("Source") !== -1
    }

    readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []

    readonly property var sinkList: {
        var out = []
        for (var i = 0; i < nodes.length; i++) {
            var n = nodes[i]
            if (n && n.isSink && !n.isStream) out.push(n)
        }
        if (sink && out.indexOf(sink) < 0) out.unshift(sink)
        return out
    }

    readonly property var sourceList: {
        var out = []
        for (var i = 0; i < nodes.length; i++) {
            var n = nodes[i]
            if (!n || n.isSink || n.isStream || !isAudioSource(n)) continue
            // The bar's own PipeWire client shows up as a node; it is not a
            // microphone anyone wants to pick.
            if ((n.name || "") === "quickshell") continue
            out.push(n)
        }
        if (source && out.indexOf(source) < 0) out.unshift(source)
        return out
    }

    readonly property var streamList: {
        var out = []
        for (var i = 0; i < nodes.length; i++) {
            var n = nodes[i]
            if (n && isPlaybackStream(n) && n.audio) out.push(n)
        }
        return out
    }

    PwObjectTracker { objects: volumeWidget.sinkList }
    PwObjectTracker { objects: volumeWidget.sourceList }
    PwObjectTracker { objects: volumeWidget.streamList }

    // ------------------------------------------------------------------
    //  Display snapshots
    // ------------------------------------------------------------------
    //  The Repeaters in the card are fed copies, not the live PipeWire lists.
    //  PipeWire can remove a node while Quickshell is still dispatching the
    //  removal, and rebuilding a Repeater from inside that signal has crashed
    //  the PipeWire service; the 75ms debounce lets the mutation settle first.
    //  While the card is shut the snapshots are emptied, so a closed popup
    //  holds no delegates at all.

    property var displaySinks: []
    property var displaySources: []
    property var displayStreams: []

    function refreshSnapshots() {
        if (!dropdownOpen) return
        displaySinks = sinkList.slice()
        displaySources = sourceList.slice()
        displayStreams = streamList.slice()
    }

    Timer {
        id: snapshotDebounce
        interval: 75
        repeat: false
        onTriggered: volumeWidget.refreshSnapshots()
    }

    onSinkListChanged: if (dropdownOpen) snapshotDebounce.restart()
    onSourceListChanged: if (dropdownOpen) snapshotDebounce.restart()
    onStreamListChanged: if (dropdownOpen) snapshotDebounce.restart()

    onDropdownOpenChanged: {
        if (dropdownOpen) {
            refreshSnapshots()
        } else {
            snapshotDebounce.stop()
            displaySinks = []
            displaySources = []
            displayStreams = []
        }
    }

    // ------------------------------------------------------------------
    //  Labels and glyphs
    // ------------------------------------------------------------------

    function nodeLabel(node) {
        if (!node) return "Unknown"
        var p = nodeProps(node)
        var nick = node.nickname || p["node.nick"] || p["device.profile.description"] || ""
        if (nick) return String(nick)
        return String(node.description || p["node.description"] || node.name || "Unknown")
    }

    function nodeBlob(node) {
        var p = nodeProps(node)
        return String([
            node.name, node.description, node.nickname,
            p["device.icon-name"] || "",
            p["device.product.name"] || "",
            p["node.description"] || ""
        ].join(" ")).toLowerCase()
    }

    function sinkGlyph(node) {
        if (!node) return "󰓃"
        var b = nodeBlob(node)
        if (b.indexOf("headphone") !== -1 || b.indexOf("headset") !== -1
            || b.indexOf("earbud") !== -1 || b.indexOf("earphone") !== -1
            || b.indexOf("airpod") !== -1) return "󰋋"
        if (b.indexOf("bluetooth") !== -1 || b.indexOf("bluez") !== -1) return "󰂯"
        if (b.indexOf("hdmi") !== -1 || b.indexOf("displayport") !== -1
            || b.indexOf("display") !== -1) return "󰍹"
        return "󰓃"
    }

    function sourceGlyph(node) {
        if (!node) return "󰍬"
        var b = nodeBlob(node)
        if (b.indexOf("headset") !== -1) return "󰋋"
        if (b.indexOf("bluetooth") !== -1 || b.indexOf("bluez") !== -1) return "󰂯"
        return "󰍬"
    }

    // An application's name, preferring what it calls itself over the raw
    // node name (which is often just "playback" or the binary).
    function streamLabel(node) {
        if (!node) return "Stream"
        var p = nodeProps(node)
        var name = p["application.name"]
            || p["media.name"]
            || node.description
            || node.name
            || "Stream"
        return String(name)
    }

    // ------------------------------------------------------------------
    //  Card height
    // ------------------------------------------------------------------
    //  DropdownWidget takes a fixed popupHeight, so the card reports what its
    //  body measured and that is what sizes it. Computing the height from row
    //  counts instead was tried first and clipped the last application: text
    //  height follows the font's line metrics, not the pixelSize it was set
    //  from, so every row was a few pixels taller than the arithmetic said.
    //
    //  Past the cap the body scrolls rather than growing a card taller than
    //  the screen. Nothing in the panel wraps, so its content height does not
    //  depend on the height it is given and this cannot feed back on itself.

    property real measuredContentHeight: 0

    //  The 30 is DropdownWidget's own insets, which the body never sees: the
    //  popup Loader sits below the 12px stem with an 8px margin above and
    //  below it. Measured content plus those, plus 2 so the last slider is
    //  not flush against the card's bottom edge.
    readonly property int cardHeight:
        Math.max(120, Math.min(Math.ceil(measuredContentHeight) + 30, 560))

    // ------------------------------------------------------------------
    //  Bar item
    // ------------------------------------------------------------------

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: volumeWidget.volumeIcon + " " + volumeWidget.volumeLevel + "%"
        color: volumeWidget.volumeMuted ? Theme.colGrey : Theme.colWhite
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
        font.bold: true; style: Text.Outline; styleColor: Theme.colTextShadow
    }

    // Left-click mutes, wheel adjusts - both unchanged from before the card
    // existed. DropdownWidget hands these back rather than swallowing them.
    onOtherClicked: button => {
        if (button === Qt.LeftButton)
            volumeWidget.toggleMute()
    }

    onWheelMoved: deltaY => {
        if (deltaY > 0) volumeWidget.adjustVolume(0.05)
        else if (deltaY < 0) volumeWidget.adjustVolume(-0.05)
    }

    popupContent: Component {
        AudioPanel {
            anchors.fill: parent
            ctl: volumeWidget
            onContentHeightChanged: volumeWidget.measuredContentHeight = contentHeight
            Component.onCompleted: volumeWidget.measuredContentHeight = contentHeight
        }
    }
}
