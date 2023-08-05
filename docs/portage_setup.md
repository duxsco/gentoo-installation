!!! info "Application of configuration changes"
    Starting with this chapter, **execute [dispatch-conf](https://wiki.gentoo.org/wiki/Dispatch-conf) after every codeblock** where a [".\_cfg0000_" prefixed file](https://projects.gentoo.org/pms/8/pms.html#x1-14600013.3.3) has been created. {==The creation of ".\_cfg0000_" prefixed files will be highlighted in yellow.==} Alternatively, [etc-update](https://wiki.gentoo.org/wiki/Handbook:X86/Portage/Tools#etc-update) or [cfg-update](https://wiki.gentoo.org/wiki/Cfg-update) might be s.th. to consider, but I haven't tested those.

Make "dispatch-conf" show [diffs in color](https://wiki.gentoo.org/wiki/Dispatch-conf#Changing_diff_or_merge_tools) and use [vimdiff for merging](https://wiki.gentoo.org/wiki/Dispatch-conf#Use_.28g.29vimdiff_to_merge_changes):

```shell hl_lines="1"
rsync -a /etc/dispatch-conf.conf /etc/._cfg0000_dispatch-conf.conf && \
sed -i \
-e "s/diff=\"diff -Nu '%s' '%s'\"/diff=\"diff --color=always -Nu '%s' '%s'\"/" \
-e "s/merge=\"sdiff --suppress-common-lines --output='%s' '%s' '%s'\"/merge=\"vimdiff -c'saveas %s' -c next -c'setlocal noma readonly' -c prev %s %s\"/" \
/etc/._cfg0000_dispatch-conf.conf && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

## 6.1. Portage Configuration

Configure [make.conf](https://wiki.gentoo.org/wiki//etc/portage/make.conf) (copy&paste one after the other):

``` { .shell hl_lines="1" .no-copy }
rsync -av /etc/portage/make.conf /etc/portage/._cfg0000_make.conf

# If you use distcc, beware of:
# https://wiki.gentoo.org/wiki/Distcc#-march.3Dnative
#
# You could resolve "-march=native" with app-misc/resolve-march-native
sed -i 's/COMMON_FLAGS="-O2 -pipe"/COMMON_FLAGS="-march=native -O2 -pipe"/' /etc/portage/._cfg0000_make.conf

# https://wiki.gentoo.org/wiki/EMERGE_DEFAULT_OPTS
# https://wiki.gentoo.org/wiki/Binary_package_guide#Excluding_creation_of_some_packages
#
# For all other flags, take a look at "man emerge" or
# https://gitweb.gentoo.org/proj/portage.git/tree/man/emerge.1
echo 'EMERGE_DEFAULT_OPTS="--buildpkg --buildpkg-exclude '\''*/*-bin sys-kernel/* virtual/*'\'' --noconfmem --with-bdeps=y --complete-graph=y"' >> /etc/portage/._cfg0000_make.conf

# https://wiki.gentoo.org/wiki/Localization/Guide#L10N
# https://wiki.gentoo.org/wiki/Localization/Guide#LINGUAS
echo '
L10N="de"
LINGUAS="${L10N}"' >> /etc/portage/._cfg0000_make.conf

# https://wiki.gentoo.org/wiki/GENTOO_MIRRORS
# https://www.gentoo.org/downloads/mirrors/
echo '
GENTOO_MIRRORS="https://ftp-stud.hs-esslingen.de/pub/Mirrors/gentoo/ https://ftp.fau.de/gentoo/ https://ftp.tu-ilmenau.de/mirror/gentoo/"' >> /etc/portage/._cfg0000_make.conf

# https://wiki.gentoo.org/wiki/Handbook:AMD64/Full/Portage#Fetch_commands
#
# Default values from /usr/share/portage/config/make.globals are:
# FETCHCOMMAND="wget -t 3 -T 60 --passive-ftp -O \"\${DISTDIR}/\${FILE}\" \"\${URI}\""
# RESUMECOMMAND="wget -c -t 3 -T 60 --passive-ftp -O \"\${DISTDIR}/\${FILE}\" \"\${URI}\""
#
# File in git: https://gitweb.gentoo.org/proj/portage.git/tree/cnf/make.globals
#
# They are insufficient in my opinion.
# Thus, I am enforcing TLSv1.2 or greater, secure TLSv1.2 cipher suites and https-only.
# TLSv1.3 cipher suites are secure. Thus, I don't set "--tls13-ciphers".
echo 'FETCHCOMMAND="curl --fail --silent --show-error --location --proto '\''=https'\'' --tlsv1.2 --ciphers '\''ECDHE+AESGCM:ECDHE+CHACHA20'\'' --retry 2 --connect-timeout 60 -o \"\${DISTDIR}/\${FILE}\" \"\${URI}\""
RESUMECOMMAND="${FETCHCOMMAND} --continue-at -"' >> /etc/portage/._cfg0000_make.conf

# Some useflags I set for personal use.
# Feel free to adjust as with any other codeblock. 😄
echo '
USE_HARDENED="caps pie -sslv3 -suid"
USE="${USE_HARDENED}"' >> /etc/portage/._cfg0000_make.conf
```

I prefer English manpages and ignore above [L10N](https://wiki.gentoo.org/wiki/Localization/Guide#L10N) setting for "sys-apps/man-pages". Makes using Stackoverflow easier :wink:.

```shell
echo "sys-apps/man-pages -l10n_de" >> /etc/portage/package.use/main && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Set [CPU flags](https://wiki.gentoo.org/wiki/CPU_FLAGS_X86#Using_cpuid2cpuflags):

```shell
emerge --oneshot app-portage/cpuid2cpuflags && \
echo "*/* $(cpuid2cpuflags)" > /etc/portage/package.use/00cpu-flags && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

## 6.2. (Optional) Custom Mirrors

If you don't live in Germany, you probably should change [GENTOO_MIRRORS](https://wiki.gentoo.org/wiki/GENTOO_MIRRORS) previously set in [6.1. Portage Configuration](#61-portage-configuration). You can pick the mirrors from the [mirror list](https://www.gentoo.org/downloads/mirrors/), use [mirrorselect](https://wiki.gentoo.org/wiki/Mirrorselect) or do as I do and select local/regional, IPv4/IPv6 dual-stack and TLSv1.3 supporting mirrors (copy&paste one after the other):

``` { .shell .no-copy }
# Install app-misc/yq
ACCEPT_KEYWORDS="~amd64" emerge --oneshot app-misc/yq

# Get a list of country codes and names:
curl -fsSL --proto '=https' --tlsv1.3 https://api.gentoo.org/mirrors/distfiles.xml | xq -r '.mirrors.mirrorgroup[] | "\(.["@country"]) \(.["@countryname"])"' | sort -k2.2

# Choose your countries the mirrors should be located in:
country='"AU","BE","BR","CA","CH","CL","CN","CZ","DE","DK","ES","FR","GR","HK","IL","IT","JP","KR","KZ","LU","NA","NC","NL","PH","PL","PT","RO","RU","SG","SK","TR","TW","UK","US","ZA"'

# Get a list of mirrors available over IPv4/IPv6 dual-stack in the countries of your choice with TLSv1.3 support
while read -r i; do
  if curl -fsL --proto '=https' --tlsv1.3 -I "${i}" >/dev/null; then
    echo "${i}"
  fi
done < <(
  curl -fsSL --proto '=https' --tlsv1.3 https://api.gentoo.org/mirrors/distfiles.xml | \
  xq -r ".mirrors.mirrorgroup[] | select([.\"@country\"] | inside([${country}])) | .mirror | if type==\"array\" then .[] else . end | .uri | if type==\"array\" then .[] else . end | select(.\"@protocol\" == \"http\" and .\"@ipv4\" == \"y\" and .\"@ipv6\" == \"y\" and (.\"#text\" | startswith(\"https://\"))) | .\"#text\""
)
```

## 6.3. Repo Syncing

Mitigate [CVE-2022-29154](https://bugs.gentoo.org/show_bug.cgi?id=CVE-2022-29154) among others before using "rsync" via "eix-sync":

```shell
echo 'net-misc/rsync ~amd64' >> /etc/portage/package.accept_keywords/main && \
emerge --oneshot net-misc/rsync && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

I personally prefer syncing the repo via ["eix-sync"](https://wiki.gentoo.org/wiki/Eix#Method_2:_Using_eix-sync) which is provided by [app-portage/eix](https://wiki.gentoo.org/wiki/Eix). But, there are [some of other options](https://wiki.gentoo.org/wiki/Gentoo_Cheat_Sheet#Sync_methods):

=== "eix-sync"
    ```shell
    emerge app-portage/eix && \
    eix-sync
    ```

=== "emaint (replaced "emerge --sync")"
    ```shell
    emaint --auto sync
    ```

=== "emerge-webrsync"
    ```shell
    emerge-webrsync
    ```

Read [Gentoo news items](https://www.gentoo.org/glep/glep-0042.html):

```shell
eselect news list
# eselect news read 1
# eselect news read 2
# etc.
```

## 6.4. (Optional) Hardened Profiles

!!! info "Desktop Profiles"
    To make things simple, hardened desktop profiles are only considered for selection at the end of this guide in chapter [15. Desktop profiles (optional)](desktop_profiles.md).

Switch over to the custom [hardened](https://wiki.gentoo.org/wiki/Project:Hardened) profile. Additional ressources:

- [My custom profiles](https://github.com/duxsco/gentoo-installation/tree/main/overlay/duxsco/profiles)
- [Creating custom profiles](https://wiki.gentoo.org/wiki/Profile_(Portage)#Creating_custom_profiles)
- [Switching to a hardened profile](https://wiki.gentoo.org/wiki/Hardened_Gentoo#Switching_to_a_Hardened_profile)

```shell
eselect profile set duxsco:hardened-systemd-merged-usr && \
env-update && source /etc/profile && export PS1="(chroot) $PS1" && \
emerge --oneshot sys-devel/gcc && \
emerge --oneshot sys-devel/binutils sys-libs/glibc && \
env-update && source /etc/profile && export PS1="(chroot) $PS1" && \
emerge -e @world && \
env-update && source /etc/profile && export PS1="(chroot) $PS1" && \
echo -e "\e[1;32mSUCCESS\e[0m"
```
