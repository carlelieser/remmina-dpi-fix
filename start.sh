#!/bin/bash

set -a && source .env && set +a

KEYS=()

if [ ! -f keys.txt ]; then
	PREFS=$(sudo -k cat "$PREFS_FILE")

	while IFS= read -r pair; do
	    if [[ $pair =~ \[.*\] ]]; then
		continue
	    fi

	    KEYS+=("$(echo "$pair" | awk -F'=' '{print $1}')")
	done <<< "$PREFS"

	rm -f keys.txt

	echo "${KEYS[*]}" > keys.txt
fi

KEYS=($(cat keys.txt))

MONITOR_DATA_SOURCE=$(gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig --method org.gnome.Mutter.DisplayConfig.GetCurrentState)
MONITOR_DATA=$(echo "$MONITOR_DATA_SOURCE" | grep -oP "\('[0-9]+x[0-9]+@[0-9]+\.[0-9]+', [0-9]+, [0-9]+, [0-9]+\.[0-9]+" | head -n 1)

DEFAULT_INTERFACE=$(echo "$MONITOR_DATA_SOURCE" | grep -oP "\('[a-zA-Z0-9-]+', 'SDC'" | awk -F\' '{print $2}' | head -n 1)
DEFAULT_RESOLUTION=$(echo "$MONITOR_DATA" | awk -F'@' '{print $1}' | awk -F\' '{print $2}')
DEFAULT_REFRESH_RATE=$(echo "$MONITOR_DATA" | awk -F'@' '{print $2}' | awk -F\' '{print $1}')
DEFAULT_SCALE_FACTOR=$(echo "$MONITOR_DATA_SOURCE" | awk -F'legacy-ui-scaling-factor' '{print $2}' | awk -F'[<>]' '{for(i=2; i<=NF; i+=2) print $i}')

INTERFACE=${INTERFACE:-$DEFAULT_INTERFACE}
RESOLUTION=${RESOLUTION:-$DEFAULT_RESOLUTION}
REFRESH_RATE=${REFRESH_RATE:-$DEFAULT_REFRESH_RATE}
SCALE_FACTOR=${SCALE_FACTOR:-$DEFAULT_SCALE_FACTOR}
PROFILE="$RESOLUTION@$REFRESH_RATE"

OPTIONS=($(ls $CONNECTIONS_DIR))

config=()
arrow_right="\e[32m→\e[0m"

apply_scale_factor() {
	gdbus call --session --dest=org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig --method org.gnome.Mutter.DisplayConfig.ApplyMonitorsConfig 1 1 "[(0, 0, $TEMP_SCALE_FACTOR, 0, true, [('$INTERFACE', '$PROFILE', [] )] )]" "[]"
}

restore_scale_factor() {
	gdbus call --session --dest=org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig --method org.gnome.Mutter.DisplayConfig.ApplyMonitorsConfig 1 1 "[(0, 0, $SCALE_FACTOR, 0, true, [('$INTERFACE', '$PROFILE', [] )] )]" "[]"
}

backup_prefs_file() {
	if [ ! -f "$PREFS_BACKUP_FILE" ]; then
		cp "$PREFS_FILE" "$PREFS_BACKUP_FILE"
	fi
}

restore_prefs_file() {
	if [ -f "$PREFS_BACKUP_FILE" ]; then
		mv "$PREFS_BACKUP_FILE" "$PREFS_FILE"
	fi
}

cleanup(){
	restore_scale_factor
	restore_prefs_file
	echo "👋 Bye"
}

is_global_config() {
	local key=$1
	for global_key in "${KEYS[@]}"; do
	if [[ $key == "$global_key" ]]; then
	    return 0
	fi
	done
	return 1
}

modify_global_setting() {
    local key=$1
    local value=$2

	backup_prefs_file

    echo -e "$arrow_right Modifying global setting '$key'..."
    if grep -q "^$key=" "$PREFS_FILE"; then
        sed -i "s|^$key=.*|$key=$value|" "$PREFS_FILE"
    else
        echo "$key=$value" >> "$PREFS_FILE"
    fi
}

process_argument() {
    local arg=$1
    local key="${arg%%=*}"
    local value="${arg#*=}"

    if is_global_config "$key"; then
        modify_global_setting "$key" "$value"
    else
        config+=("--set-option $arg")
    fi
}

trap cleanup SIGINT SIGTERM

echo "🚀 Starting..."

killall remmina > /dev/null 2>&1 &

if [ ${#OPTIONS[@]} -eq 0 ]; then
	echo -e "$arrow_right No connections found! Please check the REMMINA_CONNECTIONS_DIR environment variable or add a connection."
	cleanup
	exit 1
fi

echo -e "$arrow_right Choose a connection:"

select opt in "${OPTIONS[@]}" "Cancel"; do
    case $opt in
        "Cancel")
            cleanup
            exit 0
            ;;
        *)
            if [ -n "$opt" ]; then
                break
            else
                echo "🚫 Invalid option $REPLY"
                exit 1
            fi
            ;;
    esac
done

REMMINA_PROFILE_PATH="$CONNECTIONS_DIR/$opt"

apply_scale_factor

sleep 1

if [ $# -gt 0 ]; then
    for arg in "$@"; do
        if [[ $arg == *=* ]]; then
            process_argument "$arg"
        else
            echo "⚠️ Warning: Skipping invalid argument '$arg'. Expected format key=value."
        fi
    done

    commands=$(IFS=' '; echo "${config[*]}")

    remmina $commands --update-profile $REMMINA_PROFILE_PATH
fi

remmina --set-option postcommand="killall remmina" --update-profile $REMMINA_PROFILE_PATH &
remmina $REMMINA_PROFILE_PATH

cleanup

exit 0