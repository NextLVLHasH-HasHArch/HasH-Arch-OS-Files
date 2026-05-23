#!/usr/bin/env bash
# hash-weather-sync — keep the LOCK SCREEN and SDDM LOGIN weather correct.
#
# Neither greeter can be trusted to do its own HTTP/own config read:
#   - the kscreenlocker greeter runs as the user but is sandboxed for network,
#   - the SDDM greeter runs as the `sddm` user and cannot read ~/.config at all.
# So we do the work HERE, in the live user session (network + config access):
#   1. READ the user's DESKTOP matrixrain config (location, lat/lon, units,
#      clock) — no hardcoded location anymore.
#   2. FETCH live weather for that location.
#   3. WRITE the resolved config to:
#        - kscreenlockerrc                  (lock screen, user-readable)
#        - /var/lib/hash/weather.json       (SDDM greeter, world-readable)
#
# Runs from a user timer (boot + every 15 min). Safe to run by hand.
set -uo pipefail

DESK_FILE=plasma-org.kde.plasma.desktop-appletsrc
SHARED=/var/lib/hash/weather.json

# ---- 1. read the desktop matrixrain config (first containment that has it) ----
read_desktop_key() {  # $1=key  -> first non-empty value across containments
    local key="$1" cid val
    for cid in $(seq 1 12); do
        val="$(kreadconfig6 --file "$DESK_FILE" \
                 --group Containments --group "$cid" --group Wallpaper \
                 --group com.hash.matrixrain --group General --key "$key" 2>/dev/null)"
        [ -n "$val" ] && { printf '%s' "$val"; return 0; }
    done
    return 1
}

LOCATION="$(read_desktop_key locationName  || echo 'Manchester, GB')"
LAT="$(read_desktop_key fixedLatitude       || echo 53.4808)"
LON="$(read_desktop_key fixedLongitude      || echo -2.2426)"
UNITS="$(read_desktop_key units             || echo metric)"
SHOWINFO="$(read_desktop_key showInfo       || echo true)"

[ "$UNITS" = "imperial" ] && TUNIT=fahrenheit || TUNIT=celsius

# ---- 2. fetch live weather for that location ----
# UK gets BBC Weather (Met Office observed conditions — far more accurate than a
# global model, which over-reports high cirrus as "overcast"). Everywhere else
# falls back to open-meteo. is_day always comes from open-meteo (tiny, reliable).
desc=""; source="open-meteo"

isday="$(curl -fsS --max-time 10 \
  "https://api.open-meteo.com/v1/forecast?latitude=${LAT}&longitude=${LON}&current=is_day&timezone=auto" \
  2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin).get("current",{}).get("is_day",1))' 2>/dev/null)"
isday="${isday:-1}"

# Resolve the geonames ID (== BBC location ID) + country for the configured place,
# choosing the geocoder result closest to the configured lat/lon.
QUERY="${LOCATION%%,*}"
geo="$(curl -fsS --max-time 12 \
  "https://geocoding-api.open-meteo.com/v1/search?count=10&language=en&name=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$QUERY")" \
  2>/dev/null)"
read -r GID CC <<<"$(printf '%s' "$geo" | LAT="$LAT" LON="$LON" python3 -c '
import sys, json, os
lat=float(os.environ["LAT"]); lon=float(os.environ["LON"])
res=json.load(sys.stdin).get("results",[]) or []
best=None; bd=1e18
for r in res:
    d=(r.get("latitude",1e3)-lat)**2 + (r.get("longitude",1e3)-lon)**2
    if d<bd: bd=d; best=r
if best: print(best.get("id",""), best.get("country_code",""))
' 2>/dev/null)"

cond=""; temp=""
if [ "$CC" = "GB" ] && [ -n "${GID:-}" ]; then
    # ---- BBC Weather (UK) ----
    bbc="$(curl -fsS --max-time 15 "https://weather-broker-cdn.api.bbci.co.uk/en/forecast/aggregated/${GID}" 2>/dev/null)"
    read -r wtype temp desc <<<"$(printf '%s' "$bbc" | UNITS="$UNITS" python3 -c '
