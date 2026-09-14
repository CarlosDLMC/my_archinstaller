import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Hyprland
import ".."

RowLayout {
    id: windowInfo
    spacing: 0

    property string activeWindow: ""
    // Address of the focused window, tracked so a title change can be matched
    // against it. Hyprland reports title changes per window, not per focus.
    property string activeAddress: ""

    // The title is read straight off the Hyprland event payload. This used to
    // run `hyprctl activewindow -j | jq` - three processes - on EVERY raw
    // event, with no filter at all: workspace switches, mouse focus changes,
    // and the ten activelayout events Hyprland fires for each keyboard switch
    // (see KeyboardLayoutWidget, which reads its payload for the same reason).
    // On a two-monitor setup that is two bars doing it. The payloads carry
    // everything needed, so none of it is necessary.
    //
    //   activewindow    "<class>,<title>"    focus moved, or "," when nothing
    //                                        is focused - which is also how
    //                                        the title finally clears when the
    //                                        last window closes
    //   activewindowv2  "<address>"          same event, address form
    //   windowtitlev2   "<address>,<title>"  a window retitled itself
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activewindow") {
                var i = event.data.indexOf(",")
                windowInfo.activeWindow = i < 0 ? "" : event.data.substring(i + 1)
            } else if (event.name === "activewindowv2") {
                windowInfo.activeAddress = event.data.trim()
            } else if (event.name === "windowtitlev2") {
                var j = event.data.indexOf(",")
                if (j < 0) return
                if (event.data.substring(0, j) === windowInfo.activeAddress)
                    windowInfo.activeWindow = event.data.substring(j + 1)
            }
        }
    }

    // One query at startup, because no event has fired yet at that point.
    // The 0x prefix is stripped: hyprctl prints "0x55fac9af6e80" but the event
    // payloads carry the bare "55fac9af6e80", and the two have to compare equal
    // or the first title change would be missed.
    Process {
        id: initialProc
        command: ["sh", "-c",
            "hyprctl activewindow -j | jq -r '((.address // \"\") | sub(\"^0x\";\"\")) + \"\\t\" + (.title // \"\")'"]
        stdout: SplitParser {
            onRead: data => {
                if (!data) return
                var parts = data.split("\t")
                if (parts.length < 2) return
                windowInfo.activeAddress = parts[0].trim()
                windowInfo.activeWindow = parts[1]
            }
        }
        Component.onCompleted: running = true
    }

    Text {
        text: activeWindow
        color: Theme.colWindow
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
        font.bold: true; style: Text.Outline; styleColor: Theme.colTextShadow
        Layout.leftMargin: 0
        Layout.maximumWidth: 375
        elide: Text.ElideRight
        maximumLineCount: 1
        visible: activeWindow.length > 0
    }
}
