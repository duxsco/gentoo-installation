In the following, I am using the [SystemRescueCD](https://www.system-rescue.org/), **not** the [official Gentoo Linux installation media](https://www.gentoo.org/downloads/). If not otherwise stated, commands are executed on the remote machine where Gentoo Linux needs to be installed, in the beginning via TTY, later on over SSH. Most of the time, you can copy&paste the whole codeblock, but understand the commands first and make adjustments (e.g. IP address, disk names) if required.

Boot into the SystemRescueCD and [set the correct keyboard layout](https://man7.org/linux/man-pages/man1/loadkeys.1.html):

```shell
loadkeys de-latin1-nodeadkeys
```

Make sure you have booted with UEFI:

```shell
[ -d /sys/firmware/efi ] && echo UEFI || echo BIOS
```

Disable "magic SysRq" for [security sake](https://wiki.gentoo.org/wiki/Vlock#Disable_SysRq_key):

```shell
sysctl -w kernel.sysrq=0
```

Do the initial setup (copy&paste one after the other):

```shell
# Start a "screen" session to better cope with networks disconnects
screen -S install

# If no automatic network setup has been done via DHCP...
nmtui

# Insert iptables rules at the correct place for SystemRescueCD to accept SSH connection requests.
# Verify with "iptables -L -v -n"
iptables -I INPUT 4 -p tcp --dport 22 -j ACCEPT -m conntrack --ctstate NEW

# Alternatively, setup /root/.ssh/authorized_keys
passwd root
```

!!! info "Using screen"
    You can detach from screen's session with ++ctrl+a+d++ and reattach with `screen -d -r install`. Scrolling works with ++ctrl+a+esc++ and ++up++ / ++down++ / ++page-up++ / ++page-down++ . You can exit "scroll mode" with ++esc++ .

Print out fingerprints to be able to double check later on upon initial SSH connection to the SystemRescueCD system:

```shell
find /etc/ssh/ -type f -name "ssh_host*\.pub" -exec ssh-keygen -vlf {} \;
```

Execute following "rsync" and "ssh" commands **on your local machine** (copy&paste one after the other):

```shell
# Copy installation files to remote machine. Don't forget to set the correct IP.
rsync -e "ssh -o VisualHostKey=yes" -av --numeric-ids --chown=0:0 {bin/{portage_hook_kernel,disk.sh,fetch_files.sh,firewall.nft,firewall.sh},overlay} root@XXX:/tmp/

# From local machine, login into the remote machine
ssh root@...
```

Resume "screen":

```shell
screen -d -r install
```

(Optional) Lock the screen on the remote machine by typing the following command on its keyboard (**not over SSH**) (copy&paste one after the other):

```shell
# If you have set /root/.ssh/authorized_keys in the previous steps
# and haven't executed "passwd" make sure to do it now for "vlock" to work.
passwd root

# Execute "vlock" without any flags first.
# If relogin doesn't work you can switch tty and set a password again.
# If relogin succeeds execute vlock with flag "-a" to lock all tty.
vlock -a
```

[Set the date and time](https://wiki.gentoo.org/wiki/Handbook:AMD64/Full/Installation#Setting_the_date_and_time) if the current system time is not correct:

```shell
! grep -q -w "hypervisor" <(grep "^flags[[:space:]]*:[[:space:]]*" /proc/cpuinfo) && \
# replace "MMDDhhmmYYYY" with UTC time
date --utc MMDDhhmmYYYY
```

Update the [hardware clock](https://wiki.gentoo.org/wiki/System_time#Hardware_clock):

```shell
! grep -q -w "hypervisor" <(grep "^flags[[:space:]]*:[[:space:]]*" /proc/cpuinfo) && \
hwclock --systohc --utc
```
