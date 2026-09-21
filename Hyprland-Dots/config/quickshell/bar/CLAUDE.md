# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Quickshell configuration for a Hyprland Wayland desktop bar. The config uses QML with Quickshell-specific modules, organized into modular components.

## Commands

```bash
# Restart quickshell to apply changes
pkill -x quickshell; sleep 0.5; quickshell &

# Test weather script
~/.config/quickshell/bar/scripts/weather-fetch.sh | jq -r '.text'
```

## Architecture

### File Structure

```
shell.qml           # Main entry point, assembles the bar layout
Theme.qml           # Singleton with colors, fonts, and theme settings
qmldir              # QML module definition for the singletons
Monitors.qml        # Singleton: connected monitors, shared by the capture dialogs
RecordState.qml     # Singleton: screen-recording dialog state + global shortcuts
ShotState.qml       # Singleton: screenshot dialog state + global shortcut
SystemStats.qml     # Singleton: CPU usage/temp + memory, read from /proc via FileView
BatteryState.qml    # Singleton: every battery reading, read from /sys via FileView
AgentUsage.qml      # Singleton: Claude Code allowance + token stats
ClipboardState.qml  # Singleton: clipboard history state + the clipMenu shortcut
NightLight.qml      # Singleton: night-light state, watched off Hyprsunset.sh's state file
components/         # Modular widget components
  ├── DropdownWidget.qml   # Base component for click-to-open dropdown widgets (notch design)
  ├── AudioPanel.qml       # Audio card body: output/input device + level, per-app levels
  ├── NetworkPanel.qml     # Network card body: link, connection, traffic, DNS, speed test, share QR
  ├── ClipboardOsd.qml     # Clipboard picker (centred overlay, list + preview)
  ├── AgentWidget.qml      # Claude Code usage: session % in the bar, card on click
  ├── AgentPanel.qml       # Agents card body: plan, allowance meters, tokens by day/model
  ├── VolumeSlider.qml     # Draggable level track, shared by every row of the audio card
  ├── WeatherStatItem.qml  # Reusable stat row for weather popup
  ├── WorkspaceBar.qml     # Hyprland workspaces with app icons (pill-shaped)
  ├── WindowInfo.qml       # Current window title
  ├── CenterInfo.qml       # Date/DND/weather with click popup showing detailed forecast
  ├── CpuWidget.qml        # CPU usage + temperature (renders SystemStats)
  ├── MemoryWidget.qml     # Memory in use (renders SystemStats)
  ├── DiskWidget.qml       # Disk usage percentage
  ├── VolumeWidget.qml     # Volume with mute/sink detection (speaker/headphone/bluetooth/hdmi)
  ├── BatteryWidget.qml    # Battery level in the bar (renders BatteryState)
  ├── BatteryPanel.qml     # Battery card body: health, cycles, packs, charge limit
  ├── WifiWidget.qml       # WiFi status with network speeds (extends DropdownWidget)
  ├── BluetoothWidget.qml  # Bluetooth status with dropdown (extends DropdownWidget)
  ├── PowerProfileWidget.qml # Power profile selector (extends DropdownWidget)
  ├── PowerWidget.qml      # Power menu: lock, logout, reboot, shutdown (extends DropdownWidget)
  ├── RecordOsd.qml        # Screen-recording dialog (centred box, big buttons, audio toggles)
  ├── ShotOsd.qml          # Screenshot dialog (same box, no audio row)
  ├── BigButton.qml        # Big icon+label button, shared by both capture dialogs
  ├── ToggleRow.qml        # Labelled switch, shared by both capture dialogs
  ├── SlackWidget.qml      # Slack indicator, click to focus app
  ├── WhatsAppWidget.qml   # WhatsApp indicator, click to focus app
  ├── Spinner.qml          # Ring of dots for indeterminate waits (drawn, not a glyph)
  └── Separator.qml        # Visual separator line
```

### Key Components

- **Theme.qml**: Singleton pragma provides `Theme.colBg`, `Theme.fontSize`, etc. to all components.
  Colours are **not** hardcoded here — see Theming below.
- **WorkspaceBar.qml**: Pill-shaped workspace indicators with numbers and deduplicated app icons (max 3). Hover effects and active state highlighting
- **RecordOsd.qml**: Screen-recording dialog on `$mainMod SHIFT R` (global shortcut
  `quickshell:recordMenu`). Two big mode buttons (full screen / region), a monitor
  picker shown only when more than one is connected, and switches for system audio
  and mic. State lives in `RecordState.qml`; the recording itself is done by
  `~/.config/hypr/scripts/ScreenRecord.sh`, so the dialog and the bare keybinds
  share one code path. Keys: `F` full screen, `R` region, `W` window, `S`/`M` audio
  toggles, `Esc` dismiss. Pressing the shortcut while recording stops it.
