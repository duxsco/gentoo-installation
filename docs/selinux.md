!!! info
    The following covers the SELinux denials from bootup until login via tty/SSH and up to `sudo -i` into the root account.

!!! note
    I haven't taken a close look at all denials yet. First, I wanted to take care of all denials until I can login successfully. I need to check next whether all policies are necessary and make sure that PAM (see constraint violation below) is working correctly.

## 9.1. Enable SELinux

!!! info
    Currently, I only use SELinux on servers, and only `mcs` policy type to be able to "isolate" virtual machines from each other.

Keep the number of services to a minimum (copy&paste one after the other):

```shell
systemctl mask user@.service --now
systemctl disable systemd-userdbd.socket
```

Prepare for SELinux (copy&paste one after the other):

```shell
cp -av /etc/portage/make.conf /etc/portage/._cfg0000_make.conf
echo -e 'POLICY_TYPES="mcs"\n' >> /etc/portage/._cfg0000_make.conf
sed -i 's/^USE_HARDENED="\(.*\)"/USE_HARDENED="\1 -ubac -unconfined"/' /etc/portage/._cfg0000_make.conf
# execute dispatch-conf

eselect profile set --force "default/linux/amd64/17.1/systemd/selinux"

echo 'sec-policy/* ~amd64' >> /etc/portage/package.accept_keywords/main

# To get a nice looking html site in /usr/share/doc/selinux-base-<VERSION>/mcs/html:
echo 'sec-policy/selinux-base doc' >> /etc/portage/package.use/main

FEATURES="-selinux" emerge -1 selinux-base

cp -av /etc/selinux/config /etc/selinux/._cfg0000_config
sed -i 's/^SELINUXTYPE=strict$/SELINUXTYPE=mcs/' /etc/selinux/._cfg0000_config
# execute dispatch-conf

FEATURES="-selinux -sesandbox" emerge -1 selinux-base
FEATURES="-selinux -sesandbox" emerge -1 selinux-base-policy
emerge -atuDN @world
```

Enable logging:

```shell
systemctl enable auditd.service
```

Rebuild the kernel with SELinux support:

```shell
emerge sys-kernel/gentoo-kernel-bin && \
rm -v /boot/efi*/EFI/Linux/gentoo-*-gentoo-dist.efi
```

Reboot with `permissive` kernel.

Make sure that UBAC gets disabled:

```shell
bash -c '( cd /usr/share/selinux/mcs && semodule -i base.pp -i $(ls *.pp | grep -v base.pp) )'
```

## 9.2. Relabel

