#!/usr/bin/env bash

# Credits: martin f. krafft <madduck@debian.org> for the "checkarray" script

# Prevent tainting variables via environment
# See: https://gist.github.com/duxsco/fad211d5828e09d0391f018834f955c9
unset LAST_RUN MD_DEVICE MD_DIR RESYNC_PID

if  [[ -f /proc/mdstat ]] && \
    grep -E '^raid([1456]|10)$' /sys/block/md*/md/level >/dev/null 2>&1 && \
    ls /sys/block/md*/md/sync_action >/dev/null 2>&1
then
    find /sys/block/md* -exec basename {} \; | while read -r MD_DEVICE; do

        LAST_RUN="$(date -u -d "$(TZ=UTC mdadm --detail "/dev/${MD_DEVICE}" | grep -Pio "^[[:space:]]*update time[[:space:]]*:[[:space:]]*\K.*")" "+%s")"
        MD_DIR="/sys/block/${MD_DEVICE}/md"

        if  [[ ${LAST_RUN} -le $(date -u -d "-28 days" "+%s") ]] && \
            [[ -w ${MD_DIR}/sync_action ]] && \
            grep -q "idle" "${MD_DIR}/sync_action" && \
            ! grep -q "read-auto" "${MD_DIR}/array_state"
        then
            echo "check" > "${MD_DIR}/sync_action"

            # shellcheck disable=SC2034
            for TRY in {1..5}; do
                if RESYNC_PID="$(pidof -w "${MD_DEVICE}_resync")"; then
                    ionice -p "${RESYNC_PID}" -c3 >/dev/null 2>&1
                    renice -p "${RESYNC_PID}" -n15 >/dev/null 2>&1
                    break
                fi
                sleep 1
            done
        fi
    done
fi
