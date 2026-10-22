pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../.."

/**
 * The windows the overview draws, and a picture of each.
 *
 * Only while the overview is open: `watch all-clients` on mango's socket pushes
 * the whole window list on every change (and once at the start). Each open
 * also takes one still picture per window (scripts/overview-shots.sh, grim
 * capturing the window itself - a covered window or one on another workspace
 * too) and bumps shotGeneration when they are on disk.
 *
 * A window, as mango lists it: id, title, appid, monitor (name), tags [n],
 * x, y, width, height (border included), is_floating, is_global, is_focused,
 * is_minimized, is_xwayland, is_group, is_group_focus (the shown tab of a
 * group), foreign_toplevel_id.
 */
Singleton {
    id: root
    property var windowList: []
    property var windowById: ({})

    readonly property string shotDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/quickshell-overview"
    property int shotGeneration: 0
    property bool shotsPending: false

    function applyClients(list) {
        root.windowList = list
        var byId = {}
        for (var i = 0; i < list.length; ++i)
            byId[list[i].id] = list[i]
        root.windowById = byId
        if (root.shotsPending) {
            root.shotsPending = false
            root.takeShots()
        }
    }

    function takeShots() {
        var cmd = [Quickshell.shellDir + "/scripts/overview-shots.sh", root.shotDir]
        for (var i = 0; i < root.windowList.length; ++i) {
            var w = root.windowList[i]
            if (w.foreign_toplevel_id && !w.is_minimized && !(w.is_group && !w.is_group_focus))
                cmd.push(w.id + ":" + w.foreign_toplevel_id + ":" + w.width + "x" + w.height)
        }
        shots.command = cmd
        shots.running = true
    }

    // The stream connects once per open (this singleton is first created by
    // that open, too late for a signal from GlobalStates), so the pictures
    // are asked for here: taken as soon as the window list is in.
    Socket {
        path: Mango.socketPath
        connected: GlobalStates.overviewOpen && Mango.socketPath !== ""
        onConnectedChanged: {
            if (connected) {
                root.shotsPending = true
                write("watch all-clients\n")
                flush()
            }
        }
        parser: SplitParser {
            onRead: line => {
                var data
                try {
                    data = JSON.parse(line)
                } catch (e) {
                    return
                }
                if (data && Array.isArray(data.clients))
                    root.applyClients(data.clients)
            }
        }
    }

    Process {
        id: shots
        onExited: root.shotGeneration++
    }
}
