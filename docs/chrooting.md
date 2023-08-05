Setup the [/etc/resolv.conf](https://wiki.gentoo.org/wiki/Resolv.conf) file:

```shell
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/ && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Setup [~/.bashrc](https://wiki.gentoo.org/wiki/Bash#Files):

```shell
rsync -av --numeric-ids --chown=0:0 --chmod=u=rw,go=r /mnt/gentoo/etc/skel/.bash* /mnt/gentoo/root/ && \
echo -e 'alias cp="cp -i"\nalias mv="mv -i"\nalias rm="rm -i"' >> /mnt/gentoo/root/.bash_aliases && \
echo 'source "${HOME}/.bash_aliases"

# Raise an alert if something is wrong with btrfs or mdadm
if  { [[ -f /proc/mdstat ]] && grep -q "\[[U_]*_[U_]*\]" /proc/mdstat; } || \
    [[ $(find /sys/fs/btrfs -type f -name "error_stats" -exec awk '\''{sum += $2} END {print sum}'\'' {} +) -ne 0 ]]; then
echo '\''
  _________________
< Something smells! >
  -----------------
         \   ^__^
          \  (oo)\_______
             (__)\       )\/\
                 ||----w |
                 ||     ||
'\''
fi' >> /mnt/gentoo/root/.bashrc && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Take care of [localisation](https://wiki.gentoo.org/wiki/Localization/Guide#Generating_specific_locales):

```shell
echo "C.UTF-8 UTF-8
de_DE.UTF-8 UTF-8
en_US.UTF-8 UTF-8" >> /mnt/gentoo/etc/locale.gen && \
echo 'LANG="de_DE.UTF-8"
LC_COLLATE="C.UTF-8"
LC_MESSAGES="en_US.UTF-8"' > /mnt/gentoo/etc/env.d/02locale && \
chroot /mnt/gentoo /bin/bash -c "source /etc/profile && locale-gen" && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

!!! note
    After executing the following codeblock, check the value set for `MAKEOPTS` in `/etc/portage/make.conf` for correctness. In the worst case, `MAKEOPTS="-j"` is set. You can find further info in the [Gentoo handbook](https://wiki.gentoo.org/wiki/Handbook:AMD64/Full/Installation#MAKEOPTS).

Setup [MAKEOPTS](https://wiki.gentoo.org/wiki/MAKEOPTS):

```shell
ram_size="$(dmidecode -t memory | grep -Pio "^[[:space:]]Size:[[:space:]]+\K[0-9]*(?=[[:space:]]*GB$)" | paste -d '+' -s - | bc)" && \
number_cores="$(grep -cE "^processor[[:space:]]+:[[:space:]]+[0-9]+$" /proc/cpuinfo)" && \
[[ $((number_cores*2)) -le ${ram_size} ]] && jobs="${number_cores}" || jobs="$(bc <<<"${ram_size} / 2")" && \
echo -e "\nMAKEOPTS=\"-j${jobs}\"" >> /mnt/gentoo/etc/portage/make.conf && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

[Chroot](https://wiki.gentoo.org/wiki/Chroot) (copy&paste one command after the other):

``` { .shell .no-copy }
chroot /mnt/gentoo /bin/bash
source /etc/profile
su -
env-update && source /etc/profile && export PS1="(chroot) $PS1"
```
