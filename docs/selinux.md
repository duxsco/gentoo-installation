!!! info
    The following covers the SELinux denials from bootup until login via tty/SSH and up to `sudo -i` into the root account.

!!! note
    I haven't taken a close look at all denials yet. First, I wanted to take care of all denials until I can login successfully. I need to check next whether all policies are necessary and make sure that PAM (see constraint violation below) is working correctly.

## 9.1. Enable SELinux

!!! info
    Currently, I only use SELinux on servers, and only `mcs` policy type to be able to "isolate" virtual machines from each other.

Prepare for SELinux (copy&paste one after the other):

```bash
cp -av /etc/portage/make.conf /etc/portage/._cfg0000_make.conf
echo -e 'POLICY_TYPES="mcs"\n' >> /etc/portage/._cfg0000_make.conf
sed -i 's/^USE_HARDENED="\(.*\)"/USE_HARDENED="\1 -ubac -unconfined"/' /etc/portage/._cfg0000_make.conf
# execute dispatch-conf

eselect profile set --force 18 # should be "[18]  default/linux/amd64/17.1/systemd/selinux (exp)"

FEATURES="-selinux" emerge -1 selinux-base

cp -av /etc/selinux/config /etc/selinux/._cfg0000_config
sed -i 's/^SELINUXTYPE=strict$/SELINUXTYPE=mcs/' /etc/selinux/._cfg0000_config
# execute dispatch-conf

FEATURES="-selinux -sesandbox" emerge -1 selinux-base
FEATURES="-selinux -sesandbox" emerge -1 selinux-base-policy
emerge -avuDN @world
```

Enable logging:

```bash
systemctl enable auditd.service
```

Rebuild the kernel with SELinux support:

```bash
emerge sys-kernel/gentoo-kernel-bin && \
rm -v /boot/efi*/EFI/Linux/gentoo-*-gentoo-dist.efi
```

Reboot with `permissive` kernel.

Make sure that UBAC gets disabled:

```bash
semodule -i /usr/share/selinux/mcs/*.pp
```

## 9.2. Relabel

