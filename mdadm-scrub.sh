#!/usr/bin/env bash

# Credits: martin f. krafft <madduck@debian.org> for the "checkarray" script

set -euo pipefail

if  [ -f /proc/mdstat ] && \
    grep -E '^raid([1456]|10)$' /sys/block/md*/md/level 1>/dev/null 2>&1 && \
    ls /sys/block/md*/md/sync_action 1>/dev/null 2>&1
then
    find /sys/block/md* -exec basename {} \; | while read -r I; do

        LAST_RUN="$(date -u -d "$(TZ=UTC mdadm --detail "/dev/${I}" | grep -Pio "^[[:space:]]*update time[[:space:]]*:[[:space:]]*\K.*")" "+%s")"
        MD_DIR="/sys/block/${I}/md"

        if  [[ ${LAST_RUN} -le $(date -u -d "-28 days" "+%s") ]] && \
            [ -w "${MD_DIR}/sync_action" ] && \
            grep -q "idle" "${MD_DIR}/sync_action" && \
            ! grep -q "read-auto" "${MD_DIR}/array_state"
        then
            echo "check" > "${MD_DIR}/sync_action"

            # shellcheck disable=SC2034
            for TRY in {1..5}; do
                if RESYNC_PID="$(pidof -w "${I}_resync")"; then
                    ionice -p "${RESYNC_PID}" -c3 2>/dev/null || true
                    renice -p "${RESYNC_PID}" -n15 1>/dev/null 2>&1 || true
                    break
                fi
                sleep 1
            done
        fi
    done
fi