- **ShotOsd.qml**: Screenshot dialog on `$mainMod Print` (global shortcut
  `quickshell:shotMenu`). Same box as RecordOsd without the audio row. State in
  `ShotState.qml`, capture by `~/.config/hypr/scripts/ScreenShot.sh`. Keys: `F`
  full screen, `R` region, `W` active window, `E` annotate (satty), `Esc` dismiss.
  `ShotState.settleMs` (300ms) waits for the overlay to leave the screen before
  grim runs, otherwise the shot contains the dialog and its dim — it must stay
  comfortably above the 160ms fade.
- **Monitors.qml**: Shared monitor list (`list`, `multiple`, `focusedName()`,
  `resolveTarget()`). `resolveTarget` keeps a remembered monitor while it is still
  plugged in and falls back to the focused one, so neither dialog can aim at a
  monitor that has been unplugged.

  Note: both capture tools **must** be given an explicit output. wf-recorder with
  no `-o` on a multi-monitor setup falls back to an interactive stdin prompt and
  silently records the laptop panel; grim with no `-o` captures the whole layout
  (both screens stitched together with the dead space between them).
- **SystemStats.qml**: CPU usage, CPU temperature and memory in use, sampled once
  every 5s for the whole shell. `CpuWidget` and `MemoryWidget` are pure renderers
  over it. Reads `/proc/stat`, `/proc/meminfo` and the hwmon sensor with `FileView`,
  so it costs no subprocesses at all; the sensor path is resolved once at startup
  rather than probed on every tick.
- **NightLight.qml**: night-light state and toggle. `Hyprsunset.sh` records what it
  did in `~/.cache/.hyprsunset_state` and rewrites it in place, so a `FileView` with
  `watchChanges` sees every change instantly - whether it came from the bar or from
  `SUPER + N`. A 60s check against `pgrep` runs only while the file says "on", to
  catch hyprsunset having died and left the file lying.
- **AgentWidget.qml / AgentPanel.qml / AgentUsage.qml**: Claude Code usage.
  The bar shows the share of the 5-hour session spent (the number that says
  whether you are about to be cut off); the card adds the plan, weekly and
  per-model allowances with reset countdowns, tokens by day, and tokens by
  model. The two charts cover **deliberately different periods**, matching
  Omarchy: by day is the last 7 **calendar** days (`today-6 .. today`), by
  model is **all time**. Anchoring the day chart to the weekly allowance window
  was tried and reverted - upstream's `recent_date_strings()` is plainly 7
  rolling days, and the meter above is the thing that tracks the allowance.
  The two charts are also drawn differently, which is upstream's choice and not
  an inconsistency: a day is a label, a thin track and a value, while a model is
  one filled row with its name and total *inside* the bar, scaled so the
  heaviest model is full. Hovering a model row swaps its name for the
  input/output/cache split - upstream puts that in a tooltip, and this bar has
  no tooltip layer to put it in.

  The model chart's header carries the date its history actually begins -
  `· SINCE 10 AUG`, from the oldest record still on disk, with the year added
  once the data reaches into a previous one. It is **not** "all time": Claude
  Code prunes its own transcripts (`cleanupPeriodDays`, 30 by default), so the
  chart only ever reaches as far back as the oldest survivor, and that date
  moves forward on its own as files are deleted. A measured span was tried in
  between (`· LAST 35 DAYS`) and reverted on request. Nothing is derived from
  the retention setting - the date comes from the data, so it stays honest if
  that setting changes. Deleted transcripts drop out cleanly: the scan rebuilds
  its cache from the files that exist, so both the date and the totals shrink
  (tested).

  The headers carry the scope (`· LAST 7 DAYS`, `· SINCE 10 AUG`), which
  upstream does not: with two windows in one card and no labels, the numbers invite a
  comparison that does not hold. "Tokens" is prompt + completion only: cache
  reads are around 200x larger (2,712M against 11.9M for opus-5 here) and would
  flatten every other bar. Ported from Omarchy's agents plugin, reduced to the one
  agent this machine runs.

  `AgentUsage` is a **singleton** for the same reason `SystemStats` is: the bar
  is instantiated per screen, and this polls a network endpoint - two monitors
  would otherwise mean two calls to Anthropic every five minutes for the same
  number. It runs two cadences: the OAuth probe alone every 5 minutes (cheap,
  always, because the bar readout needs it), and the probe plus a transcript
  scan only while a card is open.

  `scripts/agent-usage.py` is the collector. The access token comes from the
  Claude CLI's own store and goes exactly one place - the Authorization header
  of Anthropic's usage endpoint; it is never printed or cached, and only the
  plan label reaches the output. The transcript scan caches **per file**, keyed
  by (mtime, size): a cold scan reads 160MB and costs ~1.3s of CPU, a repeat
  costs ~0.1s because only the session you are in has changed. **Every**
  transcript is read, not just recent ones, because the model totals are all
  time - 2.46s cold, 0.58s warm. It stores raw **hour buckets** rather than
  whole days, keyed on epoch hours, so the cache stays independent of whatever
  window is applied later and survives the timezone moving under it, which the
  VPN widget does.

  `scripts/clip.sh`'s thumbnail cache is capped and cleaned - see the clipboard
  entry above for why.

  The widget hides on `installed` - whether `~/.claude` exists at all - and not
  on whether a probe returned anything. Those were conflated at first, and the
  whole widget vanished from the bar the first time the usage endpoint rate
  limited us. The endpoint does rate limit, returns no useful headers (only a
  `Retry-After: 0` that is wrong), and a refusal can last many minutes, so:
  the last good reading is cached to disk and shown with its age, and the
  icon's colour is **fixed** - it never signals state.

  Cadence matches Omarchy's: a 15-minute background probe (its
  `refreshIntervalSec` default is 900 too), no network refresh at all while the
  card is open - the 60s timer there re-reads only the local transcripts - and
  one 30s retry **only** when the endpoint was never reached. An HTTP status,
  429 included, never triggers a retry: a server answered, and answering back
  sooner is how you stay rate limited. Opening the card probes only if the
  reading is over two minutes old. Worst case is about 4-6 requests an hour; an
  earlier version ran a full probe every 30s while the card was open, which is
  120.