[Relabel the entire system](https://wiki.gentoo.org/wiki/SELinux/Installation#Relabel):

```shell
mkdir /mnt/gentoo && \
mount -o bind / /mnt/gentoo && \
setfiles -r /mnt/gentoo /etc/selinux/mcs/contexts/files/file_contexts /mnt/gentoo/{dev,home,proc,run,sys,tmp,boot/efi*,var/cache/binpkgs,var/cache/distfiles,var/db/repos/gentoo,var/tmp} && \
umount /mnt/gentoo && \
rlpkg -a -r && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Make sure that nothing (except `.keep` files) is unlabeled:

```shell
export tmpdir="$(mktemp -d)" && \
mount --bind / "$tmpdir" && \
find "$tmpdir" -context system_u:object_r:unlabeled_t:s0 && \
umount "$tmpdir" && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

In the [custom Gentoo Linux installation](https://github.com/duxsco/gentoo-installation), the SSH port has been changed to 50022. This needs to be considered for no SELinux denials to occur:

```shell
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

```shell
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

```shell
semanage login -a -s staff_u david
restorecon -RFv /home/david
bash -c 'echo "%wheel ALL=(ALL) TYPE=sysadm_t ROLE=sysadm_r ALL" | EDITOR="tee" visudo -f /etc/sudoers.d/wheel; echo $?'
```

Now, we should have:

```shell
❯ semanage login -l

Login Name           SELinux User         MLS/MCS Range        Service

__default__          user_u               s0-s0                *
david                staff_u              s0-s0:c0.c1023       *
root                 root                 s0-s0:c0.c1023       *
```

Create `/var/lib/sepolgen/interface_info` for `audit2why -R` to work:

```shell
sepolgen-ifgen -i /usr/share/selinux/mcs/include/support/
```

## 9.4. SELinux policies

### 9.4.1. Denials: timesyncd (optional)

!!! note
    This section is only relevant if `timesyncd.service` has not been disabled in section [8.1. Systemd Configuration](/post-boot_configuration/#81-systemd-configuration).

```shell
❯ cat <<EOF | audit2allow
[   15.416390] audit: type=1400 audit(1663429524.986:3): avc:  denied  { create } for  pid=1065 comm="(imesyncd)" name="timesync" scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:ntp_drift_t:s0 tclass=dir permissive=0
[   13.192323] audit: type=1400 audit(1663429927.743:3): avc:  denied  { setattr } for  pid=1065 comm="(imesyncd)" name="timesync" dev="dm-1" ino=251563 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:ntp_drift_t:s0 tclass=dir permissive=0
EOF


#============= init_t ==============
allow init_t ntp_drift_t:dir { create setattr };

❯ selocal -a "allow init_t ntp_drift_t:dir { create setattr };" -c my_optioanl_000000

❯ selocal -b -L
```

### 9.4.2. Denials: dmesg

!!! info
    The following denials were retrieved from `dmesg`.

```shell
# [   22.450146] audit: type=1400 audit(1663353624.006:3): avc:  denied  { read } for  pid=946 comm="10-gentoo-path" name="profile.env" dev="dm-1" ino=221184 scontext=system_u:system_r:systemd_generator_t:s0 tcontext=system_u:object_r:etc_runtime_t:s0 tclass=file permissive=0

❯ find / -inum 221184
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

```shell
❯ cat <<EOF | audit2allow
[   31.247917] audit: type=1400 audit(1663353989.806:3): avc:  denied  { write } for  pid=981 comm="systemd-udevd" name="systemd-udevd.service" dev="cgroup2" ino=1919 scontext=system_u:system_r:udev_t:s0 tcontext=system_u:object_r:cgroup_t:s0 tclass=dir permissive=0
[   15.613447] audit: type=1400 audit(1663354882.173:3): avc:  denied  { add_name } for  pid=980 comm="systemd-udevd" name="udev" scontext=system_u:system_r:udev_t:s0 tcontext=system_u:object_r:cgroup_t:s0 tclass=dir permissive=0
[   19.752551] audit: type=1400 audit(1663354989.273:3): avc:  denied  { create } for  pid=987 comm="systemd-udevd" name="udev" scontext=system_u:system_r:udev_t:s0 tcontext=system_u:object_r:cgroup_t:s0 tclass=dir permissive=0
[   15.386494] audit: type=1400 audit(1663355129.020:3): avc:  denied  { write } for  pid=981 comm="systemd-udevd" name="cgroup.procs" dev="cgroup2" ino=1954 scontext=system_u:system_r:udev_t:s0 tcontext=system_u:object_r:cgroup_t:s0 tclass=file permissive=0
EOF


#============= udev_t ==============
allow udev_t cgroup_t:dir { add_name create write };
allow udev_t cgroup_t:file write;

❯ selocal -a "allow udev_t cgroup_t:dir { add_name create write };" -c my_dmesg_000000_dir

❯ selocal -a "allow udev_t cgroup_t:file write;" -c my_dmesg_000000_file

❯ selocal -b -L
```

```shell
❯ cat <<EOF | audit2allow
[   12.880861] audit: type=1400 audit(1663355463.436:3): avc:  denied  { getattr } for  pid=1005 comm="mdadm" path="/run/udev" dev="tmpfs" ino=71 scontext=system_u:system_r:mdadm_t:s0 tcontext=system_u:object_r:udev_runtime_t:s0 tclass=dir permissive=0
EOF


#============= mdadm_t ==============
allow mdadm_t udev_runtime_t:dir getattr;

❯ selocal -a "allow mdadm_t udev_runtime_t:dir getattr;" -c my_dmesg_000001

❯ selocal -b -L
```

```shell
❯ cat <<EOF | audit2allow
[   16.257926] audit: type=1400 audit(1663355873.803:3): avc:  denied  { search } for  pid=1010 comm="mdadm" name="block" dev="debugfs" ino=29 scontext=system_u:system_r:mdadm_t:s0 tcontext=system_u:object_r:debugfs_t:s0 tclass=dir permissive=0
[   16.315999] audit: type=1400 audit(1663355873.860:4): avc:  denied  { search } for  pid=1010 comm="mdadm" name="bdi" dev="debugfs" ino=22 scontext=system_u:system_r:mdadm_t:s0 tcontext=system_u:object_r:debugfs_t:s0 tclass=dir permissive=0
EOF


#============= mdadm_t ==============
allow mdadm_t debugfs_t:dir search;

❯ selocal -a "kernel_search_debugfs(mdadm_t)" -c my_dmesg_000002

❯ selocal -b -L
```

```shell
❯ cat <<EOF | audit2allow
[   13.211511] audit: type=1400 audit(1663356309.846:3): avc:  denied  { getattr } for  pid=26 comm="kdevtmpfs" path="/fb0" dev="devtmpfs" ino=152 scontext=system_u:system_r:kernel_t:s0 tcontext=system_u:object_r:framebuf_device_t:s0 tclass=chr_file permissive=0
[   18.418356] audit: type=1400 audit(1663356643.869:3): avc:  denied  { setattr } for  pid=26 comm="kdevtmpfs" name="fb0" dev="devtmpfs" ino=152 scontext=system_u:system_r:kernel_t:s0 tcontext=system_u:object_r:framebuf_device_t:s0 tclass=chr_file permissive=0
[   48.414265] audit: type=1400 audit(1663356886.916:3): avc:  denied  { unlink } for  pid=26 comm="kdevtmpfs" name="fb0" dev="devtmpfs" ino=152 scontext=system_u:system_r:kernel_t:s0 tcontext=system_u:object_r:framebuf_device_t:s0 tclass=chr_file permissive=0
EOF


#============= kernel_t ==============
allow kernel_t framebuf_device_t:chr_file { getattr setattr unlink };

❯ selocal -a "dev_getattr_framebuffer_dev(kernel_t)" -c my_dmesg_000003
❯ selocal -a "dev_setattr_framebuffer_dev(kernel_t)" -c my_dmesg_000003
❯ selocal -a "allow kernel_t framebuf_device_t:chr_file unlink;" -c my_dmesg_000003

❯ selocal -b -L
```

```shell
❯ cat <<EOF | audit2allow
[   14.904914] audit: type=1400 audit(1663357537.436:3): avc:  denied  { getattr } for  pid=1057 comm="systemd-tmpfile" path="/var/cache/eix" dev="dm-3" ino=69394 scontext=system_u:system_r:systemd_tmpfiles_t:s0 tcontext=system_u:object_r:portage_cache_t:s0 tclass=dir permissive=0
EOF


#============= systemd_tmpfiles_t ==============

#!!!! This avc can be allowed using the boolean 'systemd_tmpfiles_manage_all'
allow systemd_tmpfiles_t portage_cache_t:dir getattr;

❯ setsebool -P systemd_tmpfiles_manage_all on
```

```shell
❯ cat <<EOF | audit2allow
[   12.725364] audit: type=1400 audit(1663357675.259:3): avc:  denied  { mounton } for  pid=1062 comm="(auditd)" path="/run/systemd/unit-root/proc" dev="dm-0" ino=67581 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:unlabeled_t:s0 tclass=dir permissive=0
EOF


#============= init_t ==============
allow init_t unlabeled_t:dir mounton;

# Credits: grift :)
❯ echo '(filecon "/proc" dir (system_u object_r proc_t ((s0)(s0))))
(allow proc_t fs_t (filesystem (associate)))
(typeattributeset mountpoint proc_t)'> my_proc.cil
❯ semodule -i my_proc.cil
❯ export tmpdir="$(mktemp -d)" && mount --bind / "$tmpdir" && chcon system_u:object_r:proc_t:s0 "$tmpdir"/proc && umount "$tmpdir" && echo -e "\e[1;32mSUCCESS\e[0m"
```

```shell
❯ cat <<EOF | audit2allow
[   20.366108] audit: type=1400 audit(1663357918.869:3): avc:  denied  { mounton } for  pid=1059 comm="(resolved)" path="/run/systemd/unit-root/run/systemd/resolve" dev="tmpfs" ino=1394 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:systemd_resolved_runtime_t:s0 tclass=dir permissive=0
EOF


#============= init_t ==============

#!!!! This avc can be allowed using the boolean 'init_mounton_non_security'
allow init_t systemd_resolved_runtime_t:dir mounton;

❯ setsebool -P init_mounton_non_security on
```

```shell
❯ cat <<EOF | audit2allow
[   15.209677] audit: type=1400 audit(1663370258.649:3): avc:  denied  { getattr } for  pid=1036 comm="loadkeys" path="/tmp" dev="tmpfs" ino=1 scontext=system_u:system_r:udev_t:s0 tcontext=system_u:object_r:tmpfs_t:s0 tclass=dir permissive=0
EOF


#============= udev_t ==============
allow udev_t tmpfs_t:dir getattr;

❯ selocal -a "fs_getattr_tmpfs_dirs(udev_t)" -c my_dmesg_000004

❯ selocal -b -L
```

### 9.4.3. Denials: auditd.service

!!! info
    The following denials were retrieved with the help of `auditd.service`.

```shell
❯ cat <<EOF | audit2allow
----
time->Fri Sep 16 21:57:21 2022
type=AVC msg=audit(1663358241.729:19): avc:  denied  { read write } for  pid=1 comm="systemd" name="rfkill" dev="devtmpfs" ino=178 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:wireless_device_t:s0 tclass=chr_file permissive=0
----
time->Fri Sep 16 21:59:29 2022
type=AVC msg=audit(1663358369.983:19): avc:  denied  { open } for  pid=1 comm="systemd" path="/dev/rfkill" dev="devtmpfs" ino=178 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:wireless_device_t:s0 tclass=chr_file permissive=0
EOF


#============= init_t ==============
allow init_t wireless_device_t:chr_file { open read write };

❯ selocal -a "dev_rw_wireless(init_t)" -c my_auditd_000000

❯ selocal -b -L
```

!!! note
    At this point, ssh connections for non-root and the switch to root via "sudo" should be possible without denials.

### 9.4.4. VM host

!!! note
    I connect to libvirtd via TCP and SSH port forwarding, because I want to use my SSH key which is secured on a hardware token, and `virt-manager` doesn't seem to be able to handle my hardware token directly. Thus, I can't use s.th. like `qemu+ssh://david@192.168.10.3:50022/system`.

I prefer managing downloads and network myself:

```shell
echo "\
app-emulation/libvirt -virt-network
app-emulation/qemu -curl" >> /etc/portage/package.use/main
```

I setup the internal network manually:

```shell
❯ head /etc/systemd/network/br0.*
==> /etc/systemd/network/br0.netdev <==
[NetDev]
Name=br0
Kind=bridge

==> /etc/systemd/network/br0.network <==
[Match]
Name=br0

[Network]
Address=192.168.110.1/24
ConfigureWithoutCarrier=true
```

Install:

```shell
emerge -av app-emulation/libvirt
```

Enable libvirt's [TCP transport](https://libvirt.org/remote.html#transports):

```shell
systemctl enable libvirtd-tcp.socket && \
systemctl start libvirtd-tcp.socket && \
systemctl enable libvirt-guests.service && \
systemctl start libvirt-guests.service && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

systemd should listen now on TCP port 16509:

```shell
❯ lsof -nP -iTCP -sTCP:LISTEN
COMMAND    PID            USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
systemd      1            root   48u  IPv6  50548      0t0  TCP *:16509 (LISTEN)
systemd-r 1063 systemd-resolve   12u  IPv4  18306      0t0  TCP *:5355 (LISTEN)
systemd-r 1063 systemd-resolve   14u  IPv6  18309      0t0  TCP *:5355 (LISTEN)
systemd-r 1063 systemd-resolve   18u  IPv4  18313      0t0  TCP 127.0.0.53:53 (LISTEN)
systemd-r 1063 systemd-resolve   20u  IPv4  18315      0t0  TCP 127.0.0.54:53 (LISTEN)
sshd      1096            root    3u  IPv4  18400      0t0  TCP *:50022 (LISTEN)
sshd      1096            root    4u  IPv6  18401      0t0  TCP *:50022 (LISTEN)
```

Forward the connection with:

```shell
ssh -NL 56509:127.0.0.1:16509 -p 50022 david@192.168.10.3
```

Add this connection in `virt-manager`:

```shell
qemu+tcp://127.0.0.1:56509/system
```

#### 9.4.4.1 Connecting with virt-manager over TCP

```shell
❯ cat <<EOF | audit2allow
----
time->Fri Sep 16 22:51:23 2022
type=AVC msg=audit(1663361483.820:41): avc:  denied  { write } for  pid=1 comm="systemd" name="libvirt-sock" dev="tmpfs" ino=1548 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:virt_runtime_t:s0 tclass=sock_file permissive=0
EOF


#============= init_t ==============
allow init_t virt_runtime_t:sock_file write;

❯ selocal -a "virt_stream_connect(init_t)" -c my_libvirtd_service_000000

❯ selocal -b -L
```

```shell
❯ cat <<EOF | audit2allow
----
time->Fri Sep 16 22:54:07 2022
type=AVC msg=audit(1663361647.136:50): avc:  denied  { write } for  pid=1 comm="systemd" name="virtlockd-sock" dev="tmpfs" ino=1558 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:virtlockd_run_t:s0 tclass=sock_file permissive=0
EOF


#============= init_t ==============
allow init_t virtlockd_run_t:sock_file write;

❯ selocal -a "allow init_t virtlockd_run_t:sock_file write;" -c my_libvirtd_service_000001

❯ selocal -b -L
```

```shell
❯ cat <<EOF | audit2allow
----
time->Fri Sep 16 22:56:14 2022
type=PROCTITLE msg=audit(1663361774.700:52): proctitle="/lib/systemd/systemd-machined"
type=SYSCALL msg=audit(1663361774.700:52): arch=c000003e syscall=138 success=no exit=-13 a0=3 a1=7ffef47c94d0 a2=0 a3=7fbe36521df0 items=0 ppid=1 pid=1221 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="systemd-machine" exe="/lib/systemd/systemd-machined" subj=system_u:system_r:systemd_machined_t:s0 key=(null)
type=AVC msg=audit(1663361774.700:52): avc:  denied  { getattr } for  pid=1221 comm="systemd-machine" name="/" dev="proc" ino=1 scontext=system_u:system_r:systemd_machined_t:s0 tcontext=system_u:object_r:proc_t:s0 tclass=filesystem permissive=0
EOF


#============= systemd_machined_t ==============
allow systemd_machined_t proc_t:filesystem getattr;

❯ selocal -a "kernel_getattr_proc(systemd_machined_t)" -c my_libvirtd_service_000002

❯ selocal -b -L
```

```shell
❯ cat <<EOF | audit2allow
----
time->Fri Sep 16 22:59:47 2022
type=PROCTITLE msg=audit(1663361987.606:52): proctitle="/lib/systemd/systemd-machined"
type=PATH msg=audit(1663361987.606:52): item=0 name="/" inode=256 dev=00:1f mode=040755 ouid=0 ogid=0 rdev=00:00 obj=system_u:object_r:root_t:s0 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1663361987.606:52): cwd="/"
type=SYSCALL msg=audit(1663361987.606:52): arch=c000003e syscall=137 success=no exit=-13 a0=7f10c6beeccd a1=7ffcc787c590 a2=3 a3=523234cc234200f5 items=1 ppid=1 pid=1206 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="systemd-machine" exe="/lib/systemd/systemd-machined" subj=system_u:system_r:systemd_machined_t:s0 key=(null)
type=AVC msg=audit(1663361987.606:52): avc:  denied  { getattr } for  pid=1206 comm="systemd-machine" name="/" dev="dm-1" ino=256 scontext=system_u:system_r:systemd_machined_t:s0 tcontext=system_u:object_r:fs_t:s0 tclass=filesystem permissive=0
EOF


#============= systemd_machined_t ==============
allow systemd_machined_t fs_t:filesystem getattr;

❯ selocal -a "fs_getattr_xattr_fs(systemd_machined_t)" -c my_libvirtd_service_000003

❯ selocal -b -L
```

```shell
❯ cat <<EOF | audit2allow
----
time->Fri Sep 16 23:04:27 2022
type=PROCTITLE msg=audit(1663362267.026:53): proctitle=2F7573722F7362696E2F6C69627669727464002D2D74696D656F757400313230
type=PATH msg=audit(1663362267.026:53): item=0 name="/var/run/utmp" inode=98 dev=00:1a mode=0100664 ouid=0 ogid=406 rdev=00:00 obj=system_u:object_r:initrc_runtime_t:s0 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1663362267.026:53): cwd="/"
type=SYSCALL msg=audit(1663362267.026:53): arch=c000003e syscall=257 success=no exit=-13 a0=ffffff9c a1=7fdcd4460e88 a2=80000 a3=0 items=1 ppid=1 pid=1221 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="libvirtd" exe="/usr/sbin/libvirtd" subj=system_u:system_r:virtd_t:s0 key=(null)
type=AVC msg=audit(1663362267.026:53): avc:  denied  { read } for  pid=1221 comm="libvirtd" name="utmp" dev="tmpfs" ino=98 scontext=system_u:system_r:virtd_t:s0 tcontext=system_u:object_r:initrc_runtime_t:s0 tclass=file permissive=0
----
time->Fri Sep 16 23:06:32 2022
type=PROCTITLE msg=audit(1663362392.993:53): proctitle=2F7573722F7362696E2F6C69627669727464002D2D74696D656F757400313230
type=PATH msg=audit(1663362392.993:53): item=0 name="/var/run/utmp" inode=95 dev=00:1a mode=0100664 ouid=0 ogid=406 rdev=00:00 obj=system_u:object_r:initrc_runtime_t:s0 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1663362392.993:53): cwd="/"
type=SYSCALL msg=audit(1663362392.993:53): arch=c000003e syscall=257 success=no exit=-13 a0=ffffff9c a1=7f02818d6e88 a2=80000 a3=0 items=1 ppid=1 pid=1197 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="libvirtd" exe="/usr/sbin/libvirtd" subj=system_u:system_r:virtd_t:s0 key=(null)
type=AVC msg=audit(1663362392.993:53): avc:  denied  { open } for  pid=1197 comm="libvirtd" path="/run/utmp" dev="tmpfs" ino=95 scontext=system_u:system_r:virtd_t:s0 tcontext=system_u:object_r:initrc_runtime_t:s0 tclass=file permissive=0
----
time->Fri Sep 16 23:09:33 2022
type=AVC msg=audit(1663362573.460:53): avc:  denied  { lock } for  pid=1189 comm="libvirtd" path="/run/utmp" dev="tmpfs" ino=95 scontext=system_u:system_r:virtd_t:s0 tcontext=system_u:object_r:initrc_runtime_t:s0 tclass=file permissive=0
EOF


