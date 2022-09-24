#!/usr/bin/env bash

function add_permissive_types() {
    for type in dracut_t portage_t; do
        if ! grep -q "^${type}$" <(semanage permissive --list --noheading); then
            permissive_types+=("${type}")

            if ! semanage permissive --add "${type}"; then
                return 1
            fi
        fi
    done
}

function clear_permissive_types() {
    for type in "${permissive_types[@]}"; do
        semanage permissive --delete "${type}"
    done
}

declare -a permissive_types
temp_dir="$(mktemp -d)"

pushd "${temp_dir}" || { printf "Failed to switch directory!" >&2; exit 1; }

cat <<'EOF' > my_kernel_build_policy.te
policy_module(my_kernel_build_policy, 1.0)

gen_require(`
    type gcc_config_t;
    type kmod_t;
    type ldconfig_t;
    type portage_tmp_t;
')

allow gcc_config_t self:capability dac_read_search;
allow kmod_t portage_tmp_t:dir { add_name getattr open read remove_name search write };
allow kmod_t portage_tmp_t:file { create getattr open rename write };
allow kmod_t self:capability dac_read_search;
allow ldconfig_t portage_tmp_t:dir { add_name getattr open read remove_name search write };
allow ldconfig_t portage_tmp_t:file { create open rename setattr write };
allow ldconfig_t portage_tmp_t:lnk_file read;
allow ldconfig_t self:capability dac_read_search;
EOF

if b2sum --quiet -c <<<"49b04d6dc0bc6bf7837a378b94e35005cf3eba6d48d744c29e50d9b98086e1bfa30a9fec5edc924bfd99800c4a722286ac34ad5a69fe78b9895ed29be214ba6e  my_kernel_build_policy.te" && \
   make -f /usr/share/selinux/mcs/include/Makefile my_kernel_build_policy.pp && \
   semodule -i my_kernel_build_policy.pp && \
   add_permissive_types
then
    emerge sys-kernel/gentoo-kernel-bin
fi

clear_permissive_types
semodule -r my_kernel_build_policy.pp

popd || { printf "Failed to switch directory!" >&2; exit 1; }
