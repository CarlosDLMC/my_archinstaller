pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Claude Code usage, produced once for the whole shell.
//
// A singleton for the same reason SystemStats is one: the bar is instantiated
// per screen, and this one polls a network endpoint - two monitors would mean
// two calls to Anthropic every five minutes to render the same number twice.
//
// Two cadences, because the two halves cost very different things:
//   limits  one HTTPS probe, every 5 minutes, always - this is what the bar
//           readout shows, so it has to be current whether or not the card
//           has ever been opened.
//   full    the above plus a transcript scan, only while the card is open.
//           Cold that reads 160MB; the collector caches per file, so a repeat
//           costs about 0.1s of CPU.
Singleton {
    id: root

    property string plan: ""
    property var limits: []          // [{label, window, percent, resetsAt}]
    property string limitsError: ""
    property var byDay: []           // [{day, tokens}]
    property var byModel: []         // [{model, tokens, input, output, cacheRead, cacheCreate}]
    property bool loaded: false
    property bool busy: false

    // Two different questions, and conflating them is what made the widget
    // vanish the first time the usage endpoint rate-limited us:
    //   installed  is Claude Code on this machine at all
    //   hasData    did we manage to read anything yet
    // The widget's visibility keys off the first. A machine that has never run
    // Claude Code draws nothing; a machine that has, but whose probe was
    // refused, keeps its place in the bar and shows a dash.
    property bool installed: false

    // Set when the numbers on screen came from the on-disk cache rather than a
    // live probe, with the instant they were actually read.
    property bool stale: false
    property int staleAt: 0
    readonly property bool hasData: loaded && (limits.length > 0 || byDay.length > 0)

    readonly property string script:
        (Quickshell.env("HOME") || "") + "/.config/quickshell/bar/scripts/agent-usage.py"

    function bucket(name) {
        for (var i = 0; i < limits.length; i++)
            if (limits[i].label === name) return limits[i]
        return null
    }

    readonly property var session: bucket("Session")
    readonly property var weekly: bucket("Weekly")

    function apply(text) {
        try {
            var j = JSON.parse(text)
            if (j.plan) root.plan = j.plan
            // Keep the last good readings when a probe comes back empty. The
            // usage endpoint rate-limits (HTTP 429 is easy to provoke), and a
            // transient refusal used to blank every meter and leave the bar
            // reading "—" until the next successful poll five minutes later.
            // The error still shows; the numbers just stay as last known.
            if (j.installed === true) root.installed = true
            if (j.limits && j.limits.length > 0) root.limits = j.limits
            root.stale = j.stale === true
            root.staleAt = j.staleAt || 0
            root.limitsError = j.limitsError || ""
            // A "limits" run reports no transcript data; keep what we had
            // rather than blanking the charts every five minutes.
            if (j.byDay && j.byDay.length > 0) root.byDay = j.byDay
            if (j.byModel && j.byModel.length > 0) root.byModel = j.byModel
            root.loaded = true
        } catch (e) {
            console.warn("AgentUsage: could not parse collector output:", e)
        }
    }

    Process {
        id: proc
        property string buf: ""
        property bool full: false
        stdout: SplitParser {
            onRead: data => { if (data) proc.buf += data }
        }
        onRunningChanged: {
            if (running) { buf = ""; root.busy = true; return }
            root.busy = false
            if (buf) root.apply(buf)
        }
    }

    function run(full) {
        if (proc.running) return
        proc.full = full
        proc.command = ["sh", "-c", root.script + (full ? " full" : " limits")]
        proc.running = true
    }

    function refreshLimits() { run(false) }
    function refreshFull() { run(true) }

    // Set by the widget while its card is open, so the expensive half only
    // runs when something is actually rendering it.
    property bool cardOpen: false

    Timer {
        interval: 300000            // 5 minutes
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.run(root.cardOpen)
    }

    // While the card is open, refresh faster and include the charts.
    Timer {
        interval: 30000
        running: root.cardOpen
        repeat: true
        onTriggered: root.run(true)
    }

    onCardOpenChanged: if (cardOpen) run(true)

    // A failed probe should not leave the bar showing a dash for five minutes,
    // so retry sooner - but back off each time. The usual reason for failing
    // is that the endpoint is rate limiting, and answering a rate limiter with
    // a fixed 60s retry is how you stay rate limited. Doubles 60s -> 300s and
    // then matches the normal cadence; any success resets it.
    property int retryDelay: 60000

    Timer {
        id: retryTimer
        interval: root.retryDelay
        running: root.loaded && root.limits.length === 0 && root.limitsError !== ""
        repeat: true
        onTriggered: {
            root.retryDelay = Math.min(root.retryDelay * 2, 300000)
            root.run(false)
        }
    }

    onLimitsChanged: if (limits.length > 0) retryDelay = 60000
}
