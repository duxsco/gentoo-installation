#!/usr/bin/env bash

# Credits: https://github.com/kdave/btrfsmaintenance

sort -u -k1,1 /etc/fstab | awk '$1 ~ /^UUID=/ && $3 == "btrfs" && $4 !~ /noauto/ {print $2}' | while read -r MOUNTPOINT; do

    if  mountpoint --quiet "${MOUNTPOINT}" && \
        ! grep -q -i "^status:[[:space:]]*running$" < <(btrfs scrub status "${MOUNTPOINT}") && \
        {
            ! grep -q -i "^scrub started:" < <(btrfs scrub status "${MOUNTPOINT}") || \
            [[ $(date -u -d "$(TZ=UTC btrfs scrub status "${MOUNTPOINT}" | grep -Poi "^scrub started:[[:space:]]*\K.*")" "+%s") -lt $(date -u -d "-28 days" "+%s") ]]
        }
    then
        btrfs scrub start -c3 "${MOUNTPOINT}"
    fi
done
