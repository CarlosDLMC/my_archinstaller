#!/usr/bin/env python3
# Weather script for the Quickshell bar.
# Usage: weather-location.py [city | "lat,lon" [display name]]
#   - If [city] matches VPN_LOCATIONS, those coordinates are used.
#   - "lat,lon" uses those coordinates directly, with the display name that
#     follows it. This is how the bar asks for *home* while a tunnel is up:
#     IP geolocation would answer with the exit node, and a plain city name
#     only resolves for the seven in VPN_LOCATIONS, so home - which can be
#     anywhere - has to travel as coordinates.
#   - Otherwise location comes from IP geolocation.
#
# The output carries `lat`, `lon` and `source` ("ip", "vpn" or "fixed")
# alongside the display fields, so the caller can tell where a reading came
# from. vpn-sync.sh uses that to snapshot home before the first departure:
# only a reading whose source is "ip" is a real location for this machine.
#
# Data sources, in order: Open-Meteo (https://open-meteo.com) and, when it
# refuses, wttr.in. Both are keyless and worldwide, and neither is trusted to
# be up: Open-Meteo counts requests per source IP, so a shared VPN exit node
# can exhaust the daily quota without this machine asking for anything, and
# then every request answers 429 until the counter rolls over. One provider
# being out should cost the weather nothing, so the second is tried before
# anything falls back to cached data. Borrowed from omarchy, which reaches for
# wttr.in first and Open-Meteo for the forecast detail.
#
# Open-Meteo replaced the previous weather.com HTML scraper:
# weather.com removed the CSS classes / data-testid attributes the scraper
# relied on (TemperatureValue, wxPhrase, CurrentConditions--*), so PyQuery
# selectors silently returned empty strings and the widget rendered blank.
#
# Output is Waybar-compatible JSON whose `text`/`alt`/`tooltip` are shaped to
# match the regex parsing in ../components/CenterInfo.qml. Keep that contract
# in sync if you edit the tooltip layout.

import requests
import json
import os
import re
import subprocess
import sys
import time

CACHE_PATH = os.path.expanduser("~/.cache/quickshell/weather.json")

# Weather icons (Nerd Font Material Design Icons — render correctly in Qt)
weather_icons = {
    "sunnyDay": "󰖙",         # nf-md-weather_sunny
    "clearNight": "󰖔",       # nf-md-weather_night
    "cloudyFoggyDay": "󰖐",   # nf-md-weather_cloudy
    "cloudyFoggyNight": "󰼱", # nf-md-weather_night_partly_cloudy
    "rainyDay": "󰖖",         # nf-md-weather_rainy
    "rainyNight": "󰖖",       # nf-md-weather_rainy
    "snowyIcyDay": "󰼴",      # nf-md-weather_snowy
    "snowyIcyNight": "󰼴",    # nf-md-weather_snowy
    "severe": "󰖓",           # nf-md-weather_lightning (U+F0593, plain bolt)
    "default": "󰖐",          # nf-md-weather_cloudy (fallback)
}

# VPN location mappings (city -> coordinates)
VPN_LOCATIONS = {
    "berlin": (52.520008, 13.404954),
    "warsaw": (52.237049, 21.017532),
    "tbilisi": (41.715138, 44.827096),
    "madrid": (40.416775, -3.703790),
    "kyiv": (50.450001, 30.523333),
    "vilnius": (54.687157, 25.279652),
    "jakarta": (-6.200000, 106.816666),
}

# Russian display names for the VPN cities above. Everywhere else the city name
# is localised by ip-api itself (&lang=ru), so there is nothing to maintain here
# beyond these seven overrides.
VPN_LOCATION_NAMES_RU = {
    "berlin": "Берлин",
    "warsaw": "Варшава",
    "tbilisi": "Тбилиси",
    "madrid": "Мадрид",
    "kyiv": "Киев",
    "vilnius": "Вильнюс",
    "jakarta": "Джакарта",
}

