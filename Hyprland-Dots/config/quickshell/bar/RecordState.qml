pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// State for the screen-recording dialog.
//
// The dialog only collects intent; ScreenRecord.sh does the recording, so the
// keybind, this UI and the shell all share one code path. wf-recorder needs an
// explicit -o or it falls back to an interactive stdin prompt and silently
// lands on the laptop panel, which is why a monitor is always chosen here.
Singleton {
    id: root

    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/ScreenRecord.sh"
    readonly property string audioStateFile: Quickshell.env("HOME") + "/.cache/screenrecord_audio"

    property bool dialogOpen: false
    property bool recording: false

    // Name of the monitor the "Full screen" button will capture.
    property string targetMonitor: ""

    property bool audioSystem: false
    property bool audioMic: false

    // The four states ScreenRecord.sh understands.
    readonly property string audioMode:
        audioSystem && audioMic ? "both"
        : audioSystem ? "system"
        : audioMic ? "mic"
        : "none"

    // Same key stops a running recording, so it stays a one-press stop - asked
    // of ScreenRecord.sh when the key is pressed (statusProc decides). It used
    // to be polled every 3 s for the whole session: sh, bash, date,
    // xdg-user-dir and pgrep each time, the largest periodic cost left in the
    // bar, only to be ready for this one press.
    property bool openPending: false

    function open() {
        openPending = true
        statusProc.running = true
    }

    function openDialog() {
        Monitors.refresh()
        targetMonitor = Monitors.resolveTarget(targetMonitor)
        dialogOpen = true
    }

    function close() {
        dialogOpen = false
    }

    function persistAudio() {
        persistProc.command = ["sh", "-c",
            "printf '%s' " + audioMode + " > " + audioStateFile]
        persistProc.running = true
    }

    function run(args) {
        runProc.command = ["sh", "-c",
            script + " " + args + " --audio=" + audioMode + " >/dev/null 2>&1 &"]
        runProc.running = true
        statusTimer.restart()
    }

    function recordFullscreen() {
        var mon = Monitors.resolveTarget(targetMonitor)
        close()
        run("--fullscreen " + mon)
    }

    // The dialog must be gone before slurp draws, or the overlay ends up in
    // the selection and steals the drag.
    function recordRegion() {
        close()
        regionDelay.restart()
    }

    function recordWindow() {
        close()
        windowDelay.restart()
    }

    function stop() {
        close()
        run("--stop")
    }

    Timer {
        id: regionDelay
        interval: 180
        onTriggered: root.run("--area")
    }

    Timer {
        id: windowDelay
        interval: 180
        onTriggered: root.run("--active")
    }

    // Recording state is read back from the script rather than assumed, so a
    // wf-recorder that died on startup does not leave the UI claiming to record.
    Timer {
        id: statusTimer
        interval: 900
        onTriggered: statusProc.running = true
    }

    Process {
        id: runProc
        command: ["true"]
    }

    Process {
        id: persistProc
        command: ["true"]
    }

    Process {
        id: statusProc
        command: ["sh", "-c", root.script + " --status"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.recording = (text.trim() === "recording")
                if (root.openPending) {
                    root.openPending = false
                    if (root.recording) root.stop()
                    else root.openDialog()
                }
            }
        }
    }

    // Restore the toggles from the last session so the keybind and the dialog
    // start out agreeing with each other. Read through a Process rather than a
    // FileView: on a fresh install the file does not exist yet, and FileView
    // logs a warning for that on every start.
    Process {
        id: loadAudioProc
        command: ["sh", "-c", "cat " + root.audioStateFile + " 2>/dev/null"]
        stdout: SplitParser {
            onRead: data => {
                var m = (data || "").trim()
                root.audioSystem = (m === "system" || m === "both")
                root.audioMic = (m === "mic" || m === "both")
            }
        }
        Component.onCompleted: running = true
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "recordMenu"
        description: "Screen recording dialog"
        onPressed: root.open()
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "recordStop"
        description: "Stop screen recording"
        onPressed: root.stop()
    }
}
