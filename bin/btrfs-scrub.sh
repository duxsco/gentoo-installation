#!/usr/bin/env bash

# Credits: https://github.com/kdave/btrfsmaintenance

while read -r mountpoint; do

    if  mountpoint --quiet "${mountpoint}" && \
        ! grep -q -i "^status:[[:space:]]*running$" < <(btrfs scrub status "${mountpoint}") && \
        {
            ! grep -q -i "^scrub started:" < <(btrfs scrub status "${mountpoint}") || \
            [[ $(date -u -d "$(TZ=UTC btrfs scrub status "${mountpoint}" | grep -Poi "^scrub started:[[:space:]]*\K.*")" "+%s") -lt $(date -u -d "-28 days" "+%s") ]]
        }
    then
        btrfs scrub start -c3 "${mountpoint}"
    fi
done < <(sort -u -k1,1 /etc/fstab | awk '$1 ~ /^UUID=/ && $3 == "btrfs" && $4 !~ /noauto/ {print $2}')
