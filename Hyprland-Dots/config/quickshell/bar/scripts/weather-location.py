#!/usr/bin/env python3
# Weather script with manual location support
# Usage: weather-location.py [city]
# If no city provided, uses IP-based location

import requests
import json
import os
import sys
from pyquery import PyQuery

# Weather icons (Nerd Font Material Design Icons)
weather_icons = {
    "sunnyDay": "󰖙",      # nf-md-weather_sunny
    "clearNight": "󰖔",    # nf-md-weather_night
    "cloudyFoggyDay": "󰖐", # nf-md-weather_cloudy
    "cloudyFoggyNight": "󰼱", # nf-md-weather_night_partly_cloudy
    "rainyDay": "󰖖",      # nf-md-weather_rainy
    "rainyNight": "󰖖",    # nf-md-weather_rainy
    "snowyIcyDay": "󰼴",   # nf-md-weather_snowy
    "snowyIcyNight": "󰼴",  # nf-md-weather_snowy
    "severe": "󰼺",        # nf-md-weather_lightning
    "default": "󰖐",       # nf-md-weather_cloudy (fallback)
}

# VPN location mappings (city -> coordinates)
VPN_LOCATIONS = {
    "berlin": (52.520008, 13.404954),
    "warsaw": (52.237049, 21.017532),
    "tbilisi": (41.715138, 44.827096),
    "madrid": (40.416775, -3.703790),
    "kyiv": (50.450001, 30.523333),
    "vilnius": (54.687157, 25.279652),
}

# Get location
def get_location():
    """Get location from IP address"""
    # Try ip-api.com first (more generous rate limits: 45/minute for non-commercial)
    try:
        response = requests.get("http://ip-api.com/json/?fields=lat,lon,city,status,message", timeout=5)
        data = response.json()
        if data.get("status") == "success":
            return float(data["lat"]), float(data["lon"]), data.get("city", "")
        else:
            print(f"ip-api.com error: {data.get('message', 'Unknown error')}", file=sys.stderr)
    except Exception as e:
        print(f"ip-api.com error: {e}", file=sys.stderr)

    # Fallback to ipinfo.io (stricter rate limits but HTTPS)
    try:
        response = requests.get("https://ipinfo.io", timeout=5)
        data = response.json()
        if "loc" in data:
            loc = data["loc"].split(",")
            return float(loc[0]), float(loc[1]), data.get("city", "")
        else:
            print(f"ipinfo.io error: {data.get('error', data)}", file=sys.stderr)
    except Exception as e:
        print(f"ipinfo.io error: {e}", file=sys.stderr)

    return None, None, ""

# Check for city argument
city_arg = sys.argv[1].lower() if len(sys.argv) > 1 else None

# Get coordinates
ip_city = ""
if city_arg and city_arg in VPN_LOCATIONS:
    latitude, longitude = VPN_LOCATIONS[city_arg]
else:
    latitude, longitude, ip_city = get_location()
    if latitude is None:
        # Fallback to cached data if available
        cache_path = os.path.expanduser("~/.cache/quickshell/weather.json")
        if os.path.exists(cache_path):
            with open(cache_path, "r") as f:
                print(f.read())
                sys.exit(0)
        else:
            print(json.dumps({"text": "", "alt": "", "tooltip": "", "class": ""}))
            sys.exit(1)

# Weather.com API endpoint
url = f"https://weather.com/en-PH/weather/today/l/{latitude},{longitude}"