# WMO weather code -> (description, icon category)
# https://open-meteo.com/en/docs#weathervariables (WMO code interpretation)
WMO = {
    0: ("Clear sky", "sunny"),
    1: ("Mainly clear", "sunny"),
    2: ("Partly cloudy", "cloudy"),
    3: ("Overcast", "cloudy"),
    45: ("Fog", "fog"),
    48: ("Depositing rime fog", "fog"),
    51: ("Light drizzle", "rainy"),
    53: ("Moderate drizzle", "rainy"),
    55: ("Dense drizzle", "rainy"),
    56: ("Light freezing drizzle", "snowy"),
    57: ("Dense freezing drizzle", "snowy"),
    61: ("Slight rain", "rainy"),
    63: ("Moderate rain", "rainy"),
    65: ("Heavy rain", "rainy"),
    66: ("Light freezing rain", "snowy"),
    67: ("Heavy freezing rain", "snowy"),
    71: ("Slight snow", "snowy"),
    73: ("Moderate snow", "snowy"),
    75: ("Heavy snow", "snowy"),
    77: ("Snow grains", "snowy"),
    80: ("Slight rain showers", "rainy"),
    81: ("Moderate rain showers", "rainy"),
    82: ("Violent rain showers", "rainy"),
    85: ("Slight snow showers", "snowy"),
    86: ("Heavy snow showers", "snowy"),
    95: ("Thunderstorm", "severe"),
    96: ("Thunderstorm with slight hail", "severe"),
    99: ("Thunderstorm with heavy hail", "severe"),
}

# Russian condition text, keyed by the same WMO code. Kept separate from WMO so
# the English string survives as the machine-readable key: getConditionColor()
# in ../components/CenterInfo.qml matches on English substrings ("sun", "rain",
# "thunder", ...) to tint the popup icon, and would fall back to a flat colour
# if it were handed Cyrillic.
WMO_RU = {
    0: "Ясно",
    1: "Преимущественно ясно",
    2: "Переменная облачность",
    3: "Пасмурно",
    45: "Туман",
    48: "Изморозь",
    51: "Слабая морось",
    53: "Умеренная морось",
    55: "Сильная морось",
    56: "Слабая ледяная морось",
    57: "Сильная ледяная морось",
    61: "Небольшой дождь",
    63: "Умеренный дождь",
    65: "Сильный дождь",
    66: "Слабый ледяной дождь",
    67: "Сильный ледяной дождь",
    71: "Небольшой снег",
    73: "Умеренный снег",
    75: "Сильный снег",
    77: "Снежные зёрна",
    80: "Небольшой ливень",
    81: "Умеренный ливень",
    82: "Сильный ливень",
    85: "Небольшой снегопад",
    86: "Сильный снегопад",
    95: "Гроза",
    96: "Гроза с небольшим градом",
    99: "Гроза с сильным градом",
}

# icon category + day/night -> weather_icons key
ICON_CATEGORY = {
    ("sunny", 1): "sunnyDay",
    ("sunny", 0): "clearNight",
    ("cloudy", 1): "cloudyFoggyDay",
    ("cloudy", 0): "cloudyFoggyNight",
    ("fog", 1): "cloudyFoggyDay",
    ("fog", 0): "cloudyFoggyNight",
    ("rainy", 1): "rainyDay",
    ("rainy", 0): "rainyNight",
    ("snowy", 1): "snowyIcyDay",
    ("snowy", 0): "snowyIcyNight",
    ("severe", 1): "severe",
    ("severe", 0): "severe",
}


def log(msg):
    print(msg, file=sys.stderr)


def get_location():
    """Get (lat, lon, city, tz) from IP address.

    The timezone comes back with the coordinates because both providers hand it
    over for free, and it is the only trustworthy source for *this machine's*
    own timezone: the system clock cannot be asked, since a previous VPN sync
    may already have moved it. See the timezone_default snapshot in vpn-sync.sh.
    """
    # Try ip-api.com first (45 req/min for non-commercial)
    try:
        r = requests.get(
            "http://ip-api.com/json/?fields=lat,lon,city,timezone,status,message&lang=ru",
            timeout=5,
        )
        data = r.json()
        if data.get("status") == "success":
            return (
                float(data["lat"]),
                float(data["lon"]),
                data.get("city", ""),
                data.get("timezone", ""),
            )
        log(f"ip-api.com error: {data.get('message', 'Unknown error')}")
    except Exception as e:
        log(f"ip-api.com error: {e}")

    # Fallback to ipinfo.io (HTTPS, stricter limits)
    try:
        r = requests.get("https://ipinfo.io", timeout=5)
        data = r.json()
        if "loc" in data:
            lat, lon = data["loc"].split(",")
            return float(lat), float(lon), data.get("city", ""), data.get("timezone", "")
        log(f"ipinfo.io error: {data.get('error', data)}")
    except Exception as e:
        log(f"ipinfo.io error: {e}")

    return None, None, "", ""


