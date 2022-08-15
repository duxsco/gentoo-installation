## 9.1. Enable SELinux

Currently, I only use SELinux on servers, and only `mcs` policy type to be able to "isolate" virtual machines from each other.

```bash
echo 'POLICY_TYPES="mcs"' >> /etc/portage/make.conf
eselect profile set --force 18 # should be "[18]  default/linux/amd64/17.1/systemd/selinux (exp)"
FEATURES="-selinux" emerge -1 selinux-base
sed -i 's/^SELINUXTYPE=strict$/SELINUXTYPE=mcs/' /etc/selinux/config
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
emerge -at sys-kernel/gentoo-kernel-bin
```

## 9.2. Relabel

[Relabel the entire system](https://wiki.gentoo.org/wiki/SELinux/Installation#Relabel):

```bash
mkdir /mnt/gentoo
mount -o bind / /mnt/gentoo
setfiles -r /mnt/gentoo /etc/selinux/mcs/contexts/files/file_contexts /mnt/gentoo/{dev,home,proc,run,sys,tmp,efi*,var/cache/binpkgs,var/cache/distfiles,var/db/repos/gentoo,var/tmp}
umount /mnt/gentoo
rlpkg -a -r
```

In the [custom Gentoo Linux installation](https://github.com/duxsco/gentoo-installation), the SSH port has been changed to 50022. This needs to be considered for no SELinux denials to occur:

```bash
➤ semanage port -l | grep -e ssh -e Port
SELinux Port Type              Proto    Port Number
ssh_port_t                     tcp      22
➤ semanage port -a -t ssh_port_t -p tcp 50022
➤ semanage port -l | grep -e ssh -e Port
SELinux Port Type              Proto    Port Number
ssh_port_t                     tcp      50022, 22
```

## 9.3. SELinux policies

The following log entries were retrieved over a serial connection while booting the test VM into enforcing mode.

### 9.3.1. Exclusion of dontaudit denials

The following audit logs don't contain those `dontaudit` ones.

```bash
# [   40.783704] audit: type=1400 audit(1659801628.356:3): avc:  denied  { read } for  pid=3418 comm="10-gentoo-path" name="profile.env" dev="dm-2" ino=2237658 scontext=system_u:system_r:systemd_generator_t:s0 tcontext=system_u:object_r:etc_runtime_t:s0 tclass=file permissive=0

❯ find / -inum 2237658
/etc/profile.env

❯ semanage fcontext -l | grep '/etc/profile\\\.env' | column -t
/etc/profile\.env  regular  file  system_u:object_r:etc_runtime_t:s0

❯ sesearch -A -s systemd_generator_t -c file -p read | grep etc
allow systemd_generator_t etc_t:file { getattr ioctl lock map open read };
allow systemd_generator_t lvm_etc_t:file { getattr ioctl lock map open read };

❯ semanage fcontext -m -f f -t etc_t '/etc/profile\.env'

❯ restorecon -RFv /etc/profile.env
Relabeled /etc/profile.env from system_u:object_r:etc_runtime_t:s0 to system_u:object_r:etc_t:s0
```

```bash
❯ cat <<EOF | audit2allow
[   38.215380] audit: type=1400 audit(1659803032.739:3): avc:  denied  { create } for  pid=1 comm="systemd" name="io.systemd.NameServiceSwitch" scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:systemd_userdbd_runtime_t:s0 tclass=lnk_file permissive=0
# [   38.218433] systemd[1]: systemd-userdbd.socket: Failed to create symlink /run/systemd/userdb/io.systemd.Multiplexer → /run/systemd/userdb/io.systemd.NameServiceSwitch, ignoring: Permission denied
# [   38.223036] systemd[1]: systemd-userdbd.socket: Failed to create symlink /run/systemd/userdb/io.systemd.Multiplexer → /run/systemd/userdb/io.systemd.DropIn, ignoring: Permission denied
[   38.223037] audit: type=1400 audit(1659803032.749:4): avc:  denied  { create } for  pid=1 comm="systemd" name="io.systemd.DropIn" scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:systemd_userdbd_runtime_t:s0 tclass=lnk_file permissive=0
EOF


#============= init_t ==============
allow init_t systemd_userdbd_runtime_t:lnk_file create;

❯ selocal -a "allow init_t systemd_userdbd_runtime_t:lnk_file create;" -c my_000000

❯ selocal -b -L
```

```bash
❯ cat <<EOF | audit2allow
[   38.348743] audit: type=1400 audit(1659804660.863:3): avc:  denied  { mounton } for  pid=3192 comm="(-userdbd)" path="/run/systemd/unit-root/proc" dev="dm-0" ino=67034 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:unlabeled_t:s0 tclass=dir permissive=0
EOF


#============= init_t ==============
allow init_t unlabeled_t:dir mounton;

❯ selocal -a "allow init_t unlabeled_t:dir mounton;" -c my_000001

❯ selocal -b -L
```

```bash
❯ cat <<EOF | audit2allow
[   38.650222] audit: type=1400 audit(1659806737.170:3): avc:  denied  { write } for  pid=3391 comm="systemd-udevd" name="systemd-udevd.service" dev="cgroup2" ino=2051 scontext=system_u:system_r:udev_t:s0 tcontext=system_u:object_r:cgroup_t:s0 tclass=dir permissive=0
[   39.204268] audit: type=1400 audit(1659808040.666:3): avc:  denied  { add_name } for  pid=3290 comm="systemd-udevd" name="udev" scontext=system_u:system_r:udev_t:s0 tcontext=system_u:object_r:cgroup_t:s0 tclass=dir permissive=0
[   39.817148] audit: type=1400 audit(1659809598.336:3): avc:  denied  { create } for  pid=3405 comm="systemd-udevd" name="udev" scontext=system_u:system_r:udev_t:s0 tcontext=system_u:object_r:cgroup_t:s0 tclass=dir permissive=0
[   41.510248] audit: type=1400 audit(1659810088.010:3): avc:  denied  { write } for  pid=3202 comm="systemd-udevd" name="cgroup.procs" dev="cgroup2" ino=2086 scontext=system_u:system_r:udev_t:s0 tcontext=system_u:object_r:cgroup_t:s0 tclass=file permissive=0
EOF


#============= udev_t ==============

#!!!! This avc is allowed in the current policy
allow udev_t cgroup_t:dir { add_name create write };
allow udev_t cgroup_t:file write;

❯ selocal -a "allow udev_t cgroup_t:dir { add_name create write };" -c my_000002_dir

❯ selocal -a "allow udev_t cgroup_t:file write;" -c my_000002_file

❯ selocal -b -L
```

```bash
❯ cat <<EOF | audit2allow
[   39.016492] audit: type=1400 audit(1659813497.523:3): avc:  denied  { read } for  pid=3405 comm="systemd-udevd" name="network" dev="tmpfs" ino=78 scontext=system_u:system_r:udev_t:s0 tcontext=system_u:object_r:init_runtime_t:s0 tclass=dir permissive=0
EOF


#============= udev_t ==============
allow udev_t init_runtime_t:dir read;

❯ selocal -a "allow udev_t init_runtime_t:dir read;" -c my_000003

❯ selocal -b -L
```

```bash
❯ cat <<EOF | audit2allow
[   39.725495] audit: type=1400 audit(1659818788.233:3): avc:  denied  { getattr } for  pid=3318 comm="mdadm" path="/run/udev" dev="tmpfs" ino=71 scontext=system_u:system_r:mdadm_t:s0 tcontext=system_u:object_r:udev_runtime_t:s0 tclass=dir permissive=0
EOF


#============= mdadm_t ==============
allow mdadm_t udev_runtime_t:dir getattr;

❯ selocal -a "allow mdadm_t udev_runtime_t:dir getattr;" -c my_000004

❯ selocal -b -L
```

```bash
❯ cat <<EOF | audit2allow
[   39.729566] audit: type=1400 audit(1659818788.233:4): avc:  denied  { search } for  pid=3318 comm="mdadm" name="block" dev="debugfs" ino=29 scontext=system_u:system_r:mdadm_t:s0 tcontext=system_u:object_r:debugfs_t:s0 tclass=dir permissive=0
[   39.732824] audit: type=1400 audit(1659818788.233:5): avc:  denied  { search } for  pid=3318 comm="mdadm" name="bdi" dev="debugfs" ino=22 scontext=system_u:system_r:mdadm_t:s0 tcontext=system_u:object_r:debugfs_t:s0 tclass=dir permissive=0
EOF


#============= mdadm_t ==============
allow mdadm_t debugfs_t:dir search;

❯ selocal -a "allow mdadm_t debugfs_t:dir search;" -c my_000005

❯ selocal -b -L
```

```bash
❯ cat <<EOF | audit2allow
[   39.069622] audit: type=1400 audit(1659889748.730:3): avc:  denied  { getattr } for  pid=26 comm="kdevtmpfs" path="/fb0" dev="devtmpfs" ino=152 scontext=system_u:system_r:kernel_t:s0 tcontext=system_u:object_r:framebuf_device_t:s0 tclass=chr_file permissive=0
EOF


#============= kernel_t ==============
allow kernel_t framebuf_device_t:chr_file getattr;

❯ selocal -a "allow kernel_t framebuf_device_t:chr_file getattr;" -c my_000006

❯ selocal -b -L
```

```bash
❯ cat <<EOF | audit2allow
[   39.408676] audit: type=1400 audit(1659890472.969:3): avc:  denied  { setattr } for  pid=26 comm="kdevtmpfs" name="fb0" dev="devtmpfs" ino=152 scontext=system_u:system_r:kernel_t:s0 tcontext=system_u:object_r:framebuf_device_t:s0 tclass=chr_file permissive=0
[   39.411761] audit: type=1400 audit(1659890472.969:4): avc:  denied  { unlink } for  pid=26 comm="kdevtmpfs" name="fb0" dev="devtmpfs" ino=152 scontext=system_u:system_r:kernel_t:s0 tcontext=system_u:object_r:framebuf_device_t:s0 tclass=chr_file permissive=0
EOF


#============= kernel_t ==============
allow kernel_t framebuf_device_t:chr_file { setattr unlink };

❯ selocal -a "allow kernel_t framebuf_device_t:chr_file { setattr unlink };" -c my_000007

❯ selocal -b -L
```

```bash
# [   38.924284] audit: type=1400 audit(1659892115.476:7): avc:  denied  { getattr } for  pid=3351 comm="loadkeys" path="/root" dev="dm-2" ino=67027 scontext=system_u:system_r:udev_t:s0 tcontext=system_u:object_r:default_t:s0 tclass=dir permissive=0

# fcontext under "strict"
# semanage fcontext -l | grep "^/root"
❯ my_fcontext="/root                                              directory          root:object_r:user_home_dir_t
/root/((www)|(web)|(public_html))(/.*)?/\.htaccess regular file       root:object_r:httpd_user_htaccess_t
/root/((www)|(web)|(public_html))(/.*)?/logs(/.*)? all files          root:object_r:httpd_user_ra_content_t
/root/((www)|(web)|(public_html))(/.+)?            all files          root:object_r:httpd_user_content_t
/root/((www)|(web)|(public_html))/cgi-bin(/.+)?    all files          root:object_r:httpd_user_script_exec_t
/root/.+                                           all files          root:object_r:user_home_t
/root/Documents(/.*)?                              all files          root:object_r:xdg_documents_t
/root/DovecotMail(/.*)?                            all files          root:object_r:mail_home_rw_t
/root/Downloads(/.*)?                              all files          root:object_r:xdg_downloads_t
/root/Maildir(/.*)?                                all files          root:object_r:mail_home_rw_t
/root/Music(/.*)?                                  all files          root:object_r:xdg_music_t
/root/Pictures(/.*)?                               all files          root:object_r:xdg_pictures_t
/root/Videos(/.*)?                                 all files          root:object_r:xdg_videos_t
/root/\.cache(/.*)?                                all files          root:object_r:xdg_cache_t
/root/\.config(/.*)?                               all files          root:object_r:xdg_config_t
/root/\.config/git(/.*)?                           all files          root:object_r:git_xdg_config_t
/root/\.config/systemd(/.*)?                       all files          root:object_r:systemd_conf_home_t
/root/\.config/tmux(/.*)?                          regular file       root:object_r:screen_home_t
/root/\.dbus(/.*)?                                 all files          root:object_r:session_dbusd_home_t
/root/\.default_contexts                           regular file       system_u:object_r:default_context_t
/root/\.esmtp_queue                                regular file       root:object_r:mail_home_t
/root/\.forward[^/]*                               regular file       root:object_r:mail_home_t
/root/\.gitconfig                                  regular file       root:object_r:git_xdg_config_t
/root/\.gnupg(/.+)?                                all files          root:object_r:gpg_secret_t
/root/\.gnupg/S\.gpg-agent.*                       socket             root:object_r:gpg_agent_tmp_t
/root/\.gnupg/S\.scdaemon                          socket             root:object_r:gpg_agent_tmp_t
/root/\.gnupg/crls\.d(/.+)?                        all files          root:object_r:dirmngr_home_t
/root/\.gnupg/log-socket                           socket             root:object_r:gpg_agent_tmp_t
/root/\.k5login                                    regular file       root:object_r:krb5_home_t
/root/\.local(/.*)?                                all files          root:object_r:xdg_data_t
/root/\.local/bin(/.*)?                            all files          root:object_r:user_bin_t
/root/\.local/share/systemd(/.*)?                  all files          root:object_r:systemd_data_home_t
/root/\.maildir(/.*)?                              all files          root:object_r:mail_home_rw_t
/root/\.mailrc                                     regular file       root:object_r:mail_home_t
/root/\.msmtprc                                    regular file       root:object_r:mail_home_t
/root/\.pki(/.*)?                                  all files          root:object_r:user_cert_t
/root/\.screen(/.*)?                               all files          root:object_r:screen_home_t
/root/\.screenrc                                   regular file       root:object_r:screen_home_t
/root/\.ssh(/.*)?                                  all files          root:object_r:ssh_home_t
/root/\.tmux\.conf                                 regular file       root:object_r:screen_home_t
/root/bin(/.*)?                                    all files          root:object_r:user_bin_t
/root/dead\.letter                                 regular file       root:object_r:mail_home_t
/root/public_git(/.*)?                             all files          root:object_r:git_user_content_t"

❯ while read -r line; do
    case $(awk '{print $2}' <<<"${line}") in
        regular)
            file_type="f";;
        directory)
            file_type="d";;
        character)
            file_type="c";;
        block)
            file_type="b";;
        socket)
            file_type="s";;
        symbolic)
            file_type="l";;
        named)
            file_type="p";;
        all)
            file_type="a";;
    esac

    selinux_user="$(awk -F':' '{print $(NF-2)}' <<<"${line}" | awk '{print $NF}')"
    selinux_type="$(awk -F':' '{print $NF}' <<<"${line}")"
    path="$(awk '{print $1}' <<<"${line}")"

    semanage fcontext -a -f "${file_type}" -s "${selinux_user}" -t "${selinux_type}" "${path}" || \
    semanage fcontext -m -f "${file_type}" -s "${selinux_user}" -t "${selinux_type}" "${path}"
done <<<"${my_fcontext}"

❯ restorecon -RFv /root
```

```bash
❯ cat <<EOF | audit2allow
[   40.218232] audit: type=1400 audit(1659904082.793:3): avc:  denied  { read write } for  pid=1 comm="systemd" name="rfkill" dev="devtmpfs" ino=178 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:wireless_device_t:s0 tclass=chr_file permissive=0
[   39.054725] audit: type=1400 audit(1659906160.603:3): avc:  denied  { open } for  pid=1 comm="systemd" path="/dev/rfkill" dev="devtmpfs" ino=178 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:wireless_device_t:s0 tclass=chr_file permissive=0
EOF


#============= init_t ==============
allow init_t wireless_device_t:chr_file { open read write };

❯ selocal -a "allow init_t wireless_device_t:chr_file { open read write };" -c my_000008

❯ selocal -b -L
```

```bash
❯ cat <<EOF | audit2allow
[   39.048851] audit: type=1400 audit(1659906509.586:3): avc:  denied  { execute } for  pid=3175 comm="(bootctl)" name="bootctl" dev="dm-1" ino=2234398 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:bootloader_exec_t:s0 tclass=file permissive=0
[   39.132364] audit: type=1400 audit(1659907055.619:3): avc:  denied  { read open } for  pid=3167 comm="(bootctl)" path="/usr/bin/bootctl" dev="dm-3" ino=2234398 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:bootloader_exec_t:s0 tclass=file permissive=0
[   39.413367] audit: type=1400 audit(1659908226.933:3): avc:  denied  { execute_no_trans } for  pid=3470 comm="(bootctl)" path="/usr/bin/bootctl" dev="dm-0" ino=2234398 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:bootloader_exec_t:s0 tclass=file permissive=0
[   40.029697] audit: type=1400 audit(1659908634.563:3): avc:  denied  { map } for  pid=3473 comm="bootctl" path="/usr/bin/bootctl" dev="dm-0" ino=2234398 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:bootloader_exec_t:s0 tclass=file permissive=0
EOF


#============= init_t ==============
allow init_t bootloader_exec_t:file { execute execute_no_trans map open read };

❯ selocal -a "allow init_t bootloader_exec_t:file { execute execute_no_trans map open read };" -c my_000009

❯ selocal -b -L
```

```bash
❯ cat <<EOF | audit2allow
[   40.774118] audit: type=1400 audit(1659904083.350:6): avc:  denied  { getattr } for  pid=3282 comm="systemd-tmpfile" path="/var/cache/eix" dev="dm-0" ino=76668 scontext=system_u:system_r:systemd_tmpfiles_t:s0 tcontext=system_u:object_r:portage_cache_t:s0 tclass=dir permissive=0
[   40.779591] audit: type=1400 audit(1659904083.350:7): avc:  denied  { read } for  pid=3282 comm="systemd-tmpfile" name="eix" dev="dm-0" ino=76668 scontext=system_u:system_r:systemd_tmpfiles_t:s0 tcontext=system_u:object_r:portage_cache_t:s0 tclass=dir permissive=0
EOF


#============= systemd_tmpfiles_t ==============

#!!!! This avc can be allowed using the boolean 'systemd_tmpfiles_manage_all'
allow systemd_tmpfiles_t portage_cache_t:dir { getattr read };

❯ setsebool -P systemd_tmpfiles_manage_all on
```

```bash
❯ cat <<EOF | audit2allow
[   40.289519] audit: type=1400 audit(1659909973.819:3): avc:  denied  { mounton } for  pid=3379 comm="(resolved)" path="/run/systemd/unit-root/run/systemd/resolve" dev="tmpfs" ino=1544 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:systemd_resolved_runtime_t:s0 tclass=dir permissive=0
EOF


#============= init_t ==============

#!!!! This avc can be allowed using the boolean 'init_mounton_non_security'
allow init_t systemd_resolved_runtime_t:dir mounton;

❯ setsebool -P init_mounton_non_security on
```

```bash
# [   39.984771] audit: type=1400 audit(1659910969.506:3): avc:  denied  { getattr } for  pid=3292 comm="nft" path="/var/lib/nftables/rules-save" dev="dm-0" ino=2333394 scontext=system_u:system_r:iptables_t:s0 tcontext=system_u:object_r:var_lib_t:s0 tclass=file permissive=0

❯ semanage fcontext -l | grep -i "/var/lib" | grep tables | column -t
/var/lib/ip6?tables(/.*)?  all  files  system_u:object_r:initrc_tmp_t:s0

❯ semanage fcontext -a -f a -s system_u -t initrc_tmp_t '/var/lib/nftables(/[^\.].*)?'

❯ restorecon -RFv /var/lib/nftables
Relabeled /var/lib/nftables from system_u:object_r:var_lib_t:s0 to system_u:object_r:initrc_tmp_t:s0
Relabeled /var/lib/nftables/rules-save from system_u:object_r:var_lib_t:s0 to system_u:object_r:initrc_tmp_t:s0
```

```bash
❯ cat <<EOF | audit2allow
[   40.155132] audit: type=1400 audit(1659912307.676:3): avc:  denied  { read } for  pid=3318 comm="systemd-network" name="network" dev="tmpfs" ino=78 scontext=system_u:system_r:systemd_networkd_t:s0 tcontext=system_u:object_r:init_runtime_t:s0 tclass=dir permissive=0
[   40.558773] audit: type=1400 audit(1659912839.089:3): avc:  denied  { getattr } for  pid=3309 comm="systemd-network" path="/run/systemd/network/90-enp1s0.network" dev="tmpfs" ino=80 scontext=system_u:system_r:systemd_networkd_t:s0 tcontext=system_u:object_r:init_runtime_t:s0 tclass=file permissive=0
[   49.671301] audit: type=1400 audit(1660397172.236:3): avc:  denied  { read } for  pid=3507 comm="systemd-network" name="90-enp1s0.network" dev="tmpfs" ino=80 scontext=system_u:system_r:systemd_networkd_t:s0 tcontext=system_u:object_r:init_runtime_t:s0 tclass=file permissive=0
[   40.820487] audit: type=1400 audit(1660397629.459:3): avc:  denied  { open } for  pid=3305 comm="systemd-network" path="/run/systemd/network/90-enp1s0.network" dev="tmpfs" ino=79 scontext=system_u:system_r:systemd_networkd_t:s0 tcontext=system_u:object_r:init_runtime_t:s0 tclass=file permissive=0
[   40.436302] audit: type=1400 audit(1660398037.003:3): avc:  denied  { ioctl } for  pid=3304 comm="systemd-network" path="/run/systemd/network/90-enp1s0.network" dev="tmpfs" ino=79 ioctlcmd=0x5401 scontext=system_u:system_r:systemd_networkd_t:s0 tcontext=system_u:object_r:init_runtime_t:s0 tclass=file permissive=0
EOF


#============= systemd_networkd_t ==============
allow systemd_networkd_t init_runtime_t:dir read;
allow systemd_networkd_t init_runtime_t:file { getattr ioctl open read };

❯ selocal -a "allow systemd_networkd_t init_runtime_t:dir read;" -c my_000010_dir
❯ selocal -a "allow systemd_networkd_t init_runtime_t:file { getattr ioctl open read };" -c my_000010_file

❯ selocal -b -L
```

```bash
❯ cat <<EOF | audit2allow
[   41.110108] audit: type=1400 audit(1660400958.629:3): avc:  denied  { relabelto } for  pid=3318 comm="(unbound)" name="/" dev="tmpfs" ino=1 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:named_conf_t:s0 tclass=dir permissive=0
[   40.552975] audit: type=1400 audit(1660402251.079:3): avc:  denied  { write } for  pid=3407 comm="(unbound)" name="/" dev="tmpfs" ino=1 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:named_conf_t:s0 tclass=dir permissive=0
[   40.297757] audit: type=1400 audit(1660402820.809:3): avc:  denied  { add_name } for  pid=3306 comm="(unbound)" name="log" scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:named_conf_t:s0 tclass=dir permissive=0
[   39.927797] audit: type=1400 audit(1660403248.466:3): avc:  denied  { create } for  pid=3415 comm="(unbound)" name="log" scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:named_conf_t:s0 tclass=file permissive=0
[   39.828873] audit: type=1400 audit(1660403547.326:3): avc:  denied  { create } for  pid=3316 comm="(unbound)" name="systemd" scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:named_conf_t:s0 tclass=dir permissive=0
EOF


#============= init_t ==============
allow init_t named_conf_t:dir { add_name create relabelto write };
allow init_t named_conf_t:file create;

❯ selocal -a "allow init_t named_conf_t:dir { add_name create relabelto write };" -c my_000011_dir
❯ selocal -a "allow init_t named_conf_t:file create;" -c my_000011_file

❯ selocal -b -L
```

```bash
❯ cat <<EOF | audit2allow
[   56.466014] audit: type=1400 audit(1660417565.086:3): avc:  denied  { watch watch_reads } for  pid=3813 comm="(agetty)" path="/dev/tty1" dev="devtmpfs" ino=20 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:tty_device_t:s0 tclass=chr_file permissive=0
[   56.603505] audit: type=1400 audit(1660417565.226:10): avc:  denied  { watch watch_reads } for  pid=3821 comm="(agetty)" path="/dev/ttyS0" dev="devtmpfs" ino=96 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:tty_device_t:s0 tclass=chr_file permissive=0
[   56.479764] audit: type=1400 audit(1660417565.103:5): avc:  denied  { setattr } for  pid=1 comm="systemd" name="ttyS0" dev="devtmpfs" ino=96 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:tty_device_t:s0 tclass=chr_file permissive=0
EOF


#============= init_t ==============
allow init_t tty_device_t:chr_file { setattr watch watch_reads };

❯ selocal -a "allow init_t tty_device_t:chr_file { setattr watch watch_reads };" -c my_000012

❯ selocal -b -L
```

### 9.3.2. Inclusion of dontaudit denials

At this point, a login is still not possible. So, a look has to be taken at those `dontaudit` denials:

```bash
semodule --disable_dontaudit --build
```

TODO
