#!/usr/bin/env bash

# Prevent tainting variables via environment
# See: https://gist.github.com/duxsco/fad211d5828e09d0391f018834f955c9
unset audit2allow audit2allow_allow ausearch_context ausearch_denials denials_relevant dmesg_context dmesg_denials index log_source output selinux_mode selinux_type

if grep -q -E "^\[.*\][[:space:]]+audit:[[:space:]]+type=1404[[:space:]]+.*[[:space:]]+enforcing=1[[:space:]]+" < <(dmesg); then
	selinux_mode="enforcing"
else
	selinux_mode="permissive"
fi

#######
# log #
#######

dmesg_denials="$(dmesg | grep -E "^\[.*\][[:space:]]+audit:[[:space:]]+.*[[:space:]]+avc:[[:space:]]+denied[[:space:]]")"
ausearch_denials="$(ausearch --message avc --start boot)"

if [[ -n ${dmesg_denials} ]]; then
    dmesg_context="$(dmesg | grep -Po "^\[.*\][[:space:]]+audit:[[:space:]]+.*[[:space:]]+avc:[[:space:]]+denied[[:space:]]+.*\Kscontext=[^[:space:]]+[[:space:]]+tcontext=[^[:space:]]+" | uniq)"

    if [[ $(wc -l <<<"${dmesg_context}") -ge 2 ]]; then
        denials_relevant="$(grep -m 1 -B 999 "$(sed '2q;d' <<<"${dmesg_context}")" <<<"${dmesg_denials}" | sed '$d')"
    else
        denials_relevant="${dmesg_denials}"
    fi

    log_source="dmesg"
elif [[ -n ${ausearch_denials} ]]; then
    ausearch_context="$(ausearch --message avc --start boot | grep -Po "^type=AVC[[:space:]]+msg=audit(.*):[    [:space:]]+avc:[[:space:]]+denied[[:space:]]+{.*}.*\Kscontext=[^[:space:]]+[[:space:]]+tcontext=[^[:space:] ]+" | uniq)"

    if [[ $(wc -l <<<"${ausearch_context}") -ge 2 ]]; then
        denials_relevant="$(grep -m 1 -B 999 "$(sed '2q;d' <<<"${ausearch_context}")" <<<"${ausearch_denials}" | grep -B 999 "$(head -n 1 <<<"${ausearch_context}")")"
    else
        denials_relevant="${ausearch_denials}"
    fi

    log_source="ausearch"
else
    echo "No denials found. Aborting..." >&2
    exit 0
fi

#######
# meh #
#######

audit2allow="$(audit2allow <<<"${denials_relevant}")"

if grep -q '#!!!!' <<<"${audit2allow}"; then
cat <<EOF >&2
audit2allow printed a warning:
${audit2allow}

Aborting...
EOF
    exit 1
fi

audit2allow_allow="$(grep "^allow[[:space:]]" <<<"${audit2allow}")"
readarray -t selinux_type < <(cut -d ':' -f1 <<<"${audit2allow_allow}" | awk '{print $2" "$3}' | xargs | tr ' ' '\n')

if grep -q -E "^my_[0-9]{5}_" < <(semodule -l); then
    index="$(printf "%05d" "$(( $(semodule -l | grep -Po "^my_\K[0-9]{5}" | sort | tail -n 1 | sed -e 's/^0*\([1-9]*\)/\1/' -e 's/^$/0/') + 1 ))")"
else
    index="00000"
fi

output="my_${index}_${selinux_mode}_${log_source}-${selinux_type[0]}-${selinux_type[1]}"

# shellcheck disable=SC2001
cat <<EOF > "${output}.te"
$(sed 's/^/#/' <<<"${denials_relevant}")

policy_module(${output}, 1.0)

gen_require(\`
$(printf '  type %s;\n' "${selinux_type[@]}" | sort -u | grep -v "^  type self;$")
')

${audit2allow_allow}
EOF

cat <<EOF
"${output}.te" has been created!

Please, check the file, create the policy module and install it:
make -f /usr/share/selinux/strict/include/Makefile ${output}.pp
semodule -i ${output}.pp
EOF
