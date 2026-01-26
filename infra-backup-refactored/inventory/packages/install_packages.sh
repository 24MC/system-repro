#!/usr/bin/env bash
set -euo pipefail

log_info() { echo "[INFO] $*"; }
log_error() { echo "[ERROR] $*" >&2; }
log_success() { echo "[SUCCESS] $*"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

detect_aur_helper() {
    for helper in yay paru aura; do
        if command -v "${helper}" >/dev/null 2>&1; then
            echo "${helper}"
            return 0
        fi
    done
    return 1
}

install_official_packages() {
    local package_list=(
        alsa-firmware
        alsa-plugins
        alsa-utils
        android-tools
        archlinux-keyring
        ark
        audacious
        b43-fwcutter
        base
        base-devel
        bash-completion
        bind
        bleachbit
        bluedevil
        bluez
        bluez-utils
        breeze-gtk
        btrfs-progs
        cantarell-fonts
        code
        cryptsetup
        device-mapper
        dialog
        diffutils
        dmidecode
        dmraid
        dnsmasq
        docker
        docker-compose
        dolphin
        dolphin-plugins
        dosfstools
        downgrade
        dracut
        duf
        e2fsprogs
        efibootmgr
        efitools
        endeavouros-branding
        endeavouros-keyring
        endeavouros-mirrorlist
        eos-apps-info
        eos-breeze-sddm
        eos-hooks
        eos-log-tool
        eos-packagelist
        eos-quickstart
        eos-rankmirrors
        eos-settings-plasma
        ethtool
        exfatprogs
        f2fs-tools
        fakeroot
        ffmpegthumbs
        firefox
        firewalld
        flameshot
        flatpak
        freetype2
        fwupd
        git
        glances
        gpm
        gptfdisk
        gradle
        gst-libav
        gst-plugin-pipewire
        gst-plugins-bad
        gst-plugins-ugly
        gwenview
        haruna
        haveged
        htop
        hwdetect
        hwinfo
        inetutils
        intel-ucode
        inxi
        iptables-nft
        iwd
        jdk21-openjdk
        jdk-openjdk
        jfsutils
        kate
        kcalc
        kde-cli-tools
        kdeconnect
        kdegraphics-thumbnailers
        kde-gtk-config
        kdenetwork-filesharing
        kdeplasma-addons
        kernel-install-for-dracut
        kgamma
        kimageformats
        kinfocenter
        kio-admin
        kio-extras
        kio-fuse
        knights
        konsole
        kscreen
        kwallet-pam
        kwayland-integration
        less
        libappindicator
        libdvdcss
        libgsf
        libopenraw
        libreoffice-fresh
        linux
        linux-firmware
        linux-firmware-marvell
        linux-firmware-nvidia
        linux-headers
        liquidctl
        logrotate
        lsb-release
        lsscsi
        lvm2
        man-db
        man-pages
        mdadm
        meld
        memtest86+-efi
        mesa
        mesa-utils
        mkinitcpio-nfs-utils
        modemmanager
        mtools
        nano
        nano-syntax-highlighting
        nbd
        ncdu
        ndisc6
        netctl
        net-tools
        networkmanager
        networkmanager-openconnect
        networkmanager-openvpn
        nfs-utils
        nilfs-utils
        noto-fonts
        noto-fonts-cjk
        noto-fonts-emoji
        noto-fonts-extra
        nss-mdns
        ntfs-3g
        ntp
        okular
        openconnect
        openvpn
        os-prober
        pacman-contrib
        paru
        pavucontrol
        perl
        perl-geoip
        pipewire-alsa
        pipewire-jack
        pipewire-pulse
        pkgfile
        plasma-browser-integration
        plasma-desktop
        plasma-disks
        plasma-firewall
        plasma-nm
        plasma-pa
        plasma-systemmonitor
        plasma-workspace
        plocate
        poppler-glib
        powerdevil
        power-profiles-daemon
        ppp
        pptpclient
        print-manager
        python-capng
        python-huggingface-hub
        python-packaging
        python-pip
        python-pipx
        python-pyqt5
        python-six
        qemu-full
        qt5-virtualkeyboard
        rebuild-detector
        reflector
        reflector-simple
        rp-pppoe
        rsync
        rtkit
        rustup
        sddm-kcm
        sg3_utils
        sl
        smartmontools
        s-nail
        sof-firmware
        steam
        sudo
        swi-prolog
        sysfsutils
        systemd-sysvcompat
        telegram-desktop
        tesseract
        tesseract-data-ron
        texinfo
        timeshift
        tk
        tldr
        traceroute
        tree
        ttf-bitstream-vera
        ttf-dejavu
        ttf-liberation
        ttf-opensans
        unrar
        unzip
        usb_modeswitch
        usbutils
        vi
        virt-manager
        vpnc
        welcome
        wget
        which
        whois
        wireless-regdb
        wireplumber
        wpa_supplicant
        xbindkeys
        xdg-desktop-portal-kde
        xdg-user-dirs
        xdg-utils
        xdotool
        xf86-input-libinput
        xf86-video-qxl
        xfce4-screenshooter
        xfsprogs
        xl2tpd
        xorg-server
        xorg-xdpyinfo
        xorg-xev
        xorg-xhost
        xorg-xinit
        xorg-xinput
        xorg-xkill
        xorg-xrandr
        xsettingsd
        xz
        yay
        zsh
    )

    log_info "Installing official packages..."

    if [[ ${#package_list[@]} -gt 0 ]]; then
        pacman -Syu --needed --noconfirm "${package_list[@]}"
        log_success "Official packages installed"
    fi
}

install_aur_packages() {
    local package_list=(
        apache-spark
        appimagelauncher
        coolercontrol-bin
        coolercontrold-bin
        debtap
        google-tasks-desktop
        maliit-framework
        maliit-keyboard
        neofetch
        presage
    )

    if [[ ${#package_list[@]} -gt 0 ]]; then
        local aur_helper
        if ! aur_helper=$(detect_aur_helper); then
            log_error "No AUR helper found. Install yay or paru first"
            return 1
        fi

        log_info "Installing AUR packages using ${aur_helper}..."
        "${aur_helper}" -S --needed --noconfirm "${package_list[@]}"
        log_success "AUR packages installed"
    fi
}

main() {
    check_root
    log_info "Starting package installation..."
    pacman -Sy
    install_official_packages
    install_aur_packages
    log_success "Package installation completed!"
}

main "$@"
