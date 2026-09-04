#!/bin/bash
# Flash the Android 17 x86_64 image to a disk.
#
#   ./flash.sh /dev/sdX            write to that disk, after confirmation
#   ./flash.sh --list              just list candidate disks and exit
#
# Refuses to touch any disk carrying /, /boot, /boot/efi or /home, and asks you
# to retype the device path before it writes anything.
set -u

IMG=android-pc.img.xz
RED=$'\e[31m'; GRN=$'\e[32m'; BLD=$'\e[1m'; NC=$'\e[0m'
die() { printf '%sfail%s %s\n' "$RED" "$NC" "$*" >&2; exit 1; }

list_disks() {
    printf '%sAvailable disks%s  (identify yours by MODEL and SERIAL, not by name --\n' "$BLD" "$NC"
    printf '                  /dev/sdX names change between reboots)\n\n'
    lsblk -dno NAME,SIZE,MODEL,SERIAL,TRAN 2>/dev/null | while read -r n s m sr t; do
        printf '  /dev/%-8s %-9s %-22s %-20s %s\n' "$n" "$s" "${m:-?}" "${sr:-?}" "${t:-?}"
    done
    printf '\n  your system disk is %s -- never pick that one\n' "$(findmnt -no SOURCE / 2>/dev/null)"
}

[ "${1:-}" = "--list" ] && { list_disks; exit 0; }
[ $# -eq 1 ] || { list_disks; printf '\nusage: %s /dev/sdX\n' "$0"; exit 1; }

TARGET=$1
[ -b "$TARGET" ] || die "$TARGET is not a block device"
[ -e "/sys/block/$(basename "$TARGET")" ] || die "$TARGET looks like a partition; pass the whole disk (e.g. /dev/sdb, not /dev/sdb1)"
[ -r "$IMG" ] || die "$IMG not found -- download it from the Releases page and run this beside it"

# Never a disk the running system depends on.
for mp in / /boot /boot/efi /home; do
    src=$(findmnt -no SOURCE "$mp" 2>/dev/null) || continue
    case "$src" in "$TARGET"*) die "REFUSING: $TARGET carries $mp";; esac
done

sz=$(lsblk -dno SIZE "$TARGET"); model=$(lsblk -dno MODEL "$TARGET"); serial=$(lsblk -dno SERIAL "$TARGET")
printf '\n%sAbout to ERASE:%s  %s  %s  %s  (serial %s)\n' "$BLD" "$NC" "$TARGET" "$sz" "${model:-?}" "${serial:-?}"
printf 'Everything on it will be destroyed.\n\n'
read -r -p "Type the device path again to confirm: " confirm
[ "$confirm" = "$TARGET" ] || die "confirmation did not match; nothing written"

if command -v sha256sum >/dev/null && [ -r "$IMG.sha256" ]; then
    printf '\nverifying checksum...\n'
    sha256sum -c "$IMG.sha256" || die "checksum mismatch -- do not flash this file"
fi

for part in $(lsblk -lno NAME "$TARGET" | tail -n +2); do
    mp=$(findmnt -no TARGET "/dev/$part" 2>/dev/null)
    [ -n "$mp" ] && { sudo umount "/dev/$part" && echo "unmounted /dev/$part"; }
done

printf '\nwriting (this takes a few minutes)...\n'
# Buffered 1 MiB, deliberately NOT oflag=direct with a large block size: that
# pattern makes some USB bridges drop off the bus under UAS mid-write.
xz -dc "$IMG" | sudo dd of="$TARGET" bs=1M conv=fsync status=progress || die "write failed"
sync
command -v sgdisk >/dev/null && sudo sgdisk -e "$TARGET" >/dev/null 2>&1
command -v partprobe >/dev/null && sudo partprobe "$TARGET" >/dev/null 2>&1

printf '\n%sdone%s -- reboot, disable Secure Boot, and pick this disk in the boot menu\n' "$GRN" "$NC"