#============= virtd_t ==============
allow virtd_t initrc_runtime_t:file { lock open read };

❯ selocal -a "allow virtd_t initrc_runtime_t:file { lock open read };" -c my_libvirtd_service_000004

❯ selocal -b -L
```

```shell
❯ cat <<EOF | audit2allow
----
time->Fri Sep 16 23:12:30 2022
type=PROCTITLE msg=audit(1663362750.713:55): proctitle=2F7573722F7362696E2F6C69627669727464002D2D74696D656F757400313230
type=PATH msg=audit(1663362750.713:55): item=0 name="/run/systemd/userdb/io.systemd.Machine" inode=1562 dev=00:1a mode=0140666 ouid=0 ogid=0 rdev=00:00 obj=system_u:object_r:systemd_userdbd_runtime_t:s0 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1663362750.713:55): cwd="/"
type=SOCKADDR msg=audit(1663362750.713:55): saddr=01002F72756E2F73797374656D642F7573657264622F696F2E73797374656D642E4D616368696E6500
type=SYSCALL msg=audit(1663362750.713:55): arch=c000003e syscall=42 success=no exit=-13 a0=1b a1=7f1d8dffa660 a2=29 a3=7f1d740302b0 items=1 ppid=1 pid=1205 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="daemon-init" exe="/usr/sbin/libvirtd" subj=system_u:system_r:virtd_t:s0 key=(null)
type=AVC msg=audit(1663362750.713:55): avc:  denied  { connectto } for  pid=1205 comm="daemon-init" path="/run/systemd/userdb/io.systemd.Machine" scontext=system_u:system_r:virtd_t:s0 tcontext=system_u:system_r:systemd_machined_t:s0 tclass=unix_stream_socket permissive=0
EOF


