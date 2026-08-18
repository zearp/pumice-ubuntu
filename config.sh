#!/bin/bash
#
# this config.sh runs chrooted during kiwi's system-prepare phase and
# before config.xml's own <delete> block takes effect, use images.sh
# for things that need applying after deletes in config.xml/config.sh
#
set -euo pipefail
test -f /.kconfig && . /.kconfig
test -f /.profile && . /.profile

echo "Configure image: [${kiwi_iname}]"

#=======================================
# setup system locale/keymap/timezone
#---------------------------------------
IMAGE_LOCALE="en_US"
IMAGE_KEYMAP="us"
IMAGE_TIMEZONE="UTC"

#=======================================
# clean up crud from macOS
# kiwi's overlay sync has no excludes
#---------------------------------------
find / -xdev -name '.DS_Store' -delete 2>/dev/null

#=======================================
# apply system locale/keymap/timezone
#---------------------------------------
echo "LANG=${IMAGE_LOCALE}.UTF-8" > /etc/locale.conf
locale-gen "${IMAGE_LOCALE}.UTF-8"

echo "KEYMAP=${IMAGE_KEYMAP}" > /etc/vconsole.conf

[ -e /etc/localtime ] && rm -f /etc/localtime
ln -s /usr/share/zoneinfo/${IMAGE_TIMEZONE} /etc/localtime

echo "0.0 0 0.0" > /etc/adjtime
echo "0" >> /etc/adjtime
echo "UTC" >> /etc/adjtime

#=======================================
# machine identity can not make it into the image
#---------------------------------------
rm -f /etc/machine-id
touch /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id
rm -f /var/lib/systemd/random-seed

#=======================================
# root: no password, sudo only
#---------------------------------------
passwd -d root
passwd -l root

#=======================================
# default target
#---------------------------------------
systemctl set-default graphical.target
#systemctl set-default multi-user.target

#=======================================
# setup persistent journal
#---------------------------------------
mkdir -p /var/log/journal
systemd-tmpfiles --create --prefix /var/log/journal

#=======================================
# enable services needed by the installer
#---------------------------------------
systemctl enable gdm3
systemctl enable pumice_cdrom_compat.service
systemctl enable pumice_early_cleanup.service
systemctl enable pumice_firstboot_cleanup.service
systemctl enable pumice_liveuser_setup.service
systemctl enable pumice_live_zfs_mask.service

#=======================================
# enable ssh server socket activation
#---------------------------------------
systemctl disable ssh.service
systemctl enable ssh.socket

#=======================================
# keyd installed but masked by default
# a global input remapper should not autostart
#---------------------------------------
systemctl disable keyd.service 2>/dev/null
systemctl mask keyd.service

#=======================================
# enable fingerprint auth for sudo etc
#---------------------------------------
pam-auth-update --enable fprintd

#=======================================
# set pumice spinner theme as system default
#---------------------------------------
update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth /usr/share/plymouth/themes/pumice/pumice.plymouth 100
update-alternatives --set default.plymouth /usr/share/plymouth/themes/pumice/pumice.plymouth

#=======================================
# mask gnome-initial-setup on live boots
#---------------------------------------
mkdir -p /etc/systemd/user
ln -sf /dev/null /etc/systemd/user/gnome-initial-setup-first-login.service

#=======================================
# disable screen lock/sleep modes to prevent
# user lock-outs when installer is not running
# the passwordless "liveuser" can't unlock it
#---------------------------------------
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

#=======================================
# needed for dconf settings to apply
#-------------------------------------
if [ ! -e /etc/dconf/profile/user ]; then
    mkdir -p /etc/dconf/profile
    printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user
fi
dconf update

#=======================================
# seed the installer snaps for the live session
#-------------------------------------
seed_dir=/var/lib/snapd/seed
mkdir -p "${seed_dir}/snaps" "${seed_dir}/assertions"
ubuntu_desktop_bootstrap_channel="26.04/stable"

