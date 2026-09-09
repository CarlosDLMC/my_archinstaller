#!/usr/bin/env python3
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  #
# Soviet-brutalist TUI renderer for hyprlock.
# Mirrors the aesthetic of the ly display manager (see assets/ly/config.ini
# and assets/ly/lang/soviet.ini) so the login and lock screens match.
#
# Modes:
#   --date    uppercase Russian date line
#   --panel   the bordered status panel, refresh every 30s
#   --footer  ly-style key hint row
#
# The bigclock is deliberately NOT here - it lives in SovietClock.sh, because
# it is the one widget hyprlock re-runs every second per monitor and Python's
# startup dominated its cost. Nothing in this file refreshes faster than 30s.
#
# hyprlock only renders multi-line text when it arrives via cmd[...], and it
# ignores literal \n in a `text =` field, so every block here is emitted with
# real newlines from a single command.

import locale
import os
import pwd
import re
import subprocess
import sys
from datetime import datetime

W = 62  # inner width of the panel, in characters
LABEL = 16  # label column width

HOME = os.path.expanduser("~")

# %A / %B must come back in Cyrillic; fall back silently to the C locale
# if ru_RU is not generated on this machine.
for _loc in ("ru_RU.utf8", "ru_RU.UTF-8", "ru_RU"):
    try:
        locale.setlocale(locale.LC_TIME, _loc)
        break
    except locale.Error:
        continue

# Private Use Area, where Nerd Font glyphs live. The weather cache is written
# for the pretty lock screen and prefixes each line with one.
PUA = re.compile("[\ue000-\uf8ff\U000f0000-\U000ffffd]")

WEATHER_RU = {
    "Clear sky": "ЯСНО",
    "Mainly clear": "В ОСНОВНОМ ЯСНО",
    "Partly cloudy": "ПЕРЕМЕННАЯ ОБЛАЧНОСТЬ",
    "Overcast": "ПАСМУРНО",
    "Fog": "ТУМАН",
    "Depositing rime fog": "ИЗМОРОЗЬ",
    "Light drizzle": "СЛАБАЯ МОРОСЬ",
    "Moderate drizzle": "МОРОСЬ",
    "Dense drizzle": "СИЛЬНАЯ МОРОСЬ",
    "Freezing drizzle": "ЛЕДЯНАЯ МОРОСЬ",
    "Light rain": "СЛАБЫЙ ДОЖДЬ",
    "Moderate rain": "ДОЖДЬ",
    "Heavy rain": "СИЛЬНЫЙ ДОЖДЬ",
    "Freezing rain": "ЛЕДЯНОЙ ДОЖДЬ",
    "Slight snow": "СЛАБЫЙ СНЕГ",
    "Moderate snow": "СНЕГ",
    "Heavy snow": "СИЛЬНЫЙ СНЕГ",
    "Snow grains": "СНЕЖНАЯ КРУПА",
    "Rain showers": "ЛИВНИ",
    "Violent rain showers": "СИЛЬНЫЕ ЛИВНИ",
    "Snow showers": "СНЕЖНЫЕ ЛИВНИ",
    "Heavy snow showers": "СИЛЬНЫЕ СНЕЖНЫЕ ЛИВНИ",
    "Thunderstorm": "ГРОЗА",
    "Thunderstorm w/ hail": "ГРОЗА С ГРАДОМ",
    "Unknown": "НЕТ ДАННЫХ",
}

BATTERY_RU = {
    "Full": "ПОЛОН",
    "Charging": "ЗАРЯДКА",
    "Discharging": "РАЗРЯД",
    "Not charging": "НЕ ЗАРЯЖАЕТСЯ",
    "Unknown": "НЕИЗВЕСТНО",
}


def sh(*cmd):
    """Run a command, return stripped stdout, or '' on any failure."""
    try:
        out = subprocess.run(
            cmd, capture_output=True, text=True, timeout=2, check=False
        )
        return out.stdout.strip()
    except Exception:
        return ""


def read(path, default=""):
    try:
        with open(path) as fh:
            return fh.read().strip()
    except Exception:
        return default


# ---------------------------------------------------------------- data sources


