#!/usr/bin/env bash

# Prevent tainting variables via environment
# See: https://gist.github.com/duxsco/fad211d5828e09d0391f018834f955c9
unset denials denials_context denials_relevant dmesg_denials index ino_number ino_objects ino_tcontext line policy_name

if [[ ! -d ${HOME}/my_selinux_policies ]]; then
    printf 'Folder "%s" doesn'\''t exist! Aborting...\n' "${HOME}/my_selinux_policies" >&2
    exit 1
fi

dmesg_denials="$(mktemp)"
dmesg | grep -E "[[:space:]]+type=(1400|1107)[[:space:]]+.*[[:space:]]+avc:[[:space:]]+denied[[:space:]]+" > "${dmesg_denials}"

denials=""

if [[ -s ${dmesg_denials} ]]; then
    while read -r denials_context; do
        sed -i "0,/.*${denials_context}.*/s//----\n&/" "${dmesg_denials}"
    done < <(
        grep -Po "[[:space:]]+\Kscontext=[^[:space:]]+[[:space:]]+tcontext=[^[:space:]]+" "${dmesg_denials}" | \
        sort -u
    )

    denials="$(<"${dmesg_denials}")
"
fi

denials="${denials}$(ausearch --message AVC,USER_AVC --start boot)"

if [[ -n ${denials} ]]; then
    while read -r denials_context; do
        if index="10#$(grep -m 1 -Po "^${HOME}/my_selinux_policies/my-\K[0-9]{7}(?=-)" < <(find "${HOME}/my_selinux_policies" -maxdepth 1 -mindepth 1 -type f -name "my-*.te" 2>/dev/null | sort -r))"; then
            index="$(printf "%07d" "$((++index))")"
        else
            index="0000000"
        fi

        stype="$(grep -Po "scontext=[^:]+:[^:]+:\K[^:]+" <<< "${denials_context}")"
        ttype="$(grep -Po "tcontext=[^:]+:[^:]+:\K[^:]+" <<< "${denials_context}")"

        policy_name="my-${index}-${stype}-${ttype}"

        denials_relevant="$(tac <<<"${denials}" | sed -n "/${denials_context}/,/^----$/p" | tac)"

        (
            cd "${HOME}/my_selinux_policies" && \
            audit2allow -M "${policy_name}-allow" <<< "${denials_relevant}" && \
            audit2allow -D -M "${policy_name}-dontaudit" <<< "${denials_relevant}"
        )

        cat <<EOF >> "${HOME}/my_selinux_policies/${policy_name}-readme.txt"
The SELinux denial(s):
${denials_relevant}
EOF

        unset ino_objects
        declare -A ino_objects

        while read -r line; do
            if  ino_number="$(grep -Po "[[:space:]]+ino=\K[0-9]+" <<< "${line}")" && \
                ino_tcontext="$(grep -Po "[[:space:]]+tcontext=\K[^[:space:]]+" <<< "${line}")"
            then
                ino_objects[${ino_number}]="${ino_tcontext}"
            fi
        done <<< "${denials_relevant}"

        if [[ ${#ino_objects[@]} -gt 0 ]]; then
            printf "\nObject(s) mentioned in SELinux denials with inode number(s):\n" >> "${HOME}/my_selinux_policies/${policy_name}-readme.txt"
        fi

        for key in "${!ino_objects[@]}"; do
            cat <<EOF >> "${HOME}/my_selinux_policies/${policy_name}-readme.txt"
❯ find / -inum "${key}" -context "${ino_objects[${key}]}"
$(find / -inum "${key}" -context "${ino_objects[${key}]}")
EOF
        done
    done < <(grep -Po "[[:space:]]+\Kscontext=[^[:space:]]+[[:space:]]+tcontext=[^[:space:]]+" <<< "${denials}" | cat -n | sort -uk2 | sort -n | cut -f2-)
else
    printf "No denials found. Aborting..."
    exit 0
fi
