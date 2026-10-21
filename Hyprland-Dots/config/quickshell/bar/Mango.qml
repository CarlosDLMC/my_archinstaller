pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The compositor's state for the whole shell, from mango's IPC socket
// ($MANGO_INSTANCE_SIGNATURE). One connection streams `watch all-monitors`:
// mango pushes a full snapshot of every monitor - its tags, the focused
// window, the layout - on every change, so nothing here polls and no process
// is started. A second one streams `watch keyboardlayout`, which fires only on
// a real layout switch (the monitor snapshot's own layout field follows
// whichever keyboard typed last, wtype included).
//
// Snapshots come 2-4 per user action with intermediate states; a property only
// changes when its value does, so bindings settle by themselves.
//
// Replaces Quickshell.Hyprland (Hyprland's own IPC), which mango does not speak.
Singleton {
    id: root

    readonly property string socketPath: Quickshell.env("MANGO_INSTANCE_SIGNATURE") || ""

    // Every monitor as mango reports it: name, active (= focused), x, y,
    // width, height (logical), scale, tags [{index, is_active, is_urgent,
    // client_count, layout}], active_tags [n], active_client {id, title,
    // appid}, layout_symbol, keyboardlayout, keymode.
    property var monitors: []

    readonly property var focusedMonitor: monitors.find(m => m.active) || null
    readonly property string focusedMonitorName: focusedMonitor ? focusedMonitor.name : ""

    // The focused window, on whichever monitor has focus.
    readonly property var focusedClient: focusedMonitor && focusedMonitor.active_client
                                         && focusedMonitor.active_client.id !== null
                                         ? focusedMonitor.active_client : null
    readonly property string focusedClientId: focusedClient ? String(focusedClient.id) : ""
    readonly property string focusedClientTitle: focusedClient ? (focusedClient.title || "") : ""

    // The active XKB layout's full name ("English (US)", "Russian", ...).
    property string keyboardLayout: ""

    function monitor(name) {
        return monitors.find(m => m.name === name) || null
    }

    // mmsg dispatch <func>[,args] [client,<id>]
    function dispatch(command, clientId) {
        var cmd = ["mmsg", "dispatch", command]
        if (clientId !== undefined && clientId !== null && clientId !== "")
            cmd.push("client," + clientId)
        Quickshell.execDetached(cmd)
    }

    function parse(line) {
        try {
            return JSON.parse(line)
        } catch (e) {
            return null
        }
    }

    Socket {
        id: monitorStream
        path: root.socketPath
        connected: root.socketPath !== ""
        onConnectedChanged: {
            if (connected) {
                write("watch all-monitors\n")
                flush()
            }
        }
        parser: SplitParser {
            onRead: line => {
                var data = root.parse(line)
                if (data && Array.isArray(data.monitors))
                    root.monitors = data.monitors
            }
        }
    }

    Socket {
        id: layoutStream
        path: root.socketPath
        connected: root.socketPath !== ""
        onConnectedChanged: {
            if (connected) {
                write("watch keyboardlayout\n")
                flush()
            }
        }
        parser: SplitParser {
            onRead: line => {
                var data = root.parse(line)
                if (data && typeof data.layout === "string" && data.layout !== root.keyboardLayout)
                    root.keyboardLayout = data.layout
            }
        }
    }
}
