#!/usr/bin/env bash
# Add OneThing Edge Cube (OEC) / OEC Turbo  --  RK3566  --  device support to an
# ImmortalWrt / OpenWrt tree.  Idempotent: safe to run more than once.
#
# What it does (3 places, per the target's design):
#   1. target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/
#          rk3566-onething-edge-cube.dts          (device tree; auto-compiled)
#   2. target/linux/rockchip/image/armv8.mk
#          Device/onething_oec + TARGET_DEVICES
#   3. package/boot/uboot-rockchip/Makefile
#          minimal      - add onething_oec to U-Boot/nanopi-r3s-rk3566's
#                         BUILD_DEVICES, so its kconfig default fires for us
#          --own-uboot  - add a whole new U-Boot/onething-oec-rk3566 board
#                         + BOOTLOADERS entry
#
# Two modes:
#   (default)      minimal  - reuse the existing nanopi-r3s-rk3566 U-Boot blob.
#                             Fastest path to a bootable image; U-Boot stage uses
#                             the R3S device tree, Linux stage uses the OEC one.
#   --own-uboot    full     - add our own U-Boot board (needs the defconfig from
#                             u-boot/ to be dropped into the u-boot source too).
#
# Usage:  bash apply-to-immortalwrt.sh [/path/to/immortalwrt] [--own-uboot] [--dry-run]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
IMM=""
OWN_UBOOT=0
DRY=0
for a in "$@"; do
  case "$a" in
    --own-uboot) OWN_UBOOT=1;;
    --dry-run)   DRY=1;;
    -*) echo "unknown option: $a"; exit 2;;
    *)  IMM="$a";;
  esac
done
[ -n "$IMM" ] || IMM="$(cd "$HERE/../.." && pwd)/immortalwrt"

[ -d "$IMM/target/linux/rockchip" ] || { echo "ERROR: not an ImmortalWrt tree: $IMM"; exit 1; }
echo "ImmortalWrt tree : $IMM"
echo "mode             : $([ $OWN_UBOOT -eq 1 ] && echo 'own-uboot (full)' || echo 'minimal (reuse nanopi-r3s U-Boot)')"
[ $DRY -eq 1 ] && echo "dry-run          : yes"
echo

# ---------------------------------------------------------------- 1. device tree
DTSDIR="$IMM/target/linux/rockchip/files/arch/arm64/boot/dts/rockchip"
echo "[1/3] device tree -> $DTSDIR/"
if [ $DRY -eq 0 ]; then
  mkdir -p "$DTSDIR"
  cp -f "$HERE/files/rk3566-onething-edge-cube.dts" "$DTSDIR/"
fi
echo "      rk3566-onething-edge-cube.dts  ($(wc -c < "$HERE/files/rk3566-onething-edge-cube.dts") bytes)"

# ------------------------------------------------------------- 2+3. make edits
echo "[2/3] armv8.mk  Device/onething_oec"
echo "[3/3] uboot-rockchip/Makefile  $([ $OWN_UBOOT -eq 1 ] && echo 'U-Boot/onething-oec-rk3566 + BOOTLOADERS' || echo 'U-Boot/nanopi-r3s-rk3566  BUILD_DEVICES += onething_oec')"

OWN="$OWN_UBOOT" python3 - "$IMM" "$DRY" <<'PY'
import os, sys, io

imm, dry = sys.argv[1], sys.argv[2] == "1"
own = os.environ.get("OWN", "0") == "1"
changed = []

def read(p):
    with io.open(p, "r", encoding="utf-8", newline="") as f:
        return f.read()

def write(p, s):
    if dry:
        return
    with io.open(p, "w", encoding="utf-8", newline="") as f:
        f.write(s)

# ---- 2. armv8.mk -------------------------------------------------------------
av = os.path.join(imm, "target/linux/rockchip/image/armv8.mk")
s = read(av)
if "Device/onething_oec" in s:
    print("      armv8.mk : already present, skipped")
else:
    anchor = "TARGET_DEVICES += friendlyarm_nanopi-r3s\n"
    if anchor not in s:
        print("      armv8.mk : ANCHOR NOT FOUND (nanopi-r3s) - aborting this file")
    else:
        uboot_name = "onething-oec-rk3566" if own else "nanopi-r3s-rk3566"
        block = (
            "\n"
            "define Device/onething_oec\n"
            "  $(Device/rk3566)\n"
            "  DEVICE_VENDOR := OneThing\n"
            "  DEVICE_MODEL := Edge Cube (OEC)/OEC Turbo\n"
            "  DEVICE_DTS := rk3566-onething-edge-cube\n"
            "  SUPPORTED_DEVICES := onething,edge-cube\n"
            "  UBOOT_DEVICE_NAME := %s\n"
            "  DEVICE_PACKAGES := kmod-usb-net-cdc-ncm kmod-usb-net-rndis\n"
            "endef\n"
            "TARGET_DEVICES += onething_oec\n" % uboot_name
        )
        s = s.replace(anchor, anchor + block, 1)
        write(av, s)
        changed.append("armv8.mk")
        print("      armv8.mk : inserted Device/onething_oec (UBOOT_DEVICE_NAME=%s)" % uboot_name)

