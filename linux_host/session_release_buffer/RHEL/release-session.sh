#!/bin/bash

# Support for RHEL systems

# Set PATH variable
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

LOG_FILE="/var/log/release-session.log"
LOCK_FILE="/tmp/release-session.lockfile"
LOCATION_PATH="/usr/local/bin"
SCRIPT_PATH_TO_CHECK_XRDP_USERS_INFO="$LOCATION_PATH/xrdp-who-xorg.sh"
CURRENT_USERS_DETAILS="$LOCATION_PATH/xrdp-loggedin-users.txt"
PREVIOUS_USERS_FILE="/tmp/previous_users.txt"
hostname=$(hostname)

# Default run mode
RUN_MODE="manual"

# Check for '--cron' argument
for arg in "$@"; do
    if [ "$arg" == "--cron" ]; then
        RUN_MODE="cron"
        break
    fi
done

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [$RUN_MODE] - $1" | tee -a "$LOG_FILE"
}

log "Script started, lock acquired."

trap "log 'Script exiting.'" EXIT INT TERM

get_access_token() {
    local resource="api://YOUR_LINUX_BROKER_API_CLIENT_ID"
    local imds_endpoint="http://169.254.169.254/metadata/identity/oauth2/token"
    local api_version="2018-02-01"
    local uri="$imds_endpoint?api-version=$api_version&resource=$resource"

    local headers="Metadata:true"
    local access_token=$(/usr/bin/curl -s --header "$headers" "$uri" | /usr/bin/jq -r '.access_token')

    if [ "$access_token" == "null" ]; then
        log "ERROR: Failed to obtain access token."
        exit 1
    fi

    echo "$access_token"
}

release_vm() {
    local api_base_url="YOUR_LINUX_BROKER_API_URL"
    local release_vm_url="$api_base_url/vms/$hostname/release"
    local access_token=$(get_access_token)

    if [ -z "$access_token" ]; then
        log "ERROR: Unable to obtain access token."
        exit 1
    fi

    local response=$(/usr/bin/curl -s -w "%{http_code}" -o response.json -X POST "$release_vm_url" \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json")

    local http_status=$(tail -n1 response.json)
    local json_hostname=$(echo "$http_status" | /usr/bin/jq -r '.Hostname')

    if [ "$json_hostname" == "$hostname" ]; then
        log "INFO: Successfully released VM with Hostname: $hostname"
        cat response.json >> "$LOG_FILE"
    else
        log "ERROR: Failed to release VM with Hostname: $hostname (HTTP Status: $http_status)"
        cat response.json >> "$LOG_FILE"
    fi

     local xorg_pid=$(ps h -C Xorg -o pid,user | awk -v user="$username" '$2 == user {print $1}')
     log "Xorg PID for user $username: $xorg_pid"
     if [ -n "$xorg_pid" ]; then
         kill -9 $xorg_pid
         log "Terminated Xorg process $xorg_pid for user $username."
    fi

    rm -f response.json
}

logoff_user() {
    local username=$1

    (
        log "User $username disconnected. Scheduling logoff in 20 minutes."
        sleep 1200

        local is_logged_in=$(loginctl list-users | awk -v user="$username" '$2 == user {print $2}')

        if [ -z "$is_logged_in" ]; then
            local session_ids=$(loginctl list-sessions | grep $username | awk '{print $1}')

            for session_id in $session_ids; do
                loginctl terminate-session $session_id
                log "Logged off user $username session $session_id after 20 minutes delay."
            done

        else
            log "User $username is now logged in. Cancelling scheduled logoff."
        fi
    ) &
}

check_unmount_user_homes() {
    log "Scanning for orphaned mounted user home directories."

    # Get currently logged-in usernames
    mapfile -t logged_in_users < <(loginctl list-users | awk 'NR > 1 {print $2}')

    # Find only top-level /home/<user> mount points of type 'nfs' or 'nfs4'
    while read -r device mountpoint fstype rest; do
        # Match only mountpoints like /home/username (no subdirs)
        if [[ "$mountpoint" =~ ^/home/[^/]+$ ]]; then
            username=$(basename "$mountpoint")
            # Only proceed if user is not logged in
            if [[ ! " ${logged_in_users[*]} " =~ " ${username} " ]]; then
                log "User $username is not logged in. Attempting to unmount $mountpoint"

                if umount -l "$mountpoint"; then
                    log "Successfully unmounted $mountpoint for user $username."
                else
                    log "Failed to unmount $mountpoint for user $username."
                fi
            else
                log "User $username is still logged in. Skipping unmount."
            fi
        fi
    done < <(mount | awk '$5 ~ /^nfs/ {print $1, $3, $5, $6}')
}

while true; do
    log "Checking XRDP session status."

    if ! . $SCRIPT_PATH_TO_CHECK_XRDP_USERS_INFO > $CURRENT_USERS_DETAILS; then
        log "ERROR: Failed to execute $SCRIPT_PATH_TO_CHECK_XRDP_USERS_INFO"
        sleep 60
        continue
    fi

    log "Contents of $CURRENT_USERS_DETAILS:"
    cat $CURRENT_USERS_DETAILS | tee -a "$LOG_FILE"

    current_users=()

    while IFS= read -r line; do
        pid=$(echo $line | awk '{print $1}')
        username=$(echo $line | awk '{print $2}')
        start_time=$(echo $line | awk '{print $3}')
        status=$(echo $line | awk '{print $NF}' | xargs)
        current_users+=("$username")

        if ! [[ -z "$start_time" || "$start_time" == *"START_TIME"* ]]; then
            log "PID: $pid, Username: $username, Start Time: $start_time, Status: $status"
        fi

        if [[ "$status" == *"disconnected"* ]]; then
            log "User $username is disconnected. Calling release_vm and scheduling logoff."
            release_vm
            logoff_user "$username"

            current_users=("${current_users[@]/$username}")
            
            break
        elif [[ "$status" == *"active"* ]]; then
            log "User $username is active. No action to perform."
            break
        fi
    done < "$CURRENT_USERS_DETAILS"

    > $CURRENT_USERS_DETAILS

    if [ -e "$PREVIOUS_USERS_FILE" ]; then
        while IFS= read -r prev_user; do
            if [[ ! " ${current_users[@]} " =~ " ${prev_user} " ]]; then
                log "User $prev_user has no session record. Releasing VM for user $prev_user."
                release_vm
            fi
        done < "$PREVIOUS_USERS_FILE"
    fi

    printf "%s\n" "${current_users[@]}" > "$PREVIOUS_USERS_FILE"

    check_unmount_user_homes
    
    log "Sleeping for 60 seconds before next check."
    sleep 60
done