def tunnel_up():
    """True if a WireGuard tunnel is up.

    An IP reading taken through a tunnel describes the exit node, not this
    machine, so `source: "ip"` alone is not enough to call a reading home -
    vpn-sync.sh needs both. Getting this wrong would save the exit node as home
    and make the way back point at the place you were leaving.
    """
    try:
        out = subprocess.run(
            ["wg", "show", "interfaces"], capture_output=True, text=True, timeout=3
        )
        return bool(out.stdout.strip())
    except Exception:
        return False


def fetch_air_quality(lat, lon):
    """Return European AQI as int, or None."""
    try:
        r = requests.get(
            "https://air-quality-api.open-meteo.com/v1/air-quality",
            params={"latitude": lat, "longitude": lon, "current": "european_aqi"},
            timeout=8,
        )
        val = r.json().get("current", {}).get("european_aqi")
        return int(round(val)) if val is not None else None
    except Exception as e:
        log(f"air-quality error: {e}")
        return None


# wttr.in reports World Weather Online codes, not WMO ones, so its readings
# have to be translated before they can use the tables above. Mapped onto the
# nearest WMO code rather than onto the icon directly, so a wttr reading picks
# up the same English status, the same Russian text and the same icon as an
# Open-Meteo reading of the same sky - the bar must not be able to tell which
# provider answered.
WWO_TO_WMO = {
    113: 0,    # Sunny / Clear
    116: 2,    # Partly cloudy
    119: 3,    # Cloudy
    122: 3,    # Overcast
    143: 45,   # Mist
    176: 80,   # Patchy rain possible
    179: 85,   # Patchy snow possible
    182: 66,   # Patchy sleet possible
    185: 56,   # Patchy freezing drizzle possible
    200: 95,   # Thundery outbreaks possible
    227: 73,   # Blowing snow
    230: 75,   # Blizzard
    248: 45,   # Fog
    260: 48,   # Freezing fog
    263: 51,   # Patchy light drizzle
    266: 53,   # Light drizzle
    281: 56,   # Freezing drizzle
    284: 57,   # Heavy freezing drizzle
    293: 61,   # Patchy light rain
    296: 61,   # Light rain
    299: 63,   # Moderate rain at times
    302: 63,   # Moderate rain
    305: 65,   # Heavy rain at times
    308: 65,   # Heavy rain
    311: 66,   # Light freezing rain
    314: 67,   # Moderate or heavy freezing rain
    317: 66,   # Light sleet
    320: 67,   # Moderate or heavy sleet
    323: 71,   # Patchy light snow
    326: 71,   # Light snow
    329: 73,   # Patchy moderate snow
    332: 73,   # Moderate snow
    335: 75,   # Patchy heavy snow
    338: 75,   # Heavy snow
    350: 77,   # Ice pellets
    353: 80,   # Light rain shower
    356: 81,   # Moderate or heavy rain shower
    359: 82,   # Torrential rain shower
    362: 85,   # Light sleet showers
    365: 86,   # Moderate or heavy sleet showers
    368: 85,   # Light snow showers
    371: 86,   # Moderate or heavy snow showers
    374: 85,   # Light showers of ice pellets
    377: 86,   # Moderate or heavy showers of ice pellets
    386: 95,   # Patchy light rain with thunder
    389: 95,   # Moderate or heavy rain with thunder
    392: 96,   # Patchy light snow with thunder
    395: 99,   # Moderate or heavy snow with thunder
}

# How many times to ask a provider that failed for a reason that might pass,
# and how long to wait between tries. omarchy's numbers: three attempts, 2.5s
# apart, then give up and leave it to the next refresh rather than hammering.
RETRY_ATTEMPTS = 3
RETRY_DELAY = 2.5

# Exit code for "this output is the last good reading, not a fresh one". The
# callers care: vpn-sync.sh must not write a stale reading back over the cache
# and must not report a sync that did not happen.
EXIT_STALE = 2


class WeatherError(Exception):
    """A provider refused. `retryable` says whether asking again can help."""

    def __init__(self, message, retryable=True):
        super().__init__(message)
        self.retryable = retryable


