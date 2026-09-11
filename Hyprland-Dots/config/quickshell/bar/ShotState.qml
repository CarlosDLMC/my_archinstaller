pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// State for the screenshot dialog. Mirrors RecordState: the dialog only
// collects intent, ScreenShot.sh takes the picture, so the dialog and the bare
// keybinds share one code path.
Singleton {
    id: root

    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/ScreenShot.sh"

    property bool dialogOpen: false
    property string targetMonitor: ""

    // The overlay has to be gone from the screen before grim or slurp runs,
    // or the shot catches the dialog and its dim. Comfortably longer than the
    // 160ms fade.
    readonly property int settleMs: 300

    property string pending: ""

    function open() {
        Monitors.refresh()
        targetMonitor = Monitors.resolveTarget(targetMonitor)
        dialogOpen = true
    }

    function close() {
        dialogOpen = false
    }

    function run(args) {
        pending = args
        close()
        settle.restart()
    }

    function shotFullscreen() {
        run("--monitor " + Monitors.resolveTarget(targetMonitor))
    }

    function shotRegion() {
        run("--area")
    }

    function shotWindow() {
        run("--active")
    }

    function shotSwappy() {
        run("--swappy")
    }

    Timer {
        id: settle
        interval: root.settleMs
        onTriggered: {
            runProc.command = ["sh", "-c",
                root.script + " " + root.pending + " >/dev/null 2>&1 &"]
            runProc.running = true
        }
    }

    Process {
        id: runProc
        command: ["true"]
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "shotMenu"
        description: "Screenshot dialog"
        onPressed: root.open()
    }
}
