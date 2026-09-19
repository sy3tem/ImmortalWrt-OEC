# OEC 设备支持（OneThing Edge Cube / OEC Turbo, RK3566）for ImmortalWrt

把网心云 OEC 加进 ImmortalWrt / OpenWrt 的 `rockchip/armv8` target。
**幂等**，可重复运行。

本仓库同时是**云编译仓库**：`.github/workflows/build-firmware.yml` 直接产出可刷写的整机固件。

---

## 云编译（推荐）

Actions → *Build ImmortalWrt firmware for OneThing Edge Cube (OEC) - RK3566* → **Run workflow**

| 输入 | 默认 | 说明 |
|---|---|---|
| `imm_ref` | `master` | ImmortalWrt 源码 ref（分支 / tag / commit） |
| `include_luci` | `true` | 是否带 LuCI |
| `extra_packages` | `luci-app-openclash` | 额外包，空格分隔 |

产物：`immortalwrt-rockchip-armv8-onething_oec-squashfs-sysupgrade.img.gz`
（整盘镜像，含 U-Boot + GPT，`BOOT_FLOW = pine64-img`）

> 首次构建（无 ccache）约 3–5 小时；单 job 上限 355 分钟。

---

## 本地用法

```bash
bash apply-to-immortalwrt.sh /mnt/d/workbuddy/immortalwrt              # 最小实现（推荐先跑这个）
bash apply-to-immortalwrt.sh /mnt/d/workbuddy/immortalwrt --own-uboot  # 自建 U-Boot 板级（见下文，暂不可用）
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
| **minimal**（默认） | `nanopi-r3s-rk3566` | 直接复用现成的 U-Boot 产物。**U-Boot 阶段**用 R3S 的设备树（同 SoC、同 RTL8211F、同 uart2、同 1500000 波特率），**Linux 阶段**用 OEC 的设备树。最快跑通，不用写 U-Boot 板级 |
| **--own-uboot** | `onething-oec-rk3566` | U-Boot 阶段也用 OEC 的 DTS。**当前不可用**，见下一节 |

> **建议先跑 minimal 拿到能启动的固件，再考虑 own-uboot。**
> U-Boot 的板级适配（尤其 SPL 阶段的 `-u-boot.dtsi`、电源时序）需要在真机上迭代，
> 而 minimal 模式把这部分风险推给了已经验证过的 R3S 配置。

---

## U-Boot 现状（重要）

ImmortalWrt 的 `package/boot/uboot-rockchip/Makefile` 用 `PKG_VERSION:=2026.07`。

| U-Boot 版本 | 有 OEC 设备树吗 |
|---|---|
| **v2026.07**（ImmortalWrt 在用） | ❌ 没有 |
| **v2026.10-rc4** | ✅ 有 → `dts/upstream/src/arm64/rockchip/rk3566-onething-edge-cube.dts` |

（该路径是新版 U-Boot 的 upstream-dts 布局；v2026.07 里连 `rk3566-onething-edge-cube.dts`
这个名字都搜不到，也没有对应的 `-u-boot.dtsi`。）

所以**当前只能走 minimal 模式**。`--own-uboot` 模式目前是**不完整**的：
它会往 `uboot-rockchip/Makefile` 里插 `U-Boot/onething-oec-rk3566`（进而要求
`configs/onething-oec-rk3566_defconfig` 和 `arch/arm/dts/rk3566-onething-edge-cube.dts`），
但**脚本并没有把这两个文件注入 U-Boot 源码**，而 v2026.07 里它们本来就不存在 → 必然编译失败。

要真正启用 own-uboot，先做其中一件：

1. 把 `PKG_VERSION` 提到 v2026.10（上游已自带 OEC dts，最干净），或
2. 给 `uboot-rockchip` 加补丁，把 OEC 的 dts / `-u-boot.dtsi` / defconfig 注入 v2026.07 源码

### U-Boot 包是 HIDDEN —— 不能用 `.config` 选它

`Build/pine64-img`（`target/linux/rockchip/image/Makefile:43`）会做：

```make
dd if="$(STAGING_DIR_IMAGE)"/$(UBOOT_DEVICE_NAME)-u-boot-rockchip.bin of="$@" seek=64 conv=notrunc
```

`Device/onething_oec` 设了 `UBOOT_DEVICE_NAME := nanopi-r3s-rk3566`，所以这个 blob 必须由
包 `u-boot-nanopi-r3s-rk3566` 产出（`uboot-rockchip/Makefile:613` 那句
`$(CP) $(PKG_BUILD_DIR)/u-boot-rockchip.bin $(STAGING_DIR_IMAGE)/$(BUILD_VARIANT)-u-boot-rockchip.bin`）。

**但你不能靠 `.config` 选中它。** 原因链条：

1. `package/boot/uboot-rockchip/Makefile:21-25` 的 `U-Boot/Default` 设了 **`HIDDEN:=1`**
2. `scripts/package-metadata.pl:353-354` 对 hidden 包做 `$pkg->{hidden} and $title = ""`
3. 于是生成的 kconfig 是**没有 prompt 的 `bool`**：

```
	config PACKAGE_u-boot-nanopi-r3s-rk3566
		bool
		default y if DEFAULT_PACKAGE_u-boot-nanopi-r3s-rk3566
		default y if (TARGET_rockchip_armv8_Default || \
		              TARGET_rockchip_armv8_DEVICE_friendlyarm_nanopi-r3s || \
		              TARGET_rockchip_armv8_DEVICE_onething_oec || ...)
