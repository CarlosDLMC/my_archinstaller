pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// НЕ ЗАСЫПАТЬ - the ПУЛЬТ switch that keeps the machine from going idle.
//
// While it is on the bar holds a logind idle inhibitor (systemd-inhibit
// --what=idle), the same lock agent-awake takes while an agent works; hypridle
// honours it, so the screensaver and the lock never come. Off, the inhibitor
// is released and the idle timer runs as usual.
//
// The choice is kept in $XDG_RUNTIME_DIR, not ~/.cache: it survives a bar
// reload or restart but not a logout or reboot, so a forgotten switch cannot
// keep a fresh session awake for good.
//
// The inhibitor's child watches both the bar and systemd-inhibit itself and
// exits when either is gone - so the lock is dropped even if the bar dies
// without stopping it, and stopping it leaves nothing behind.
Singleton {
    id: root

    property bool on: false
    readonly property string prefPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/quickshell-keep-awake"

    function setOn(value) {
        root.on = value
        prefWriteProc.value = value ? "on" : "off"
        prefWriteProc.running = true
    }

    function toggle() {
        setOn(!root.on)
    }

    FileView {
        id: prefFile
        path: root.prefPath
        printErrors: false
        blockAllReads: true
        onLoadedChanged: if (loaded) root.on = text().trim() === "on"
        onLoadFailed: root.on = false
    }

    Process {
        id: prefWriteProc
        property string value: "off"
        command: ["sh", "-c", 'printf "%s\\n" "$2" > "$1"', "sh", root.prefPath, value]
    }

    Process {
        id: inhibitProc
        running: root.on
        // Outer $PPID = the bar; inner $PPID = systemd-inhibit.
        command: ["sh", "-c",
            'exec systemd-inhibit --what=idle --who="Quickshell bar" --why="НЕ ЗАСЫПАТЬ is on" --mode=block '
            + 'sh -c \'while kill -0 "$1" 2>/dev/null && kill -0 "$PPID" 2>/dev/null; do sleep 5; done\' sh "$PPID"']
    }
}