[Relabel the entire system](https://wiki.gentoo.org/wiki/SELinux/Installation#Relabel):

```bash
mkdir /mnt/gentoo && \
mount -o bind / /mnt/gentoo && \
setfiles -r /mnt/gentoo /etc/selinux/mcs/contexts/files/file_contexts /mnt/gentoo/{dev,home,proc,run,sys,tmp,boot/efi*,var/cache/binpkgs,var/cache/distfiles,var/db/repos/gentoo,var/tmp} && \
umount /mnt/gentoo && \
rlpkg -a -r && \
echo SUCCESS
```

In the [custom Gentoo Linux installation](https://github.com/duxsco/gentoo-installation), the SSH port has been changed to 50022. This needs to be considered for no SELinux denials to occur:

```bash
❯ semanage port -l | grep -e ssh -e Port
SELinux Port Type              Proto    Port Number
ssh_port_t                     tcp      22
❯ semanage port -a -t ssh_port_t -p tcp 50022
❯ semanage port -l | grep -e ssh -e Port
SELinux Port Type              Proto    Port Number
ssh_port_t                     tcp      50022, 22
```

## 9.3. Users and services

Default `mcs` SELinux `login` and `user` settings:

```bash
❯ semanage login -l

Login Name           SELinux User         MLS/MCS Range        Service

__default__          user_u               s0-s0                *
root                 root                 s0-s0:c0.c1023       *

❯ semanage user -l

                Labeling   MLS/       MLS/
SELinux User    Prefix     MCS Level  MCS Range                      SELinux Roles

root            sysadm     s0         s0-s0:c0.c1023                 staff_r sysadm_r
staff_u         staff      s0         s0-s0:c0.c1023                 staff_r sysadm_r
sysadm_u        sysadm     s0         s0-s0:c0.c1023                 sysadm_r
system_u        user       s0         s0-s0:c0.c1023                 system_r
unconfined_u    unconfined s0         s0-s0:c0.c1023                 unconfined_r
user_u          user       s0         s0                             user_r
```

Add the initial user to the [administration SELinux user](https://wiki.gentoo.org/wiki/SELinux/Installation#Define_the_administrator_accounts):

```bash
semanage login -a -s staff_u david
restorecon -RFv /home/david
bash -c 'echo "%wheel ALL=(ALL) TYPE=sysadm_t ROLE=sysadm_r ALL" | EDITOR="tee" visudo -f /etc/sudoers.d/wheel; echo $?'
```

Now, we should have:

```bash
❯ semanage login -l

Login Name           SELinux User         MLS/MCS Range        Service

__default__          user_u               s0-s0                *
david                staff_u              s0-s0:c0.c1023       *
root                 root                 s0-s0:c0.c1023       *
```

## 9.4. SELinux policies

### 9.4.1. Denials: dmesg

!!! info
    The following denials were retrieved from `dmesg`.

```bash
# [   37.545369] audit: type=1400 audit(1661366541.083:3): avc:  denied  { read } for  pid=2999 comm="10-gentoo-path" name="profile.env" dev="dm-1" ino=217358 scontext=system_u:system_r:systemd_generator_t:s0 tcontext=system_u:object_r:etc_runtime_t:s0 tclass=file permissive=0

❯ find / -inum 217358
/etc/profile.env

❯ semanage fcontext -l | grep '/etc/profile\\\.env' | column -t
/etc/profile\.env  regular  file  system_u:object_r:etc_runtime_t:s0

❯ sesearch -A -s systemd_generator_t -c file -p read | grep etc
allow systemd_generator_t etc_t:file { getattr ioctl lock open read };
allow systemd_generator_t lvm_etc_t:file { getattr ioctl lock map open read };

❯ semanage fcontext -m -f f -t etc_t '/etc/profile\.env'

❯ restorecon -Fv /etc/profile.env
Relabeled /etc/profile.env from system_u:object_r:etc_runtime_t:s0 to system_u:object_r:etc_t:s0
```

```bash
❯ cat <<EOF | audit2allow
[   37.726930] audit: type=1400 audit(1661366541.263:4): avc:  denied  { create } for  pid=1 comm="systemd" name="io.systemd.NameServiceSwitch" scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:systemd_userdbd_runtime_t:s0 tclass=lnk_file permissive=0
[   37.726917] systemd[1]: systemd-userdbd.socket: Failed to create symlink /run/systemd/userdb/io.systemd.Multiplexer → /run/systemd/userdb/io.systemd.NameServiceSwitch, ignoring: Permission denied
[   37.729729] systemd[1]: systemd-userdbd.socket: Failed to create symlink /run/systemd/userdb/io.systemd.Multiplexer → /run/systemd/userdb/io.systemd.DropIn, ignoring: Permission denied
[   37.732899] audit: type=1400 audit(1661366541.269:5): avc:  denied  { create } for  pid=1 comm="systemd" name="io.systemd.DropIn" scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:systemd_userdbd_runtime_t:s0 tclass=lnk_file permissive=0
EOF


#============= init_t ==============
allow init_t systemd_userdbd_runtime_t:lnk_file create;

❯ selocal -a "allow init_t systemd_userdbd_runtime_t:lnk_file create;" -c my_dmesg_000000

❯ selocal -b -L
```

```bash
❯ cat <<EOF | audit2allow
[   37.796200] audit: type=1400 audit(1661367313.330:3): avc:  denied  { mounton } for  pid=3224 comm="(-userdbd)" path="/run/systemd/unit-root/proc" dev="dm-0" ino=67139 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:unlabeled_t:s0 tclass=dir permissive=0
EOF


#============= init_t ==============
allow init_t unlabeled_t:dir mounton;

❯ selocal -a "allow init_t unlabeled_t:dir mounton;" -c my_dmesg_000001

❯ selocal -b -L
```

```bash
❯ cat <<EOF | audit2allow
[   38.036245] audit: type=1400 audit(1661366541.573:6): avc:  denied  { write } for  pid=3039 comm="systemd-udevd" name="systemd-udevd.service" dev="cgroup2" ino=2051 scontext=system_u:system_r:udev_t:s0 tcontext=system_u:object_r:cgroup_t:s0 tclass=dir permissive=0
[   37.962046] audit: type=1400 audit(1661367313.496:8): avc:  denied  { add_name } for  pid=3235 comm="systemd-udevd" name="udev" scontext=system_u:system_r:udev_t:s0 tcontext=system_u:object_r:cgroup_t:s0 tclass=dir permissive=0
[   37.054171] audit: type=1400 audit(1661367691.596:3): avc:  denied  { create } for  pid=3126 comm="systemd-udevd" name="udev" scontext=system_u:system_r:udev_t:s0 tcontext=system_u:object_r:cgroup_t:s0 tclass=dir permissive=0
[   36.687743] audit: type=1400 audit(1661368167.216:3): avc:  denied  { write } for  pid=3125 comm="systemd-udevd" name="cgroup.procs" dev="cgroup2" ino=2119 scontext=system_u:system_r:udev_t:s0 tcontext=system_u:object_r:cgroup_t:s0 tclass=file permissive=0
EOF


#============= udev_t ==============
allow udev_t cgroup_t:dir { add_name create write };
allow udev_t cgroup_t:file write;

❯ selocal -a "allow udev_t cgroup_t:dir { add_name create write };" -c my_dmesg_000002_dir

❯ selocal -a "allow udev_t cgroup_t:file write;" -c my_dmesg_000002_file

❯ selocal -b -L
```

```bash
❯ cat <<EOF | audit2allow
[   38.044041] audit: type=1400 audit(1661366541.579:7): avc:  denied  { read } for  pid=3039 comm="systemd-udevd" name="network" dev="tmpfs" ino=78 scontext=system_u:system_r:udev_t:s0 tcontext=system_u:object_r:init_runtime_t:s0 tclass=dir permissive=0
EOF


#============= udev_t ==============
allow udev_t init_runtime_t:dir read;

❯ selocal -a "allow udev_t init_runtime_t:dir read;" -c my_dmesg_000003

❯ selocal -b -L
```

```bash
❯ cat <<EOF | audit2allow
[   38.129178] audit: type=1400 audit(1661366541.666:9): avc:  denied  { getattr } for  pid=3051 comm="mdadm" path="/run/udev" dev="tmpfs" ino=71 scontext=system_u:system_r:mdadm_t:s0 tcontext=system_u:object_r:udev_runtime_t:s0 tclass=dir permissive=0
EOF


#============= mdadm_t ==============
allow mdadm_t udev_runtime_t:dir getattr;

❯ selocal -a "allow mdadm_t udev_runtime_t:dir getattr;" -c my_dmesg_000004

❯ selocal -b -L
```

```bash
❯ cat <<EOF | audit2allow
[   38.143600] audit: type=1400 audit(1661366541.679:10): avc:  denied  { search } for  pid=3051 comm="mdadm" name="block" dev="debugfs" ino=29 scontext=system_u:system_r:mdadm_t:s0 tcontext=system_u:object_r:debugfs_t:s0 tclass=dir permissive=0
[   38.169458] audit: type=1400 audit(1661366541.683:11): avc:  denied  { search } for  pid=3051 comm="mdadm" name="bdi" dev="debugfs" ino=22 scontext=system_u:system_r:mdadm_t:s0 tcontext=system_u:object_r:debugfs_t:s0 tclass=dir permissive=0
EOF


#============= mdadm_t ==============
allow mdadm_t debugfs_t:dir search;

❯ selocal -a "allow mdadm_t debugfs_t:dir search;" -c my_dmesg_000005

❯ selocal -b -L
```

```bash
❯ cat <<EOF | audit2allow
[   38.102386] audit: type=1400 audit(1661367313.636:9): avc:  denied  { getattr } for  pid=26 comm="kdevtmpfs" path="/fb0" dev="devtmpfs" ino=152 scontext=system_u:system_r:kernel_t:s0 tcontext=system_u:object_r:framebuf_device_t:s0 tclass=chr_file permissive=0
EOF


#============= kernel_t ==============
allow kernel_t framebuf_device_t:chr_file getattr;

❯ selocal -a "allow kernel_t framebuf_device_t:chr_file getattr;" -c my_dmesg_000006

❯ selocal -b -L
```

```bash
❯ cat <<EOF | audit2allow
[   37.167114] audit: type=1400 audit(1661367691.709:4): avc:  denied  { setattr } for  pid=26 comm="kdevtmpfs" name="fb0" dev="devtmpfs" ino=152 scontext=system_u:system_r:kernel_t:s0 tcontext=system_u:object_r:framebuf_device_t:s0 tclass=chr_file permissive=0
[   37.191217] audit: type=1400 audit(1661367691.709:5): avc:  denied  { unlink } for  pid=26 comm="kdevtmpfs" name="fb0" dev="devtmpfs" ino=152 scontext=system_u:system_r:kernel_t:s0 tcontext=system_u:object_r:framebuf_device_t:s0 tclass=chr_file permissive=0
EOF


#============= kernel_t ==============
allow kernel_t framebuf_device_t:chr_file { setattr unlink };

❯ selocal -a "allow kernel_t framebuf_device_t:chr_file { setattr unlink };" -c my_dmesg_000007

❯ selocal -b -L
```


```bash
❯ cat <<EOF | audit2allow
[   38.226602] audit: type=1400 audit(1661367313.759:10): avc:  denied  { read write } for  pid=1 comm="systemd" name="rfkill" dev="devtmpfs" ino=178 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:wireless_device_t:s0 tclass=chr_file permissive=0
[   37.280830] audit: type=1400 audit(1661367691.823:6): avc:  denied  { open } for  pid=1 comm="systemd" path="/dev/rfkill" dev="devtmpfs" ino=178 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:wireless_device_t:s0 tclass=chr_file permissive=0
EOF


#============= init_t ==============
allow init_t wireless_device_t:chr_file { open read write };

❯ selocal -a "allow init_t wireless_device_t:chr_file { open read write };" -c my_dmesg_000008

❯ selocal -b -L
```

```bash
❯ cat <<EOF | audit2allow
[   38.701549] audit: type=1400 audit(1661367314.236:11): avc:  denied  { execute } for  pid=3307 comm="(bootctl)" name="bootctl" dev="dm-0" ino=186106 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:bootloader_exec_t:s0 tclass=file permissive=0
[   37.857611] audit: type=1400 audit(1661367692.393:7): avc:  denied  { read open } for  pid=3198 comm="(bootctl)" path="/usr/bin/bootctl" dev="dm-0" ino=186106 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:bootloader_exec_t:s0 tclass=file permissive=0
[   37.524074] audit: type=1400 audit(1661368168.053:4): avc:  denied  { execute_no_trans } for  pid=3197 comm="(bootctl)" path="/usr/bin/bootctl" dev="dm-3" ino=186106 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:bootloader_exec_t:s0 tclass=file permissive=0
[   37.776422] audit: type=1400 audit(1661368671.299:3): avc:  denied  { map } for  pid=3202 comm="bootctl" path="/usr/bin/bootctl" dev="dm-2" ino=186106 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:bootloader_exec_t:s0 tclass=file permissive=0
EOF


#============= init_t ==============
allow init_t bootloader_exec_t:file { execute execute_no_trans map open read };

❯ selocal -a "allow init_t bootloader_exec_t:file { execute execute_no_trans map open read };" -c my_dmesg_000009

❯ selocal -b -L
```

```bash
❯ cat <<EOF | audit2allow
[   37.880262] audit: type=1400 audit(1661367692.423:8): avc:  denied  { getattr } for  pid=3199 comm="systemd-tmpfile" path="/var/cache/eix" dev="dm-0" ino=68937 scontext=system_u:system_r:systemd_tmpfiles_t:s0 tcontext=system_u:object_r:portage_cache_t:s0 tclass=dir permissive=0
[   37.890742] audit: type=1400 audit(1661367692.426:10): avc:  denied  { read } for  pid=3199 comm="systemd-tmpfile" name="eix" dev="dm-0" ino=68937 scontext=system_u:system_r:systemd_tmpfiles_t:s0 tcontext=system_u:object_r:portage_cache_t:s0 tclass=dir permissive=0
EOF


#============= systemd_tmpfiles_t ==============

#!!!! This avc can be allowed using the boolean 'systemd_tmpfiles_manage_all'
allow systemd_tmpfiles_t portage_cache_t:dir { getattr read };

❯ setsebool -P systemd_tmpfiles_manage_all on
```

```bash
❯ cat <<EOF | audit2allow
[   37.623382] audit: type=1400 audit(1661368168.150:5): avc:  denied  { mounton } for  pid=3203 comm="(resolved)" path="/run/systemd/unit-root/run/systemd/resolve" dev="tmpfs" ino=1551 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:systemd_resolved_runtime_t:s0 tclass=dir permissive=0
EOF


#============= init_t ==============

#!!!! This avc can be allowed using the boolean 'init_mounton_non_security'
allow init_t systemd_resolved_runtime_t:dir mounton;

❯ setsebool -P init_mounton_non_security on
```

### 9.4.2. Denials: auditd.service

!!! info
    The following denials were retrieved with the help of `auditd.service`.

```bash
# ----
# time->Wed Aug 24 21:38:26 2022
# type=PROCTITLE msg=audit(1661369906.239:39): proctitle=6E6674002D66002D
# type=PATH msg=audit(1661369906.239:39): item=0 name="/var/lib/nftables/rules-save" inode=221279 dev=00:21 mode=0100600 ouid=0 ogid=0 rdev=00:00 obj=system_u:object_r:var_lib_t:s0 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
# type=CWD msg=audit(1661369906.239:39): cwd="/"
# type=SYSCALL msg=audit(1661369906.239:39): arch=c000003e syscall=262 success=no exit=-13 a0=ffffff9c a1=7ffee5ea26c0 a2=7ffee5ea2760 a3=100 items=1 ppid=3248 pid=3250 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="nft" exe="/sbin/nft" subj=system_u:system_r:iptables_t:s0 key=(null)
# type=AVC msg=audit(1661369906.239:39): avc:  denied  { getattr } for  pid=3250 comm="nft" path="/var/lib/nftables/rules-save" dev="dm-1" ino=221279 scontext=system_u:system_r:iptables_t:s0 tcontext=system_u:object_r:var_lib_t:s0 tclass=file permissive=0

❯ semanage fcontext -l | grep -i "/var/lib" | grep tables | column -t
/var/lib/ip6?tables(/.*)?  all  files  system_u:object_r:initrc_tmp_t:s0

❯ sesearch -A -s iptables_t -t initrc_tmp_t -c file -p getattr
allow iptables_t initrc_tmp_t:file { append getattr ioctl lock open read write };

❯ semanage fcontext -a -f a -s system_u -t initrc_tmp_t '/var/lib/nftables(/[^\.].*)?'

❯ restorecon -RFv /var/lib/nftables
Relabeled /var/lib/nftables from system_u:object_r:var_lib_t:s0 to system_u:object_r:initrc_tmp_t:s0
Relabeled /var/lib/nftables/rules-save from system_u:object_r:var_lib_t:s0 to system_u:object_r:initrc_tmp_t:s0
```

```bash
❯ cat <<EOF | audit2allow
----
time->Wed Aug 24 23:53:08 2022
type=PROCTITLE msg=audit(1661377988.663:43): proctitle="/lib/systemd/systemd-networkd"
type=PATH msg=audit(1661377988.663:43): item=0 name="/run/systemd/network" inode=78 dev=00:1a mode=040755 ouid=0 ogid=0 rdev=00:00 obj=system_u:object_r:init_runtime_t:s0 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1661377988.663:43): cwd="/"
type=SYSCALL msg=audit(1661377988.663:43): arch=c000003e syscall=257 success=no exit=-13 a0=ffffff9c a1=55df73b28c00 a2=90800 a3=0 items=1 ppid=1 pid=3261 auid=4294967295 uid=192 gid=192 euid=192 suid=192 fsuid=192 egid=192 sgid=192 fsgid=192 tty=(none) ses=4294967295 comm="systemd-network" exe="/lib/systemd/systemd-networkd" subj=system_u:system_r:systemd_networkd_t:s0 key=(null)
type=AVC msg=audit(1661377988.663:43): avc:  denied  { read } for  pid=3261 comm="systemd-network" name="network" dev="tmpfs" ino=78 scontext=system_u:system_r:systemd_networkd_t:s0 tcontext=system_u:object_r:init_runtime_t:s0 tclass=dir permissive=0
----
time->Thu Aug 25 00:14:48 2022
type=PROCTITLE msg=audit(1661379288.763:43): proctitle="/lib/systemd/systemd-networkd"
type=PATH msg=audit(1661379288.763:43): item=0 name="/run/systemd/network/90-enp1s0.network" inode=79 dev=00:1a mode=0100644 ouid=0 ogid=0 rdev=00:00 obj=system_u:object_r:init_runtime_t:s0 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1661379288.763:43): cwd="/"
type=SYSCALL msg=audit(1661379288.763:43): arch=c000003e syscall=262 success=no exit=-13 a0=ffffff9c a1=55da01904c00 a2=7ffca10da400 a3=0 items=1 ppid=1 pid=3333 auid=4294967295 uid=192 gid=192 euid=192 suid=192 fsuid=192 egid=192 sgid=192 fsgid=192 tty=(none) ses=4294967295 comm="systemd-network" exe="/lib/systemd/systemd-networkd" subj=system_u:system_r:systemd_networkd_t:s0 key=(null)
type=AVC msg=audit(1661379288.763:43): avc:  denied  { getattr } for  pid=3333 comm="systemd-network" path="/run/systemd/network/90-enp1s0.network" dev="tmpfs" ino=79 scontext=system_u:system_r:systemd_networkd_t:s0 tcontext=system_u:object_r:init_runtime_t:s0 tclass=file permissive=0
----
time->Thu Aug 25 00:17:28 2022
type=PROCTITLE msg=audit(1661379448.229:51): proctitle="/lib/systemd/systemd-networkd"
type=PATH msg=audit(1661379448.229:51): item=0 name="/run/systemd/network/90-enp1s0.network" inode=79 dev=00:1a mode=0100644 ouid=0 ogid=0 rdev=00:00 obj=system_u:object_r:init_runtime_t:s0 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1661379448.229:51): cwd="/"
type=SYSCALL msg=audit(1661379448.229:51): arch=c000003e syscall=257 success=no exit=-13 a0=ffffff9c a1=5564bc5f9c00 a2=80000 a3=0 items=1 ppid=1 pid=3078 auid=4294967295 uid=192 gid=192 euid=192 suid=192 fsuid=192 egid=192 sgid=192 fsgid=192 tty=(none) ses=4294967295 comm="systemd-network" exe="/lib/systemd/systemd-networkd" subj=system_u:system_r:systemd_networkd_t:s0 key=(null)
type=AVC msg=audit(1661379448.229:51): avc:  denied  { read } for  pid=3078 comm="systemd-network" name="90-enp1s0.network" dev="tmpfs" ino=79 scontext=system_u:system_r:systemd_networkd_t:s0 tcontext=system_u:object_r:init_runtime_t:s0 tclass=file permissive=0
----
time->Thu Aug 25 00:20:51 2022
type=PROCTITLE msg=audit(1661379651.029:43): proctitle="/lib/systemd/systemd-networkd"
type=PATH msg=audit(1661379651.029:43): item=0 name="/run/systemd/network/90-enp1s0.network" inode=80 dev=00:1a mode=0100644 ouid=0 ogid=0 rdev=00:00 obj=system_u:object_r:init_runtime_t:s0 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1661379651.029:43): cwd="/"
type=SYSCALL msg=audit(1661379651.029:43): arch=c000003e syscall=257 success=no exit=-13 a0=ffffff9c a1=55732695ec00 a2=80000 a3=0 items=1 ppid=1 pid=3176 auid=4294967295 uid=192 gid=192 euid=192 suid=192 fsuid=192 egid=192 sgid=192 fsgid=192 tty=(none) ses=4294967295 comm="systemd-network" exe="/lib/systemd/systemd-networkd" subj=system_u:system_r:systemd_networkd_t:s0 key=(null)
type=AVC msg=audit(1661379651.029:43): avc:  denied  { open } for  pid=3176 comm="systemd-network" path="/run/systemd/network/90-enp1s0.network" dev="tmpfs" ino=80 scontext=system_u:system_r:systemd_networkd_t:s0 tcontext=system_u:object_r:init_runtime_t:s0 tclass=file permissive=0
----
time->Thu Aug 25 00:24:20 2022
type=PROCTITLE msg=audit(1661379860.443:43): proctitle="/lib/systemd/systemd-networkd"
type=SYSCALL msg=audit(1661379860.443:43): arch=c000003e syscall=16 success=no exit=-13 a0=10 a1=5401 a2=7ffd638e1410 a3=1 items=0 ppid=1 pid=2975 auid=4294967295 uid=192 gid=192 euid=192 suid=192 fsuid=192 egid=192 sgid=192 fsgid=192 tty=(none) ses=4294967295 comm="systemd-network" exe="/lib/systemd/systemd-networkd" subj=system_u:system_r:systemd_networkd_t:s0 key=(null)
type=AVC msg=audit(1661379860.443:43): avc:  denied  { ioctl } for  pid=2975 comm="systemd-network" path="/run/systemd/network/90-enp1s0.network" dev="tmpfs" ino=79 ioctlcmd=0x5401 scontext=system_u:system_r:systemd_networkd_t:s0 tcontext=system_u:object_r:init_runtime_t:s0 tclass=file permissive=0
EOF


#============= systemd_networkd_t ==============
allow systemd_networkd_t init_runtime_t:dir read;
allow systemd_networkd_t init_runtime_t:file { getattr ioctl open read };

❯ selocal -a "allow systemd_networkd_t init_runtime_t:dir read;" -c my_auditd_000000_dir
❯ selocal -a "allow systemd_networkd_t init_runtime_t:file { getattr ioctl open read };" -c my_auditd_000000_file

❯ selocal -b -L
```

```bash
❯ cat <<EOF | audit2allow
----
time->Thu Aug 25 00:39:19 2022
type=PROCTITLE msg=audit(1661380759.276:59): proctitle="(agetty)"
type=PATH msg=audit(1661380759.276:59): item=0 name="/dev/tty1" inode=20 dev=00:05 mode=020620 ouid=0 ogid=5 rdev=04:01 obj=system_u:object_r:tty_device_t:s0 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1661380759.276:59): cwd="/"
type=SYSCALL msg=audit(1661380759.276:59): arch=c000003e syscall=254 success=no exit=-13 a0=3 a1=560c815bb0c0 a2=18 a3=5f932dd639e4204a items=1 ppid=1 pid=3416 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="(agetty)" exe="/lib/systemd/systemd" subj=system_u:system_r:init_t:s0 key=(null)
type=AVC msg=audit(1661380759.276:59): avc:  denied  { watch watch_reads } for  pid=3416 comm="(agetty)" path="/dev/tty1" dev="devtmpfs" ino=20 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:tty_device_t:s0 tclass=chr_file permissive=0
----
time->Thu Aug 25 13:34:38 2022
type=AVC msg=audit(1661427278.566:70): avc:  denied  { setattr } for  pid=1 comm="systemd" name="ttyS0" dev="devtmpfs" ino=96 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:tty_device_t:s0 tclass=chr_file permissive=0
EOF


#============= init_t ==============
allow init_t tty_device_t:chr_file { setattr watch watch_reads };

❯ selocal -a "allow init_t tty_device_t:chr_file { setattr watch watch_reads };" -c my_auditd_000001

❯ selocal -b -L
```

```bash
❯ cat <<EOF | audit2allow
----
time->Thu Aug 25 00:44:42 2022
type=PROCTITLE msg=audit(1661381082.870:61): proctitle=2F6C69622F73797374656D642F73797374656D64002D2D75736572
type=PATH msg=audit(1661381082.870:61): item=1 name="/run/user/1000/systemd" nametype=CREATE cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(1661381082.870:61): item=0 name="/run/user/1000/" inode=1 dev=00:38 mode=040700 ouid=1000 ogid=1000 rdev=00:00 obj=staff_u:object_r:user_runtime_t:s0 nametype=PARENT cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1661381082.870:61): cwd="/"
type=SYSCALL msg=audit(1661381082.870:61): arch=c000003e syscall=258 success=no exit=-13 a0=ffffff9c a1=55eb393f4ea0 a2=1ed a3=a5491cfe1f2629de items=2 ppid=1 pid=3288 auid=1000 uid=1000 gid=1000 euid=1000 suid=1000 fsuid=1000 egid=1000 sgid=1000 fsgid=1000 tty=(none) ses=2 comm="systemd" exe="/lib/systemd/systemd" subj=system_u:system_r:init_t:s0 key=(null)
type=AVC msg=audit(1661381082.870:61): avc:  denied  { write } for  pid=3288 comm="systemd" name="/" dev="tmpfs" ino=1 scontext=system_u:system_r:init_t:s0 tcontext=staff_u:object_r:user_runtime_t:s0 tclass=dir permissive=0
----
time->Thu Aug 25 00:47:57 2022
type=PROCTITLE msg=audit(1661381277.279:69): proctitle=2F6C69622F73797374656D642F73797374656D64002D2D75736572
type=PATH msg=audit(1661381277.279:69): item=1 name="/run/user/1000/systemd" nametype=CREATE cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(1661381277.279:69): item=0 name="/run/user/1000/" inode=1 dev=00:37 mode=040700 ouid=1000 ogid=1000 rdev=00:00 obj=staff_u:object_r:user_runtime_t:s0 nametype=PARENT cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1661381277.279:69): cwd="/"
type=SYSCALL msg=audit(1661381277.279:69): arch=c000003e syscall=258 success=no exit=-13 a0=ffffff9c a1=55b3fd2dbea0 a2=1ed a3=dbecf310753cd1c items=2 ppid=1 pid=3324 auid=1000 uid=1000 gid=1000 euid=1000 suid=1000 fsuid=1000 egid=1000 sgid=1000 fsgid=1000 tty=(none) ses=2 comm="systemd" exe="/lib/systemd/systemd" subj=system_u:system_r:init_t:s0 key=(null)
type=AVC msg=audit(1661381277.279:69): avc:  denied  { add_name } for  pid=3324 comm="systemd" name="systemd" scontext=system_u:system_r:init_t:s0 tcontext=staff_u:object_r:user_runtime_t:s0 tclass=dir permissive=0
EOF


#============= init_t ==============
allow init_t user_runtime_t:dir { add_name write };

❯ selocal -a "allow init_t user_runtime_t:dir { add_name write };" -c my_auditd_000002

❯ selocal -b -L
```

```bash
❯ cat <<EOF | audit2allow
----
time->Thu Aug 25 00:59:07 2022
type=PROCTITLE msg=audit(1661381947.629:69): proctitle=2F6C69622F73797374656D642F73797374656D64002D2D75736572
type=PATH msg=audit(1661381947.629:69): item=1 name="/run/user/1000/systemd" nametype=CREATE cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(1661381947.629:69): item=0 name="/run/user/1000/" inode=1 dev=00:38 mode=040700 ouid=1000 ogid=1000 rdev=00:00 obj=staff_u:object_r:user_runtime_t:s0 nametype=PARENT cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1661381947.629:69): cwd="/"
type=SYSCALL msg=audit(1661381947.629:69): arch=c000003e syscall=258 success=no exit=-13 a0=ffffff9c a1=559df6213ea0 a2=1ed a3=60ed288b719f5baa items=2 ppid=1 pid=3432 auid=1000 uid=1000 gid=1000 euid=1000 suid=1000 fsuid=1000 egid=1000 sgid=1000 fsgid=1000 tty=(none) ses=2 comm="systemd" exe="/lib/systemd/systemd" subj=system_u:system_r:init_t:s0 key=(null)
type=AVC msg=audit(1661381947.629:69): avc:  denied  { create } for  pid=3432 comm="systemd" name="systemd" scontext=system_u:system_r:init_t:s0 tcontext=staff_u:object_r:systemd_user_runtime_t:s0 tclass=dir permissive=0
----
time->Thu Aug 25 01:08:31 2022
type=PROCTITLE msg=audit(1661382511.569:63): proctitle=2F6C69622F73797374656D642F73797374656D64002D2D75736572
type=PATH msg=audit(1661382511.569:63): item=1 name="/run/user/1000/systemd/inaccessible" nametype=CREATE cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(1661382511.569:63): item=0 name="/run/user/1000/systemd/" inode=2 dev=00:38 mode=040755 ouid=1000 ogid=1000 rdev=00:00 obj=staff_u:object_r:systemd_user_runtime_t:s0 nametype=PARENT cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1661382511.569:63): cwd="/"
type=SYSCALL msg=audit(1661382511.569:63): arch=c000003e syscall=258 success=no exit=-13 a0=ffffff9c a1=55a9e2cdfb70 a2=1ed a3=1aeec676b3642e3d items=2 ppid=1 pid=3159 auid=1000 uid=1000 gid=1000 euid=1000 suid=1000 fsuid=1000 egid=1000 sgid=1000 fsgid=1000 tty=(none) ses=2 comm="systemd" exe="/lib/systemd/systemd" subj=system_u:system_r:init_t:s0 key=(null)
type=AVC msg=audit(1661382511.569:63): avc:  denied  { write } for  pid=3159 comm="systemd" name="systemd" dev="tmpfs" ino=2 scontext=system_u:system_r:init_t:s0 tcontext=staff_u:object_r:systemd_user_runtime_t:s0 tclass=dir permissive=0
----
time->Thu Aug 25 01:11:17 2022
type=PROCTITLE msg=audit(1661382677.403:61): proctitle=2F6C69622F73797374656D642F73797374656D64002D2D75736572
type=PATH msg=audit(1661382677.403:61): item=1 name="/run/user/1000/systemd/inaccessible" nametype=CREATE cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(1661382677.403:61): item=0 name="/run/user/1000/systemd/" inode=2 dev=00:38 mode=040755 ouid=1000 ogid=1000 rdev=00:00 obj=staff_u:object_r:systemd_user_runtime_t:s0 nametype=PARENT cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1661382677.403:61): cwd="/"
type=SYSCALL msg=audit(1661382677.403:61): arch=c000003e syscall=258 success=no exit=-13 a0=ffffff9c a1=562000db7b70 a2=1ed a3=7e7ebf467e69ce4 items=2 ppid=1 pid=3363 auid=1000 uid=1000 gid=1000 euid=1000 suid=1000 fsuid=1000 egid=1000 sgid=1000 fsgid=1000 tty=(none) ses=2 comm="systemd" exe="/lib/systemd/systemd" subj=system_u:system_r:init_t:s0 key=(null)
type=AVC msg=audit(1661382677.403:61): avc:  denied  { add_name } for  pid=3363 comm="systemd" name="inaccessible" scontext=system_u:system_r:init_t:s0 tcontext=staff_u:object_r:systemd_user_runtime_t:s0 tclass=dir permissive=0
----
time->Thu Aug 25 01:52:49 2022
type=PROCTITLE msg=audit(1661385169.613:61): proctitle=2F6C69622F73797374656D642F73797374656D64002D2D75736572
type=PATH msg=audit(1661385169.613:61): item=1 name="/run/user/1000/systemd/generator" inode=10 dev=00:37 mode=040755 ouid=1000 ogid=1000 rdev=00:00 obj=staff_u:object_r:systemd_user_runtime_unit_t:s0 nametype=DELETE cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(1661385169.613:61): item=0 name="/run/user/1000/systemd/" inode=2 dev=00:37 mode=040755 ouid=1000 ogid=1000 rdev=00:00 obj=staff_u:object_r:systemd_user_runtime_t:s0 nametype=PARENT cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1661385169.613:61): cwd="/"
type=SYSCALL msg=audit(1661385169.613:61): arch=c000003e syscall=84 success=no exit=-13 a0=55dfb321d8a0 a1=cd7 a2=7fa895152d72 a3=4 items=2 ppid=1 pid=3281 auid=1000 uid=1000 gid=1000 euid=1000 suid=1000 fsuid=1000 egid=1000 sgid=1000 fsgid=1000 tty=(none) ses=2 comm="systemd" exe="/lib/systemd/systemd" subj=system_u:system_r:init_t:s0 key=(null)
type=AVC msg=audit(1661385169.613:61): avc:  denied  { remove_name } for  pid=3281 comm="systemd" name="generator" dev="tmpfs" ino=10 scontext=system_u:system_r:init_t:s0 tcontext=staff_u:object_r:systemd_user_runtime_t:s0 tclass=dir permissive=0
EOF


#============= init_t ==============
allow init_t systemd_user_runtime_t:dir { add_name create remove_name write };

❯ selocal -a "allow init_t systemd_user_runtime_t:dir { add_name create remove_name write };" -c my_auditd_000003

❯ selocal -b -L
```

```bash
❯ cat <<EOF | audit2allow
----
time->Thu Aug 25 01:14:01 2022
type=PROCTITLE msg=audit(1661382841.039:61): proctitle=2F6C69622F73797374656D642F73797374656D64002D2D75736572
type=PATH msg=audit(1661382841.039:61): item=1 name="/run/user/1000/systemd/inaccessible/reg" nametype=CREATE cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(1661382841.039:61): item=0 name="/run/user/1000/systemd/inaccessible/" inode=3 dev=00:38 mode=040755 ouid=1000 ogid=1000 rdev=00:00 obj=system_u:object_r:systemd_user_runtime_t:s0 nametype=PARENT cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1661382841.039:61): cwd="/"
type=SYSCALL msg=audit(1661382841.039:61): arch=c000003e syscall=259 success=no exit=-13 a0=ffffff9c a1=55933399bb70 a2=8000 a3=0 items=2 ppid=1 pid=3268 auid=1000 uid=1000 gid=1000 euid=1000 suid=1000 fsuid=1000 egid=1000 sgid=1000 fsgid=1000 tty=(none) ses=2 comm="systemd" exe="/lib/systemd/systemd" subj=system_u:system_r:init_t:s0 key=(null)
type=AVC msg=audit(1661382841.039:61): avc:  denied  { create } for  pid=3268 comm="systemd" name="reg" scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:systemd_user_runtime_t:s0 tclass=file permissive=0
----
time->Thu Aug 25 01:16:35 2022
type=PROCTITLE msg=audit(1661382995.279:61): proctitle=2F6C69622F73797374656D642F73797374656D64002D2D75736572
type=PATH msg=audit(1661382995.279:61): item=1 name="/run/user/1000/systemd/inaccessible/fifo" nametype=CREATE cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(1661382995.279:61): item=0 name="/run/user/1000/systemd/inaccessible/" inode=3 dev=00:38 mode=040755 ouid=1000 ogid=1000 rdev=00:00 obj=system_u:object_r:systemd_user_runtime_t:s0 nametype=PARENT cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1661382995.279:61): cwd="/"
type=SYSCALL msg=audit(1661382995.279:61): arch=c000003e syscall=259 success=no exit=-13 a0=ffffff9c a1=564c02a30b70 a2=1000 a3=0 items=2 ppid=1 pid=3262 auid=1000 uid=1000 gid=1000 euid=1000 suid=1000 fsuid=1000 egid=1000 sgid=1000 fsgid=1000 tty=(none) ses=2 comm="systemd" exe="/lib/systemd/systemd" subj=system_u:system_r:init_t:s0 key=(null)
type=AVC msg=audit(1661382995.279:61): avc:  denied  { create } for  pid=3262 comm="systemd" name="fifo" scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:systemd_user_runtime_t:s0 tclass=fifo_file permissive=0
----
time->Thu Aug 25 01:23:17 2022
type=PROCTITLE msg=audit(1661383397.123:61): proctitle=2F6C69622F73797374656D642F73797374656D64002D2D75736572
type=PATH msg=audit(1661383397.123:61): item=1 name="/run/user/1000/systemd/inaccessible/sock" nametype=CREATE cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(1661383397.123:61): item=0 name="/run/user/1000/systemd/inaccessible/" inode=3 dev=00:38 mode=040755 ouid=1000 ogid=1000 rdev=00:00 obj=system_u:object_r:systemd_user_runtime_t:s0 nametype=PARENT cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1661383397.123:61): cwd="/"
type=SYSCALL msg=audit(1661383397.123:61): arch=c000003e syscall=259 success=no exit=-13 a0=ffffff9c a1=55e4a6ed1b70 a2=c000 a3=0 items=2 ppid=1 pid=3278 auid=1000 uid=1000 gid=1000 euid=1000 suid=1000 fsuid=1000 egid=1000 sgid=1000 fsgid=1000 tty=(none) ses=2 comm="systemd" exe="/lib/systemd/systemd" subj=system_u:system_r:init_t:s0 key=(null)
type=AVC msg=audit(1661383397.123:61): avc:  denied  { create } for  pid=3278 comm="systemd" name="sock" scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:systemd_user_runtime_t:s0 tclass=sock_file permissive=0
----
time->Thu Aug 25 01:29:20 2022
type=PROCTITLE msg=audit(1661383760.239:62): proctitle=2F6C69622F73797374656D642F73797374656D64002D2D75736572
type=PATH msg=audit(1661383760.239:62): item=1 name="/run/user/1000/systemd/inaccessible/chr" nametype=CREATE cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(1661383760.239:62): item=0 name="/run/user/1000/systemd/inaccessible/" inode=3 dev=00:38 mode=040755 ouid=1000 ogid=1000 rdev=00:00 obj=system_u:object_r:systemd_user_runtime_t:s0 nametype=PARENT cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1661383760.239:62): cwd="/"
type=SYSCALL msg=audit(1661383760.239:62): arch=c000003e syscall=259 success=no exit=-13 a0=ffffff9c a1=5632bff78b70 a2=2000 a3=0 items=2 ppid=1 pid=3187 auid=1000 uid=1000 gid=1000 euid=1000 suid=1000 fsuid=1000 egid=1000 sgid=1000 fsgid=1000 tty=(none) ses=2 comm="systemd" exe="/lib/systemd/systemd" subj=system_u:system_r:init_t:s0 key=(null)
type=AVC msg=audit(1661383760.239:62): avc:  denied  { create } for  pid=3187 comm="systemd" name="chr" scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:systemd_user_runtime_t:s0 tclass=chr_file permissive=0
----
time->Thu Aug 25 01:56:22 2022
type=PROCTITLE msg=audit(1661385382.983:61): proctitle=2F6C69622F73797374656D642F73797374656D64002D2D75736572
type=PATH msg=audit(1661385382.983:61): item=0 name="/proc/self/fd/20" inode=14 dev=00:37 mode=0140755 ouid=1000 ogid=1000 rdev=00:00 obj=system_u:object_r:systemd_user_runtime_t:s0 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1661385382.983:61): cwd="/"
type=SYSCALL msg=audit(1661385382.983:61): arch=c000003e syscall=280 success=no exit=-13 a0=ffffff9c a1=7fffd56539c0 a2=0 a3=0 items=1 ppid=1 pid=3378 auid=1000 uid=1000 gid=1000 euid=1000 suid=1000 fsuid=1000 egid=1000 sgid=1000 fsgid=1000 tty=(none) ses=2 comm="systemd" exe="/lib/systemd/systemd" subj=system_u:system_r:init_t:s0 key=(null)
type=AVC msg=audit(1661385382.983:61): avc:  denied  { write } for  pid=3378 comm="systemd" name="private" dev="tmpfs" ino=14 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:systemd_user_runtime_t:s0 tclass=sock_file permissive=0
----
time->Thu Aug 25 02:04:33 2022
type=PROCTITLE msg=audit(1661385873.076:61): proctitle=2F6C69622F73797374656D642F73797374656D64002D2D75736572
type=PATH msg=audit(1661385873.076:61): item=2 name="/run/user/1000/systemd/units/.#invocation:dbus.socketccab4f1d32dec060" nametype=CREATE cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(1661385873.076:61): item=1 name="3cc59378b35f4d579b487118b4e918ea" nametype=UNKNOWN cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(1661385873.076:61): item=0 name="/run/user/1000/systemd/units/" inode=9 dev=00:38 mode=040755 ouid=1000 ogid=1000 rdev=00:00 obj=system_u:object_r:systemd_user_runtime_t:s0 nametype=PARENT cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1661385873.076:61): cwd="/"
type=SYSCALL msg=audit(1661385873.076:61): arch=c000003e syscall=88 success=no exit=-13 a0=559116ee34b0 a1=559116f5da50 a2=55944ffae8ee a3=caab043e32a02748 items=3 ppid=1 pid=3266 auid=1000 uid=1000 gid=1000 euid=1000 suid=1000 fsuid=1000 egid=1000 sgid=1000 fsgid=1000 tty=(none) ses=2 comm="systemd" exe="/lib/systemd/systemd" subj=system_u:system_r:init_t:s0 key=(null)
type=AVC msg=audit(1661385873.076:61): avc:  denied  { create } for  pid=3266 comm="systemd" name=".#invocation:dbus.socketccab4f1d32dec060" scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:systemd_user_runtime_t:s0 tclass=lnk_file permissive=0
----
time->Thu Aug 25 10:03:06 2022
type=PROCTITLE msg=audit(1661414586.303:61): proctitle=2F6C69622F73797374656D642F73797374656D64002D2D75736572
type=PATH msg=audit(1661414586.303:61): item=3 name="/run/user/1000/systemd/units/invocation:dbus.socket" nametype=CREATE cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(1661414586.303:61): item=2 name="/run/user/1000/systemd/units/.#invocation:dbus.socket6fa23590912098d5" inode=16 dev=00:38 mode=0120777 ouid=1000 ogid=1000 rdev=00:00 obj=system_u:object_r:systemd_user_runtime_t:s0 nametype=DELETE cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(1661414586.303:61): item=1 name="/run/user/1000/systemd/units/" inode=9 dev=00:38 mode=040755 ouid=1000 ogid=1000 rdev=00:00 obj=system_u:object_r:systemd_user_runtime_t:s0 nametype=PARENT cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(1661414586.303:61): item=0 name="/run/user/1000/systemd/units/" inode=9 dev=00:38 mode=040755 ouid=1000 ogid=1000 rdev=00:00 obj=system_u:object_r:systemd_user_runtime_t:s0 nametype=PARENT cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1661414586.303:61): cwd="/"
type=SYSCALL msg=audit(1661414586.303:61): arch=c000003e syscall=82 success=no exit=-13 a0=55ad42211f70 a1=55ad421951e0 a2=55a818ce4340 a3=66f3775c14331539 items=4 ppid=1 pid=3770 auid=1000 uid=1000 gid=1000 euid=1000 suid=1000 fsuid=1000 egid=1000 sgid=1000 fsgid=1000 tty=(none) ses=2 comm="systemd" exe="/lib/systemd/systemd" subj=system_u:system_r:init_t:s0 key=(null)
type=AVC msg=audit(1661414586.303:61): avc:  denied  { rename } for  pid=3770 comm="systemd" name=".#invocation:dbus.socket6fa23590912098d5" dev="tmpfs" ino=16 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:systemd_user_runtime_t:s0 tclass=lnk_file permissive=0
EOF


#============= init_t ==============
allow init_t systemd_user_runtime_t:chr_file create;
allow init_t systemd_user_runtime_t:fifo_file create;
allow init_t systemd_user_runtime_t:file create;
allow init_t systemd_user_runtime_t:lnk_file { create rename };
allow init_t systemd_user_runtime_t:sock_file { create write };

❯ selocal -a "allow init_t systemd_user_runtime_t:chr_file create;" -c my_auditd_000005_chr_file
❯ selocal -a "allow init_t systemd_user_runtime_t:fifo_file create;" -c my_auditd_000005_fifo_file
❯ selocal -a "allow init_t systemd_user_runtime_t:file create;" -c my_auditd_000005_file
❯ selocal -a "allow init_t systemd_user_runtime_t:lnk_file { create rename };" -c my_auditd_000005_lnk_file
❯ selocal -a "allow init_t systemd_user_runtime_t:sock_file { create write };" -c my_auditd_000005_sock_file

❯ selocal -b -L
```

```bash
❯ cat <<EOF | audit2allow
----
time->Thu Aug 25 01:35:11 2022
type=PROCTITLE msg=audit(1661384111.956:61): proctitle="/usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator"
type=PATH msg=audit(1661384111.956:61): item=0 name="" inode=265 dev=00:21 mode=040700 ouid=1000 ogid=1000 rdev=00:00 obj=staff_u:object_r:xdg_config_t:s0 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1661384111.956:61): cwd="/"
type=SYSCALL msg=audit(1661384111.956:61): arch=c000003e syscall=262 success=no exit=-13 a0=4 a1=7ff72be7df13 a2=7ffff656b200 a3=1000 items=1 ppid=3264 pid=3265 auid=1000 uid=1000 gid=1000 euid=1000 suid=1000 fsuid=1000 egid=1000 sgid=1000 fsgid=1000 tty=(none) ses=2 comm="30-systemd-envi" exe="/usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator" subj=system_u:system_r:systemd_generator_t:s0 key=(null)
type=AVC msg=audit(1661384111.956:61): avc:  denied  { getattr } for  pid=3265 comm="30-systemd-envi" path="/home/david/.config" dev="dm-0" ino=265 scontext=system_u:system_r:systemd_generator_t:s0 tcontext=staff_u:object_r:xdg_config_t:s0 tclass=dir permissive=0
----
time->Thu Aug 25 01:38:28 2022
type=PROCTITLE msg=audit(1661384308.306:61): proctitle="/usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator"
type=PATH msg=audit(1661384308.306:61): item=0 name="environment.d" nametype=UNKNOWN cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1661384308.306:61): cwd="/"
type=SYSCALL msg=audit(1661384308.306:61): arch=c000003e syscall=257 success=no exit=-13 a0=4 a1=561d1e9652d0 a2=2a0000 a3=0 items=1 ppid=3273 pid=3274 auid=1000 uid=1000 gid=1000 euid=1000 suid=1000 fsuid=1000 egid=1000 sgid=1000 fsgid=1000 tty=(none) ses=2 comm="30-systemd-envi" exe="/usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator" subj=system_u:system_r:systemd_generator_t:s0 key=(null)
type=AVC msg=audit(1661384308.306:61): avc:  denied  { search } for  pid=3274 comm="30-systemd-envi" name=".config" dev="dm-1" ino=265 scontext=system_u:system_r:systemd_generator_t:s0 tcontext=staff_u:object_r:xdg_config_t:s0 tclass=dir permissive=0
EOF


#============= systemd_generator_t ==============
allow systemd_generator_t xdg_config_t:dir { getattr search };

❯ selocal -a "allow systemd_generator_t xdg_config_t:dir { getattr search };" -c my_auditd_000006

❯ selocal -b -L
```

```bash
❯ cat <<EOF | audit2allow
----
time->Thu Aug 25 02:00:35 2022
type=PROCTITLE msg=audit(1661385635.276:61): proctitle=2F6C69622F73797374656D642F73797374656D64002D2D75736572
type=PATH msg=audit(1661385635.276:61): item=0 name="/proc/self/fd/26" inode=15 dev=00:38 mode=0140666 ouid=1000 ogid=1000 rdev=00:00 obj=staff_u:object_r:session_dbusd_runtime_t:s0 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1661385635.276:61): cwd="/"
type=SYSCALL msg=audit(1661385635.276:61): arch=c000003e syscall=280 success=no exit=-13 a0=ffffff9c a1=7ffc4a0a5f70 a2=0 a3=0 items=1 ppid=1 pid=3268 auid=1000 uid=1000 gid=1000 euid=1000 suid=1000 fsuid=1000 egid=1000 sgid=1000 fsgid=1000 tty=(none) ses=2 comm="systemd" exe="/lib/systemd/systemd" subj=system_u:system_r:init_t:s0 key=(null)
type=AVC msg=audit(1661385635.276:61): avc:  denied  { write } for  pid=3268 comm="systemd" name="bus" dev="tmpfs" ino=15 scontext=system_u:system_r:init_t:s0 tcontext=staff_u:object_r:session_dbusd_runtime_t:s0 tclass=sock_file permissive=0
EOF


#============= init_t ==============
allow init_t session_dbusd_runtime_t:sock_file write;

❯ selocal -a "allow init_t session_dbusd_runtime_t:sock_file write;" -c my_auditd_000007

❯ selocal -b -L
```

```bash
❯ cat <<EOF | audit2allow
----
time->Thu Aug 25 11:18:48 2022
type=PROCTITLE msg=audit(1661419128.603:65): proctitle=7375646F002D69
type=PATH msg=audit(1661419128.603:65): item=0 name="/proc/3268/stat" nametype=UNKNOWN cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1661419128.603:65): cwd="/home/david"
type=SYSCALL msg=audit(1661419128.603:65): arch=c000003e syscall=257 success=no exit=-13 a0=ffffff9c a1=7ffebc1a77b0 a2=20000 a3=0 items=1 ppid=3268 pid=3296 auid=1000 uid=1000 gid=1000 euid=0 suid=0 fsuid=0 egid=1000 sgid=1000 fsgid=1000 tty=pts0 ses=1 comm="sudo" exe="/usr/bin/sudo" subj=staff_u:staff_r:staff_sudo_t:s0-s0:c0.c1023 key=(null)
type=AVC msg=audit(1661419128.603:65): avc:  denied  { search } for  pid=3296 comm="sudo" name="3268" dev="proc" ino=23326 scontext=staff_u:staff_r:staff_sudo_t:s0-s0:c0.c1023 tcontext=staff_u:staff_r:staff_t:s0-s0:c0.c1023 tclass=dir permissive=0
----
time->Thu Aug 25 11:21:23 2022
type=PROCTITLE msg=audit(1661419283.933:65): proctitle=7375646F002D69
type=PATH msg=audit(1661419283.933:65): item=0 name="/proc/3172/stat" inode=21310 dev=00:16 mode=0100444 ouid=1000 ogid=1000 rdev=00:00 obj=staff_u:staff_r:staff_t:s0-s0:c0.c1023 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1661419283.933:65): cwd="/home/david"
type=SYSCALL msg=audit(1661419283.933:65): arch=c000003e syscall=257 success=no exit=-13 a0=ffffff9c a1=7ffc8f06ad90 a2=20000 a3=0 items=1 ppid=3172 pid=3197 auid=1000 uid=1000 gid=1000 euid=0 suid=0 fsuid=0 egid=1000 sgid=1000 fsgid=1000 tty=pts0 ses=1 comm="sudo" exe="/usr/bin/sudo" subj=staff_u:staff_r:staff_sudo_t:s0-s0:c0.c1023 key=(null)
type=AVC msg=audit(1661419283.933:65): avc:  denied  { read } for  pid=3197 comm="sudo" name="stat" dev="proc" ino=21310 scontext=staff_u:staff_r:staff_sudo_t:s0-s0:c0.c1023 tcontext=staff_u:staff_r:staff_t:s0-s0:c0.c1023 tclass=file permissive=0
----
time->Thu Aug 25 11:24:21 2022
type=PROCTITLE msg=audit(1661419461.606:65): proctitle=7375646F002D69
type=PATH msg=audit(1661419461.606:65): item=0 name="/proc/3077/stat" inode=22073 dev=00:16 mode=0100444 ouid=1000 ogid=1000 rdev=00:00 obj=staff_u:staff_r:staff_t:s0-s0:c0.c1023 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1661419461.606:65): cwd="/home/david"
type=SYSCALL msg=audit(1661419461.606:65): arch=c000003e syscall=257 success=no exit=-13 a0=ffffff9c a1=7ffde6d86d20 a2=20000 a3=0 items=1 ppid=3077 pid=3102 auid=1000 uid=1000 gid=1000 euid=0 suid=0 fsuid=0 egid=1000 sgid=1000 fsgid=1000 tty=pts0 ses=1 comm="sudo" exe="/usr/bin/sudo" subj=staff_u:staff_r:staff_sudo_t:s0-s0:c0.c1023 key=(null)
type=AVC msg=audit(1661419461.606:65): avc:  denied  { open } for  pid=3102 comm="sudo" path="/proc/3077/stat" dev="proc" ino=22073 scontext=staff_u:staff_r:staff_sudo_t:s0-s0:c0.c1023 tcontext=staff_u:staff_r:staff_t:s0-s0:c0.c1023 tclass=file permissive=0
EOF


#============= staff_sudo_t ==============
allow staff_sudo_t staff_t:dir search;
allow staff_sudo_t staff_t:file { open read };

❯ selocal -a "allow staff_sudo_t staff_t:dir search;" -c my_auditd_000008_dir
❯ selocal -a "allow staff_sudo_t staff_t:file { open read };" -c my_auditd_000008_file

❯ selocal -b -L
```

```bash
❯ semodule -DB

❯ cat <<EOF | audit2allow
----
type=AVC msg=audit(1661427872.643:74): avc:  denied  { use } for  pid=3163 comm="login" path="/dev/ttyS0" dev="devtmpfs" ino=96 scontext=system_u:system_r:local_login_t:s0 tcontext=system_u:system_r:init_t:s0 tclass=fd permissive=0
EOF


#============= local_login_t ==============
allow local_login_t init_t:fd use;

❯ semodule -B

❯ selocal -a "allow local_login_t init_t:fd use;" -c my_dont_audit_000000

❯ selocal -b -L
```
