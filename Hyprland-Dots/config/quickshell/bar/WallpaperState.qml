pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Wallpaper carousel state, on SUPER W (global shortcut quickshell:wallMenu).
//
// Replaces the rofi menu of hypr/UserScripts/WallpaperSelect.sh. That script
// still does the applying (`WallpaperSelect.sh FILE`), so awww and its
// transition, mpvpaper for videos, the Startup_Apps.lua rewrite, wallust and
// the refresh are exactly what they were - only the picker is new.
//
// scripts/wallpapers.py walks ~/Pictures/wallpapers and keeps a thumbnail of
// every wallpaper in ~/.cache/quickshell/wall-thumbs. The carousel this is
// modelled on (motor-dev/wallpaperCarousel) decodes every wallpaper into
// memory when the shell starts instead. Measured on this machine's 54, that
// took 1.9s and grew a quickshell from 144MB to 337MB, held for the whole
// session. The thumbnails cost 2.3s once and ~8MB on disk, a rescan is ~36ms,
// and the overlay decodes only the cards it shows and drops them on close.
//
// A singleton because the overlay is instantiated per screen, like the
// clipboard picker: one scan, one thumbnail queue.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string wallDir: home + "/Pictures/wallpapers"
    readonly property string script: home + "/.config/quickshell/bar/scripts/wallpapers.py"
    readonly property string thumbDir:
        (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/quickshell/wall-thumbs"

    property bool dialogOpen: false
    property var items: []          // [{id, name, dir, kind, src, thumb}], top level first
    property var ready: ({})        // id -> true once its thumbnail is on disk
    property var failed: ({})       // id -> true when no thumbnail could be made
    property string currentId: ""   // the wallpaper on screen
    property string pickedId: ""    // between Enter and the fade-out
    property bool scanning: false
    property bool scanned: false    // a list has arrived at least once
    // Set by the overlay on the first key or click. Until then a rescan that
    // finds a different wallpaper on screen re-centres on it.
    property bool navigated: false

    signal stepRequested(int delta)
    signal recenterRequested()

    // ------------------------------------------------------------------
    //  Folders and the strip
    // ------------------------------------------------------------------

    // ALL first, then one tab per folder that holds wallpapers itself, in the
    // order the script sorted them (top level first). A folder holding only
    // subfolders gets no tab of its own; its subfolders do, by path.
    readonly property var folders: {
        var out = [{ dir: null, label: "все", count: items.length }]
        var at = {}
        for (var i = 0; i < items.length; i++) {
            var d = items[i].dir
            if (at[d] === undefined) {
                at[d] = out.length
                out.push({ dir: d, label: d === "" ? rootLabel : d, count: 0 })
            }
            out[at[d]].count++
        }
        return out
    }
    readonly property string rootLabel: wallDir.substring(wallDir.lastIndexOf("/") + 1)
    // A row of tabs is worth it only when there is more than one place to look.
    readonly property bool hasFolders: folders.length > 2

    property int folderIndex: 0
    property string filter: ""

    // The cards in the carousel: the chosen folder - or, while searching,
    // every wallpaper whose folder or name matches, wherever it lives.
    readonly property var strip: {
        var f = filter.trim().toLowerCase()
        if (f !== "")
            return items.filter(it => (it.dir + "/" + it.name).toLowerCase().indexOf(f) !== -1)
        if (folderIndex <= 0 || folderIndex >= folders.length)
            return items
        var d = folders[folderIndex].dir
        return items.filter(it => it.dir === d)
    }

    function folderOf(id) {
        for (var i = 0; i < items.length; i++) {
            if (items[i].id !== id) continue
            for (var j = 1; j < folders.length; j++)
                if (folders[j].dir === items[i].dir) return hasFolders ? j : 0
        }
        return 0
    }

    function stepFolder(delta) {
        if (!hasFolders) return
        navigated = true
        filter = ""
        folderIndex = (folderIndex + delta + folders.length) % folders.length
    }

    // The picture for a card: its thumbnail once made; until then the
    // original, decoded at card size, which is slower but shows something.
    // A video has no picture until ffmpeg has pulled a frame out of it.
    function thumbUrl(it) {
        if (!it) return ""
        if (ready[it.id]) return it.thumb
        if (it.kind === "video" || failed[it.id]) return ""
        return it.src
    }

    // ------------------------------------------------------------------
    //  Scanning
    // ------------------------------------------------------------------

    property bool rescan: false

    function refresh() {
        if (scanProc.running) { rescan = true; return }
        scanProc.running = true
    }

    function sameList(a, b) {
        if (a.length !== b.length) return false
        for (var i = 0; i < a.length; i++)
            if (a[i].id !== b[i].id || a[i].thumb !== b[i].thumb || a[i].name !== b[i].name)
                return false
        return true
    }

    function mark(id, ok) {
        // Reassign the whole map: mutating it in place does not notify the
        // bindings that draw the cards.
        var next = {}
        var map = ok ? ready : failed
        for (var k in map) next[k] = map[k]
        next[id] = true
        if (ok) ready = next
        else failed = next
    }

    function onScanLine(line) {
        if (line.startsWith("{")) {
            var d
            try {
                d = JSON.parse(line)
            } catch (e) {
                console.warn("WallpaperState: unreadable scan:", e)
                return
            }
            var next = d.items || []
            var r = {}
            for (var i = 0; i < next.length; i++)
                if (next[i].ready) r[next[i].id] = true
            // Only swap the model when the tree actually changed. Most opens
            // find nothing new, and reassigning rebuilds the carousel under
            // the cursor a beat after it appeared.
            if (!sameList(next, items)) items = next
            ready = r
            failed = ({})
            scanned = true
            var cur = d.current || ""
            if (cur !== currentId && pickedId === "") {
                currentId = cur
                if (dialogOpen && !navigated) {
                    folderIndex = folderOf(cur)
                    recenterRequested()
                }
            }
        } else if (line.startsWith("thumb ")) {
            mark(line.substring(6), true)
        } else if (line.startsWith("fail ")) {
            mark(line.substring(5), false)
        }
    }

    Process {
        id: scanProc
        command: [root.script, "scan", root.wallDir, root.thumbDir]
        stdout: SplitParser {
            onRead: line => root.onScanLine(line)
        }
        onRunningChanged: {
            root.scanning = running
            if (!running && root.rescan) {
                root.rescan = false
                root.refresh()
            }
        }
    }

    // Every wallpaper change ends with wallust rewriting the bar's palette, so
    // that file changing is the cue to rescan. It keeps currentId right after
    // CTRL ALT W, the auto-changer or game mode, without polling anything.
    FileView {
        path: Qt.resolvedUrl("wallust-colors.json")
        watchChanges: true
        printErrors: false
        onFileChanged: {
            reload()
            paletteSettle.restart()
        }
    }

    Timer {
        id: paletteSettle
        interval: 400
        onTriggered: root.refresh()
    }

    // ------------------------------------------------------------------
    //  Open, close, apply
    // ------------------------------------------------------------------

    function open() {
        filter = ""
        pickedId = ""
        navigated = false
        // Open on the folder of the wallpaper on screen, centred on it.
        folderIndex = folderOf(currentId)
        dialogOpen = true
        refresh()
    }

    function close() {
        dialogOpen = false
    }

    function toggle() {
        if (dialogOpen) close()
        else open()
    }

    // Applied by the script, detached, so a bar reload in the middle of
    // wallust and the refresh cannot cut it short. The card plays its zoom
    // while that starts; the overlay leaves when the zoom is done.
    function pick(it) {
        if (!it || pickedId !== "") return
        pickedId = it.id
        currentId = it.id
        Quickshell.execDetached([script, "apply", wallDir, it.id])
        pickClose.restart()
    }

    Timer {
        id: pickClose
        interval: 260
        onTriggered: {
            root.close()
            root.pickedId = ""
        }
    }

    // Warm at startup, so the first press opens on a full carousel and any
    // missing thumbnail is made in the background (niced) before it is needed.
    Component.onCompleted: refresh()

    GlobalShortcut {
        appid: "quickshell"
        name: "wallMenu"
        description: "Wallpaper carousel"
        onPressed: root.toggle()
    }

    // `qs -c bar ipc call wallpaper <fn>`, for scripts and other binds. next
    // and prev open the carousel first when it is shut, as upstream's do.
    IpcHandler {
        target: "wallpaper"

        function toggle(): void { root.toggle() }
        function open(): void { if (!root.dialogOpen) root.open() }
        function close(): void { root.close() }
        function next(): void {
            if (!root.dialogOpen) root.open()
            else root.stepRequested(1)
        }
        function prev(): void {
            if (!root.dialogOpen) root.open()
            else root.stepRequested(-1)
        }
        function nextFolder(): void { root.stepFolder(1) }
        function prevFolder(): void { root.stepFolder(-1) }
    }
}