try:
    html_data = PyQuery(url=url)

    # Location name - use argument if provided, otherwise parse from HTML
    if city_arg and city_arg in VPN_LOCATIONS:
        location = city_arg.capitalize()
        location_short = location
    else:
        location = html_data("h1[class*='CurrentConditions--location']").text()
        location_parts = location.split(",") if location else []
        location_short = location_parts[1].split()[0] if len(location_parts) > 1 else location_parts[0] if location_parts else ""
        # Fallback to IP geolocation city if weather.com didn't return one
        if not location_short and ip_city:
            location_short = ip_city
        if not location and ip_city:
            location = ip_city

    # Current temperature
    temp = html_data("span[data-testid='TemperatureValue']").eq(0).text()

    # Current status phrase
    status = html_data("div[data-testid='wxPhrase']").text()

    # Status code - get from weather icon SVG name attribute
    wx_icon = html_data("svg[class*='CurrentConditions--wxIcon']").attr("name")

    # Map weather.com icon names to our status codes
    icon_name_map = {
        "sunny": "sunnyDay",
        "clear-day": "sunnyDay",
        "clear-night": "clearNight",
        "mostly-clear-night": "clearNight",
        "cloudy": "cloudyFoggyDay",
        "mostly-cloudy-day": "cloudyFoggyDay",
        "mostly-cloudy-night": "cloudyFoggyNight",
        "partly-cloudy-day": "cloudyFoggyDay",
        "partly-cloudy-night": "cloudyFoggyNight",
        "fog": "cloudyFoggyDay",
        "haze": "cloudyFoggyDay",
        "rain": "rainyDay",
        "scattered-showers-day": "rainyDay",
        "scattered-showers-night": "rainyNight",
        "showers-day": "rainyDay",
        "showers-night": "rainyNight",
        "thunderstorm": "rainyDay",
        "snow": "snowyIcyDay",
        "snow-showers": "snowyIcyDay",
        "sleet": "snowyIcyDay",
        "ice": "snowyIcyDay",
        "winter-mix": "snowyIcyDay",
        "tornado": "severe",
        "hurricane": "severe",
    }

    status_code = icon_name_map.get(wx_icon, "default")
    icon = weather_icons.get(status_code, weather_icons["default"])

    # Temperature feels like
    temp_feel = html_data(
        "div[data-testid='FeelsLikeSection'] > span > span[data-testid='TemperatureValue']"
    ).text()
    temp_feel_text = f"Feels like {temp_feel}c"

    # Min-max temperature
    temp_min = (
        html_data("div[data-testid='wxData'] > span[data-testid='TemperatureValue']")
        .eq(1)
        .text()
    )
    temp_max = (
        html_data("div[data-testid='wxData'] > span[data-testid='TemperatureValue']")
        .eq(0)
        .text()
    )
    temp_min_max = f"  {temp_min}\t\t  {temp_max}"

    # Wind speed
    wind_speed = str(html_data("span[data-testid='Wind'] > span").text())
    wind_text = f"  {wind_speed}"

    # Humidity
    humidity = html_data("span[data-testid='PercentageValue']").text()
    humidity_text = f"  {humidity}"

    # Visibility
    visibility = html_data("span[data-testid='VisibilityValue']").text()
    visibility_text = f"  {visibility}"

    # Air quality index
    air_quality_index = html_data("text[data-testid='DonutChartValue']").text()

    # Hourly rain prediction
    prediction = html_data("section[aria-label='Hourly Forecast']")(
        "div[data-testid='SegmentPrecipPercentage'] > span"
    ).text()
    prediction = prediction.replace("Chance of Rain", "")
    prediction = f"\n\n (hourly) {prediction}" if len(prediction) > 0 else prediction

    # Tooltip text
    tooltip_text = str.format(
        "{}\n\t\t{}\t\t\n{}\n{}\n{}\n\n{}\n{}\n{}{}",
        f"<b>{location}</b>",
        f'<span size="xx-large">{temp}</span>',
        f"<big> {icon}</big>",
        f"<b>{status}</b>",
        f"<small>{temp_feel_text}</small>",
        f"<b>{temp_min_max}</b>",
        f"{wind_text}\t{humidity_text}",
        f"{visibility_text}\tAQI {air_quality_index}",
        f"<i> {prediction}</i>",
    )

    # Print waybar module data
    out_data = {
        "text": f"{icon}  {temp} {location_short}",
        "alt": status,
        "tooltip": tooltip_text,
        "class": status_code,
    }
    output_json = json.dumps(out_data)
    print(output_json)

    # Save to cache for offline use
    try:
        cache_path = os.path.expanduser("~/.cache/quickshell/weather.json")
        os.makedirs(os.path.dirname(cache_path), exist_ok=True)
        with open(cache_path, "w") as f:
            f.write(output_json)
    except Exception as e:
        print(f"Warning: Failed to write cache: {e}", file=sys.stderr)

except Exception as e:
    # On error, try to use cached data
    print(f"Weather fetch error: {e}", file=sys.stderr)
    import traceback
    traceback.print_exc(file=sys.stderr)
    cache_path = os.path.expanduser("~/.cache/quickshell/weather.json")
    if os.path.exists(cache_path):
        print("Using cached weather data", file=sys.stderr)
        with open(cache_path, "r") as f:
            print(f.read())
    else:
        print("No cache available", file=sys.stderr)
        print(json.dumps({"text": "", "alt": "", "tooltip": "", "class": ""}))
    sys.exit(1)
