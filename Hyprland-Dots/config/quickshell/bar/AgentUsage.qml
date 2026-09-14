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
    // When the charts' window opened, and whether it is Anthropic's own weekly
    // window or a 7-day fallback because no reset time was available.
    property real windowStart: 0
    property bool windowAnchored: false
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

    // Set only when the endpoint was never reached - no route, no DNS. An HTTP
    // status, 429 included, does NOT set it: a server answered, and trying
    // again sooner cannot help.
    property bool retryAdvised: false
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
            if (j.installed === true) root.installed = true

            // Only a run that actually talked to the endpoint may touch the
            // allowance state. A stats-only run carries no limits, and reading
            // that as "the probe returned nothing" would clear good numbers and
            // raise a phantom error every time the card refreshed its charts.
            if (j.probed === true) {
                if (j.plan) root.plan = j.plan
                // Keep the last good readings when a probe comes back empty.
                // The endpoint rate limits easily, and a refusal used to blank
                // every meter. The error still shows; the numbers stay as last
                // known, tagged with their age.
                if (j.limits && j.limits.length > 0) root.limits = j.limits
                root.limitsError = j.limitsError || ""
                root.stale = j.stale === true
                root.staleAt = j.staleAt || 0
                root.retryAdvised = j.retryAdvised === true
                root.lastProbeAt = Date.now()
            }

            // A "limits" run reports no transcript data; keep what we had
            // rather than blanking the charts.
            if (j.windowStart) {
                root.windowStart = j.windowStart
                root.windowAnchored = j.windowAnchored === true
            }
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

    property real lastProbeAt: 0

    function run(mode) {
        if (proc.running) return
        proc.command = ["sh", "-c", root.script + " " + mode]
        proc.running = true
    }

    // Probe the endpoint only when the last reading is older than maxAgeMs,
    // otherwise just re-read the local transcripts. This is what stops opening
    // and reopening the card from becoming a burst of requests.
    function refresh(maxAgeMs) {
        run(Date.now() - root.lastProbeAt > maxAgeMs ? "full" : "stats")
    }

    function refreshLimits() { run("limits") }
    function refreshFull() { run("full") }

    // Set by the widget while its card is open, so the expensive half only
    // runs when something is actually rendering it.
    property bool cardOpen: false

    // The background cadence. 15 minutes, not 5: the icon carries no number any
    // more, so nothing on screen depends on this being fresh - it exists only
    // to keep the card instant when opened and the disk cache warm.
    Timer {
        interval: 900000            // 15 minutes
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.run("limits")
    }

    // While the card is open, re-read the LOCAL transcripts every minute - the
    // token charts do move as you work. No network call: this used to run a
    // full probe every 30s, which is 120 requests an hour for figures that
    // describe a 5-hour and a 7-day window.
    Timer {
        interval: 60000
        running: root.cardOpen
        repeat: true
        onTriggered: root.run("stats")
    }

    // Opening the card probes only if the reading is over two minutes old;
    // otherwise it just refreshes the charts.
    onCardOpenChanged: if (cardOpen) refresh(120000)

    // One sooner try, and only when the endpoint was never reached - typically
    // the seconds after login before the network is up. Matches Omarchy's rule.
    //
    // What this deliberately does NOT do is retry on an HTTP status. The first
    // version here backed off 60s -> 300s on any failure, which meant a rate
    // limited endpoint got answered back every minute; a 429 is a server
    // telling you to stop, so the right response is to wait for the next
    // ordinary refresh.
    Timer {
        interval: 30000
        running: root.retryAdvised
        repeat: false
        onTriggered: root.run("limits")
    }
}