# ---- 3. uboot-rockchip/Makefile ---------------------------------------------
ub = os.path.join(imm, "package/boot/uboot-rockchip/Makefile")
s = read(ub)
if not own:
    # minimal mode: reuse the R3S U-Boot blob -- but teach it about our device.
    #
    # U-Boot/Default sets HIDDEN:=1, and scripts/package-metadata.pl renders a
    # hidden package as a prompt-less `bool`:
    #
    #     config PACKAGE_u-boot-nanopi-r3s-rk3566
    #             bool                                   <-- no prompt!
    #             default y if DEFAULT_PACKAGE_u-boot-nanopi-r3s-rk3566
    #
    # A prompt-less kconfig symbol CANNOT be set from .config, so writing
    # CONFIG_PACKAGE_u-boot-nanopi-r3s-rk3566=y is silently discarded (verified:
    # it comes out MISS after `make defconfig`).  The only supported way in is
    # the `default y if (... DEVICE_<board>)` rule that include/u-boot.mk
    # (lines 102-104) derives from BUILD_DEVICES.  So register our device there.
    if "onething_oec" in s:
        print("      uboot    : onething_oec already referenced, skipped")
    else:
        anchor = ("define U-Boot/nanopi-r3s-rk3566\n"
                  "  $(U-Boot/rk3566/Default)\n"
                  "  NAME:=NanoPi R3S\n"
                  "  BUILD_DEVICES:= \\\n"
                  "    friendlyarm_nanopi-r3s\n"
                  "endef\n")
        if anchor not in s:
            print("      uboot    : ANCHOR NOT FOUND (U-Boot/nanopi-r3s-rk3566) - aborting this file")
        else:
            repl = anchor.replace("    friendlyarm_nanopi-r3s\n",
                                  "    friendlyarm_nanopi-r3s \\\n    onething_oec\n", 1)
            s = s.replace(anchor, repl, 1)
            write(ub, s)
            changed.append("uboot-rockchip/Makefile")
            print("      uboot    : BUILD_DEVICES += onething_oec (makes the R3S blob default y)")
else:
    if "U-Boot/onething-oec-rk3566" in s:
        print("      uboot    : board already present, skipped")
    else:
        anchor = ("define U-Boot/rock-3c-rk3566\n"
                  "  $(U-Boot/rk3566/Default)\n"
                  "  NAME:=ROCK 3C\n"
                  "  BUILD_DEVICES:= \\\n"
                  "    radxa_rock-3c\n"
                  "endef\n")
        if anchor not in s:
            print("      uboot    : ANCHOR NOT FOUND (rock-3c-rk3566) - aborting this file")
        else:
            block = ("\n"
                     "define U-Boot/onething-oec-rk3566\n"
                     "  $(U-Boot/rk3566/Default)\n"
                     "  NAME:=OneThing Edge Cube (OEC)\n"
                     "  BUILD_DEVICES:= \\\n"
                     "    onething_oec\n"
                     "endef\n")
            s = s.replace(anchor, anchor + block, 1)
            bl_anchor = "  nanopi-r3s-rk3566 \\\n"
            if bl_anchor not in s:
                print("      uboot    : BOOTLOADERS anchor NOT FOUND")
            else:
                s = s.replace(bl_anchor, bl_anchor + "  onething-oec-rk3566 \\\n", 1)
            write(ub, s)
            changed.append("uboot-rockchip/Makefile")
            print("      uboot    : inserted board + BOOTLOADERS entry")

print()
print("      files changed: %s" % (", ".join(changed) if changed else "none"))
PY

echo
echo "=== done ==="
if [ $DRY -eq 0 ]; then
  echo "next:"
  echo "  cd $IMM && make menuconfig      # Target: Rockchip / armv8, select 'OneThing Edge Cube (OEC)'"
  echo "  make -j\$(nproc) V=s"
  echo "  -> bin/targets/rockchip/armv8/*onething_oec*squashfs-sysupgrade.img.gz"
fi