def get_json(url, params=None, timeout=10):
    """GET JSON, treating an error response as an error rather than as data.

    This is `curl -fsS`, which is what omarchy uses for exactly this reason. An
    HTTP error still carries a body, and Open-Meteo's is valid JSON:

        {"error":true,"reason":"Daily API request limit exceeded..."}

    Handing that to the parser is how a rate limit used to surface three lines
    later as KeyError('current') - a message that says nothing about what went
    wrong, on a path that then quietly reused stale data.
    """
    r = requests.get(url, params=params, timeout=timeout)

    if r.status_code >= 400:
        reason = ""
        try:
            reason = str(r.json().get("reason", "")).strip()
        except Exception:
            reason = (r.text or "").strip()[:120]
        # A quota or a bad request will say the same thing however many times
        # it is asked; only server-side trouble is worth a second attempt.
        raise WeatherError(
            f"HTTP {r.status_code}" + (f": {reason}" if reason else ""),
            retryable=r.status_code >= 500,
        )

    data = r.json()
    if isinstance(data, dict) and data.get("error"):
        raise WeatherError(str(data.get("reason", "provider reported an error")),
                           retryable=False)
    return data


def with_retries(what, fn):
    """Run fn, retrying the failures that a retry can actually fix."""
    last = None
    for attempt in range(1, RETRY_ATTEMPTS + 1):
        try:
            return fn()
        except WeatherError as e:
            last = e
            if not e.retryable:
                break
        except Exception as e:
            last = e
        if attempt < RETRY_ATTEMPTS:
            log(f"{what}: {last} (attempt {attempt}/{RETRY_ATTEMPTS}, retrying)")
            time.sleep(RETRY_DELAY)
    raise WeatherError(f"{what}: {last}")


def reading_from_open_meteo(lat, lon):
    """Normalised reading from Open-Meteo, the preferred source.

    Preferred because it answers with exactly the fields the tooltip wants -
    hourly precipitation probability and visibility included - in one request.
    """
    data = get_json(
        "https://api.open-meteo.com/v1/forecast",
        params={
            "latitude": lat,
            "longitude": lon,
            "current": "temperature_2m,relative_humidity_2m,apparent_temperature,"
            "is_day,weather_code,wind_speed_10m",
            "hourly": "precipitation_probability,visibility",
            "daily": "temperature_2m_max,temperature_2m_min",
            "timezone": "auto",
            "forecast_days": 1,
        },
    )
    cur = data["current"]

    temp = int(round(cur["temperature_2m"]))
    daily = data.get("daily", {})
    try:
        temp_max = int(round(daily["temperature_2m_max"][0]))
        temp_min = int(round(daily["temperature_2m_min"][0]))
    except (KeyError, IndexError, TypeError):
        temp_max = temp_min = temp

    # Align the hourly arrays to the current hour.
    hourly = data.get("hourly", {})
    times = hourly.get("time", [])
    cur_time = cur.get("time")
    start = times.index(cur_time) if cur_time in times else 0

    precip = hourly.get("precipitation_probability", [])
    rain = [int(round(p)) for p in precip[start:start + 5] if p is not None]

    vis_list = hourly.get("visibility", [])
    try:
        visibility_km = f"{vis_list[start] / 1000:.1f}"
    except (IndexError, TypeError, ZeroDivisionError):
        visibility_km = ""

    return {
        "provider": "open-meteo",
        "temp": temp,
        "feels": int(round(cur["apparent_temperature"])),
        "humidity": int(round(cur["relative_humidity_2m"])),
        "wind": int(round(cur["wind_speed_10m"])),
        "is_day": int(cur.get("is_day", 1)),
        "code": int(cur.get("weather_code", -1)),
        "temp_min": temp_min,
        "temp_max": temp_max,
        "rain": rain,
        "visibility_km": visibility_km,
    }


