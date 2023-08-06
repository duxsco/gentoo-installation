## 7.1. Account Creation

Create a [non-root user](https://wiki.gentoo.org/wiki/Handbook:AMD64/Full/Installation#Optional:_User_accounts) with ["wheel" group membership and thus the privilege to use "sudo"](https://wiki.gentoo.org/wiki/FAQ#How_do_I_add_a_normal_user.3F):

```shell
useradd -m -G wheel -s /bin/bash david && \
chmod u=rwx,og= /home/david && \
echo -e 'alias cp="cp -i"\nalias mv="mv -i"\nalias rm="rm -i"' >> /home/david/.bash_aliases && \
chown david:david /home/david/.bash_aliases && \
echo 'source "${HOME}/.bash_aliases"' >> /home/david/.bashrc && \
passwd david
```

## 7.2. Access Control

Setup [app-admin/sudo](https://wiki.gentoo.org/wiki/Sudo):

```shell
echo "app-admin/sudo -sendmail" >> /etc/portage/package.use/main && \
emerge app-admin/sudo && \
{ [[ -d /etc/sudoers.d ]] || mkdir -m u=rwx,g=rx,o= /etc/sudoers.d; } && \
echo "%wheel ALL=(ALL) ALL" | EDITOR="tee" visudo -f /etc/sudoers.d/wheel && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Setup SSH client config:

```shell
mkdir -m 0700 /home/david/.ssh && \
echo "AddKeysToAgent no
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
HashKnownHosts no
StrictHostKeyChecking ask
VisualHostKey yes" > /home/david/.ssh/config && \
chown -R david:david /home/david/.ssh && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

## 7.3. ~/.bashrc and chroot

Add the following to "/root/.bashrc"
for [chroot.sh](https://github.com/duxsco/gentoo-installation/blob/main/bin/disk.sh#L281) to work:

```shell
echo '
# Use fish in place of bash
# keep this line at the bottom of ~/.bashrc
if [[ -z ${chrooted} ]]; then
    if [[ -x /bin/fish ]]; then
        SHELL=/bin/fish exec /bin/fish
    fi
elif [[ -z ${chrooted_su} ]]; then
    export chrooted_su=true
    source /etc/profile && su --login --whitelist-environment=chrooted,chrooted_su
else
    env-update && source /etc/profile && export PS1="(chroot) $PS1"
fi' >> /root/.bashrc
```

## 7.4. (Optional) VIM Editor

Setup [app-editors/vim](https://wiki.gentoo.org/wiki/Vim):

```shell hl_lines="2"
emerge -at app-editors/vim app-vim/molokai && \
rsync -a /etc/portage/make.conf /etc/portage/._cfg0000_make.conf && \
sed -i 's/^USE="\([^"]*\)"$/USE="\1 vim-syntax"/' /etc/portage/._cfg0000_make.conf && \
echo "filetype plugin on
filetype indent on
set number
set paste
syntax on
colorscheme molokai

if &diff
  colorscheme murphy
endif" | tee -a /root/.vimrc >> /home/david/.vimrc  && \
chown david:david /home/david/.vimrc && \
eselect editor set vi && \
eselect vi set vim && \
env-update && source /etc/profile && export PS1="(chroot) $PS1" && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

## 7.5. (Optional) starship, fish shell and nerd fonts

Install [app-shells/starship](https://starship.rs/):

```shell
# If you have insufficient ressources, you may want to execute "emerge --oneshot dev-lang/rust-bin" beforehand.
echo "app-shells/starship ~amd64" >> /etc/portage/package.accept_keywords/main && \
emerge app-shells/starship && \
{ [[ -d /home/david/.config ]] || mkdir --mode=0700 /home/david/.config; } && \
{ [[ -d /root/.config ]] || mkdir --mode=0700 /root/.config; } && \
touch /home/david/.config/starship.toml && \
chown -R david:david /home/david/.config && \
starship preset nerd-font-symbols | tee /root/.config/starship.toml > /home/david/.config/starship.toml && \
sed -i -e '/^\[hostname\]$/a format = "\[$hostname\](bold red) "' -e '/^\[hostname\]$/a ssh_only = false' /root/.config/starship.toml /home/david/.config/starship.toml && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Install [app-shells/fish](https://wiki.gentoo.org/wiki/Fish):

```shell hl_lines="4"
echo "=dev-libs/libpcre2-$(qatom -F "%{PVR}" "$(portageq best_visible / dev-libs/libpcre2)") pcre32" >> /etc/portage/package.use/main && \
echo "app-shells/fish ~amd64" >> /etc/portage/package.accept_keywords/main && \
emerge app-shells/fish && \
rsync -a /etc/portage/make.conf /etc/portage/._cfg0000_make.conf && \
sed -i 's/^USE="\([^"]*\)"$/USE="\1 fish-completion"/' /etc/portage/._cfg0000_make.conf && \
echo '
# Use fish in place of bash
# keep this line at the bottom of ~/.bashrc
if [[ -x /bin/fish ]]; then
    SHELL=/bin/fish exec /bin/fish
fi' >> /home/david/.bashrc && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Setup [auto-completion for the fish shell](https://wiki.archlinux.org/title/fish#Command_completion) (copy&paste one command after the other):

``` { .shell .no-copy }
# root
/bin/fish -c fish_update_completions

# non-root
su -l david -c "/bin/fish -c fish_update_completions"
```

Enable aliases and starship (copy&paste one command after the other):

``` { .shell .no-copy }
su -
exit
su - david
exit
sed -i 's/^end$/    source "$HOME\/.bash_aliases"\n    starship init fish | source\nend/' /root/.config/fish/config.fish
sed -i 's/^end$/    source "$HOME\/.bash_aliases"\n    starship init fish | source\nend/' /home/david/.config/fish/config.fish
```

Install [nerd fonts](https://www.nerdfonts.com/):

```shell
emerge media-libs/fontconfig && \
su -l david -c "curl --proto '=https' --tlsv1.3 -fsSL -o /tmp/FiraCode.tar.xz https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/FiraCode.tar.xz" && \
b2sum -c <<<"e2df25cfe81c8f0b2d64f0bf199fa3ec856aad3293d583a1dc80cb3d6a47a5352c417e8f377984e788724f487e34f4b49bd8ab207fbb4fd68191b969886657e6  /tmp/FiraCode.tar.xz" && \
mkdir /tmp/FiraCode && \
tar -C /tmp/FiraCode/ -xf /tmp/FiraCode.tar.xz && \
mkdir /usr/share/fonts/nerd-firacode && \
rsync -a --chown=0:0 --chmod=a=r /tmp/FiraCode/*.ttf /usr/share/fonts/nerd-firacode/ && \
echo -e "\e[1;32mSUCCESS\e[0m"
```
