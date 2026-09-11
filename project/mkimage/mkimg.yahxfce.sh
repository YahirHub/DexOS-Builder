profile_yahxfce() {
    profile_standard
    # Desktop does not need xtables-addons kernel modules. Omitting this
    # standard-profile addon saves several MiB and keeps offline builds stable.
    kernel_addons=""
    initfs_cmdline="modules=loop,squashfs,sd-mod,usb-storage,uas,sr-mod,isofs quiet"
    profile_abbrev="dexos"
    title="DexOS Live"
    desc="DexOS: sistema Live ligero basado en Alpine Linux con XFCE para PC y laptop."
    arch="x86_64"
    image_name="DexOS"
    output_filename="DexOS-edge-x86_64-v015.iso"
    hostname="dexos-live"
    apkovl="genapkovl-yahxfce.sh"
    kernel_flavors="lts"
    kernel_firmware_packages="linux-firmware-amd linux-firmware-amdgpu linux-firmware-i915 linux-firmware-xe linux-firmware-intel linux-firmware-nvidia linux-firmware-realtek linux-firmware-rtlwifi linux-firmware-rtw88 linux-firmware-rtw89 linux-firmware-mediatek linux-firmware-ath6k linux-firmware-ath9k_htc linux-firmware-ath10k linux-firmware-ath11k linux-firmware-ath12k linux-firmware-brcm linux-firmware-cypress linux-firmware-qca linux-firmware-mwl8k linux-firmware-mwlwifi linux-firmware-libertas linux-firmware-ti-connectivity linux-firmware-rsi linux-firmware-wfx sof-firmware"
    boot_addons="amd-ucode intel-ucode"
    initrd_ucode="/boot/amd-ucode.img /boot/intel-ucode.img"
    syslinux_timeout=10
    syslinux_prompt=0
    apks="alpine-base alpine-conf doas bash shadow sudo python3 py3-gobject3 chrony chrony-openrc firefox \
        dbus dbus-x11 dbus-openrc \
        eudev eudev-openrc udev-init-scripts udev-init-scripts-openrc \
        elogind elogind-openrc polkit-elogind polkit-common \
        xorg-server xinit xsetroot xf86-input-libinput xf86-video-vesa xf86-video-vmware xf86-video-qxl xf86-video-amdgpu \
        mesa-dri-gallium mesa-gl mesa-va-gallium mesa-utils libva-utils intel-media-driver libva-intel-driver vulkan-loader mesa-vulkan-ati mesa-vulkan-intel libva-vdpau-driver libvdpau vdpauinfo ffmpeg gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav \
        xfce4 xfce4-terminal xfce4-screensaver xfce4-whiskermenu-plugin xfce4-power-manager xfce4-battery-plugin \
        xfce4-pulseaudio-plugin xfce4-notifyd xfce4-taskmanager xfce4-screenshooter \
        lightdm lightdm-openrc lightdm-gtk-greeter \
        font-dejavu font-noto adw-gtk3 adwaita-xfce-icon-theme breeze-cursors xfce-polkit redshift geoclue geoclue-lang power-profiles-daemon musl-locales musl-locales-lang gettext-lang libxfce4ui-lang libxfce4util-lang libxfce4windowing-lang xfce4-appfinder-lang xfce4-panel-lang xfce4-session-lang xfce4-settings-lang xfce4-terminal-lang thunar-lang xfdesktop-lang xfwm4-lang xfce4-power-manager-lang xfce4-pulseaudio-plugin-lang xfce4-notifyd-lang xfce4-screensaver-lang xfce4-whiskermenu-plugin-lang xfce4-taskmanager-lang xfce4-screenshooter-lang lightdm-lang lightdm-gtk-greeter-lang thunar-volman-lang garcon-lang exo-lang tumbler-lang \
        gvfs udisks2 thunar-volman tumbler \
        networkmanager networkmanager-openrc networkmanager-wifi networkmanager-cli network-manager-applet \
        iw util-linux-misc wireless-tools wpa_supplicant wireless-regdb bluez bluez-openrc \
        pipewire pipewire-pulse pipewire-alsa wireplumber alsa-utils alsa-utils-openrc alsa-ucm-conf sof-firmware pavucontrol \
        upower brightnessctl util-linux sfdisk dosfstools e2fsprogs efibootmgr grub grub-bios grub-efi syslinux parted mtools \
        gparted os-prober ntfs-3g ntfs-3g-progs exfatprogs btrfs-progs xfsprogs f2fs-tools nilfs-utils jfsutils udftools lvm2 mdadm cryptsetup e2fsprogs-extra pciutils usbutils tzdata ca-certificates curl linux-lts linux-firmware-amd linux-firmware-amdgpu linux-firmware-i915 linux-firmware-xe linux-firmware-intel linux-firmware-nvidia linux-firmware-realtek linux-firmware-rtlwifi linux-firmware-rtw88 linux-firmware-rtw89 linux-firmware-mediatek linux-firmware-ath6k linux-firmware-ath9k_htc linux-firmware-ath10k linux-firmware-ath11k linux-firmware-ath12k linux-firmware-brcm linux-firmware-cypress linux-firmware-qca linux-firmware-mwl8k linux-firmware-mwlwifi linux-firmware-libertas linux-firmware-ti-connectivity linux-firmware-rsi linux-firmware-wfx sof-firmware"
}