def user():
    try:
        return pwd.getpwuid(os.getuid()).pw_name
    except Exception:
        return os.environ.get("USER", "—")


def host():
    return read("/etc/hostname", "localhost")


def kernel():
    return os.uname().release


def uptime_ru():
    """Uptime as e.g. '3 ДН 07 Ч 15 МИН'."""
    raw = read("/proc/uptime", "0").split()
    try:
        secs = int(float(raw[0]))
    except (IndexError, ValueError):
        return "НЕТ ДАННЫХ"
    days, rem = divmod(secs, 86400)
    hours, rem = divmod(rem, 3600)
    mins = rem // 60
    if days:
        return f"{days} ДН {hours:02d} Ч {mins:02d} МИН"
    if hours:
        return f"{hours} Ч {mins:02d} МИН"
    return f"{mins} МИН"


def batteries():
    """One entry per real battery. The stock Battery.sh loops BAT0..BAT3 and
    prints a line per match, which double-printed on this two-battery
    ThinkPad; a long status ("НЕ ЗАРЯЖАЕТСЯ") on two packs also overflows a
    single row, so each gets its own."""
    out = []
    for i in range(4):
        base = f"/sys/class/power_supply/BAT{i}"
        cap = read(f"{base}/capacity")
        if not cap:
            continue
        status = read(f"{base}/status", "Unknown")
        out.append((f"BAT{i}", f"{cap}%".rjust(4) + "  " + BATTERY_RU.get(status, status.upper())))
    return out


def ac_online():
    for name in ("AC", "AC0", "ACAD", "ADP1"):
        val = read(f"/sys/class/power_supply/{name}/online")
        if val:
            return "ПОДКЛЮЧЕНО" if val == "1" else "ОТКЛЮЧЕНО"
    return None


def loadavg():
    parts = read("/proc/loadavg", "").split()
    return " ".join(parts[:3]) if len(parts) >= 3 else "—"


def memory():
    """Used / total in GiB, matching what free(1) calls 'used'."""
    vals = {}
    try:
        with open("/proc/meminfo") as fh:
            for line in fh:
                k, _, v = line.partition(":")
                vals[k] = int(v.split()[0])
    except Exception:
        return "—"
    total = vals.get("MemTotal", 0)
    avail = vals.get("MemAvailable", 0)
    if not total:
        return "—"
    gib = 1024 * 1024
    return f"{(total - avail) / gib:.1f}/{total / gib:.1f} ГБ"


def weather():
    """Parse ~/.cache/.weather_cache, written by UserScripts/Weather.py and
    refreshed by scripts/LockScreen.sh just before locking."""
    raw = read(f"{HOME}/.cache/.weather_cache")
    if not raw:
        return None
    lines = [PUA.sub("", ln).strip() for ln in raw.splitlines()]
    lines = [ln for ln in lines if ln]
    if not lines:
        return None

    info = {
        "loc": lines[0] if len(lines) > 0 else "",
        "cond": lines[1] if len(lines) > 1 else "",
        "temp": lines[2] if len(lines) > 2 else "",
        "wind": lines[3] if len(lines) > 3 else "",
        "hum": lines[4] if len(lines) > 4 else "",
        "vis": lines[5] if len(lines) > 5 else "",
    }
    info["cond"] = WEATHER_RU.get(info["cond"], info["cond"].upper())

    # "6km/h" -> "6 КМ/Ч", "42.2 km AQI 30" -> "42.2 КМ" + "30"
    info["wind"] = re.sub(
        r"\s*km/h", " КМ/Ч", re.sub(r"\s*mph", " МИЛЬ/Ч", info["wind"])
    ).strip()
    vis = info["vis"]
    aqi = ""
    m_aqi = re.search(r"AQI\s*(\d+)", vis)
    if m_aqi:
        aqi = m_aqi.group(1)
        vis = vis[: m_aqi.start()].strip()
    info["vis"] = re.sub(r"\s*km\b", " КМ", re.sub(r"\s*mi\b", " МИЛЬ", vis)).strip()
    info["aqi"] = aqi

    m = re.match(r"(-?\d+)°(\w).*?(-?\d+)°", info["temp"])
    if m:
        sign = "+" if int(m.group(1)) > 0 else ""
        sign2 = "+" if int(m.group(3)) > 0 else ""
        info["temp"] = (
            f"{sign}{m.group(1)}°{m.group(2)}   "
            f"ОЩУЩАЕТСЯ {sign2}{m.group(3)}°{m.group(2)}"
        )
    return info