- **ClipboardOsd.qml / ClipboardState.qml**: clipboard history on
  `SUPER + ALT + V` (global shortcut `quickshell:clipMenu`), replacing a rofi
  picker. Centred overlay built like `ShotOsd`; list on the left with inline
  thumbnails, large preview on the right, type to filter. Keys: arrows move,
  Enter pastes, `Ctrl+Del` removes one entry, `Alt+Del` wipes, `Esc` closes -
  the Del bindings are the ones the rofi picker used.

  **cliphist remains the store.** Omarchy's plugin runs its own `wl-paste
  --watch` capture because Omarchy does not ship cliphist; this machine has it
  already, populated and capturing images, so only the picker was replaced.
  `scripts/clip-paste.sh` is kept from the old rofi script: picking an entry
  pastes it into the window that had focus (`Ctrl+Shift+V` for terminals,
  `Ctrl+V` elsewhere), which is better than merely filling the clipboard. That
  needs `wtype`, now in `01-hypr-pkgs.sh` - it was a silent dependency before.

  Three things here are about speed, and each was measured rather than guessed:

  1. The list is read with **`StdioCollector`, never `SplitParser`**.
     SplitParser emits once per *line*, and handing over 750 lines that way
     took **2.1 seconds** for a payload the script produces in 30ms.
  2. QML runs **`cliphist list` directly and parses it itself**. Going through
     `jq` to build JSON cost 28ms and doubled the payload, so that JavaScript
     could parse it back. Quickshell's own process overhead is 2ms - the
     script was the entire cost.
  Decoded image previews are capped at 12 files while the picker is open and
  deleted when it closes. Clearing only the in-memory map left every decode on
  disk - 72MB of full-size screenshots, each a byte-for-byte duplicate of what
  cliphist already stores. Downscaling them instead was measured and rejected:
  `magick -resize 900x900` is 489ms against 25ms to decode, which would be felt
  on every scroll, and a thumbnail that cheap to rebuild is not worth keeping.

  3. The list is loaded **at startup** and kept, so the picker opens on a
     populated list with no wait, and the refresh lands behind it. That
     refresh only swaps the model when the history actually moved (head id or
     count differs); reassigning it unconditionally rebuilt the ListView and
     reset the scroll under the cursor a beat after opening.
- **CenterInfo.qml**: DND toggle + date + weather. Click shows popup with notch design connecting to bar. Displays location, temperature, condition, feels-like, min/max, and hourly rain forecast bars. Weather icon/temp colored by temperature. Caches weather data for offline use.
- **CpuWidget.qml / MemoryWidget.qml / DiskWidget.qml**: Simple percentage displays with themed colors
- **VolumeWidget.qml**: Volume with mute detection and audio sink icons
  (speaker/headphone/bluetooth/HDMI). Left-click mutes, wheel adjusts,
  **right-click opens the audio card** (`AudioPanel.qml`) - output device and
  level, input device and level, and a level per running application. It reads
  `Quickshell.Services.Pipewire` directly, so there is nothing to poll and no
  subprocess; it replaced launching pavucontrol.

  Two things in there are load-bearing and easy to undo by accident. The
  Repeaters are fed *copies* of the PipeWire lists, refreshed through a 75ms
  debounce and only while the card is open: PipeWire can remove a node while
  Quickshell is still dispatching the removal, and rebuilding a Repeater from
  inside that signal crashes the PipeWire service. And `node.properties` is only
  read once the node reports `ready` (see `nodeProps()`), because it is not valid
  before the node is bound. The card's height comes from what the body measured,
  not from arithmetic over row counts - text height follows the font's line
  metrics, not the pixelSize, so counting rows clips the last one
- **BatteryState.qml / BatteryWidget.qml / BatteryPanel.qml**: everything about
  the battery. `BatteryState` is a **singleton** for the reason `SystemStats` is:
  the bar is per-screen, and the old widget ran `Battery.sh` and its own `udevadm
  monitor` once per bar to produce one number. On a two-screen desk there is now
  one monitor process where the power-profile, bluetooth and network widgets each
  run two.

  It reads **one file per pack**: `/sys/class/power_supply/BAT*/uevent` carries
  STATUS, CAPACITY, ENERGY_*, POWER_NOW and CYCLE_COUNT as KEY=VALUE, so a whole
  battery costs one `FileView` instead of nine. The charge thresholds are the
  exception - they are not in `uevent` and get their own views, reloaded only on
  the slow tick and after a write, because nothing else on the machine touches
  them.

  **The trigger is `udevadm monitor`, not `watchChanges`.** sysfs attributes do
  not raise inotify events, so a `FileView` with `watchChanges` binds and then
  never fires; udev is the kernel's actual notification for this subsystem. The
  60s timer behind it only has to catch the monitor having died.

  Level is **energy-weighted** (`sum(energy_now) / sum(energy_full)`), not the
  mean of the pack percentages. This T480's internal pack holds 10.7Wh against
  the removable one's 19.7Wh, and averaging "100% and 20%" into "60%" describes
  no amount of runtime that exists. Packs reporting `charge_*` in uAh rather than
  `energy_*` in uWh are normalised on the way in, or the card reads 0 Wh on every
  machine of that kind.

  The card is ported from Omarchy Quattro's power panel (omacom/omarchy, MIT,
  DHH) - capacity, cycles, draw, time, fill bar, "holding" - **minus its
  power-profile picker**, which this bar already has as `PowerProfileWidget`. It
  adds **health** (`energy_full / energy_full_design`), which upstream does not
  show and which is the reading that actually predicts a dead pack: BAT0 here is
  44% at 239 cycles, BAT1 is 82% at 566.

  **The charge limit is not a port.** Omarchy reads
  `charge_control_end_threshold` and displays it; nothing there writes it.
  `BatteryState.setLimit()` calls `sudo /usr/local/bin/battery-charge-limit set
  N`, a root-owned helper installed by `install-scripts/battery_charge_limit.sh`
  along with a conf file and a oneshot unit that re-applies the value at boot and
  after resume. The helper is at a root-owned path on purpose: sudo is
  passwordless here, so a user-writable script behind it would be a way to run
  anything as root. Without the helper the readout still works and only the
  picker is withheld - `limitWritable` is `limitSupported && helperInstalled`.

  **The threshold files are ACPI calls.** Measured here:
  `charge_control_end_threshold` costs **1.07ms** a read against **47us** for the
  whole of `uevent`, and `AC/uevent` costs 493us. Dropping them from the 60s tick
  looked like free money and was tried; it is wrong. The limit is what decides
  whether the bar shows "holding" or "full", so a limit set from a terminal, by
  TLP, or by this shell's own helper left the wrong glyph in the bar until
  someone happened to open the card. 4.3ms a minute is 0.007% of a core and
  cannot drop a frame at 60Hz. The tick reads them; `readThresholds()` on
  `onOpened` only makes the card open on a reading that is current rather than up
  to a minute old.

  What the cost *does* rule out is paying it on the click path. That is why the
  pills bind to **`effectiveLimit`**, not
  `limitEnd`. `setLimit()` records the click in `pendingLimit` straight away and
  `effectiveLimit` prefers it, so the pill moves on the click. Waiting for the
  hardware meant sudo (~20ms) plus the helper (~14ms) plus that 4.3ms re-read
  before the 130ms fade could even start - about 170ms to confirmation, which is
  past the point a button stops feeling connected to the finger.
  `pendingLimit` is cleared when the re-read lands, so a value the firmware
  clamped or refused moves the pill back rather than leaving it lying.

  Two labels are worth keeping honest. A threshold **only stops charging**; it
  discharges nothing, so a pack already above the limit sits there until the
  machine runs off it, and the card says "Above limit · 60%" rather than "Holding
  at 60%" next to a 97% reading. And `colAlert` is spent on one state - actually
  discharging, at or below 15% - because a pack parked at its limit is the
  desired state, not a problem, and colouring it red is how you teach yourself to
  ignore the colour.
- **WifiWidget.qml**: The network list paints instantly from NetworkManager's
  cache (`--rescan no`), and the real results land at 1.4s and 3.2s. That first
  paint is usually just the AP already connected, so the card carries a
  `scanning` state for those seconds - a Spinner in the header and a "Looking
  for networks…" line - rather than presenting a one-entry list as the answer.
  Popup height is `rows * 38 + 72`: rows are 36 with 2 of spacing, and the
  header, divider and padding take 68 before the list gets any room. The old
  `length * 40 + 50` was short of that and drew a **half row** whenever the
  cache returned one network. A floor of three rows while scanning keeps the
  card from opening as a sliver and resizing under the pointer.

  WiFi status. **Left-click** opens the network list (scan,
  connect, password entry, disconnect); **right-click** opens the details card
  (`NetworkPanel.qml`) - link quality, IP/gateway/DNS, live throughput and
  latency, a DNS provider picker, the radio toggle, and two actions: a speed
  test and a share-QR for the current network. It replaced launching
  `nm-connection-editor`, which is still installed for the things the card
  deliberately leaves out - per-profile IP settings, 802.1X, VPN and wired
  profiles, and **managing saved networks**, which was tried in the card and
  removed: ten remembered profiles was more than half its height.

  Facts are laid out as label/value pairs, two to a row, in a
  `GridLayout { columns: 4 }` (the shape DHH uses). One pair per row made a
  very tall card for mostly short values. The SSID spans the full width and
  saved/long names elide in the **middle**, because several of these networks
  are one router with different suffixes and right-eliding rendered them
  identically.

  The speed test and the QR replace the card's body rather than opening
  windows of their own (DHH gives each a centred card, but this bar's cards
  are dropdowns and a second layer surface would fight the focus grab).
  Closing the card stops a running speed test - it saturates the link with
  eight parallel streams, so leaving it running would be a real cost.

  The card's header is the wifi glyph, the SSID, then the QR and speed-test
  icons. That glyph **is** the radio toggle - it was a static mark with the
  toggle off on the far right, which put the control furthest from the thing it
  controls and left a dead icon in the card's most prominent spot. It carries no
  persistent fill, unlike the two view icons beside it: a lit box there reads as
  "this tab is selected", which the radio is not.

  Both views share one popup, switched by `panelMode`, so there is still one
  notch card and one focus grab. The right-click path sets `dropdownOpen`
  directly rather than emitting `opened()`, because that signal kicks off a
  Wi-Fi rescan the details view neither shows nor needs.

  Every poll in the card is gated on it being open, and its data comes from
  `scripts/network-status.sh`. Note that script reports the **radio** and the
  **default route separately**: with WireGuard up the route interface is the
  tunnel, so keying the radio details off it (as the original did) silently
  dropped SSID, signal and rate for as long as the VPN was connected
- **VpnWidget.qml**: the WireGuard picker, and two toggles under its header -
  Time and Weather - for what follows the tunnel. They are separate because they
  are not the same size of change: the weather half rewrites one string in
  `~/.cache`, the clock half runs `timedatectl set-timezone`, which moves the
  system clock for **every process on the machine**. One button used to do both,
  so wanting the tunnel's weather meant taking its timezone with it. Each is a
  toggle: press to follow the exit node, press again to come home, either half
  on its own, with the tunnel still up. Filled means that half is away -
  white-active/grey-idle, the only state signal a 28px button has room for, and
  the card said nothing at all about it before.

  **Home is learned whenever it is knowable, and forgotten on disconnect.**
  `timezone_default` is stored when the clock half first leaves home.
  `weather_home` (`lat<TAB>lon<TAB>name`) is different: it is written by
  `weather-location.py` on *every* reading that is `source == "ip"` and not
  tunneled, not only by `vpn-sync.sh` before a departure. It used to be the
  latter, and that was a bug - see "Why the weather used to follow the tunnel"
  below. The
  disconnect button, a dropped tunnel and the stale-cache check all pass
  `--forget` to `vpn-reset.sh`, which drops `timezone_default` - with no tunnel
  an IP lookup is the better answer and the only one that notices you have
  moved. `--forget` no longer drops `weather_home`: that file is now refreshed
  by every untunneled reading, and `weather-fetch.sh` consults it only while a
  tunnel is up, so keeping it costs a disconnected machine nothing. Deleting it
  actively broke things, because the fetch `vpn-reset.sh` runs first is itself
  an untunneled reading on the dropped-tunnel path - the `rm` erased the home
  it had just learned, and the next connection showed the exit node again. The
  subtle
  part is where the weather snapshot comes from. By the time either button is
  reachable a tunnel is already up, so asking the network where we are answers
  with the **exit node** - which would save the place you are leaving *as* home
  and make the way back a no-op. So the snapshot is taken from the cached
  reading, and `weather-location.py` stamps every reading with `source`
  (`ip`/`vpn`/`fixed`) and `tunneled`. Only `source == "ip"` **and**
  `tunneled == false` is a real location for this machine. Both conditions
  matter and the second is the one that is easy to forget.

  **The clock's home comes from the same reading, not from `timedatectl`.** The
  obvious source for "this machine's own timezone" is the system clock, and it
  is the wrong one: a previous sync may already have moved it to a VPN's zone,
  and then `timezone_default` records *that* and every trip home lands in the
  wrong country - permanently, since it is only written when missing. This is
  not hypothetical; it is how this machine ended up restoring to Europe/Madrid
  while living in Minsk. So `get_location()` returns the provider's `timezone`
  beside the coordinates (both ip-api and ipinfo hand it over for free), it is
  stamped on the reading as `tz`, and the snapshot prefers it. `timedatectl` is
  the last resort and only when `timezone` - the bar's own record of "the clock
  is following a tunnel" - is empty.

  Home travels as **coordinates**, not a city name: a bare name only resolves
  for the seven in `VPN_LOCATIONS`, and home can be anywhere. Hence
  `weather-location.py "lat,lon" [name]`.

  `--forget` is passed explicitly rather than inferred from whether a tunnel is
  up, and that matters twice. The disconnect button starts `wg-quick down` and
  the reset in the same moment, so the tunnel is usually still up when the
  script runs and a live-state rule would forget almost nothing; and on the
  toggle path, where coming home *while connected* is the whole point, the
  saved home is the only thing that can answer, so forgetting there would break
  the feature. What remains of the delete comes **after** the fetch, since a
  tunnel still on its way down means that fetch was the last thing needing the
  coordinates.

  `weather-fetch.sh` owns the precedence: `weather_city` (following the tunnel)
  > `weather_home`, but **only while a tunnel is up** > IP. That last ordering
  is deliberate - with no tunnel, asking by IP every time is what keeps the
  reading honest if you actually move house, and it is also how a fresh
  `weather_home` gets captured at the next departure.

  **Why the weather used to follow the tunnel on its own.** `weather_home` had
  exactly one writer - `vpn-sync.sh`, at the moment the weather toggle was
  first pressed - and `--forget` deletes it on disconnect. So the ordinary case
  never had one: bring a tunnel up, never touch the toggle, and step 2 above
  has no file to read, leaving step 3, an IP lookup, which through a tunnel
  answers with the exit node. The weather moved to Berlin without being asked
  while the clock stayed in Minsk, because nothing moves the clock but an
  explicit `timedatectl set-timezone`. That asymmetry was the bug: the clock
  only ever moves on purpose, the weather re-resolved itself on every fetch.
  `weather-location.py` now writes `weather_home` from any untunneled `ip`
  reading, so the file exists before it is needed.

  A machine that has never fetched weather **without** a tunnel up still has no
  home to go to, and its weather falls back to IP - i.e. the exit node. That
  part cannot be fixed in code: you cannot learn where you are while all your
  traffic leaves somewhere else. One fetch off the tunnel seeds it, and from
  then on every untunneled fetch keeps it current.

- **Spinner.qml**: eight dots on a ring with the tail graded by opacity, for
  waits with no known duration. **Drawn rather than set in type**: a Nerd Font
  spinner glyph turned with a RotationAnimator visibly wobbles, because the ink
  is not centred in its character cell, so spinning it about that cell makes it
  orbit rather than rotate. Geometry cannot. `running` is bound to `visible`,
  so a hidden one costs nothing.
- **BluetoothWidget.qml**: Bluetooth status with dropdown. Icon turns green when device connected
- **Widget components**: Each has its own Process components for data fetching and PopupWindow for dropdowns

### Theming

The bar is **monochrome by design**. The desktop it sits on is a two-hue
composition (warm near-black + crimson), so any stray hue in the bar becomes
the loudest thing on screen. Widgets are distinguished by *brightness* and by
their text label, never by hue.

Colour flows one way:

```
wallpaper
  -> wallust  (~/.config/wallust/templates/bar-colors.json)
  -> ~/.config/quickshell/bar/wallust-colors.json   (generated, gitignored)
  -> Theme.qml  (FileView + watchChanges, hot-reloads)
  -> components use Theme.col*