#============= virtd_t ==============
allow virtd_t systemd_machined_t:unix_stream_socket connectto;

❯ selocal -a "systemd_connect_machined(virtd_t)" -c my_libvirtd_service_000005

❯ selocal -b -L
```

#### 9.4.4.2 VM creation with virt-manager

```shell
❯ cat <<EOF | audit2allow
----
time->Fri Sep 16 23:24:31 2022
type=PROCTITLE msg=audit(1663363471.726:56): proctitle=2F7573722F7362696E2F6C69627669727464002D2D74696D656F757400313230
type=PATH msg=audit(1663363471.726:56): item=0 name="/dev/cpu/0/msr" inode=85 dev=00:05 mode=020600 ouid=0 ogid=0 rdev=ca:00 obj=system_u:object_r:cpu_device_t:s0 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1663363471.726:56): cwd="/"
type=SYSCALL msg=audit(1663363471.726:56): arch=c000003e syscall=257 success=no exit=-13 a0=ffffff9c a1=7f02211d4670 a2=0 a3=0 items=1 ppid=1 pid=1223 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="rpc-libvirtd" exe="/usr/sbin/libvirtd" subj=system_u:system_r:virtd_t:s0 key=(null)
type=AVC msg=audit(1663363471.726:56): avc:  denied  { read } for  pid=1223 comm="rpc-libvirtd" name="msr" dev="devtmpfs" ino=85 scontext=system_u:system_r:virtd_t:s0 tcontext=system_u:object_r:cpu_device_t:s0 tclass=chr_file permissive=0
----
time->Fri Sep 16 23:28:05 2022
type=PROCTITLE msg=audit(1663363685.759:56): proctitle=2F7573722F7362696E2F6C69627669727464002D2D74696D656F757400313230
type=PATH msg=audit(1663363685.759:56): item=0 name="/dev/cpu/0/msr" inode=85 dev=00:05 mode=020600 ouid=0 ogid=0 rdev=ca:00 obj=system_u:object_r:cpu_device_t:s0 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1663363685.759:56): cwd="/"
type=SYSCALL msg=audit(1663363685.759:56): arch=c000003e syscall=257 success=no exit=-13 a0=ffffff9c a1=7fad25c9f670 a2=0 a3=0 items=1 ppid=1 pid=1204 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="rpc-libvirtd" exe="/usr/sbin/libvirtd" subj=system_u:system_r:virtd_t:s0 key=(null)
type=AVC msg=audit(1663363685.759:56): avc:  denied  { open } for  pid=1204 comm="rpc-libvirtd" path="/dev/cpu/0/msr" dev="devtmpfs" ino=85 scontext=system_u:system_r:virtd_t:s0 tcontext=system_u:object_r:cpu_device_t:s0 tclass=chr_file permissive=0
EOF


#============= virtd_t ==============
allow virtd_t cpu_device_t:chr_file { open read };

❯ selocal -a "allow virtd_t cpu_device_t:chr_file { open read };" -c my_virt-manager_000000

❯ selocal -b -L
```

```shell
❯ cat <<EOF | audit2allow
----
time->Fri Sep 16 23:31:01 2022
type=PROCTITLE msg=audit(1663363861.959:56): proctitle=2F7573722F7362696E2F6C69627669727464002D2D74696D656F757400313230
type=PATH msg=audit(1663363861.959:56): item=0 name="/dev/cpu/0/msr" inode=85 dev=00:05 mode=020600 ouid=0 ogid=0 rdev=ca:00 obj=system_u:object_r:cpu_device_t:s0 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1663363861.959:56): cwd="/"
type=SYSCALL msg=audit(1663363861.959:56): arch=c000003e syscall=257 success=no exit=-1 a0=ffffff9c a1=7f46e847c670 a2=0 a3=0 items=1 ppid=1 pid=1197 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="rpc-libvirtd" exe="/usr/sbin/libvirtd" subj=system_u:system_r:virtd_t:s0 key=(null)
type=AVC msg=audit(1663363861.959:56): avc:  denied  { sys_rawio } for  pid=1197 comm="rpc-libvirtd" capability=17  scontext=system_u:system_r:virtd_t:s0 tcontext=system_u:system_r:virtd_t:s0 tclass=capability permissive=0
EOF


#============= virtd_t ==============
allow virtd_t self:capability sys_rawio;

❯ selocal -a "allow virtd_t self:capability sys_rawio;" -c my_virt-manager_000001

❯ selocal -b -L
```

```shell
❯ cat <<EOF | audit2allow
----
time->Fri Sep 16 23:41:00 2022
type=PROCTITLE msg=audit(1663364460.659:60): proctitle="/usr/sbin/virtlogd"
type=PATH msg=audit(1663364460.659:60): item=0 name="/proc/sys/kernel/cap_last_cap" nametype=UNKNOWN cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1663364460.659:60): cwd="/"
type=SYSCALL msg=audit(1663364460.659:60): arch=c000003e syscall=257 success=no exit=-13 a0=ffffff9c a1=7f2e2ef8802a a2=0 a3=0 items=1 ppid=1 pid=1284 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="virtlogd" exe="/usr/sbin/virtlogd" subj=system_u:system_r:virtlogd_t:s0 key=(null)
type=AVC msg=audit(1663364460.659:60): avc:  denied  { search } for  pid=1284 comm="virtlogd" name="kernel" dev="proc" ino=12520 scontext=system_u:system_r:virtlogd_t:s0 tcontext=system_u:object_r:sysctl_kernel_t:s0 tclass=dir permissive=0
----
time->Fri Sep 16 23:43:15 2022
type=PROCTITLE msg=audit(1663364595.286:60): proctitle="/usr/sbin/virtlogd"
type=PATH msg=audit(1663364595.286:60): item=0 name="/proc/sys/kernel/cap_last_cap" inode=13044 dev=00:16 mode=0100444 ouid=0 ogid=0 rdev=00:00 obj=system_u:object_r:sysctl_kernel_t:s0 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1663364595.286:60): cwd="/"
type=SYSCALL msg=audit(1663364595.286:60): arch=c000003e syscall=257 success=no exit=-13 a0=ffffff9c a1=7f4091f0a02a a2=0 a3=0 items=1 ppid=1 pid=1237 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="virtlogd" exe="/usr/sbin/virtlogd" subj=system_u:system_r:virtlogd_t:s0 key=(null)
type=AVC msg=audit(1663364595.286:60): avc:  denied  { read } for  pid=1237 comm="virtlogd" name="cap_last_cap" dev="proc" ino=13044 scontext=system_u:system_r:virtlogd_t:s0 tcontext=system_u:object_r:sysctl_kernel_t:s0 tclass=file permissive=0
----
time->Fri Sep 16 23:45:38 2022
type=PROCTITLE msg=audit(1663364738.143:60): proctitle="/usr/sbin/virtlogd"
type=PATH msg=audit(1663364738.143:60): item=0 name="/proc/sys/kernel/cap_last_cap" inode=12583 dev=00:16 mode=0100444 ouid=0 ogid=0 rdev=00:00 obj=system_u:object_r:sysctl_kernel_t:s0 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1663364738.143:60): cwd="/"
type=SYSCALL msg=audit(1663364738.143:60): arch=c000003e syscall=257 success=no exit=-13 a0=ffffff9c a1=7ffbbec4802a a2=0 a3=0 items=1 ppid=1 pid=1262 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="virtlogd" exe="/usr/sbin/virtlogd" subj=system_u:system_r:virtlogd_t:s0 key=(null)
type=AVC msg=audit(1663364738.143:60): avc:  denied  { open } for  pid=1262 comm="virtlogd" path="/proc/sys/kernel/cap_last_cap" dev="proc" ino=12583 scontext=system_u:system_r:virtlogd_t:s0 tcontext=system_u:object_r:sysctl_kernel_t:s0 tclass=file permissive=0
EOF


