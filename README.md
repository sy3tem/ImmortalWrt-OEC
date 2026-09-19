# OEC 设备支持（OneThing Edge Cube / OEC Turbo, RK3566）for ImmortalWrt

把网心云 OEC 加进 ImmortalWrt / OpenWrt 的 `rockchip/armv8` target。
**幂等**，可重复运行。

---

## 快速用法

```bash
# 在 WSL 里（构建环境）
bash apply-to-immortalwrt.sh /mnt/d/workbuddy/immortalwrt              # 最小实现（推荐先跑这个）
bash apply-to-immortalwrt.sh /mnt/d/workbuddy/immortalwrt --own-uboot  # 自建 U-Boot 板级
bash apply-to-immortalwrt.sh /mnt/d/workbuddy/immortalwrt --dry-run    # 只看会改什么
```

跑完：

```bash
cd /mnt/d/workbuddy/immortalwrt
make menuconfig      # Target: Rockchip -> armv8，勾选 "OneThing Edge Cube (OEC)/OEC Turbo"
make -j$(nproc) V=s
# 产物：bin/targets/rockchip/armv8/*onething_oec*squashfs-sysupgrade.img.gz
```

---

## 它改了什么（3 处）

| # | 位置 | 内容 |
|---|---|---|
| 1 | `target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3566-onething-edge-cube.dts` | 设备树。OpenWrt 的构建系统对 `DEVICE_DTS` **直接对 .dts 跑 cpp+dtc**，不依赖内核 Makefile，所以放这儿就会自动编译 |
| 2 | `target/linux/rockchip/image/armv8.mk` | `Device/onething_oec` + `TARGET_DEVICES +=` |
| 3 | `package/boot/uboot-rockchip/Makefile` | `U-Boot/onething-oec-rk3566` + `BOOTLOADERS` 列表项（**仅 `--own-uboot` 模式**） |

`armv8.mk` 里插入的内容：

```make
define Device/onething_oec
  $(Device/rk3566)
  DEVICE_VENDOR := OneThing
  DEVICE_MODEL := Edge Cube (OEC)/OEC Turbo
  DEVICE_DTS := rk3566-onething-edge-cube
  SUPPORTED_DEVICES := onething,edge-cube
  UBOOT_DEVICE_NAME := nanopi-r3s-rk3566     # --own-uboot 时改成 onething-oec-rk3566
  DEVICE_PACKAGES := kmod-usb-net-cdc-ncm kmod-usb-net-rndis
endef
TARGET_DEVICES += onething_oec
```

`SUPPORTED_DEVICES := onething,edge-cube` 对应 DTS 的
`compatible = "onething,edge-cube", "rockchip,rk3566";`，sysupgrade 校验用。

---

## 两种模式的区别

| 模式 | `UBOOT_DEVICE_NAME` | 说明 |
|---|---|---|
| **minimal**（默认） | `nanopi-r3s-rk3566` | 直接复用现成的 U-Boot 产物。**U-Boot 阶段**用 R3S 的设备树（同 SoC、同 RTL8211F、同 uart2），**Linux 阶段**用 OEC 的设备树。最快跑通，不用写 U-Boot 板级 |
| **--own-uboot** | `onething-oec-rk3566` | 需要把 `u-boot/onething-oec-rk3566_defconfig` 也放进 u-boot 源码（`package/boot/uboot-rockchip/` 的补丁或 `src/`）。U-Boot 阶段也用 OEC 的 DTS |

> **建议先跑 minimal 拿到能启动的固件，再考虑 own-uboot。**
> U-Boot 的板级适配（尤其 SPL 阶段的 `-u-boot.dtsi`、电源时序）需要在真机上迭代，
> 而 minimal 模式把这部分风险推给了已经验证过的 R3S 配置。

---

## 文件

```
oec-imm/
├── README.md
├── apply-to-immortalwrt.sh                     # 幂等应用脚本
├── files/
│   └── rk3566-onething-edge-cube.dts           # 取自 mainline v7.1（已验证可在 6.18 上编译）
└── u-boot/
    └── onething-oec-rk3566_defconfig           # 自建 U-Boot 用，派生自 nanopi-r3s-rk3566
```

---

## 已验证 / 待验证

**已验证**
- v7.1 的这份 DTS 在 **linux-6.18.44** 源码树上 cpp+dtc 一次通过（51,164 B，39 个外设节点）
- 应用脚本两种模式 dry-run 均命中锚点，插入逻辑正确

**待验证（需要在真机或完整构建里做）**
- `Device/onething_oec` 能否通过 `make defconfig`（`DEVICE_DTS` 路径解析、`SUPPORTED_DEVICES` 语法）
- minimal 模式下 R3S 的 U-Boot 能否引导 OEC（串口 1500000、eMMC、DDR 时序）
- `pine64-img` 的 `dd seek=64` 布局对 OEC 的 eMMC 是否合适
- r306（原厂 eMMC）可能额外需要把 `env.bin` 写到 sector 294912（来自第三方 fork 的打包逻辑，未证实）
- OEC 的 3 个 RGB LED 在 OpenWrt 里的映射（`base-files/etc/board.d/01_leds`，可选）
