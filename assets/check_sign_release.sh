#!/usr/bin/env bash

declare -A url

json="$(curl -fsSL --proto '=https' --tlsv1.3 https://api.github.com/repos/duxsco/gentoo-installation/releases/latest)"
tag_name="$(jq -r '.tag_name' <<< "${json}")"
url[tar.gz]="https://github.com/duxsco/gentoo-installation/archive/refs/tags/${tag_name}.tar.gz"
url[zip]="https://github.com/duxsco/gentoo-installation/archive/refs/tags/${tag_name}.zip"
draft_status="$(jq -r '.draft' <<< "${json}")"
release_status="$(jq -r '.prerelease' <<< "${json}")"

if [[ ${draft_status} != false ]] ||  [[ ${release_status} != false ]]; then
    printf 'Draft and/or pre-release found for release with tag "%s"! Aborting...\n' "${tag_name}"
    exit 1
fi

read -r -p "Do you want to do the magic on the following two links?
\"${url[tar.gz]}\"
\"${url[zip]}\"

Your answer [y/N]: " magic

if [[ ${magic,,} != y ]]; then
    printf 'Not continuing!\n'
    exit 0
fi

temp_dir="$(mktemp -d)"

pushd "${temp_dir}" >/dev/null || {
    printf 'Failed to switch to directory "%s"! Aborting...\n' "${temp_dir}"
    exit 1
}

for file_type in "${!url[@]}"; do
    file="gentoo-installation-${tag_name#v}.${file_type}"
    curl -fsSL -o "${file}" --proto '=https' --tlsv1.3 "${url[${file_type}]}"

    mkdir "${file_type}"

    case "${file_type}" in
        tar\.gz) tar -C "./${file_type}/" -xf "${file}";;
        zip) unzip -d "./${file_type}/" -q "${file}";;
    esac

    printf '\n❯ rsync -HAXncav --delete --exclude=/site --exclude=/.git "%s" ~/00_github/gentoo-installation/ | grep -v "/$"\n' "./${file_type}/gentoo-installation-${tag_name#v}/"
    rsync -HAXncav --delete --exclude=/site --exclude=/.git "./${file_type}/gentoo-installation-${tag_name#v}/" ~/00_github/gentoo-installation/ | grep -v "/$"

    printf '\n❯ find "%s" -name "\.git" -o -name "site"\n' "./${file_type}/"
    find "./${file_type}/" -name "\.git" -o -name "site"
    echo ""

    read -r -p "Continue? [y/N] " continue

    if [[ ${continue,,} != y ]]; then
        printf "Not continuing!\n"
        exit 0
    fi

    echo ""

    sha256sum "${file}" > "${file}.sha256"
    sha512sum "${file}" > "${file}.sha512"

    gpg --armor --detach-sign "${file}.sha256"
    gpg --armor --detach-sign "${file}.sha512"

    printf '\n❯ sha256sum -c "%s.sha256\n' "${file}"
    sha256sum -c "${file}.sha256"

    printf '\n❯ sha512sum -c "%s.sha512\n' "${file}"
    sha512sum -c "${file}.sha512"

    printf '\n❯ gpg --verify "%s.sha256.asc" "%s.sha256"\n' "${file}" "${file}"
    gpg --verify "${file}.sha256.asc" "${file}.sha256"

    printf '\n❯ gpg --verify "%s.sha512.asc" "%s.sha512"\n' "${file}" "${file}"
    gpg --verify "${file}.sha512.asc" "${file}.sha512"
done

popd >/dev/null || {
    printf 'Failed to leave directory "%s"! Aborting...\n' "${temp_dir}/${file_type}"
    exit 1
}

printf '\n\e[1;32mSuccess!\e[0m Location: %s\n' "${temp_dir}"