```

Change the wallpaper and the bar recolours itself; no restart, no edits.
`Theme.qml` holds the sovietpunk palette as *fallbacks* only, used when the
generated file is missing or malformed (it logs a warning and keeps the last
good palette rather than rendering blank).

**Never put a hex literal in a component.** Use a semantic role:

| Role | Use for |
|---|---|
| `colValue` / `colFg` | numbers, primary text |
| `colLabel` / `colDim` | `CPU`, `MEM` — the noun, and secondary info |
| `colWhite` / `colGrey` | the brightness ramp: emphasis, then the step below it |
| `colMuted` | separators, inactive, "off" states |
| `colAccent` | active / connected / on |
| `colAlert` | **needs attention**: muted, low battery, DND on, VPN down, storm |
| `colWarn` | state unknown or degraded (e.g. `dunstctl` failed) |
| `colOnAlert` | text sitting on an alert-filled shape |

`colAlert` is the only real hue in the bar. Spend it only on states worth
looking at — if everything is an alert, nothing is.

**`colDim`, `colMuted` and `colFaint` carry the wallpaper's hue at full
saturation** — `atLeast()` only floors their lightness, it does not desaturate.
`colWhite` and `colGrey` are the desaturated pair (`desat()`). On a few short bar
labels that whisper of hue is the point. On a **large surface** it is not: the
clipboard picker used `colDim`/`colMuted` for its rows and chrome and read as
solidly orange on a red wallpaper. Any full-screen or card-sized surface should
use `colWhite` for what is active or selected and `colGrey` for everything else,
which is the bar's own white-active/grey-idle rule.

Ordinal data (temperature, load) is encoded as a brightness ramp, with
`colAlert` reserved for genuine extremes. See `getTempColor()` in
`CenterInfo.qml`.

There is no `colBright`. It was listed in this table for a while and never
existed in `Theme.qml` - the palette has a `palBright`, but nothing exports it,
so `Theme.colBright` is `undefined` and Qt logs `Unable to assign [undefined] to
QColor` and falls back to black. Use `colWhite` and `colGrey` for the ramp.

### Key Patterns

**The bar is instantiated once per screen.** `shell.qml` wraps it in
`Variants { model: Quickshell.screens }`, so anything a widget polls, it polls N
times on an N-monitor machine. Data that is the same on every screen belongs in a
singleton that the widgets render; only the rendering should be per-screen. See
`SystemStats.qml`.

**Prefer, in this order:**

1. **A Hyprland event payload.** `Hyprland.onRawEvent` carries the data with the
   event - `activewindow` is `"<class>,<title>"`, `windowtitlev2` is
   `"<address>,<title>"`, `activelayout` is `"<device>,<layout>"`. Parse the
   payload; do not shell out to `hyprctl` to re-fetch what you were just handed.
   **Always filter on `event.name` first** - Hyprland fires a great many events
   (ten `activelayout`s per keyboard switch), and an unfiltered handler runs on
   all of them. See `WindowInfo.qml` and `KeyboardLayoutWidget.qml`.
2. **`FileView`**, for anything that lives in a file - `/proc`, `/sys`, and the
   caches under `~/.cache/quickshell`. With `watchChanges: true` it updates on
   inotify, which is both cheaper and faster than polling an mtime by hand. Set
   `printErrors: false` where a missing file is a normal state.

   **For anything you poll - `/proc`, `/sys` - set `blockAllReads: true`, not
   `blockLoading: true`.** This is the single easiest bug to write in this
   codebase, and this file used to recommend the wrong one. `blockLoading` makes
   only the *initial* load synchronous. After that, `reload()` starts an
   **asynchronous** read and `text()` keeps returning the previous contents until
   it lands, so `reload(); text()` gives you the value from the refresh before
   this one - forever. Measured: three `reload()` + `text()` pairs in the same
   event-loop turn all returned the stale value, and it only caught up on the
   next tick. `blockAllReads` makes every read synchronous, which is what a
   polled file needs.

   It bites hardest on a write-then-read: the limit pills in the battery card
   needed two clicks for exactly this reason - the write landed, the read after
   it returned the pre-write value, and the optimistic value was dropped in
   favour of it. `SystemStats` had the quiet version of the same bug: every CPU,
   memory and temperature reading was one 5s tick old. `NightLight` had the
   user-visible version: its icon latched on and the toggle looked dead, while
   hyprsunset itself started and stopped perfectly.

   **`onLoadedChanged` does not rescue this**, which is the trap. It fires on the
   transition *into* `loaded`, and after the first read `loaded` is already true,
   so a `reload()` never re-emits it. A handler written as
   `onFileChanged: { reload(); apply(text()) }` with an `onLoadedChanged` beside
   it looks belt-and-braces and is in fact stale every time after the first.

   Neither `watchChanges` nor inotify helps on sysfs: those attributes raise no
   inotify events at all. Use `udevadm monitor` for hardware state (see
   `BatteryState`).
3. **A D-Bus / netlink monitor process** (`nmcli monitor`, `dbus-monitor`,
   `udevadm monitor`), for hardware state with no file to watch. Gate these on the
   hardware actually existing - see below.
4. **A `Process` on a timer**, only when none of the above applies. Pick the
   interval from how often the value really changes: a clock showing `HH:MM`
   needs a minute, not a second.

- **Hiding is not stopping**: `visible: false` drops a widget from the layout but
  leaves its timers and monitor processes running. Every widget that hides itself
  on absent hardware (`hasWifi`, `hasBattery`, `hasAdapter`) must also gate its
  timers and processes on the same property, or a desktop pays for a wifi scanner
  it cannot use.
- **Process + SplitParser**: how the remaining shell-command data is fetched
- **Theme singleton**: Components access theme via `import ".."` then use `Theme.colFg`, `Theme.fontSize`, etc.
- **PopupWindows**: Dropdowns use `PopupWindow` with `visible` bound to `*DropdownOpen` properties
- **HyprlandFocusGrab**: Used to close popups when clicking outside. Requires `import Quickshell.Hyprland`. Example:
  ```qml
  HyprlandFocusGrab {
      id: myFocusGrab
      windows: [myPopup]
      active: myDropdownOpen
      onCleared: myDropdownOpen = false
  }
  ```
- **Two font roles.** `Theme.fontFamily` is Terminess, the bar's face: a
  bitmap-derived terminal font that suits a row of short fixed labels.
  `Theme.fontFamilyContent` is JetBrains Mono, for surfaces that render
  **arbitrary text at paragraph length and small size** — the clipboard picker is
  the case that asked for it, since Terminess has no hinting to speak of below
  its design size and its lowercase runs together. Use the Nerd Font variant name
  (`JetBrainsMono Nerd Font`), not the bare family, because these surfaces draw
  nf-md glyphs alongside the text. Shipped by `ttf-jetbrains-mono-nerd`, already
  in `install-scripts/fonts.sh`.
- **Nerd Font Icons**: Uses Material Design Icons range (nf-md-*) which render correctly in Qt. Other ranges may not work.

### External Dependencies

- `nmcli` for WiFi scanning/connecting
- `bluetoothctl` for Bluetooth management
- `powerprofilesctl` for power profile management
- `/usr/local/bin/battery-charge-limit` (installed by `install-scripts/battery_charge_limit.sh`)
  for setting the battery charge threshold. Optional: without it the battery card
  still shows every reading and only hides the limit picker
- `dunstctl` for DND (Do Not Disturb) toggle
- `wpctl` / `pactl` for volume control and audio sink detection
- `hyprctl` for workspace/window data
- `jq` for JSON parsing
- `scripts/weather-fetch.sh` -> `scripts/weather-location.py` for weather data (outputs JSON the bar parses)
- `scripts/network-speedtest.sh <down|up> [seconds]` prints one Mb/s sample per second.
  Saturates the link with 8 parallel curl workers against fast.com's CDN endpoints and
  measures the result off `/sys` byte counters. Unlike the upstream version it **stops on
  its own** rather than running until killed. The fast.com token in it is public (it
  base64-decodes to a keyboard mash), identifies the fast.com app rather than the user,
  and is overridable with `FAST_TOKEN`
- `scripts/network-qr.sh` emits `meta` + a 0/1 matrix for a Wi-Fi join QR, drawn by the card
  as plain rectangles. Needs `qrencode` (now in `01-hypr-pkgs.sh`); without it, it prints one
  `error` line the card shows instead of failing silently
- `scripts/network-status.sh` for the network card's status (tab-separated key/value lines).
  Uses `nmcli` for the radio details rather than `iw`, which is **not** a dependency of this
  repo and is not installed - the upstream version read the radio through `iw` and so produced
  nothing at all here. `iw` is consulted only for the dBm reading, when it happens to exist

### Adding New Widgets

1. Create a new component in `components/` (e.g., `MyWidget.qml`)
2. Add Process components for data fetching with SplitParser
3. Use `import ".."` to access Theme singleton
4. Add the component to shell.qml's RowLayout
5. For dropdowns, extend `DropdownWidget`:
   ```qml
   DropdownWidget {
       id: myWidget
       popupWidth: 200
       popupHeight: 150

       // Icon content (default property - what shows in bar)
       Text {
           anchors.verticalCenter: parent.verticalCenter
           text: "󰤨"
           color: Theme.colFg
       }

       // Popup content (use myWidget.* for property references)
       popupContent: Component {
           Column {
               Text { text: myWidget.someProperty }
           }
       }

       // Optional: React to dropdown opening
       onOpened: someProcess.running = true
   }
   ```
   The base component handles: barWindow connection, dropdownOpen state, MouseArea toggle, HyprlandFocusGrab, and PopupWindow with notch design (concave corners connecting narrow stem to wider body). Popup is automatically centered on the icon.

   `triggerButton` picks which button opens the card (left by default).
   Whichever buttons are *not* the trigger arrive as `onOtherClicked(button)`,
   and the wheel as `onWheelMoved(deltaY)`, so a widget keeps its own gestures
   instead of having them swallowed by the card's hit area - that is how
   `VolumeWidget` opens on right-click while left-click still mutes.
- no need to restart quickshell, it hot reloads the config on save.