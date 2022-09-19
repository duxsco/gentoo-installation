#!/usr/bin/env bash

# Prevent tainting variables via environment
# See: https://gist.github.com/duxsco/fad211d5828e09d0391f018834f955c9
unset audit2allow audit2allow_allow ausearch_denials denials_context denials_relevant dmesg_denials index log_source output selinux_mode selinux_type

dmesg_denials="$(dmesg | grep -E "[[:space:]]+type=(1400|1107)[[:space:]]+.*[[:space:]]+avc:[[:space:]]+denied[[:space:]]+")"
ausearch_denials="$(ausearch --message AVC,USER_AVC --start boot)"

if [[ -n ${dmesg_denials} ]]; then
    denials_context="$(dmesg | grep -Po "[[:space:]]+type=(1400|1107)[[:space:]]+.*[[:space:]]+avc:[[:space:]]+denied[[:space:]]+.*[[:space:]]+\Kscontext=[^[:space:]]+[[:space:]]+tcontext=[^[:space:]]+" | uniq)"

    if [[ $(wc -l <<<"${denials_context}") -ge 2 ]]; then
        denials_relevant="$(sed -n "/$(sed '2q;d' <<<"${denials_context}")/q;p" <<<"${dmesg_denials}")"
    else
        denials_relevant="${dmesg_denials}"
    fi
elif [[ -n ${ausearch_denials} ]]; then
    denials_context="$(ausearch --message AVC,USER_AVC --start boot | grep -Po "^type=(AVC|USER_AVC)[[:space:]]+.*[[:space:]]+avc:[[:space:]]+denied[[:space:]]+.*[[:space:]]+\Kscontext=[^[:space:]]+[[:space:]]+tcontext=[^[:space:]]+" | uniq)"

    if [[ $(wc -l <<<"${denials_context}") -ge 2 ]]; then
        denials_relevant="$(tac <<<"${ausearch_denials}" | sed -n "/$(head -n1 <<<"${denials_context}")/,\$p" | tac)"
    else
        denials_relevant="${ausearch_denials}"
    fi
else
    echo "No denials found. Aborting..." >&2
    exit 0
fi

if index="10#$(grep -m 1 -Po "^my-\K[0-9]{7}(?=-)" < <(semodule -l | sort -r))"; then
    index="$(printf "%07d" "$((++index))")"
else
    index="0000000"
fi

scontext="$(grep -m 1 -Po "scontext=[^[:space:]^:]+_u:[^[:space:]^:]+_r:\K[^[:space:]^:]+_t" <<< "${denials_relevant}")"
tcontext="$(grep -m 1 -Po "tcontext=[^[:space:]^:]+_u:[^[:space:]^:]+_r:\K[^[:space:]^:]+_t" <<< "${denials_relevant}")"

audit2allow -M "my-${index}-${scontext}-${tcontext}" <<< "${denials_relevant}"

echo "" >> "my-${index}-${scontext}-${tcontext}.te"

# shellcheck disable=SC2001
sed 's/^/# /' <<< "${denials_relevant}" >> "my-${index}-${scontext}-${tcontext}.te"
