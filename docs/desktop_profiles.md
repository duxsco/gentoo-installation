At this point, you can consider the switch to a desktop profile:

=== "non-SELinux profile"

    ```shell
    eselect profile set duxsco:hardened-systemd-desktop && \
    emerge -atuDN @world
    ```

=== "SELinux profile"

    ```shell
    eselect profile set duxsco:hardened-systemd-desktop-selinux && \
    emerge -atuDN @world
    ```