#============= virtlogd_t ==============
allow virtlogd_t sysctl_kernel_t:dir search;
allow virtlogd_t sysctl_kernel_t:file { open read };

❯ selocal -a "allow virtlogd_t sysctl_kernel_t:dir search;" -c my_virt-manager_000002_dir
❯ selocal -a "allow virtlogd_t sysctl_kernel_t:file { open read };" -c my_virt-manager_000002_file

❯ selocal -b -L
```

```shell
❯ cat <<EOF | audit2allow
----
time->Fri Sep 16 23:48:52 2022
type=PROCTITLE msg=audit(1663364932.490:60): proctitle="/usr/sbin/virtlogd"
type=SYSCALL msg=audit(1663364932.490:60): arch=c000003e syscall=138 success=no exit=-13 a0=5 a1=7ffded86dc50 a2=0 a3=7f2967143df0 items=0 ppid=1 pid=1253 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="virtlogd" exe="/usr/sbin/virtlogd" subj=system_u:system_r:virtlogd_t:s0 key=(null)
type=AVC msg=audit(1663364932.490:60): avc:  denied  { getattr } for  pid=1253 comm="virtlogd" name="/" dev="proc" ino=1 scontext=system_u:system_r:virtlogd_t:s0 tcontext=system_u:object_r:proc_t:s0 tclass=filesystem permissive=0
EOF


#============= virtlogd_t ==============
allow virtlogd_t proc_t:filesystem getattr;

❯ selocal -a "kernel_getattr_proc(virtlogd_t)" -c my_virt-manager_000003

❯ selocal -b -L
```

```shell
❯ cat <<EOF | audit2allow
----
time->Fri Sep 16 23:52:05 2022
type=PROCTITLE msg=audit(1663365125.670:60): proctitle="/usr/sbin/virtlogd"
type=PATH msg=audit(1663365125.670:60): item=0 name="/usr/sbin/virtlogd" nametype=UNKNOWN cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1663365125.670:60): cwd="/"
type=SYSCALL msg=audit(1663365125.670:60): arch=c000003e syscall=89 success=no exit=-13 a0=7ffff4e82120 a1=7ffff4e81cc0 a2=3ff a3=1 items=1 ppid=1 pid=1298 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="virtlogd" exe="/usr/sbin/virtlogd" subj=system_u:system_r:virtlogd_t:s0 key=(null)
type=AVC msg=audit(1663365125.670:60): avc:  denied  { search } for  pid=1298 comm="virtlogd" name="sbin" dev="dm-2" ino=53969 scontext=system_u:system_r:virtlogd_t:s0 tcontext=system_u:object_r:bin_t:s0 tclass=dir permissive=0
EOF


#============= virtlogd_t ==============
allow virtlogd_t bin_t:dir search;

❯ selocal -a "allow virtlogd_t bin_t:dir search;" -c my_virt-manager_000004

❯ selocal -b -L
```

```shell
❯ cat <<EOF | audit2allow
----
time->Fri Sep 16 23:54:28 2022
type=PROCTITLE msg=audit(1663365268.836:60): proctitle="/usr/sbin/virtlogd"
type=PATH msg=audit(1663365268.836:60): item=0 name="/run/systemd/journal/socket" nametype=UNKNOWN cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1663365268.836:60): cwd="/"
type=SYSCALL msg=audit(1663365268.836:60): arch=c000003e syscall=21 success=no exit=-13 a0=7f7b39d1de7e a1=2 a2=1 a3=ce358e085363cd20 items=1 ppid=1 pid=1221 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="virtlogd" exe="/usr/sbin/virtlogd" subj=system_u:system_r:virtlogd_t:s0 key=(null)
type=AVC msg=audit(1663365268.836:60): avc:  denied  { search } for  pid=1221 comm="virtlogd" name="journal" dev="tmpfs" ino=67 scontext=system_u:system_r:virtlogd_t:s0 tcontext=system_u:object_r:syslogd_runtime_t:s0 tclass=dir permissive=0
EOF


#============= virtlogd_t ==============
allow virtlogd_t syslogd_runtime_t:dir search;

❯ selocal -a "allow virtlogd_t syslogd_runtime_t:dir search;" -c my_virt-manager_000005

❯ selocal -b -L
```

```shell
❯ cat <<EOF | audit2allow
----
time->Fri Sep 16 23:57:52 2022
type=PROCTITLE msg=audit(1663365472.796:60): proctitle="/usr/sbin/virtlogd"
type=PATH msg=audit(1663365472.796:60): item=0 name="/run/systemd/journal/socket" inode=69 dev=00:1a mode=0140666 ouid=0 ogid=0 rdev=00:00 obj=system_u:object_r:devlog_t:s0 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1663365472.796:60): cwd="/"
type=SYSCALL msg=audit(1663365472.796:60): arch=c000003e syscall=21 success=no exit=-13 a0=7fbf53001e7e a1=2 a2=1 a3=2f9a13ca77778bab items=1 ppid=1 pid=1258 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="virtlogd" exe="/usr/sbin/virtlogd" subj=system_u:system_r:virtlogd_t:s0 key=(null)
type=AVC msg=audit(1663365472.796:60): avc:  denied  { write } for  pid=1258 comm="virtlogd" name="socket" dev="tmpfs" ino=69 scontext=system_u:system_r:virtlogd_t:s0 tcontext=system_u:object_r:devlog_t:s0 tclass=sock_file permissive=0
EOF


#============= virtlogd_t ==============
allow virtlogd_t devlog_t:sock_file write;

❯ selocal -a "allow virtlogd_t devlog_t:sock_file write;" -c my_virt-manager_000006

❯ selocal -b -L
```

```shell
❯ cat <<EOF | audit2allow
----
time->Sat Sep 17 00:01:05 2022
type=PROCTITLE msg=audit(1663365665.069:60): proctitle="/usr/sbin/virtlogd"
type=SYSCALL msg=audit(1663365665.069:60): arch=c000003e syscall=41 success=no exit=-13 a0=1 a1=2 a2=0 a3=7f3284482ac0 items=0 ppid=1 pid=1287 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="virtlogd" exe="/usr/sbin/virtlogd" subj=system_u:system_r:virtlogd_t:s0 key=(null)
type=AVC msg=audit(1663365665.069:60): avc:  denied  { create } for  pid=1287 comm="virtlogd" scontext=system_u:system_r:virtlogd_t:s0 tcontext=system_u:system_r:virtlogd_t:s0 tclass=unix_dgram_socket permissive=0
EOF


#============= virtlogd_t ==============
allow virtlogd_t self:unix_dgram_socket create;

❯ selocal -a "allow virtlogd_t self:unix_dgram_socket create;" -c my_virt-manager_000007

