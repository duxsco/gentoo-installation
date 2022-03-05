#!/usr/bin/env bash

# Credits: https://github.com/kdave/btrfsmaintenance

set -euo pipefail

sort -u -k1,1 /etc/fstab | awk '$1 ~ /^UUID=/ && $3 == "btrfs" && $4 !~ /noauto/ {print $2}' | while read -r I; do

    if  mountpoint -q "${I}" && \
        ! (btrfs scrub status "${I}" | grep -q -i "^status:[[:space:]]*running$") && \
        {
            ! (btrfs scrub status "${I}" | grep -q -i "^scrub started:") || \
            [[ $(date -u -d "$(TZ=UTC btrfs scrub status "${I}" | grep -Poi "^scrub started:[[:space:]]*\K.*")" "+%s") -lt $(date -u -d "-28 days" "+%s") ]]
        }
    then
        btrfs scrub start -c3 "${I}"
    fi
done
