profile_dexserver() {
    profile_standard
    profile_abbrev="dexserver"
    title="DexOS Server"
    desc="DexOS Server: ultra-light terminal-only Alpine Linux server with SSH, mDNS and Wi-Fi."
    arch="x86_64"
    image_name="DexOS-Server"
    output_filename="DexOS-Server-edge-x86_64.iso"
    hostname="dexos-installer"
    apkovl="genapkovl-dexserver.sh"
    kernel_flavors="lts"
    kernel_firmware_packages="linux-firmware-realtek linux-firmware-rtlwifi linux-firmware-rtw88 linux-firmware-rtw89 linux-firmware-mediatek linux-firmware-intel linux-firmware-airoha linux-firmware-atmel linux-firmware-mrvl linux-firmware-nxp linux-firmware-other linux-firmware-ath6k linux-firmware-ath9k_htc linux-firmware-ath10k linux-firmware-ath11k linux-firmware-ath12k linux-firmware-brcm linux-firmware-cypress linux-firmware-qca linux-firmware-mwl8k linux-firmware-mwlwifi linux-firmware-libertas linux-firmware-ti-connectivity linux-firmware-rsi linux-firmware-wfx"
    boot_addons="amd-ucode intel-ucode"
    initrd_ucode="/boot/amd-ucode.img /boot/intel-ucode.img"
    syslinux_timeout=5
    syslinux_prompt=0
    apks="alpine-base alpine-conf busybox-extras ca-certificates tzdata doas \
        openssh openssh-server openssh-client openssl kbd-bkeymaps \
        avahi avahi-openrc dbus dbus-openrc eudev eudev-openrc \
        networkmanager networkmanager-openrc networkmanager-wifi networkmanager-cli \
        wpa_supplicant iw wireless-regdb dnsmasq mini_httpd \
        linux-firmware-realtek linux-firmware-rtlwifi linux-firmware-rtw88 linux-firmware-rtw89 \
        linux-firmware-mediatek linux-firmware-intel linux-firmware-airoha linux-firmware-atmel linux-firmware-mrvl linux-firmware-nxp linux-firmware-other linux-firmware-ath6k linux-firmware-ath9k_htc linux-firmware-ath10k \
        linux-firmware-ath11k linux-firmware-ath12k linux-firmware-brcm linux-firmware-cypress \
        linux-firmware-qca linux-firmware-mwl8k linux-firmware-mwlwifi linux-firmware-libertas \
        linux-firmware-ti-connectivity linux-firmware-rsi linux-firmware-wfx \
        util-linux e2fsprogs dosfstools \
        grub grub-bios grub-efi efibootmgr os-prober ntfs-3g \
        linux-lts"
}
