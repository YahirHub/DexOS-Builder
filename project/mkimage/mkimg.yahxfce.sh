profile_yahxfce() {
    profile_standard
    profile_abbrev="yahxfce"
    title="Yah Alpine XFCE Live"
    desc="Alpine Linux edge con XFCE ligero para PC y laptop."
    arch="x86_64"
    image_name="yah-alpine-xfce"
    output_filename="yah-alpine-xfce-edge-x86_64.iso"
    hostname="yah-live"
    apkovl="genapkovl-yahxfce.sh"
    kernel_flavors="lts"
    boot_addons="amd-ucode intel-ucode"
    initrd_ucode="/boot/amd-ucode.img /boot/intel-ucode.img"
    syslinux_timeout=10
    syslinux_prompt=0
    apks="alpine-base alpine-conf doas bash shadow sudo \
        dbus dbus-x11 dbus-openrc \
        eudev eudev-openrc udev-init-scripts udev-init-scripts-openrc \
        elogind elogind-openrc polkit-elogind \
        xorg-server xinit xf86-input-libinput xf86-video-vesa xf86-video-vmware xf86-video-qxl xf86-video-amdgpu \
        mesa-dri-gallium mesa-gl \
        xfce4 xfce4-terminal xfce4-screensaver xfce4-whiskermenu-plugin xfce4-power-manager xfce4-battery-plugin \
        xfce4-pulseaudio-plugin xfce4-notifyd xfce4-taskmanager xfce4-screenshooter \
        lightdm lightdm-openrc lightdm-gtk-greeter \
        font-dejavu font-noto adw-gtk3 adwaita-xfce-icon-theme xfce-polkit \
        gvfs udisks2 thunar-volman tumbler \
        networkmanager networkmanager-openrc networkmanager-wifi networkmanager-cli network-manager-applet \
        iw wpa_supplicant wireless-regdb bluez bluez-openrc \
        pipewire pipewire-pulse pipewire-alsa wireplumber alsa-utils pavucontrol \
        upower brightnessctl util-linux sfdisk dosfstools e2fsprogs efibootmgr grub-bios grub-efi syslinux parted \
        pciutils usbutils tzdata ca-certificates curl linux-lts linux-firmware"
}
