pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Night-light state, watched rather than polled.
//
// Hyprsunset.sh already records what it did in ~/.cache/.hyprsunset_state, and
// it writes that file in place, so inotify sees every change - whether it came
// from the bar or from SUPER+N. Watching it replaces a 2000ms Timer that
// spawned `bash` + the script roughly 30 times a minute, per screen, to observe
// something that changes twice a day. It is also a singleton now, so the state
// is shared instead of each screen's bar keeping its own copy in sync.
Singleton {
    id: root

    // What the state file says. This is intent: the toggle writes it.
    property bool stateFileOn: false
    // Whether hyprsunset is actually alive. Only consulted to catch the one
    // case the file cannot describe - it says "on" but the process has died.
    property bool processAlive: true

    readonly property bool isOn: stateFileOn && processAlive

    readonly property string statePath: (Quickshell.env("HOME") || "") + "/.cache/.hyprsunset_state"

    function applyState() {
        root.stateFileOn = stateFile.text().trim() === "on"
        // A fresh "on" is trusted until the next reconcile proves otherwise;
        // otherwise clicking the toggle would leave the icon dark until the
        // 60s timer caught up.
        if (root.stateFileOn)
            root.processAlive = true
    }

    FileView {
        id: stateFile
        // Missing until Hyprsunset.sh has run once; that is off, not an error.
        printErrors: false
        path: root.statePath
        watchChanges: true
        blockLoading: true
        onFileChanged: {
            reload()
            root.applyState()
        }
        onLoadedChanged: if (loaded) root.applyState()
        // No file yet means the script has never run: off, not an error.
        onLoadFailed: root.stateFileOn = false
    }

    Process {
        id: toggleProc
        command: ["bash", "-c", "$HOME/.config/hypr/scripts/Hyprsunset.sh toggle"]
    }

    function toggle() {
        toggleProc.running = true
    }

    // The one thing the state file cannot tell us: hyprsunset died on its own,
    // leaving the file reading "on" while the screen is back to daylight.
    //
    // Only consulted while the file says "on". The script's OFF path starts
    // hyprsunset briefly to apply the identity ramp before killing it, so a
    // sample taken during that window would see a live process and wrongly
    // flip the icon back on - but by then the file already reads "off", and
    // this never looks at the process in that case.
    Process {
        id: aliveProc
        command: ["sh", "-c", "pgrep -x hyprsunset >/dev/null 2>&1 && echo yes || echo no"]
        stdout: SplitParser {
            onRead: data => {
                if (data) root.processAlive = (data.trim() === "yes")
            }
        }
    }

    Timer {
        interval: 60000
        running: root.stateFileOn
        repeat: true
        onTriggered: aliveProc.running = true
    }
}