❯ selocal -b -L
```

```shell
❯ cat <<EOF | audit2allow
----
time->Sat Sep 17 00:04:39 2022
type=PROCTITLE msg=audit(1663365879.139:60): proctitle="/usr/sbin/virtlogd"
type=PATH msg=audit(1663365879.139:60): item=0 name="/etc/ssl/openssl.cnf" nametype=UNKNOWN cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1663365879.139:60): cwd="/"
type=SYSCALL msg=audit(1663365879.139:60): arch=c000003e syscall=257 success=no exit=-13 a0=ffffff9c a1=5579e68a4a90 a2=0 a3=0 items=1 ppid=1 pid=1255 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="virtlogd" exe="/usr/sbin/virtlogd" subj=system_u:system_r:virtlogd_t:s0 key=(null)
type=AVC msg=audit(1663365879.139:60): avc:  denied  { search } for  pid=1255 comm="virtlogd" name="ssl" dev="dm-3" ino=456 scontext=system_u:system_r:virtlogd_t:s0 tcontext=system_u:object_r:cert_t:s0 tclass=dir permissive=0
----
time->Sat Sep 17 00:07:06 2022
type=PROCTITLE msg=audit(1663366026.166:60): proctitle="/usr/sbin/virtlogd"
type=PATH msg=audit(1663366026.166:60): item=0 name="/etc/ssl/openssl.cnf" inode=76254 dev=00:1f mode=0100644 ouid=0 ogid=0 rdev=00:00 obj=system_u:object_r:cert_t:s0 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1663366026.166:60): cwd="/"
type=SYSCALL msg=audit(1663366026.166:60): arch=c000003e syscall=257 success=no exit=-13 a0=ffffff9c a1=5636a04f1a90 a2=0 a3=0 items=1 ppid=1 pid=1234 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="virtlogd" exe="/usr/sbin/virtlogd" subj=system_u:system_r:virtlogd_t:s0 key=(null)
type=AVC msg=audit(1663366026.166:60): avc:  denied  { read } for  pid=1234 comm="virtlogd" name="openssl.cnf" dev="dm-3" ino=76254 scontext=system_u:system_r:virtlogd_t:s0 tcontext=system_u:object_r:cert_t:s0 tclass=file permissive=0
----
time->Sat Sep 17 00:09:55 2022
type=PROCTITLE msg=audit(1663366195.780:60): proctitle="/usr/sbin/virtlogd"
type=PATH msg=audit(1663366195.780:60): item=0 name="/etc/ssl/openssl.cnf" inode=76254 dev=00:1f mode=0100644 ouid=0 ogid=0 rdev=00:00 obj=system_u:object_r:cert_t:s0 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1663366195.780:60): cwd="/"
type=SYSCALL msg=audit(1663366195.780:60): arch=c000003e syscall=257 success=no exit=-13 a0=ffffff9c a1=55a7ed6ffa90 a2=0 a3=0 items=1 ppid=1 pid=1249 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="virtlogd" exe="/usr/sbin/virtlogd" subj=system_u:system_r:virtlogd_t:s0 key=(null)
type=AVC msg=audit(1663366195.780:60): avc:  denied  { open } for  pid=1249 comm="virtlogd" path="/etc/ssl/openssl.cnf" dev="dm-0" ino=76254 scontext=system_u:system_r:virtlogd_t:s0 tcontext=system_u:object_r:cert_t:s0 tclass=file permissive=0
----
time->Sat Sep 17 00:12:01 2022
type=PROCTITLE msg=audit(1663366321.463:60): proctitle="/usr/sbin/virtlogd"
type=PATH msg=audit(1663366321.463:60): item=0 name="" inode=76254 dev=00:1f mode=0100644 ouid=0 ogid=0 rdev=00:00 obj=system_u:object_r:cert_t:s0 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1663366321.463:60): cwd="/"
type=SYSCALL msg=audit(1663366321.463:60): arch=c000003e syscall=262 success=no exit=-13 a0=7 a1=7f168d651f13 a2=7ffd6c4a6040 a3=1000 items=1 ppid=1 pid=1235 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="virtlogd" exe="/usr/sbin/virtlogd" subj=system_u:system_r:virtlogd_t:s0 key=(null)
type=AVC msg=audit(1663366321.463:60): avc:  denied  { getattr } for  pid=1235 comm="virtlogd" path="/etc/ssl/openssl.cnf" dev="dm-2" ino=76254 scontext=system_u:system_r:virtlogd_t:s0 tcontext=system_u:object_r:cert_t:s0 tclass=file permissive=0
EOF


#============= virtlogd_t ==============
allow virtlogd_t cert_t:dir search;
allow virtlogd_t cert_t:file { getattr open read };

❯ selocal -a "allow virtlogd_t cert_t:dir search;" -c my_virt-manager_000008_dir
❯ selocal -a "allow virtlogd_t cert_t:file { getattr open read };" -c my_virt-manager_000008_file

❯ selocal -b -L
```

```shell
❯ cat <<EOF | audit2allow
----
time->Sat Sep 17 00:16:15 2022
type=PROCTITLE msg=audit(1663366575.140:63): proctitle=2F7573722F7362696E2F6C69627669727464002D2D74696D656F757400313230
type=PATH msg=audit(1663366575.140:63): item=0 name="/dev/urandom" inode=6 dev=00:37 mode=020666 ouid=0 ogid=0 rdev=01:09 obj=system_u:object_r:urandom_device_t:s0 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1663366575.140:63): cwd="/"
type=SYSCALL msg=audit(1663366575.140:63): arch=c000003e syscall=94 success=no exit=-13 a0=7fa59c01c990 a1=0 a2=0 a3=100 items=1 ppid=1190 pid=1267 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="rpc-libvirtd" exe="/usr/sbin/libvirtd" subj=system_u:system_r:virtd_t:s0 key=(null)
type=AVC msg=audit(1663366575.140:63): avc:  denied  { setattr } for  pid=1267 comm="rpc-libvirtd" name="urandom" dev="tmpfs" ino=6 scontext=system_u:system_r:virtd_t:s0 tcontext=system_u:object_r:urandom_device_t:s0 tclass=chr_file permissive=0
EOF


#============= virtd_t ==============
allow virtd_t urandom_device_t:chr_file setattr;

❯ selocal -a "allow virtd_t urandom_device_t:chr_file setattr;" -c my_virt-manager_000009

❯ selocal -b -L
```

```shell
❯ cat <<EOF | audit2allow
----
time->Sat Sep 17 00:37:01 2022
type=AVC msg=audit(1663367821.716:65): avc:  denied  { connectto } for  pid=1060 comm="auditd" path="/run/systemd/userdb/io.systemd.Machine" scontext=system_u:system_r:auditd_t:s0 tcontext=system_u:system_r:systemd_machined_t:s0 tclass=unix_stream_socket permissive=0
EOF


#============= auditd_t ==============
allow auditd_t systemd_machined_t:unix_stream_socket connectto;

❯ selocal -a "systemd_connect_machined(auditd_t)" -c my_virt-manager_000010

❯ selocal -b -L
```

```shell
❯ cat <<EOF | audit2allow
----
time->Sat Sep 17 00:40:50 2022
type=USER_AVC msg=audit(1663368050.436:63): pid=1076 uid=101 auid=4294967295 ses=4294967295 subj=system_u:system_r:system_dbusd_t:s0 msg='avc:  denied  { send_msg } for msgtype=method_call interface=org.freedesktop.machine1.Manager member=CreateMachineWithNetwork dest=org.freedesktop.machine1 spid=1215 tpid=1214 scontext=system_u:system_r:virtd_t:s0 tcontext=system_u:system_r:systemd_machined_t:s0 tclass=dbus permissive=0  exe="/usr/bin/dbus-daemon" sauid=101 hostname=? addr=? terminal=?'
EOF


#============= virtd_t ==============
allow virtd_t systemd_machined_t:dbus send_msg;

❯ selocal -a "systemd_dbus_chat_machined(virtd_t)" -c my_virt-manager_000011

❯ selocal -b -L
```

```shell
❯ cat <<EOF | audit2allow
----
time->Sat Sep 17 00:45:43 2022
type=USER_AVC msg=audit(1663368343.369:54): pid=1069 uid=101 auid=4294967295 ses=4294967295 subj=system_u:system_r:system_dbusd_t:s0 msg='avc:  denied  { send_msg } for msgtype=method_call interface=org.freedesktop.login1.Manager member=Inhibit dest=org.freedesktop.login1 spid=1227 tpid=1071 scontext=system_u:system_r:virtd_t:s0 tcontext=system_u:system_r:systemd_logind_t:s0 tclass=dbus permissive=0  exe="/usr/bin/dbus-daemon" sauid=101 hostname=? addr=? terminal=?'
EOF


#============= virtd_t ==============
allow virtd_t systemd_logind_t:dbus send_msg;

❯ selocal -a "systemd_dbus_chat_logind(virtd_t)" -c my_virt-manager_000012

❯ selocal -b -L
```

```shell
❯ cat <<EOF | audit2allow
----
time->Sat Sep 17 00:54:02 2022
type=USER_AVC msg=audit(1663368842.223:77): pid=1 uid=0 auid=4294967295 ses=4294967295 subj=system_u:system_r:init_t:s0 msg='avc:  denied  { start } for auid=n/a uid=0 gid=0 path="/run/systemd/transient/machine-qemu\x2d2\x2ddebian11.scope" cmdline="/lib/systemd/systemd-machined" function="bus_unit_queue_job" scontext=system_u:system_r:systemd_machined_t:s0 tcontext=system_u:object_r:systemd_transient_unit_t:s0 tclass=service permissive=0  exe="/lib/systemd/systemd" sauid=0 hostname=? addr=? terminal=?'
EOF


