#!/bin/bash

# --------------------------------
# CONFIGURATION
# --------------------------------
API_URL="https://www.groundctl.com/api/v1/launchpads/find/all?api_key=YOUR API KEY"
ALERT_SOUND="/System/Library/Sounds/Funk.aiff"
TARGET_EMAIL="YOUR EMAIL"
OUTPUT_FILE="/File Location/Prod_LPs.txt"
STATUS_FILE="/File Location/status.txt"

rm "$OUTPUT_FILE"
rm "$STATUS_FILE"

# --------------------------------
# Check Internet Connectivity
# --------------------------------
echo "🌐 Checking internet connectivity..."
if ! ping -c 1 -W 1 google.com >/dev/null 2>&1; then
    echo "❌ No internet connection detected. Aborting script." > $STATUS_FILE
    exit 1
fi
echo "✅ Internet connection OK. Continuing..."

# --------------------------------
# Check for jq
# --------------------------------
if ! command -v jq >/dev/null 2>&1; then
    echo "❌ Error: 'jq' is not installed. Please install it with 'brew install jq' and try again." > "$STATUS_FILE"
    exit 1
fi

# --------------------------------
# Call API
# --------------------------------
echo "📡 Fetching launchpad data..."
response=$(curl -s -f -X GET "$API_URL" -H "accept: application/json")
if [ $? -ne 0 ]; then
    echo "❌ Error: Failed to fetch data from API." > "$STATUS_FILE"
    exit 1
fi


# --------------------------------
# Output normal list (filtered by email)
# --------------------------------
#echo "📝 Creating list for PROD Launchpads..."
#echo "$response" | jq -r --arg email "$TARGET_EMAIL" '
#    map(select(. | tostring | contains($email)))
#    | .[]
#    | .name' | tee "$OUTPUT_FILE"
#echo "✅ Launchpad names saved to $OUTPUT_FILE"

# --------------------------------
# Head count of PROD Launchpads
# --------------------------------
count=$(echo "$response" | jq --arg email "$TARGET_EMAIL" '
  map(select(. | tostring | contains($email)))
  | length
')
echo "💻 $count Launchpads found."

# --------------------------------
# Check for alert conditions + explain why
# --------------------------------
ALERT_CACHE_DIR="/Users/brianirish/scripts/lpstatus/.alerts"
mkdir -p "$ALERT_CACHE_DIR"

alerts=""

IFS=$'\n'
launchpads=$(echo "$response" | jq -r --arg email "$TARGET_EMAIL" '
  map(select(. | tostring | contains($email)))
  | map("\(.name)|\(.connected)|\(.connectedDeviceCount)|\(.connectedBadgeReader)") 
  | .[]')

for entry in $launchpads; do
    IFS="|" read -r name connected connectedDeviceCount connectedBadgeReader <<< "$entry"

    reasons=""

    # Check no smarthub
    if [ "$connected" = "false" ]; then
        reasons="No smarthub"
    fi

    # Check no devices, but suppress if within 4 hours
    if [ "$connectedDeviceCount" -lt 1 ]; then
        alert_file="$ALERT_CACHE_DIR/$(echo "$name" | tr ' /' '_')"
        now=$(date +%s)
        if [ -f "$alert_file" ]; then
            last_alert=$(stat -f %m "$alert_file")
            elapsed=$((now - last_alert))
        else
            elapsed=999999
        fi

        if [ $elapsed -ge 14400 ]; then
            reasons="${reasons:+$reasons, }No devices"
            touch "$alert_file"
        fi
    fi

    # Check no badge reader
    if [ "$connectedBadgeReader" = "null" ]; then
        reasons="${reasons:+$reasons, }No badge reader"
    fi

    # Append to alerts if any reason found
    if [ -n "$reasons" ]; then
        alerts="${alerts}${name}: ${reasons}\n"
    fi
done

if [ -n "$alerts" ]; then
    echo "🚨 ALERT triggered!"
    echo "🚨 ALERT triggered!" > "$STATUS_FILE"
    afplay "$ALERT_SOUND"
    osascript -e "display dialog \"1 or more launchpads require your attention:\n\n$alerts\" buttons {\"OK\"} default button 1 with title \"GroundControl Launchpad Monitor\" giving up after 30"
else
   echo "👍🏻 All systems seem healthy."
   echo "👍🏻 All clear!" > "$STATUS_FILE"
fi