import sys, json, os
j=json.load(sys.stdin); rep=j["forecasts"][0]["detailed"]["reports"][0]
t=rep.get("temperatureC") if os.environ.get("UNITS")!="imperial" else rep.get("temperatureF")
print(rep.get("weatherType",-1), t, (rep.get("enhancedWeatherDescription") or "").replace(" ","_") or "_")
' 2>/dev/null)"
    if [ -n "${wtype:-}" ] && [ "$wtype" != "-1" ]; then
        # BBC weatherType -> the wallpaper's condition vocabulary
        case "$wtype" in
          0)                 cond="night" ;;                 # clear night
          1)                 cond="sun" ;;                   # sunny
          2)                 cond="night" ;;                 # partly cloudy (night)
          3)                 cond="sun" ;;                   # sunny intervals (mostly clear)
          5|6)               cond="fog" ;;                   # mist / fog
          7)                 cond="clouds" ;;                # light / white cloud
          8)                 cond="clouds" ;;                # thick / grey / overcast
          9|10|11|12|13|14|15)  cond="rain" ;;
          16|17|18|19|20|21)    cond="rain" ;;               # sleet / hail
          22|23|24|25|26|27)    cond="snow" ;;
          28|29|30)             cond="thunder" ;;
          *)                 cond="clouds" ;;
        esac
        [ "$isday" = "0" ] && [ "$cond" = "sun" ] && cond="night"
        source="BBC"
    fi
fi

if [ -z "$cond" ]; then
    # ---- open-meteo fallback (non-UK, or BBC unavailable) ----
    api="https://api.open-meteo.com/v1/forecast?latitude=${LAT}&longitude=${LON}&current=temperature_2m,weather_code,cloud_cover&temperature_unit=${TUNIT}&timezone=auto"
    json="$(curl -fsS --max-time 15 "$api" 2>/dev/null)" || { echo "weather fetch failed"; exit 1; }
    read -r code temp cloud <<<"$(printf '%s' "$json" | python3 -c '
import sys, json
c = json.load(sys.stdin).get("current", {})
print(c.get("weather_code", -1), c.get("temperature_2m", "nan"), c.get("cloud_cover", -1))
' 2>/dev/null)"
    [ -z "${code:-}" ] && { echo "parse failed"; exit 1; }
    cond="clouds"
    case "$code" in
      0|1)            [ "$isday" = "1" ] && cond="sun" || cond="night"
                      # clear code but real cloud_cover high -> show clouds
                      [ "${cloud:-0}" -ge 60 ] 2>/dev/null && cond="clouds" ;;
      2)              # partly cloudy: use real cloud_cover to decide
                      if [ "${cloud:-0}" -lt 45 ] 2>/dev/null; then
                          [ "$isday" = "1" ] && cond="sun" || cond="night"
                      else cond="clouds"; fi ;;
      3)              cond="clouds" ;;
      45|48)          cond="fog" ;;
      51|53|55|56|57|61|63|65|66|67|80|81|82) cond="rain" ;;
      71|73|75|77|85|86) cond="snow" ;;
      95|96|97|99)    cond="thunder" ;;
    esac
fi
[ -z "${temp:-}" ] && temp="nan"

# ---- 3a. write the lock screen config (kscreenlockerrc) ----
grp=(--file kscreenlockerrc --group Greeter --group Wallpaper --group com.hash.matrixrain --group General)
# NB: values are passed after `--` so negative numbers (longitude) aren't
# mistaken for options by kwriteconfig6.
kwriteconfig6 "${grp[@]}" --key locationName      -- "$LOCATION"
kwriteconfig6 "${grp[@]}" --key fixedLatitude     -- "$LAT"
kwriteconfig6 "${grp[@]}" --key fixedLongitude    -- "$LON"
kwriteconfig6 "${grp[@]}" --key units             -- "$UNITS"
kwriteconfig6 "${grp[@]}" --key forceCondition    -- "$cond"
kwriteconfig6 "${grp[@]}" --key cachedTemperature -- "$temp"
kwriteconfig6 "${grp[@]}" --key cachedPlace       -- "$LOCATION"
kwriteconfig6 "${grp[@]}" --key showInfo          -- "$SHOWINFO"
kwriteconfig6 "${grp[@]}" --key showClock         -- "true"   # KDE draws its own lock clock

# ---- 3b. write the SDDM greeter shared file (/var/lib/hash/weather.json) ----
if [ -w "$(dirname "$SHARED")" ] || [ -w "$SHARED" ]; then
    tmp="$(mktemp)"
    descTxt="${desc//_/ }"; [ "$descTxt" = " " ] && descTxt=""
    printf '{"locationName":"%s","latitude":%s,"longitude":%s,"units":"%s","condition":"%s","temperature":%s,"isDay":%s,"description":"%s","source":"%s"}\n' \
        "$LOCATION" "$LAT" "$LON" "$UNITS" "$cond" "$temp" "$isday" "$descTxt" "$source" > "$tmp"
    mv -f "$tmp" "$SHARED" 2>/dev/null && chmod 644 "$SHARED" 2>/dev/null \
        && echo "wrote $SHARED" \
        || echo "note: could not write $SHARED (run the one-time root setup to create /var/lib/hash owned by you)"
else
    echo "note: $(dirname "$SHARED") not writable — run the one-time root setup"
fi

echo "weather synced [$source]: $cond (${desc//_/ }) ${temp}° day=$isday @ $LOCATION [$LAT,$LON]"