#============= systemd_machined_t ==============
allow systemd_machined_t systemd_transient_unit_t:service start;

❯ selocal -a "init_start_transient_units(systemd_machined_t)" -c my_virt-manager_000013

❯ selocal -b -L
```

```shell
❯ cat <<EOF | audit2allow
----
time->Sat Sep 17 01:14:10 2022
type=PROCTITLE msg=audit(1663370050.736:71): proctitle=2F7573722F7362696E2F6C69627669727464002D2D74696D656F757400313230
type=SYSCALL msg=audit(1663370050.736:71): arch=c000003e syscall=321 success=yes exit=0 a0=10 a1=7f69d12cb3b0 a2=80 a3=0 items=0 ppid=1 pid=1231 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="rpc-libvirtd" exe="/usr/sbin/libvirtd" subj=system_u:system_r:virtd_t:s0 key=(null)
type=AVC msg=audit(1663370050.736:71): avc:  denied  { bpf } for  pid=1231 comm="rpc-libvirtd" capability=39  scontext=system_u:system_r:virtd_t:s0 tcontext=system_u:system_r:virtd_t:s0 tclass=capability2 permissive=0
----
time->Sat Sep 17 01:20:26 2022
type=PROCTITLE msg=audit(1663370426.119:88): proctitle=2F7573722F7362696E2F6C69627669727464002D2D74696D656F757400313230
type=SYSCALL msg=audit(1663370426.119:88): arch=c000003e syscall=321 success=yes exit=31 a0=5 a1=7f8b9ce86380 a2=80 a3=40811 items=0 ppid=1 pid=1404 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="rpc-libvirtd" exe="/usr/sbin/libvirtd" subj=system_u:system_r:virtd_t:s0 key=(null)
type=BPF msg=audit(1663370426.119:88): prog-id=33 op=LOAD
type=AVC msg=audit(1663370426.119:88): avc:  denied  { perfmon } for  pid=1404 comm="rpc-libvirtd" capability=38  scontext=system_u:system_r:virtd_t:s0 tcontext=system_u:system_r:virtd_t:s0 tclass=capability2 permissive=0
EOF


#============= virtd_t ==============
allow virtd_t self:capability2 { bpf perfmon };

❯ selocal -a "allow virtd_t self:capability2 { bpf perfmon };" -c my_virt-manager_000014

❯ selocal -b -L
```

```shell
❯ cat <<EOF | audit2allow
----
time->Sat Sep 17 01:01:30 2022
type=PROCTITLE msg=audit(1663369290.669:76): proctitle=2F7573722F7362696E2F6C69627669727464002D2D74696D656F757400313230
type=SYSCALL msg=audit(1663369290.669:76): arch=c000003e syscall=321 success=no exit=-13 a0=0 a1=7faf1344e620 a2=80 a3=4 items=0 ppid=1 pid=1191 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="rpc-libvirtd" exe="/usr/sbin/libvirtd" subj=system_u:system_r:virtd_t:s0 key=(null)
type=AVC msg=audit(1663369290.669:76): avc:  denied  { map_create } for  pid=1191 comm="rpc-libvirtd" scontext=system_u:system_r:virtd_t:s0 tcontext=system_u:system_r:virtd_t:s0 tclass=bpf permissive=0
----
time->Sat Sep 17 01:04:17 2022
type=PROCTITLE msg=audit(1663369457.883:76): proctitle=2F7573722F7362696E2F6C69627669727464002D2D74696D656F757400313230
type=SYSCALL msg=audit(1663369457.883:76): arch=c000003e syscall=321 success=no exit=-13 a0=0 a1=7f1fa0756620 a2=80 a3=4 items=0 ppid=1 pid=1192 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="rpc-libvirtd" exe="/usr/sbin/libvirtd" subj=system_u:system_r:virtd_t:s0 key=(null)
type=AVC msg=audit(1663369457.883:76): avc:  denied  { map_read map_write } for  pid=1192 comm="rpc-libvirtd" scontext=system_u:system_r:virtd_t:s0 tcontext=system_u:system_r:virtd_t:s0 tclass=bpf permissive=0
----
time->Sat Sep 17 01:06:33 2022
type=PROCTITLE msg=audit(1663369593.086:76): proctitle=2F7573722F7362696E2F6C69627669727464002D2D74696D656F757400313230
type=SYSCALL msg=audit(1663369593.086:76): arch=c000003e syscall=321 success=no exit=-13 a0=5 a1=7fa821fcd380 a2=80 a3=0 items=0 ppid=1 pid=1195 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="rpc-libvirtd" exe="/usr/sbin/libvirtd" subj=system_u:system_r:virtd_t:s0 key=(null)
type=AVC msg=audit(1663369593.086:76): avc:  denied  { prog_load } for  pid=1195 comm="rpc-libvirtd" scontext=system_u:system_r:virtd_t:s0 tcontext=system_u:system_r:virtd_t:s0 tclass=bpf permissive=0
----
time->Sat Sep 17 01:09:06 2022
type=PROCTITLE msg=audit(1663369746.156:76): proctitle=2F7573722F7362696E2F6C69627669727464002D2D74696D656F757400313230
type=SYSCALL msg=audit(1663369746.156:76): arch=c000003e syscall=321 success=no exit=-13 a0=5 a1=7f53e81bb380 a2=80 a3=0 items=0 ppid=1 pid=1192 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="rpc-libvirtd" exe="/usr/sbin/libvirtd" subj=system_u:system_r:virtd_t:s0 key=(null)
type=AVC msg=audit(1663369746.156:76): avc:  denied  { prog_run } for  pid=1192 comm="rpc-libvirtd" scontext=system_u:system_r:virtd_t:s0 tcontext=system_u:system_r:virtd_t:s0 tclass=bpf permissive=0
EOF


#============= virtd_t ==============
allow virtd_t self:bpf { map_create map_read map_write prog_load prog_run };

❯ selocal -a "allow virtd_t self:bpf { map_create map_read map_write prog_load prog_run };" -c my_virt-manager_000015

❯ selocal -b -L
```

```shell
❯ cat <<EOF | audit2allow
----
time->Sat Sep 17 01:26:04 2022
type=PROCTITLE msg=audit(1663370764.663:54): proctitle=2F7573722F7362696E2F6C69627669727464002D2D74696D656F757400313230
type=PATH msg=audit(1663370764.663:54): item=0 name="/sys/kernel/debug/kvm" inode=19632 dev=00:07 mode=040755 ouid=0 ogid=0 rdev=00:00 obj=system_u:object_r:debugfs_t:s0 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1663370764.663:54): cwd="/"
type=SYSCALL msg=audit(1663370764.663:54): arch=c000003e syscall=257 success=no exit=-13 a0=ffffff9c a1=7f0548001450 a2=90800 a3=0 items=1 ppid=1 pid=1190 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="rpc-libvirtd" exe="/usr/sbin/libvirtd" subj=system_u:system_r:virtd_t:s0 key=(null)
type=AVC msg=audit(1663370764.663:54): avc:  denied  { read } for  pid=1190 comm="rpc-libvirtd" name="kvm" dev="debugfs" ino=19632 scontext=system_u:system_r:virtd_t:s0 tcontext=system_u:object_r:debugfs_t:s0 tclass=dir permissive=0
EOF


#============= virtd_t ==============
allow virtd_t debugfs_t:dir read;

❯ selocal -a "kernel_read_debugfs(virtd_t)" -c my_virt-manager_000016

