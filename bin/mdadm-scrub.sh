#!/usr/bin/env bash

# Credits: martin f. krafft <madduck@debian.org> for the "checkarray" script

# Prevent tainting variables via environment
# See: https://gist.github.com/duxsco/fad211d5828e09d0391f018834f955c9
unset last_run md_device md_dir resync_pid

if  [[ -f /proc/mdstat ]] && \
    grep -E '^raid([1456]|10)$' /sys/block/md*/md/level >/dev/null 2>&1 && \
    ls /sys/block/md*/md/sync_action >/dev/null 2>&1
then
    while read -r md_device; do

        last_run="$(date -u -d "$(TZ=UTC mdadm --detail "/dev/${md_device}" | grep -Pio "^[[:space:]]*update time[[:space:]]*:[[:space:]]*\K.*")" "+%s")"
        md_dir="/sys/block/${md_device}/md"

        if  [[ ${last_run} -le $(date -u -d "-28 days" "+%s") ]] && \
            [[ -w ${md_dir}/sync_action ]] && \
            grep -q "idle" "${md_dir}/sync_action" && \
            ! grep -q "read-auto" "${md_dir}/array_state"
        then
            echo "check" > "${md_dir}/sync_action"

            # shellcheck disable=SC2034
            for TRY in {1..5}; do
                if resync_pid="$(pidof -w "${md_device}_resync")"; then
                    ionice -p "${resync_pid}" -c3 >/dev/null 2>&1
                    renice -p "${resync_pid}" -n15 >/dev/null 2>&1
                    break
                fi
                sleep 1
            done
        fi
    done < <(find /sys/block/md* -exec basename {} \;)
fi
