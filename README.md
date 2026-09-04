# Android 17 for x86_64 PCs

A bootable Android 17 (AOSP `android17-release`) image for ordinary 64-bit PCs.
Built and tested on an **HP ZBook Firefly 16 G11**, Intel Meteor Lake, booting
from an external USB SSD.

Rendering is **hardware-accelerated** — Mesa `iris` drives the Intel iGPU
directly, at GLES 3.2.

> **This image overwrites the whole target disk.** It writes a fresh GPT and
> five partitions. Everything already on that disk is gone. Pick your target
> deliberately — see [Choosing the right disk](#choosing-the-right-disk).

---

## Requirements

| | |
|---|---|
| CPU | x86_64 with UEFI firmware |
| GPU | Intel (i915/Xe) gets hardware GL. AMD/NVIDIA fall back to software rendering |
| Target disk | **16 GB or larger** (the image is 14 GiB) |
| Firmware | UEFI, **Secure Boot disabled** — the bootloader is not signed |

Tested on Meteor Lake. Other Intel generations should work; other vendors boot
but render in software.

---

## 1. Download and verify

Grab `android-pc.img.xz` (792 MB) from [Releases](../../releases), then verify
it **before** writing 14 GiB to a disk:

```bash
sha256sum -c android-pc.img.xz.sha256
```

The checksum file is in this repository, so you are not checking the download
against a hash from the same download.

If the checksum does not match, stop. A truncated download that still flashes
produces a disk that fails partway through boot with no useful error.

---

## 2. Choosing the right disk

Get this wrong and you erase the wrong drive. Identify the target by its
**serial number or model**, not by `/dev/sdX` — those names change between
reboots, especially with USB drives.

```bash
lsblk -o NAME,SIZE,MODEL,SERIAL,MOUNTPOINTS
```

Then confirm the one you picked is not your system disk:

```bash
findmnt -no SOURCE /        # your running system lives here — never this disk
```

---

## 3. Flash it

### Linux

```bash
# replace sdX with your target — the WHOLE disk, not a partition (no digit)
xz -dc android-pc.img.xz | sudo dd of=/dev/sdX bs=1M conv=fsync status=progress
sync
```

`xz -dc` decompresses on the fly, so you never need 14 GiB of free space for the
expanded image.

**If `dd` stalls or the drive drops off the bus**, you are probably hitting a
UAS problem — common with USB-SATA/NVMe bridges. The symptom in `dmesg`:

```
sd 14:0:0:0: [sda] tag#14 timing out command, waited 180s
              FAILED Result: hostbyte=DID_RESET
I/O error, dev sda, sector 0 op 0x1:(WRITE)
```

Two things fix it, in order of preference:

1. Drop `oflag=direct` and use a smaller block size — `bs=1M` buffered, as
   above. This alone resolved it on the machine this image was built on.
2. Force the older BOT transport instead of UAS. Find the drive's USB ID with
   `lsusb`, then add to your kernel command line:
   `usb-storage.quirks=04e8:4001:u` (substitute your own `vendor:product`).

Plugging into a port directly on the machine, rather than through a hub or
Thunderbolt dock, also helps.

### macOS

```bash
diskutil list                          # find your disk, e.g. /dev/disk4
diskutil unmountDisk /dev/disk4
xz -dc android-pc.img.xz | sudo dd of=/dev/rdisk4 bs=4m
```

Use `/dev/rdiskN` (raw), not `/dev/diskN` — it is far faster.

### Windows

Decompress `android-pc.img.xz` with [7-Zip](https://7-zip.org) to get
`android-pc.img`, then write it with one of:

- **[Rufus](https://rufus.ie)** — choose the image, select **DD Image mode**
  when prompted. Not ISO mode.
- **[balenaEtcher](https://etcher.balena.io)** — reads `.xz` directly, no
  decompression step needed.
- **[Raspberry Pi Imager](https://www.raspberrypi.com/software/)** — "Use
  custom" image; also reads `.xz` directly.

Note Windows needs ~14 GiB free to hold the decompressed image if you use Rufus.

---

## 4. Boot it

1. Enter your firmware setup (usually `F2`, `F10`, `Del`, or `Esc` at power-on).
2. **Disable Secure Boot.** The bootloader is unsigned and will be rejected
   otherwise.
3. Set the USB disk first in the boot order, or use the one-time boot menu
   (often `F12`).

You will get a GRUB menu with four entries:

| Entry | What it does |
|---|---|
| **Android pc_x86_64** | Normal boot from the USB disk |
| **Android pc_x86_64 (verbose, serial only)** | Same, with kernel logging — use this if the normal entry fails |
| **Install Android to internal disk (ERASES IT)** | Copies to the internal disk, with a confirmation prompt |
| **Install ... NO PROMPT, ERASES IT NOW** | Same, no confirmation |

The menu waits 5 seconds. The install entries are last in the list — read before
you arrow down.

### Installing to the internal disk

The installer partitions the internal disk, copies the partitions across, gives
`userdata` the entire remainder of the drive, rewrites GRUB to point at the
internal disk, and removes the install entries from the installed copy.

**It erases the internal disk completely**, including any existing operating
system. There is no dual-boot option.

---

## 5. What works

Verified on real hardware:

- **Hardware OpenGL ES 3.2** via Mesa `iris` on the Intel iGPU —
  `Intel, Mesa Intel(R) Graphics (MTL)`. Measured **9.4× faster** than the
  SwiftShader software path (SuperTuxKart, Candela City, 20 s of
  `dumpsys SurfaceFlinger --timestats`: 3.2 fps → 30 fps).
- **Camera** — preview and video recording, in colour.
- **Audio output.**
- **Display, keyboard, trackpad, WiFi, Bluetooth.**
- **adb over TCP**, on port 5555.
- **Installing to the internal disk**, then booting from it.
- A desktop-style launcher, with F-Droid included as an app source.

### Known issues

- **Microphone level is low.** Capture was reading the wrong ALSA device
  entirely (the empty analog jack rather than the internal DMIC array); that is
  fixed, but recordings still come out around -53 dBFS. Under investigation.
- **No Google Play Services or Play Store.** This is plain AOSP. F-Droid is
  included instead.
- **AMD and NVIDIA GPUs render in software.** Only Intel gets the hardware path.
- **Secure Boot must stay off.**
- **The text console is output-only** — keystrokes do not reach `/dev/console`.
  This does not affect normal use; it is why a no-prompt install entry exists.

---

## Partition layout

| # | Name | Size | Format |
|---|---|---|---|
| 1 | `esp` | 512 MiB | FAT32, label `ANDROIDESP` |
| 2 | `system` | 6 GiB | ext4 |
| 3 | `vendor` | 2 GiB | ext4 |
| 4 | `metadata` | 64 MiB | ext4 |
| 5 | `userdata` | 5.4 GiB | ext4 |

Total 14 GiB. When you install to an internal disk, `userdata` is expanded to
fill it.

---

## Building from source

The full build system, kernel configuration and device tree live in
[somalapuram/aosp-pc-x86_64](https://github.com/somalapuram/aosp-pc-x86_64).

```bash
./build.sh sync      # AOSP + kernel sources, then out-of-tree patches
./build.sh mesa      # REQUIRED before 'android' — cross-builds Mesa with the NDK
./build.sh android
./build.sh image     # produces android-pc.img
```

---

## Licence

AOSP is Apache 2.0. The Linux kernel is GPLv2. Mesa is MIT. This image is built
from published sources; see the build repository for the exact revisions and the
patches applied on top.