def reading_from_wttr(lat, lon):
    """Normalised reading from wttr.in, the second opinion.

    Same shape, one gap: wttr carries no air quality, so the AQI slot comes out
    blank rather than wrong. It also has no day/night flag - that is read off
    the icon URL, which is the only place it says so.
    """
    data = get_json(f"https://wttr.in/{lat},{lon}", params={"format": "j1"}, timeout=12)

    cur = data["current_condition"][0]
    day = (data.get("weather") or [{}])[0]

    icon_url = ""
    try:
        icon_url = str(cur["weatherIconUrl"][0]["value"])
    except (KeyError, IndexError, TypeError):
        pass

    temp = int(round(float(cur["temp_C"])))
    try:
        temp_max = int(round(float(day["maxtempC"])))
        temp_min = int(round(float(day["mintempC"])))
    except (KeyError, TypeError, ValueError):
        temp_max = temp_min = temp

    # wttr's hourly rows are three-hourly and start at midnight local time, so
    # the row covering now is hour // 3. Five rows is the same count the
    # tooltip shows from Open-Meteo, just reaching further ahead.
    hours = day.get("hourly") or []
    start = min(len(hours) - 1, max(0, time.localtime().tm_hour // 3)) if hours else 0
    # Late in the day there are not five rows left, so it runs on into
    # tomorrow's - the tooltip asks for "the next five", not "the rest of
    # today", and a row count that shrank towards midnight looked like data
    # going missing.
    upcoming = hours[start:] + ((data.get("weather") or [{}, {}])[1:2] or [{}])[0].get("hourly", [])
    rain = []
    for h in upcoming[:5]:
        try:
            rain.append(int(round(float(h["chanceofrain"]))))
        except (KeyError, TypeError, ValueError):
            pass

    try:
        visibility_km = f"{float(cur['visibility']):.1f}"
    except (KeyError, TypeError, ValueError):
        visibility_km = ""

    return {
        "provider": "wttr.in",
        "temp": temp,
        "feels": int(round(float(cur["FeelsLikeC"]))),
        "humidity": int(round(float(cur["humidity"]))),
        "wind": int(round(float(cur["windspeedKmph"]))),
        "is_day": 0 if "night" in icon_url.lower() else 1,
        "code": WWO_TO_WMO.get(int(cur.get("weatherCode", 0)), 3),
        "temp_min": temp_min,
        "temp_max": temp_max,
        "rain": rain,
        "visibility_km": visibility_km,
    }


def load_cached_reading():
    """The last good reading, or None - never a half-readable file.

    Validated rather than echoed. The cache used to be printed back byte for
    byte, which meant anything that ever landed in that file was served as a
    weather reading forever: when a caller once captured this script's stderr
    into it, the two log lines on top travelled out to every consumer and back
    in on the next failure. A file that does not parse is moved aside, so the
    next successful fetch starts from nothing rather than from wreckage.
    """
    try:
        with open(CACHE_PATH, encoding="utf-8") as f:
            data = json.loads(f.read())
    except FileNotFoundError:
        return None
    except Exception as e:
        log(f"cached reading is unusable ({e}) - moving it aside")
        try:
            os.replace(CACHE_PATH, CACHE_PATH + ".bad")
        except Exception:
            pass
        return None

    if not isinstance(data, dict) or not data.get("text"):
        log("cached reading has no weather in it - moving it aside")
        try:
            os.replace(CACHE_PATH, CACHE_PATH + ".bad")
        except Exception:
            pass
        return None
    return data


def emit_cached_or_empty(reason):
    """Every provider failed: re-emit the last good reading, marked as stale.

    Exits EXIT_STALE, not 0. The old code exited 0 here, so a caller that
    checked only the status saw a successful fetch, wrote the returned bytes
    back over the cache and reported that the weather had moved - while the bar
    kept showing the city it was already showing. Stale data stays on screen,
    which is right; claiming it is fresh is not.
    """
    log(reason)
    cached = load_cached_reading()
    if cached is not None:
        log("reusing the last good reading (stale)")
        cached["stale"] = True
        print(json.dumps(cached))
        sys.exit(EXIT_STALE)
    print(json.dumps({"text": "", "alt": "", "tooltip": "", "class": "", "stale": True}))
    sys.exit(1)


# ---- resolve coordinates -------------------------------------------------
COORD_RE = re.compile(r"^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$")

arg = sys.argv[1] if len(sys.argv) > 1 else None
city_arg = arg.lower() if arg else None
coords = COORD_RE.match(arg) if arg else None

ip_city = ""
ip_tz = ""
if coords:
    latitude, longitude = float(coords.group(1)), float(coords.group(2))
    location = sys.argv[2] if len(sys.argv) > 2 else ""
    source = "fixed"
elif city_arg and city_arg in VPN_LOCATIONS:
    latitude, longitude = VPN_LOCATIONS[city_arg]
    location = VPN_LOCATION_NAMES_RU.get(city_arg, city_arg.capitalize())
    source = "vpn"
else:
    latitude, longitude, ip_city, ip_tz = get_location()
    location = ip_city
    source = "ip"
    if latitude is None:
        emit_cached_or_empty("Could not determine location from IP")

# ---- fetch the reading ---------------------------------------------------
# Open-Meteo first, wttr.in second, cache last. Only when all three have
# nothing does the widget go blank, and each fallback is announced on stderr so
# vpn-sync.log says which one answered.
reading = None
failures = []
for name, fetch in (
    ("open-meteo", lambda: reading_from_open_meteo(latitude, longitude)),
    ("wttr.in", lambda: reading_from_wttr(latitude, longitude)),
):
    try:
        reading = with_retries(name, fetch)
        if failures:
            log(f"{name} answered instead")
        break
    except Exception as e:
        failures.append(str(e))
        log(f"{name} failed: {e}")

if reading is None:
    emit_cached_or_empty("; ".join(failures) or "no provider answered")

if not location:
    location = "Unknown"

temp = reading["temp"]
feels = reading["feels"]
humidity = reading["humidity"]
wind = reading["wind"]
is_day = reading["is_day"]
code = reading["code"]
temp_min = reading["temp_min"]
temp_max = reading["temp_max"]
visibility_km = reading["visibility_km"]
rain_tokens = " ".join(f"Rain drop {p}%" for p in reading["rain"])

status, category = WMO.get(code, ("Unknown", "default"))
status_ru = WMO_RU.get(code, "Неизвестно")
icon_key = ICON_CATEGORY.get((category, is_day), "default")
icon = weather_icons.get(icon_key, weather_icons["default"])

aqi = fetch_air_quality(latitude, longitude)
aqi_text = str(aqi) if aqi is not None else ""

location_short = location.split(",")[0].strip() or location

# ---- build Waybar JSON (format consumed by CenterInfo.qml) ---------------
# Bar text: "<icon>  <temp>° <location>"  (CenterInfo splits icon/temp/location)
text = f"{icon}  {temp}° {location_short}"

# Tooltip lines are parsed by regex in CenterInfo.qml — keep the markers:
#   first <b>...</b> = location,  <big>icon</big>,  "Feels like X°",
#   a "min°\t\tmax°" line,  "wind km/h \t humidity %",
#   "visibility km \t AQI n",  and repeated "Rain drop n%" tokens.
tooltip = (
    f"<b>{location}</b>\n"
    f'\t\t<span size="xx-large">{temp}°</span>\t\t\n'
    f"<big> {icon}</big>\n"
    f"<b>{status_ru}</b>\n"
    f"<small>Feels like {feels}°</small>\n"
    f"\n"
    f"<b>  {temp_min}°\t\t  {temp_max}°</b>\n"
    f" {wind}km/h\t {humidity}%\n"
    f" {visibility_km} km\tAQI {aqi_text}\n"
    f"<i> {rain_tokens}</i>"
)

out_data = {
    "text": text,
    "alt": status,
    "alt_display": status_ru,
    "tooltip": tooltip,
    "class": icon_key,
    # Where this reading came from, and the coordinates it came from. Not
    # rendered - CenterInfo.qml reads the fields above and ignores these - but
    # vpn-sync.sh needs them to snapshot home, and it cannot ask the network
    # for them once a tunnel is up.
    "lat": latitude,
    "lon": longitude,
    "source": source,
    # Which provider answered. Not rendered either - it is here so a reading
    # that looks wrong can be traced to the service that produced it.
    "provider": reading["provider"],
    # Only meaningful for an "ip" reading, and the whole question for it: an IP
    # lookup made through a tunnel found the exit node.
    "tunneled": tunnel_up() if source == "ip" else None,
    # The timezone at those coordinates, as the geolocation provider reports it.
    # This is what vpn-sync.sh saves as timezone_default, because the system
    # clock is not a safe answer to "where does this machine live" - a previous
    # sync may already have moved it.
    "tz": ip_tz,
}
output_json = json.dumps(out_data)
print(output_json)

# Save to cache for offline use
try:
    os.makedirs(os.path.dirname(CACHE_PATH), exist_ok=True)
    with open(CACHE_PATH, "w") as f:
        f.write(output_json)
except Exception as e:
    log(f"Warning: Failed to write cache: {e}")
