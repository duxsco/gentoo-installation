Set resolv.conf:

```bash
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
```

Set `.bashrc` etc.:

```bash
rsync -av --numeric-ids --chown=0:0 --chmod=u=rw,go=r /mnt/gentoo/etc/skel/.bash* /mnt/gentoo/root/ && \
rsync -av --numeric-ids --chown=0:0 --chmod=u=rwX,go= /mnt/gentoo/etc/skel/.ssh /mnt/gentoo/root/ && \
echo -e 'alias cp="cp -i"\nalias mv="mv -i"\nalias rm="rm -i"' >> /mnt/gentoo/root/.bash_aliases && \
cat <<'EOF'  >> /mnt/gentoo/root/.bashrc; echo $?
source "${HOME}/.bash_aliases"

# Raise an alert if something is wrong with btrfs or mdadm
if  { [[ -f /proc/mdstat ]] && grep -q "\[[U_]*_[U_]*\]" /proc/mdstat; } || \
    [[ $(find /sys/fs/btrfs -type f -name "error_stats" -exec awk '{sum += $2} END {print sum}' {} +) -ne 0 ]]; then
echo '
  _________________
< Something smells! >
  -----------------
         \   ^__^
          \  (oo)\_______
             (__)\       )\/\
                 ||----w |
                 ||     ||
'
fi
EOF
```

Set locale:

```bash
echo "C.UTF-8 UTF-8
de_DE.UTF-8 UTF-8
en_US.UTF-8 UTF-8" > /mnt/gentoo/etc/locale.gen && \
echo 'LANG="de_DE.UTF-8"
LC_COLLATE="C.UTF-8"
LC_MESSAGES="en_US.UTF-8"' > /mnt/gentoo/etc/env.d/02locale && \
chroot /mnt/gentoo /bin/bash -c "source /etc/profile && locale-gen"; echo $?
```

Set `MAKEOPTS`:

```bash
ram_size="$(dmidecode -t memory | grep -Pio "^[[:space:]]Size:[[:space:]]+\K[0-9]*(?=[[:space:]]*GB$)" | paste -d '+' -s - | bc)" && \
number_cores="$(nproc --all)" && \
[[ $((number_cores*2)) -le ${ram_size} ]] && jobs="${number_cores}" || jobs="$(bc <<<"${ram_size} / 2")" && \
cat <<EOF >> /mnt/gentoo/etc/portage/make.conf; echo $?

MAKEOPTS="-j${jobs}"
EOF
```

Chroot (copy&paste one after the other):

```bash
chroot /mnt/gentoo /bin/bash
source /etc/profile
su -
env-update && source /etc/profile && export PS1="(chroot) $PS1"
```

> ⚠ Execute `dispatch-conf` after every code block where a file with prefix `._cfg0000_` has been created. ⚠