❯ selocal -b -L
```

```shell
❯ cat <<EOF | audit2allow
----
time->Sat Sep 17 01:36:24 2022
type=PROCTITLE msg=audit(1663371384.123:37): proctitle=737368643A206461766964
type=SOCKADDR msg=audit(1663371384.123:37): saddr=0A00170C000000000000000000000000000000000000000100000000
type=SYSCALL msg=audit(1663371384.123:37): arch=c000003e syscall=49 success=no exit=-13 a0=7 a1=55f1bf7fb9b0 a2=1c a3=0 items=0 ppid=1097 pid=1101 auid=1000 uid=1000 gid=1000 euid=1000 suid=1000 fsuid=1000 egid=1000 sgid=1000 fsgid=1000 tty=(none) ses=1 comm="sshd" exe="/usr/sbin/sshd" subj=system_u:system_r:sshd_t:s0 key=(null)
type=AVC msg=audit(1663371384.123:37): avc:  denied  { name_bind } for  pid=1101 comm="sshd" src=5900 scontext=system_u:system_r:sshd_t:s0 tcontext=system_u:object_r:vnc_port_t:s0 tclass=tcp_socket permissive=0
EOF


#============= sshd_t ==============

#!!!! This avc can be allowed using the boolean 'sshd_port_forwarding'
allow sshd_t vnc_port_t:tcp_socket name_bind;

❯ setsebool -P sshd_port_forwarding on
```

```shell
❯ cat <<EOF | audit2allow
----
time->Sat Sep 17 02:14:55 2022
type=PROCTITLE msg=audit(1663373695.646:89): proctitle=2F7573722F62696E2F71656D752D73797374656D2D7838365F3634002D6E616D650067756573743D64656269616E31312C64656275672D746872656164733D6F6E002D53002D6F626A656374007B22716F6D2D74797065223A22736563726574222C226964223A226D61737465724B657930222C22666F726D6174223A227261
type=PATH msg=audit(1663373695.646:89): item=0 name="/proc/sys/kernel/cap_last_cap" nametype=UNKNOWN cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1663373695.646:89): cwd="/"
type=SYSCALL msg=audit(1663373695.646:89): arch=c000003e syscall=257 success=no exit=-13 a0=ffffff9c a1=7f4344a3802a a2=0 a3=0 items=1 ppid=1 pid=1377 auid=4294967295 uid=77 gid=77 euid=77 suid=77 fsuid=77 egid=77 sgid=77 fsgid=77 tty=(none) ses=4294967295 comm="qemu-system-x86" exe="/usr/bin/qemu-system-x86_64" subj=system_u:system_r:svirt_t:s0:c305,c965 key=(null)
type=AVC msg=audit(1663373695.646:89): avc:  denied  { search } for  pid=1377 comm="qemu-system-x86" name="kernel" dev="proc" ino=12981 scontext=system_u:system_r:svirt_t:s0:c305,c965 tcontext=system_u:object_r:sysctl_kernel_t:s0 tclass=dir permissive=0
----
time->Sat Sep 17 02:23:14 2022
type=PROCTITLE msg=audit(1663374194.313:87): proctitle=2F7573722F62696E2F71656D752D73797374656D2D7838365F3634002D6E616D650067756573743D64656269616E31312C64656275672D746872656164733D6F6E002D53002D6F626A656374007B22716F6D2D74797065223A22736563726574222C226964223A226D61737465724B657930222C22666F726D6174223A227261
type=PATH msg=audit(1663374194.313:87): item=0 name="/proc/sys/kernel/cap_last_cap" inode=12583 dev=00:16 mode=0100444 ouid=0 ogid=0 rdev=00:00 obj=system_u:object_r:sysctl_kernel_t:s0 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1663374194.313:87): cwd="/"
type=SYSCALL msg=audit(1663374194.313:87): arch=c000003e syscall=257 success=no exit=-13 a0=ffffff9c a1=7f4dc568102a a2=0 a3=0 items=1 ppid=1 pid=1260 auid=4294967295 uid=77 gid=77 euid=77 suid=77 fsuid=77 egid=77 sgid=77 fsgid=77 tty=(none) ses=4294967295 comm="qemu-system-x86" exe="/usr/bin/qemu-system-x86_64" subj=system_u:system_r:svirt_t:s0:c245,c487 key=(null)
type=AVC msg=audit(1663374194.313:87): avc:  denied  { read } for  pid=1260 comm="qemu-system-x86" name="cap_last_cap" dev="proc" ino=12583 scontext=system_u:system_r:svirt_t:s0:c245,c487 tcontext=system_u:object_r:sysctl_kernel_t:s0 tclass=file permissive=0
----
time->Sat Sep 17 02:27:13 2022
type=PROCTITLE msg=audit(1663374433.816:87): proctitle=2F7573722F62696E2F71656D752D73797374656D2D7838365F3634002D6E616D650067756573743D64656269616E31312C64656275672D746872656164733D6F6E002D53002D6F626A656374007B22716F6D2D74797065223A22736563726574222C226964223A226D61737465724B657930222C22666F726D6174223A227261
type=PATH msg=audit(1663374433.816:87): item=0 name="/proc/sys/kernel/cap_last_cap" inode=12478 dev=00:16 mode=0100444 ouid=0 ogid=0 rdev=00:00 obj=system_u:object_r:sysctl_kernel_t:s0 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1663374433.816:87): cwd="/"
type=SYSCALL msg=audit(1663374433.816:87): arch=c000003e syscall=257 success=no exit=-13 a0=ffffff9c a1=7fea28e8e02a a2=0 a3=0 items=1 ppid=1 pid=1252 auid=4294967295 uid=77 gid=77 euid=77 suid=77 fsuid=77 egid=77 sgid=77 fsgid=77 tty=(none) ses=4294967295 comm="qemu-system-x86" exe="/usr/bin/qemu-system-x86_64" subj=system_u:system_r:svirt_t:s0:c168,c285 key=(null)
type=AVC msg=audit(1663374433.816:87): avc:  denied  { open } for  pid=1252 comm="qemu-system-x86" path="/proc/sys/kernel/cap_last_cap" dev="proc" ino=12478 scontext=system_u:system_r:svirt_t:s0:c168,c285 tcontext=system_u:object_r:sysctl_kernel_t:s0 tclass=file permissive=0
EOF


#============= svirt_t ==============
allow svirt_t sysctl_kernel_t:dir search;
allow svirt_t sysctl_kernel_t:file { open read };

❯ selocal -a "allow svirt_t sysctl_kernel_t:dir search;" -c my_virt-manager_000017_dir
❯ selocal -a "allow svirt_t sysctl_kernel_t:file { open read };" -c my_virt-manager_000017_file

❯ selocal -b -L
```

```shell
❯ cat <<EOF | audit2allow
----
time->Sat Sep 17 02:29:45 2022
type=PROCTITLE msg=audit(1663374585.776:87): proctitle=2F7573722F62696E2F71656D752D73797374656D2D7838365F3634002D6E616D650067756573743D64656269616E31312C64656275672D746872656164733D6F6E002D53002D6F626A656374007B22716F6D2D74797065223A22736563726574222C226964223A226D61737465724B657930222C22666F726D6174223A227261
type=PATH msg=audit(1663374585.776:87): item=0 name="/sys/module/vhost/parameters/max_mem_regions" inode=32904 dev=00:17 mode=0100444 ouid=0 ogid=0 rdev=00:00 obj=system_u:object_r:sysfs_t:s0 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1663374585.776:87): cwd="/"
type=SYSCALL msg=audit(1663374585.776:87): arch=c000003e syscall=257 success=no exit=-13 a0=ffffff9c a1=56390eb16eb8 a2=0 a3=0 items=1 ppid=1 pid=1252 auid=4294967295 uid=77 gid=77 euid=77 suid=77 fsuid=77 egid=77 sgid=77 fsgid=77 tty=(none) ses=4294967295 comm="qemu-system-x86" exe="/usr/bin/qemu-system-x86_64" subj=system_u:system_r:svirt_t:s0:c210,c503 key=(null)
type=AVC msg=audit(1663374585.776:87): avc:  denied  { read } for  pid=1252 comm="qemu-system-x86" name="max_mem_regions" dev="sysfs" ino=32904 scontext=system_u:system_r:svirt_t:s0:c210,c503 tcontext=system_u:object_r:sysfs_t:s0 tclass=file permissive=0
EOF


#============= svirt_t ==============

#!!!! This avc can be allowed using one of the these booleans:
#     virt_use_sysfs, virt_use_usb
allow svirt_t sysfs_t:file read;

❯ setsebool -P virt_use_sysfs on
```

### 9.4.5. Denials: portage hooks

To make things simple I use this script to update the kernel in SELinux enforcing mode:

```shell
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
```