```

**prompt-less 的 kconfig symbol 无法从 `.config` 赋值** —— 写
`CONFIG_PACKAGE_u-boot-nanopi-r3s-rk3566=y` 会被静默丢弃（实测 `make defconfig` 之后
该符号根本不出现在 `.config` 里）。

**正确做法**：把设备名注册进 `BUILD_DEVICES`，让 `include/u-boot.mk:102-104` 推导出的
`default y if (..._DEVICE_<board>)` 条件成立。`apply-to-immortalwrt.sh` 就是这么做的：

```make
define U-Boot/nanopi-r3s-rk3566
  $(U-Boot/rk3566/Default)
  NAME:=NanoPi R3S
  BUILD_DEVICES:= \
    friendlyarm_nanopi-r3s \
    onething_oec          # <- 加这一行
endef
```

> 同理适用于**任何 `HIDDEN:=1` 的包**（`trusted-firmware-a`、`optee-os` 都是这套机制）。

漏掉的话，前面编译全部成功，最后打镜像时 `dd` 才报“文件不存在”。
workflow 在 `make defconfig` 之后检查 `tmp/.config-package.in` —— **注意该文件是 TAB 缩进的**，
模式必须写成 `/^[[:space:]]*config .../`，否则永远匹配不到、会报假阴性。几秒内即可失败。

### 构建依赖（容易漏）

`uboot-rockchip/Makefile:14-15` 设了 `UBOOT_USE_BINMAN:=1` 和 `UBOOT_USE_INTREE_DTC:=1`，
`include/u-boot.mk:23-48` 因此把它们变成**硬性** host 检查：

| 依赖 | 由谁要求 |
|---|---|
| `python3-pyelftools` | `UBOOT_USE_BINMAN` |
| `python3-dev` | `UBOOT_USE_INTREE_DTC` |
| `python3-setuptools` | `UBOOT_USE_INTREE_DTC` |
| `swig` | `UBOOT_USE_INTREE_DTC` |

缺任一个都会在 `Checking 'python3-pyelftools'... failed` 处中断构建。
workflow 已装齐，并额外加了一步 `Verify build prerequisites` 提前报错。

---

## 文件

```
oec-imm/
├── README.md
├── apply-to-immortalwrt.sh                     # 幂等应用脚本
├── .github/workflows/build-firmware.yml        # 云编译
├── files/
│   └── rk3566-onething-edge-cube.dts           # 取自 mainline v7.1（已验证可在 6.18 上编译）
└── u-boot/
    └── onething-oec-rk3566_defconfig           # 自建 U-Boot 用（暂未接线），派生自 nanopi-r3s-rk3566
```

---

## 已验证 / 待验证

**已在云编译里实证通过**（run 35460326796）
- `Apply OEC (OneThing Edge Cube) device support` ✓
- `Apply build config` ✓ → `OK   device onething_oec selected`
  → `OK   u-boot-nanopi-r3s-rk3566 present and defaulted for onething_oec`
- `dump-target-info devices rockchip/armv8` 列出 `onething_oec "OneThing Edge Cube (OEC)/OEC Turbo"`
- `Verify build prerequisites` ✓ ／ `Download sources` ✓

**本地已验证**
- v7.1 的这份 DTS 在 **linux-6.18.44** 源码树上 cpp+dtc 一次通过（51,164 B，39 个外设节点）
- v7.1 下同一份 DTS 编出的 DTB 为 52,951 B；`Image` 在 WSL2 上可完整编出（52.4 MB）
- 应用脚本两种模式插入逻辑正确，且**幂等**（第二次运行 `files changed: none`）
- `DEVICE_DTS_DIR = $(DTS_DIR)/rockchip`（`target/linux/rockchip/image/Makefile:75`），
  dts 放在 `files/arch/arm64/boot/dts/rockchip/` 即会被自动编译
- 上游 U-Boot 两版本的 dts 覆盖情况（见上表，git trees API 实测）

**尚未验证（等这次构建跑完 / 真机）**
- 内核 6.18 能否带上 OEC dts 编译通过、U-Boot blob 能否产出
- `pine64-img` 打包是否成功（`dd seek=64` 布局）
- minimal 模式下 R3S 的 U-Boot 能否真正引导 OEC（DDR 时序、eMMC、**OEC 无 PMIC** 时的 regulator 路径）
- r306（原厂 eMMC）可能额外需要把 `env.bin` 写到 sector 294912（来自第三方 fork 的打包逻辑，未证实）
- OEC 的 3 个 RGB LED 在 OpenWrt 里的映射（`base-files/etc/board.d/01_leds`，可选）
