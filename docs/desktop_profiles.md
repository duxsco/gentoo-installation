At this point, you can consider the switch to a hardened desktop profile coming from:

=== "duxsco:hardened-systemd-merged-usr"
    ```shell
    eselect profile set duxsco:hardened-systemd-merged-usr-desktop && \
    emerge -atuDN @world
    ```

=== "duxsco:hardened-systemd-merged-usr-selinux"
    ```shell
    eselect profile set duxsco:hardened-systemd-merged-usr-desktop-selinux && \
    emerge -atuDN @world
    ```

For everything else you can either create your own profile or use one of those printed out by `eselect profile list`.