# look up ubuntu-desktop-bootstrap's actual required base snap
# instead of always installing "core24" as upstream can change this depend
base_snap=$(curl -sS -H 'Snap-Device-Series: 16' \
    "https://api.snapcraft.io/v2/snaps/info/ubuntu-desktop-bootstrap?fields=base" \
    | python3 -c '
import json, sys
data = json.load(sys.stdin)
for entry in data["channel-map"]:
    ch = entry["channel"]
    if ch["name"] == "'"${ubuntu_desktop_bootstrap_channel}"'" and ch["architecture"] == "amd64":
        print(entry["base"])
        break
')
[ -n "${base_snap}" ] || {
    echo "ERROR: couldn't determine ubuntu-desktop-bootstrap's base snap from the store API" >&2
    exit 1
}
echo "Seeding installer snaps (${base_snap}, snapd, ubuntu-desktop-bootstrap)"

declare -A snap_channels=(
    ["${base_snap}"]="latest/stable"
    [snapd]="latest/stable"
    [ubuntu-desktop-bootstrap]="${ubuntu_desktop_bootstrap_channel}"
)
declare -A snap_classic=(
    ["${base_snap}"]="false"
    [snapd]="false"
    [ubuntu-desktop-bootstrap]="true"
)

seed_yaml="${seed_dir}/seed.yaml"
echo "snaps:" > "${seed_yaml}"

tmp_snap_dir=$(mktemp -d)
pushd "${tmp_snap_dir}" >/dev/null
for name in "${!snap_channels[@]}"; do
    channel="${snap_channels[$name]}"
    snap download "${name}" --channel="${channel}"
    snap_file=$(ls "${name}"_*.snap)
    assert_file=$(ls "${name}"_*.assert)
    mv "${snap_file}" "${seed_dir}/snaps/"
    mv "${assert_file}" "${seed_dir}/assertions/"
    {
        echo "  - name: ${name}"
        echo "    channel: ${channel}"
        echo "    file: ${snap_file}"
        if [ "${snap_classic[$name]}" = "true" ]; then
            echo "    classic: true"
        fi
    } >> "${seed_yaml}"
done
popd >/dev/null
rm -rf "${tmp_snap_dir}"

# model assertion, this is required
model_assertion="${seed_dir}/assertions/generic-classic.model"
curl -sS -H 'Accept: application/x.ubuntu.assertion' \
    'https://assertions.ubuntu.com/v1/assertions/model/16/generic/generic-classic' \
    -o "${model_assertion}"
grep -q '^type: model$' "${model_assertion}" || {
    echo "ERROR: fetched generic-classic model assertion doesn't look like a real assertion:" >&2
    cat "${model_assertion}" >&2
    exit 1
}

#=======================================
# add shell extensions not found in default repo
#---------------------------------------
gnome_shell_version=$(gnome-shell --version | grep -oE '[0-9]+' | head -1)

for uuid in \
    blur-my-shell@aunetx \
    just-perfection-desktop@just-perfection \
    caffeine@patapon.info \
    gamemodeshellextension@trsnaqe.com \
    weatheroclock@CleoMenezesJr.github.io \
; do
    download_path=$(curl -sS \
        "https://extensions.gnome.org/extension-info/?uuid=${uuid}&shell_version=${gnome_shell_version}" \
        | python3 -c "import json,sys; print(json.load(sys.stdin)['download_url'])")
    curl -sS -L -o /tmp/gnome-extension.zip \
        "https://extensions.gnome.org${download_path}"
    HOME=/etc/skel gnome-extensions install --print-uuid /tmp/gnome-extension.zip
    rm -f /tmp/gnome-extension.zip
done

#=======================================
# ptyxis original black/cyan icon restoration
#---------------------------------------
find /usr/share/icons/Yaru -iname 'org.gnome.Ptyxis*' -delete
gtk-update-icon-cache -f -t /usr/share/icons/Yaru

#=======================================
# enable ufw and allow inbound ssh connections
# https://ubuntu.com/server/docs/how-to/security/firewalls/
#---------------------------------------
ufw --force enable
ufw allow ssh

#=======================================
# delete all files a package installs from packages that can't be cleanly
# removed without cascading/taking down metapackages like ubuntu-desktop-minimal
#--------------------------------------
for fw_pkg in \
    linux-firmware-broadcom-wireless \
    linux-firmware-marvell-prestera \
    linux-firmware-marvell-wireless \
    linux-firmware-mellanox-spectrum \
    linux-firmware-netronome \
    linux-firmware-nvidia-graphics \
    linux-firmware-qualcomm-misc \
    linux-firmware-qualcomm-wireless \
    linux-firmware-qualcomm-graphics \
    linux-firmware-qlogic \
    ubuntu-wallpapers \
    ubuntu-wallpapers-resolute \
    yelp \
    yelp-xsl \
; do
    dpkg -L "${fw_pkg}" 2>/dev/null | while read -r fw_file; do
        if [ -f "${fw_file}" ]; then
            rm -f "${fw_file}"
        fi
    done
done

#=======================================
# final check for updates and clean-up
#--------------------------------------
apt update && apt -y upgrade
#apt update && apt -y upgrade && apt clean
#rm -rf /var/lib/apt/lists/*
#rm -rf /var/cache/apt/*

exit 0
