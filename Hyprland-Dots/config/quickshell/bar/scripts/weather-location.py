#!/usr/bin/env python3
# Weather script for the Quickshell bar.
# Usage: weather-location.py [city]
#   - If [city] matches VPN_LOCATIONS, those coordinates are used.
#   - Otherwise location comes from IP geolocation.
#
# Data source: Open-Meteo (https://open-meteo.com) — keyless, worldwide,
# returns structured JSON. This replaces the previous weather.com HTML scraper:
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
import sys

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
    "severe": "󰼺",           # nf-md-weather_lightning
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
    """Get (lat, lon, city) from IP address."""
    # Try ip-api.com first (45 req/min for non-commercial)
    try:
        r = requests.get(
            "http://ip-api.com/json/?fields=lat,lon,city,status,message", timeout=5
        )
        data = r.json()
        if data.get("status") == "success":
            return float(data["lat"]), float(data["lon"]), data.get("city", "")
        log(f"ip-api.com error: {data.get('message', 'Unknown error')}")
    except Exception as e:
        log(f"ip-api.com error: {e}")

    # Fallback to ipinfo.io (HTTPS, stricter limits)
    try:
        r = requests.get("https://ipinfo.io", timeout=5)
        data = r.json()
        if "loc" in data:
            lat, lon = data["loc"].split(",")
            return float(lat), float(lon), data.get("city", "")
        log(f"ipinfo.io error: {data.get('error', data)}")
    except Exception as e:
        log(f"ipinfo.io error: {e}")

    return None, None, ""


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


def emit_cached_or_empty(reason):
    """On total failure, reuse the last good cache; else emit empty JSON."""
    log(reason)
    if os.path.exists(CACHE_PATH):
        log("Using cached weather data")
        with open(CACHE_PATH, "r") as f:
            print(f.read())
        sys.exit(0)
    print(json.dumps({"text": "", "alt": "", "tooltip": "", "class": ""}))
    sys.exit(1)


# ---- resolve coordinates -------------------------------------------------
city_arg = sys.argv[1].lower() if len(sys.argv) > 1 else None

ip_city = ""
if city_arg and city_arg in VPN_LOCATIONS:
    latitude, longitude = VPN_LOCATIONS[city_arg]
    location = city_arg.capitalize()
else:
    latitude, longitude, ip_city = get_location()
    location = ip_city
    if latitude is None:
        emit_cached_or_empty("Could not determine location from IP")

# ---- fetch forecast ------------------------------------------------------
try:
    r = requests.get(
        "https://api.open-meteo.com/v1/forecast",
        params={
            "latitude": latitude,
            "longitude": longitude,
            "current": "temperature_2m,relative_humidity_2m,apparent_temperature,"
            "is_day,weather_code,wind_speed_10m",
            "hourly": "precipitation_probability,visibility",
            "daily": "temperature_2m_max,temperature_2m_min",
            "timezone": "auto",
            "forecast_days": 1,
        },
        timeout=10,
    )
    data = r.json()
    cur = data["current"]
except Exception as e:
    emit_cached_or_empty(f"Open-Meteo forecast error: {e}")

if not location:
    location = "Unknown"

temp = int(round(cur["temperature_2m"]))
feels = int(round(cur["apparent_temperature"]))
humidity = int(round(cur["relative_humidity_2m"]))
wind = int(round(cur["wind_speed_10m"]))
is_day = int(cur.get("is_day", 1))
code = int(cur.get("weather_code", -1))

status, category = WMO.get(code, ("Unknown", "default"))
icon_key = ICON_CATEGORY.get((category, is_day), "default")
icon = weather_icons.get(icon_key, weather_icons["default"])

daily = data.get("daily", {})
try:
    temp_max = int(round(daily["temperature_2m_max"][0]))
    temp_min = int(round(daily["temperature_2m_min"][0]))
except (KeyError, IndexError, TypeError):
    temp_max = temp_min = temp

# Align hourly arrays to the current hour
hourly = data.get("hourly", {})
times = hourly.get("time", [])
cur_time = cur.get("time")
start = times.index(cur_time) if cur_time in times else 0

precip_prob = hourly.get("precipitation_probability", [])
rain_slice = [p for p in precip_prob[start:start + 5] if p is not None]
rain_tokens = " ".join(f"Rain drop {int(round(p))}%" for p in rain_slice)

vis_list = hourly.get("visibility", [])
try:
    visibility_km = f"{vis_list[start] / 1000:.1f}"
except (IndexError, TypeError, ZeroDivisionError):
    visibility_km = ""

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
    f"<b>{status}</b>\n"
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
    "tooltip": tooltip,
    "class": icon_key,
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
