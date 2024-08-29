#!/bin/bash

if [[ $(id -u) -ne 0 ]]; then
	echo "Run it as root"
	exit 1
fi

set -a && source .env && set +a

PREFS_FILE="$PREFS_DIR/remmina.pref"
KEYS=($(sudo cat $PREFS_FILE | awk -F'=' '{print $1}'))

echo "${KEYS[@]}" > keys.txt