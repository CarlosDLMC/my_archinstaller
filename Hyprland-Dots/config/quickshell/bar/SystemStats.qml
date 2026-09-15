pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// CPU and memory readings, produced once for the whole shell.
//
// Two things are going on here, and both were costing real cycles before.
//
// First: the bar is instantiated per screen (shell.qml wraps it in Variants),
// so a widget that polls is a widget that polls N times on an N-monitor
// desktop. Three of the four Processes this replaces were running twice on
// the laptop-plus-monitor setup to produce two copies of the same number. A
// singleton is built once no matter how many bars render it.
//
// Second: /proc and the hwmon sensors are plain files. FileView reads them
// in-process, so the whole widget now costs zero subprocesses. The old
// `sh -c "head -1 /proc/stat"` and `sh -c "free -m | grep Mem"` were three
// forks each (sh, the tool, the pipe partner), every five seconds, per
// screen, to read two files this process can open itself.
Singleton {
    id: root

    property int cpuUsage: 0
    property int cpuTemp: 0
    property string memUsage: "0G"

    readonly property int intervalMs: 5000

    // /proc/stat counts jiffies since boot, so usage is the delta between two
    // samples. The first tick only establishes the baseline and reports 0.
    property real lastIdle: 0
    property real lastTotal: 0

    // Resolved once at startup by tempPathProc below. Empty until then, which
    // is why the FileView is guarded - reloading an empty path just errors.
    property string tempPath: ""

    // blockAllReads, NOT blockLoading. blockLoading only makes the *initial*
    // load synchronous; after that, reload() starts an async read and text()
    // keeps returning the previous contents until it lands, so every reading
    // below was one 5s tick stale. Measured on /sys while chasing it in
    // BatteryState: three reload()+text() pairs in the same turn all returned
    // the old value. CenterInfo and NightLight get away with the same pattern
    // only because they re-apply from onLoadedChanged when the read lands;
    // there is nothing here to catch it.
    FileView { id: statFile; path: "/proc/stat"; blockAllReads: true }
    FileView { id: memFile; path: "/proc/meminfo"; blockAllReads: true }
    FileView { id: tempFile; path: root.tempPath; blockAllReads: true }

    function readCpu() {
        statFile.reload()
        // The aggregate line is first: "cpu  user nice system idle iowait ..."
        var line = statFile.text().split("\n")[0]
        if (!line || line.substring(0, 3) !== "cpu")
            return

        var p = line.trim().split(/\s+/)
        var user = parseInt(p[1]) || 0
        var nice = parseInt(p[2]) || 0
        var system = parseInt(p[3]) || 0
        var idle = parseInt(p[4]) || 0
        var iowait = parseInt(p[5]) || 0
        var irq = parseInt(p[6]) || 0
        var softirq = parseInt(p[7]) || 0

        var total = user + nice + system + idle + iowait + irq + softirq
        var idleTime = idle + iowait

        if (root.lastTotal > 0) {
            var totalDiff = total - root.lastTotal
            var idleDiff = idleTime - root.lastIdle
            if (totalDiff > 0)
                root.cpuUsage = Math.round(100 * (totalDiff - idleDiff) / totalDiff)
        }

        root.lastTotal = total
        root.lastIdle = idleTime
    }

    function readMemory() {
        memFile.reload()
        var total = 0
        var available = 0
        var lines = memFile.text().split("\n")

        for (var i = 0; i < lines.length; i++) {
            // Both values are in kB. MemTotal - MemAvailable is what `free`
            // prints in its "used" column, so the reading does not change
            // meaning now that free is gone.
            if (lines[i].indexOf("MemTotal:") === 0)
                total = parseInt(lines[i].replace(/\D+/g, "")) || 0
            else if (lines[i].indexOf("MemAvailable:") === 0)
                available = parseInt(lines[i].replace(/\D+/g, "")) || 0
            if (total > 0 && available > 0)
                break
        }

        if (total > 0)
            root.memUsage = ((total - available) / 1024 / 1024).toFixed(2) + "G"
    }

    function readTemp() {
        if (root.tempPath === "")
            return
        tempFile.reload()
        var milli = parseInt(tempFile.text().trim())
        if (!isNaN(milli))
            root.cpuTemp = Math.round(milli / 1000)
    }

    function refresh() {
        readCpu()
        readMemory()
        readTemp()
    }

    // Which file holds the CPU temperature, resolved once instead of every
    // five seconds. The search order is the one the old inline probe used, and
    // it matters: thermal_zone0 is simply whichever zone the kernel registered
    // first, and it is the wrong sensor on both vendors. On this Intel ThinkPad
    // zone0 is `acpitz`, a chassis sensor reading a couple of degrees below the
    // package temperature in `coretemp`. On an AMD desktop it is worse than
    // inaccurate: those boards commonly expose no ACPI thermal zone at all, the
    // temperature lives only in `k10temp` under hwmon, so a blind zone glob
    // matched nothing and the widget sat at 0ºC forever with no error.
    //
    // So: ask the CPU's own hwmon driver first (temp1_input is the package on
    // coretemp and Tctl on k10temp), then the package thermal zone ahead of the
    // chassis one, and only then fall back to the first zone there is.
    Process {
        id: tempPathProc
        command: ["sh", "-c",
            'for d in /sys/class/hwmon/hwmon*; do case "$(cat "$d/name" 2>/dev/null)" in k10temp|zenpower|coretemp) [ -r "$d/temp1_input" ] && { echo "$d/temp1_input"; exit 0; };; esac; done\n' +
            'for want in x86_pkg_temp acpitz; do for z in /sys/class/thermal/thermal_zone*; do [ "$(cat "$z/type" 2>/dev/null)" = "$want" ] && [ -r "$z/temp" ] && { echo "$z/temp"; exit 0; }; done; done\n' +
            'for z in /sys/class/thermal/thermal_zone*/temp; do [ -r "$z" ] && { echo "$z"; exit 0; }; done\n'
        ]
        stdout: SplitParser {
            onRead: data => {
                if (!data) return
                var path = data.trim()
                if (path !== "") {
                    root.tempPath = path
                    root.readTemp()
                }
            }
        }
    }

    Timer {
        interval: root.intervalMs
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: {
        tempPathProc.running = true
        refresh()
    }
}