# -------------------------------------------------------------------- drawing


def line(text=""):
    return "║" + text.ljust(W)[:W] + "║"


def kv(label, value):
    return line("  " + label.ljust(LABEL) + str(value))


def top():
    return "╔" + "═" * W + "╗"


def bottom():
    return "╚" + "═" * W + "╝"


def section(title):
    head = "═ " + title + " "
    return "╠" + head + "═" * (W - len(head)) + "╣"


def split_row(left, right):
    """Left text, right text, flush to the two borders."""
    left = "  " + left
    gap = W - len(left) - len(right) - 2
    return line(left + " " * max(gap, 1) + right + "  ")


# ---------------------------------------------------------------------- modes


def mode_date():
    stamp = datetime.now().strftime("%A, %-d %B %Y")
    print(stamp.upper())


def mode_footer():
    """Only keys hyprlock actually honours.

    ly's own footer offers F1/F2/F3 (shutdown/restart/sleep), but hyprlock has
    no keybinds of its own, and Hyprland's `bindl` fires whether the session is
    locked or not - binding F1 to shutdown would fire while working. So the
    hints here are limited to what really works: hyprlock clears the password
    buffer on ESC, Ctrl+U and Ctrl+Backspace. ALT+SHIFT is listed because
    that bind is `bindld` and dispatches a global to quickshell, which
    keeps running while locked - so it genuinely works here."""
    print("ENTER ПОДТВЕРДИТЬ    ESC ОЧИСТИТЬ    ALT+SHIFT РАСКЛАДКА")


def mode_panel():
    out = [top()]
    out.append(split_row("ЦЕНТРАЛЬНЫЙ ТЕРМИНАЛ", f"{host().upper()}  ARCH LINUX"))

    out.append(section("ДОСТУП"))
    out.append(kv("ГРАЖДАНИН", user()))
    out.append(kv("ОКРУЖЕНИЕ", "HYPRLAND / WAYLAND"))
    # value overlaid by a live, clickable $LAYOUT label - see hyprlock.conf
    out.append(kv("РАСКЛАДКА", ""))
    # The input-field widget is overlaid onto this row; leave the value blank.
    out.append(kv("КОД ДОСТУПА", ""))

    out.append(section("СОСТОЯНИЕ СИСТЕМЫ"))
    out.append(kv("ЯДРО", kernel()))
    out.append(kv("ВРЕМЯ РАБОТЫ", uptime_ru()))
    out.append(kv("НАГРУЗКА", loadavg()))
    out.append(kv("ПАМЯТЬ", memory()))

    out.append(section("ПИТАНИЕ"))
    ac = ac_online()
    if ac:
        out.append(kv("СЕТЬ", ac))
    packs = batteries()
    if packs:
        for name, detail in packs:
            out.append(kv(name, detail))
    elif not ac:
        out.append(kv("СЕТЬ", "220В"))

    out.append(section("ПОГОДА"))
    wx = weather()
    if wx:
        out.append(kv("ПУНКТ", wx["loc"].upper()))
        out.append(kv("СОСТОЯНИЕ", wx["cond"]))
        out.append(kv("ТЕМПЕРАТУРА", wx["temp"]))
        out.append(kv("ВЕТЕР", wx["wind"]))
        out.append(kv("ВЛАЖНОСТЬ", wx["hum"]))
        if wx["vis"]:
            out.append(kv("ВИДИМОСТЬ", wx["vis"]))
        if wx["aqi"]:
            out.append(kv("ВОЗДУХ", f"ИНДЕКС {wx['aqi']}"))
    else:
        out.append(kv("СОСТОЯНИЕ", "НЕТ ДАННЫХ"))

    out.append(bottom())
    print("\n".join(out))


MODES = {
    "--date": mode_date,
    "--panel": mode_panel,
    "--footer": mode_footer,
}

if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "--panel"
    MODES.get(mode, mode_panel)()
