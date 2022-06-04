#!/usr/bin/env bash

# Prevent tainting variables via environment
# See: https://gist.github.com/duxsco/fad211d5828e09d0391f018834f955c9
unset current_stage3 temp_gpg_homedir

function gpg_verify() {
    grep -q "^GOODSIG TRUST_ULTIMATE VALIDSIG$" < <(
        gpg --homedir "${temp_gpg_homedir}" --status-fd 1 --verify "$1" "$2" 2>/dev/null | \
        grep -Po "^\[GNUPG:\][[:space:]]+\K(GOODSIG|VALIDSIG|TRUST_ULTIMATE)(?=[[:space:]])" | \
        sort | \
        paste -d " " -s -
    )
}

pushd /mnt/gentoo || (echo 'Failed to move to directory "/mnt/gentoo"! Aborting...' >&2; exit 1)

temp_gpg_homedir="$(mktemp -d)"

# prepare gnupg
if  gpg --homedir "${temp_gpg_homedir}" \
        --auto-key-locate clear,hkps://keys.gentoo.org,wkd \
        --locate-external-keys infrastructure@gentoo.org releng@gentoo.org >/dev/null 2>&1
then
    echo -e "13EBBDBEDE7A12775DFDB1BABB572E0E2D182910:6:\nDCD05B71EAB94199527F44ACDB6B8C1F96D8BF6D:6:" | \
        gpg --homedir "${temp_gpg_homedir}" --import-ownertrust --quiet
else
    echo "Failed to fetch GnuPG public keys! Aborting..." >&2
    exit 1
fi

# fetch tarballs
if ! current_stage3="$(
        grep -Po "^[0-9]{8}T[0-9]{6}Z/[^[:space:]]+" < <(
            curl \
                --fail --silent --show-error --location \
                --proto '=https' --tlsv1.3 \
                "https://mirror.leaseweb.com/gentoo/releases/amd64/autobuilds/latest-stage3-amd64-systemd.txt"
        )
    )"
then
    echo "Failed to fetch stage3 tarball info! Aborting..." >&2
    exit 1
elif ! curl \
        --fail --silent --show-error --location \
        --proto '=https' --tlsv1.3 \
        --remote-name-all \
        "https://mirror.leaseweb.com/gentoo/releases/amd64/autobuilds/${current_stage3}{,.asc}" \
        "https://mirror.leaseweb.com/gentoo/snapshots/portage-latest.tar.xz{,.gpgsig}"
then
    echo "Failed to fetch files! Aborting..." >&2
    exit 1
fi

# gnupg verify
if  ! gpg_verify "${current_stage3##*/}.asc" "${current_stage3##*/}" || \
    ! gpg_verify portage-latest.tar.xz.gpgsig portage-latest.tar.xz
then
    echo "Failed to verify GnuPG signature! Aborting..." >&2
    exit 1
fi

gpgconf --homedir "${temp_gpg_homedir}" --kill all

popd || (echo 'Failed to move out of directory "/mnt/gentoo"! Aborting...' >&2; exit 1)
