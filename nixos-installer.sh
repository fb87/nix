#!/usr/bin/env bash

# some refs. refer - https://elis.nu/blog/2020/05/nixos-tmpfs-as-root/
#                  - https://gist.github.com/samdroid-apps/3723d30953af5e1d68d4ad5327e624c0
trap exit INT

nix_disk=${1:-/dev/sdc}
mount_point="/mnt"

function die {
    echo "= Error! $1"
    exit 1
}

function warn {
    echo "= Warn! $1"
}

function check {
     parted -v > /dev/null 2>&1 || die "'parted' required but missing"
}

function check_and_clean_up {
    for i in $(mount | awk '/'$encrypted_label'/{ print $3 }')
    do
        umount $i -f
    done

    mount | grep "$mount_point/boot" && umount $mount_point/boot -f
    mount | grep "$mount_point" && umount $mount_point -f
    [ -e $encrypted_disk ] && cryptsetup luksClose $encrypted_disk
}

# main entry

## early exit if required tools not yet installed
check

read -p "-- install nixos to \"$nix_disk\" (y|N)? " answer

if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
    echo "-- quit!"
    exit 0
fi

# FIXME: allow user to not use encrypted

# encrypt root partition
encrypted_label="$(echo -ne ${nix-disk} | md5sum | awk '{print $1}')-encrypted"
encrypted_disk="/dev/mapper/${encrypted_label}"

# FIXME: warn user first
check_and_clean_up

# avoid distroying current in used disk
mount | grep "$nix_disk" > /dev/null 2>&1 && \
        die "\"$nix_disk\" mounted, please unmount first"

# partitioning the disk
parted -s $nix_disk -- mktable gpt || die "unable to create partition table"
parted -s $nix_disk -- print

# we want to be able to install multiple OSes in same
# partition layout hence boot partition should be large
# engough
parted -s $nix_disk -- mkpart ESP fat32 8MiB 2GiB  # ESP EFI partition

# wanna have EFI bootable, hidden and be ESP type
parted -s $nix_disk -- set 1 boot on
# parted $nix_disk set 1 hidden on

# use BTRFS for the root
parted -s $nix_disk mkpart Encrypted btrfs 2GiB 100%  # root partition
parted -s $nix_disk print

# set password for root partition
cryptsetup luksFormat "${nix_disk}2"

# try to decrypt partition
while true
do
    cryptsetup luksOpen "${nix_disk}2" "$encrypted_label"
    [ -e $encrypted_disk ] && break
done

mkfs.fat -F 32 "${nix_disk}1"
mkfs.btrfs $encrypted_disk

# create subvolumes
mount -t btrfs $encrypted_disk $mount_point
btrfs subvolume create $mount_point/nixos
btrfs subvolume create $mount_point/nixos/nix
btrfs subvolume create $mount_point/nixos/etc
btrfs subvolume create $mount_point/nixos/log
btrfs subvolume create $mount_point/nixos/home
btrfs subvolume create $mount_point/nixos/root
mount | grep "$mount_point" && umount $mount_point -f

# create mount points
mount -t tmpfs -o mode=755 none $mount_point
mkdir -p $mount_point/{boot,home,root,nix,etc,var/log}

# and mount all subvolumes
mount "${nix_disk}1" $mount_point/boot

mount -t btrfs -o compress=zstd,subvol=nixos/etc $encrypted_disk $mount_point/etc
mount -t btrfs -o compress=zstd,noatime,subvol=nixos/nix $encrypted_disk $mount_point/nix
mount -t btrfs -o compress=zstd,subvol=nixos/log $encrypted_disk $mount_point/var/log
mount -t btrfs -o compress=zstd,subvol=nixos/home $encrypted_disk $mount_point/home
mount -t btrfs -o compress=zstd,subvol=nixos/root $encrypted_disk $mount_point/root

mount

# generate configuration and install
nixos-generate-config --root $mount_point

# use minimal configuration
[ -z "$NIXOS_MINIMAL" ] || cp -f minimal/configuration.nix $mount_point/etc/nixos/

nixos-install --root $mount_point

# unmount all, clean up
check_and_clean_up
