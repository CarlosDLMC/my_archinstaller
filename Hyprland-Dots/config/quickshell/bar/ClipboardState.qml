pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Clipboard history state for the picker, on top of cliphist.
//
// Replaces the rofi ClipManager.sh. The store is unchanged - the same
// `wl-paste --watch cliphist store` pair from Startup_Apps.lua, the same
// history - only the picker is new, so nothing that was already captured is
// lost and images keep arriving the way they always did.
//
// A singleton because the overlay is instantiated per screen (like ShotOsd),
// and 750 entries should be read once, not once per monitor.
Singleton {
    id: root

    readonly property string script:
        (Quickshell.env("HOME") || "") + "/.config/quickshell/bar/scripts/clip.sh"
    readonly property string pasteScript:
        (Quickshell.env("HOME") || "") + "/.config/quickshell/bar/scripts/clip-paste.sh"
    readonly property string thumbDir:
        (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") || "") + "/.cache")
        + "/quickshell/clip-thumbs"

    property bool dialogOpen: false
    property var entries: []          // [{id, preview, type, size, w, h}]
    property string filter: ""
    property int selectedIndex: 0
    property bool loading: false

    // Case-insensitive substring match on the preview, which is what the rofi
    // picker did. Images are matched on the word "image" as well as their
    // marker, so typing "image" gathers the screenshots.
    readonly property var filtered: {
        var f = filter.trim().toLowerCase()
        if (f === "") return entries
        var out = []
        for (var i = 0; i < entries.length; i++) {
            var e = entries[i]
            var hay = String(e.preview).toLowerCase()
            if (e.type === "image") hay += " image screenshot picture"
            if (hay.indexOf(f) !== -1) out.push(e)
        }
        return out
    }

    readonly property var current:
        selectedIndex >= 0 && selectedIndex < filtered.length ? filtered[selectedIndex] : null

    // ------------------------------------------------------------------
    //  Loading
    // ------------------------------------------------------------------

    // cliphist's own output, parsed here. Measured end to end from QML:
    //
    //   bare process spawn                     2 ms
    //   cliphist list                         36 ms   50 KB
    //   clip.sh list (the same, through jq)   64 ms   95 KB
    //
    // So jq cost 28ms and doubled the payload to produce something JavaScript
    // can do in one pass. Quickshell's own overhead is 2ms - the script was
    // the whole cost. Reading cliphist directly also drops the `sh -c` fork.
    //
    // StdioCollector, not SplitParser: SplitParser emits once per LINE, and
    // handing over 750 lines that way took 2.1 seconds.
    readonly property var imageRe: /^\[\[ binary data ([^ ]+ [^ ]+) ([a-z]+) ([0-9]+)x([0-9]+)/

    function parseList(text) {
        var out = []
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i]
            if (!line) continue
            var t = line.indexOf("\t")
            if (t < 0) continue
            var preview = line.substring(t + 1)
            var m = root.imageRe.exec(preview)
            out.push(m
                ? { id: line.substring(0, t), preview: preview, type: "image",
                    size: m[1], w: Number(m[3]), h: Number(m[4]) }
                : { id: line.substring(0, t), preview: preview, type: "text",
                    size: "", w: 0, h: 0 })
        }
        return out
    }

    Process {
        id: listProc
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.loading = false
                var next = root.parseList(text)
                // Only swap the model when the history actually moved.
                // Reassigning rebuilds the whole ListView and throws away the
                // scroll position, and most opens find nothing has changed -
                // so the refresh that lands behind the open dialog would
                // otherwise yank the list back to the top under your cursor.
                // cliphist is newest-first, so a new id at the head or a
                // different count is the whole test.
                if (next.length === root.entries.length
                    && (next.length === 0 || next[0].id === root.entries[0].id))
                    return
                root.entries = next
            }
        }
        onRunningChanged: if (running) root.loading = true
    }

    function reload() {
        if (!listProc.running) listProc.running = true
    }

    function open() {
        filter = ""
        selectedIndex = 0
        // Deliberately NOT clearing entries: the picker opens on the list it
        // already holds and the refresh lands behind it, so there is never a
        // frame of empty dialog. The list is loaded once at startup for the
        // same reason - the first open should not be the slow one.
        dialogOpen = true
        reload()
    }

    function close() {
        dialogOpen = false
        // Let go of the decoded images: a session's worth of 3MB screenshots
        // held as QML Image sources is real memory for a dialog that is shut.
        thumbs = ({})
    }

    function toggle() {
        if (dialogOpen) close()
        else open()
    }

    // ------------------------------------------------------------------
    //  Thumbnails
    // ------------------------------------------------------------------
    //  cliphist stores the full image, so "decode" means writing a 3MB PNG to
    //  disk. That is far too much to do for every image entry when the dialog
    //  opens, so rows ask for their own picture as they scroll into view and a
    //  single worker serves the queue one at a time - one decode is ~25ms, and
    //  doing them serially keeps a fast scroll from forking fifty at once.

    property var thumbs: ({})         // id -> file path
    property var pendingThumbs: []
    property string decodingId: ""

    function thumbFor(id) {
        var p = thumbs[String(id)]
        return p ? "file://" + p : ""
    }

    function requestThumb(id) {
        var key = String(id)
        if (thumbs[key] !== undefined) return
        if (decodingId === key) return
        if (pendingThumbs.indexOf(key) !== -1) return
        pendingThumbs.push(key)
        pumpThumbs()
    }

    function pumpThumbs() {
        if (decodingId !== "" || thumbProc.running) return
        if (pendingThumbs.length === 0) return
        var key = pendingThumbs.shift()
        decodingId = key
        thumbProc.command = ["sh", "-c",
            root.script + " thumb " + key + " " + root.thumbDir + "/" + key + ".img"]
        thumbProc.running = true
    }

    Process {
        id: thumbProc
        onExited: (code) => {
            if (root.decodingId !== "") {
                if (code === 0) {
                    // Reassign the whole map: mutating it in place does not
                    // notify the bindings that draw the rows.
                    var next = {}
                    for (var k in root.thumbs) next[k] = root.thumbs[k]
                    next[root.decodingId] = root.thumbDir + "/" + root.decodingId + ".img"
                    root.thumbs = next
                }
                root.decodingId = ""
            }
            root.pumpThumbs()
        }
    }

    // ------------------------------------------------------------------
    //  Actions
    // ------------------------------------------------------------------

    Process { id: actionProc }

    // Copy, then paste into whatever had focus. The dialog closes first so
    // focus is already back where it belongs when wtype types.
    function pick(entry) {
        if (!entry) return
        close()
        actionProc.command = ["sh", "-c",
            root.script + " copy " + entry.id + " && " + root.pasteScript]
        actionProc.running = true
    }

    function remove(entry) {
        if (!entry || actionProc.running) return
        var keep = selectedIndex
        actionProc.command = ["sh", "-c", root.script + " delete " + entry.id]
        actionProc.running = true
        removeReload.pendingIndex = keep
        removeReload.restart()
    }

    function wipe() {
        if (actionProc.running) return
        actionProc.command = ["sh", "-c", root.script + " wipe"]
        actionProc.running = true
        removeReload.pendingIndex = 0
        removeReload.restart()
    }

    // Re-read after a mutation, and keep the cursor where it was rather than
    // snapping to the top - deleting three entries in a row should walk down
    // the list, not restart it.
    Timer {
        id: removeReload
        property int pendingIndex: 0
        interval: 120
        repeat: false
        onTriggered: {
            root.reload()
            root.selectedIndex = Math.max(0, pendingIndex)
        }
    }

    function move(delta) {
        if (filtered.length === 0) return
        selectedIndex = Math.max(0, Math.min(filtered.length - 1, selectedIndex + delta))
    }

    onFilterChanged: selectedIndex = 0

    // Warm at startup, so even the first press opens on a populated list.
    Component.onCompleted: reload()

    GlobalShortcut {
        appid: "quickshell"
        name: "clipMenu"
        description: "Clipboard history"
        onPressed: root.toggle()
    }
}
