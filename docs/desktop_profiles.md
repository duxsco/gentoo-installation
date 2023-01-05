At this point, you can consider the switch to a hardened desktop profile:

=== "non-SELinux profile"
    ```shell
    eselect profile set duxsco:hardened-systemd-merged-usr-desktop && \
    emerge -atuDN @world
    ```

=== "SELinux profile"
    ```shell
    eselect profile set duxsco:hardened-systemd-merged-usr-desktop-selinux && \
    emerge -atuDN @world
    ```

For everything else you can either create your own profile or use one of those printed out by `eselect profile list`.
