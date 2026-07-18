# MYiR MYS-RZG2L OpenWrt 6.12 完整使用与定制指南

本文面向以下几类使用者：

- 直接下载固件，第一次把开发板迁移到本项目
- 已经运行本项目固件，通过 LuCI 或命令行执行 sysupgrade
- Fork 仓库，在 GitHub Actions 中定制软件包
- 添加 LuCI 主题、应用、内核驱动、firmware 或设备树
- 用 tag 自动把编译产物发布到 GitHub Releases

当前可用源码分支是 [`codex/myir-sysupgrade`](https://github.com/aierm/myir-openwrt/tree/codex/myir-sysupgrade)。旧 `master` 基线不包含本项目的 MYiR sysupgrade 实现，不应拿来生成在线升级固件。

2026-07-16 已在真实 MYS-RZG2L WiFi 板上完成 `proxy-zh` profile 的 LuCI sysupgrade，经过验证的 OpenWrt commit 为 `41f7f75c3453d6cd32c8ed1d36e15b2bcf86accf`，对应的 [GitHub Actions 构建](https://github.com/aierm/myir-openwrt/actions/runs/29472379194)已通过镜像结构、内核、DTB、ext4 和元数据校验。固件已发布为 [myir-v2026.07.16-1](https://github.com/aierm/myir-openwrt/releases/tag/myir-v2026.07.16-1)。

## 1. 支持范围与磁盘布局

目前只对以下板型合同做了完整适配：

```text
设备：MYiR MYS-RZG2L WiFi
compatible：myir,mys-rzg2l-wifi
OpenWrt profile：myir_mys_rzg2l_wifi
启动根分区：/dev/mmcblk0p2
启动文件分区：/dev/mmcblk0p1（FAT）
LAN：eth0，默认 192.168.3.1
WAN：eth1，默认 PPPoE
```

当前 eMMC 分区合同是：

| 区域 | 用途 |
| --- | --- |
| eMMC 原始扇区 | 厂商 BL2/FIP，由首次恢复流程写入，sysupgrade 不修改 |
| `/dev/mmcblk0p1` | FAT 启动分区，保存 `Image`、`mys-rzg2l-wifi.dtb` 和升级配置备份 |
| `/dev/mmcblk0p2` | ext4 rootfs，sysupgrade 写入后执行 `e2fsck` 和 `resize2fs` |

sysupgrade 会拒绝可移动磁盘、错误板型、错误根设备、错误分区格式、容量不足、损坏的归档以及缺少兼容元数据的镜像。不要使用 `-F` 绕过这些检查。

## 2. 两棵源码树

本项目不是单独一棵 OpenWrt 树，构建时同时使用：

```text
myir-rzg2l/
├── openwrt/       OpenWrt、软件包、镜像、板级默认值和 sysupgrade
└── rz_linux-cip/  Linux 驱动、Kconfig、内核 Makefile 和 DTS
```

OpenWrt 仓库：

```text
https://github.com/aierm/myir-openwrt
branch: codex/myir-sysupgrade
```

外部内核仓库：

```text
https://github.com/aierm/myir-rz-linux-cip
branch: rz-6.12-cip7
```

两棵树的职责不能混淆：

| 修改内容 | 应修改的仓库或目录 |
| --- | --- |
| OpenWrt 软件包、LuCI、feed | `openwrt/package/`、`feeds.conf*`、profile config |
| 镜像布局、默认包、升级逻辑 | `openwrt/target/linux/renesas/` |
| 内核驱动源码、Kconfig、内核 Makefile | `rz_linux-cip/` |
| 板级 DTS/DTSI | `rz_linux-cip/arch/arm64/boot/dts/renesas/` |
| 外部内核的选择 | `.github/workflows/myir-rzg2l-build.yml` 或仓库变量 |

### 外部内核模式的重要限制

本项目设置了：

```config
CONFIG_EXTERNAL_KERNEL_TREE="$(CURDIR)/../rz_linux-cip"
```

这种模式下，OpenWrt 直接链接外部内核目录，不会执行普通内核源码包路径中的 `Kernel/Patch`。因此，把 DTS 或驱动补丁只放到：

```text
target/linux/renesas/patches-6.12/
```

并不会应用到当前构建。DTS、内核 Kconfig/Makefile 和内核内驱动修改必须提交到 `myir-rz-linux-cip`，然后让 Actions 使用对应的 tag 或完整 commit。

## 3. 在 Ubuntu 本地编译

### 3.1 安装依赖

以下依赖与 GitHub Actions 使用的 Ubuntu 24.04 环境一致：

```sh
sudo apt-get update
sudo apt-get install -y \
  build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
  gettext git libncurses5-dev libssl-dev python3 python3-docutils \
  python3-ply rsync unzip zlib1g-dev file wget subversion swig time \
  device-tree-compiler ccache qemu-utils
```

建议准备至少 60 GB 可用磁盘空间和 8 GB 内存。第一次完整构建会下载并编译工具链，耗时取决于 CPU、磁盘和下载网络。

### 3.2 克隆源码

OpenWrt 的默认配置假定两棵树处于同一级目录：

```sh
mkdir -p ~/myir-rzg2l
cd ~/myir-rzg2l

git clone --branch codex/myir-sysupgrade --single-branch \
  https://github.com/aierm/myir-openwrt.git openwrt
git clone --branch rz-6.12-cip7 --single-branch \
  https://github.com/aierm/myir-rz-linux-cip.git rz_linux-cip
```

如果使用不同目录，生成 `.config` 后必须把外部内核改成真实绝对路径：

```sh
sed -i 's|^CONFIG_EXTERNAL_KERNEL_TREE=.*|CONFIG_EXTERNAL_KERNEL_TREE="/absolute/path/to/rz_linux-cip"|' .config
```

### 3.3 选择构建 profile

仓库提供两个 profile：

| profile | 内容 | rootfs 镜像大小 |
| --- | --- | --- |
| `minimal` | 板级基础系统、网络、WiFi、LuCI 和 sysupgrade 依赖,未配置其他软件| 256 MiB |
| `proxy-zh` | 中文LuCI、passwall2、openclash、nikki代理软件及其依赖 | 512 MiB |

构建 `minimal`：

```sh
cd ~/myir-rzg2l/openwrt
./scripts/feeds update -a
./scripts/feeds install -a
./scripts/prepare-myir-config.sh minimal
make defconfig
make download -j"$(nproc)"
make -j"$(nproc)" || make -j1 V=s
```

构建 `proxy-zh` 时，使用单独的 `feeds.conf`，不要为了本地试验修改受 Git 管理的 `feeds.conf.default`：

```sh
cd ~/myir-rzg2l/openwrt
cp feeds.conf.default feeds.conf
cat configs/myir-rzg2l/feeds/proxy.feeds >> feeds.conf
./scripts/feeds update -a
./scripts/feeds install -a
./scripts/prepare-myir-config.sh proxy-zh
make defconfig
make download -j"$(nproc)"
make -j"$(nproc)" || make -j1 V=s
```

并行构建失败时，最后一条命令会自动用单线程 `V=s` 重试并显示真正的首个错误。

### 3.4 输出目录

构建成功后检查：

```sh
find bin/targets/renesas/armv8 -maxdepth 1 -type f -printf '%f\n' | sort
```

核心产物见本文第 8 节。

## 4. 创建自己的构建 profile

不要只修改顶层 `.config`。Actions 每次都会用板级基础配置和 profile 重新生成它，未写入 profile 的选择会丢失。

先复制一个 profile：

```sh
cp configs/myir-rzg2l/profiles/minimal.config \
  configs/myir-rzg2l/profiles/my-custom.config
```

把需要的包写入新文件，例如：

```config
CONFIG_TARGET_ROOTFS_PARTSIZE=512
CONFIG_LUCI_LANG_zh_Hans=y
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_htop=y
CONFIG_PACKAGE_kmod-usb-net-rtl8152=y
```

然后生成并检查配置：

```sh
./scripts/prepare-myir-config.sh my-custom
make defconfig
make menuconfig
./scripts/diffconfig.sh > /tmp/my-custom.diffconfig
```

`/tmp/my-custom.diffconfig` 用来确认最终选择；只把相对板级基础配置新增或覆盖的项目整理回 `my-custom.config`。不要把工具链自动推导出的全部选项无差别复制进去。

若要从 Actions 页面选择它，还要在工作流输入中增加：

```yaml
options:
  - minimal
  - proxy-zh
  - my-custom
```

提交 profile 后再运行 Actions：

```sh
git add configs/myir-rzg2l/profiles/my-custom.config \
  .github/workflows/myir-rzg2l-build.yml
git commit -m 'myir: add my-custom firmware profile'
git push
```

## 5. 从源码添加 LuCI 普通软件包

### 5.1 本地添加 luci-theme-argon

以 [jerrykuku/luci-theme-argon](https://github.com/jerrykuku/luci-theme-argon) 为例。先在 `prepare-myir-config.sh` 和 `make defconfig` 之前克隆包：

```sh
cd ~/myir-rzg2l/openwrt
git clone https://github.com/jerrykuku/luci-theme-argon.git \
  package/luci-theme-argon
```

然后在自定义 profile 中加入：

```config
CONFIG_PACKAGE_luci-theme-argon=y
```

重新生成配置并构建：

```sh
./scripts/feeds update -a
./scripts/feeds install -a
./scripts/prepare-myir-config.sh my-custom
make defconfig
make package/luci-theme-argon/compile V=s
make -j"$(nproc)" || make -j1 V=s
```

上面的直接 `git clone` 适合本地试验，但默认跟随上游最新代码，不能保证以后得到同一个结果。用于项目和 Release 时应固定 tag 或完整 commit。本文核对时 Argon `v2.4.4` 对应 commit `1c686ed83cdf0b79684df45074111ff56f296a6b`：

```sh
rm -rf package/luci-theme-argon
git clone https://github.com/jerrykuku/luci-theme-argon.git \
  package/luci-theme-argon
git -C package/luci-theme-argon checkout \
  1c686ed83cdf0b79684df45074111ff56f296a6b
```

### 5.2 让 GitHub Actions 也取得源码包

如果不把第三方源码放进自己的 Git 仓库，可在[工作流](https://github.com/aierm/myir-openwrt/blob/codex/myir-sysupgrade/.github/workflows/myir-rzg2l-build.yml)的 `Update and install feeds` 之前加入：

```yaml
- name: Checkout custom source packages
  working-directory: openwrt
  run: |
    git clone https://github.com/jerrykuku/luci-theme-argon.git \
      package/luci-theme-argon
    git -C package/luci-theme-argon checkout \
      1c686ed83cdf0b79684df45074111ff56f296a6b
```

然后在[自定义 profile](https://github.com/aierm/myir-openwrt/blob/codex/myir-sysupgrade/configs/myir-rzg2l/profiles/proxy-zh.config) 中加入：

```config
CONFIG_PACKAGE_luci-theme-argon=y
```

### 5.3 在 GitHub Actions构建中开启临时 SSH 用于临时调试

修改[工作流](https://github.com/aierm/myir-openwrt/blob/codex/myir-sysupgrade/.github/workflows/myir-rzg2l-build.yml)的 `Update and install feeds`之后加入如下
```yaml
      - name: Update and install feeds
        working-directory: openwrt
        run: |
          ./scripts/feeds update -a
          ./scripts/feeds install -a

      # 【新增步骤】在此处暂停并断开，为你生成一个 SSH 连接
      - name: Setup Tmate SSH Debugger
        uses: mxschmitt/action-tmate@v3
        # 提示：调完配置后在SSH终端输入 'exit'，编译就会继续往下走

      - name: Prepare defconfig
        working-directory: openwrt
        run: |
          chmod +x scripts/prepare-myir-config.sh
          ./scripts/prepare-myir-config.sh "$MYIR_PROFILE"
          sed -i "s|^CONFIG_EXTERNAL_KERNEL_TREE=.*|CONFIG_EXTERNAL_KERNEL_TREE=\"$GITHUB_WORKSPACE/rz_linux-cip\"|" .config
          export TERM=xterm
          make defconfig

```

提交代码并触发 GitHub Actions，流程运行到这一步时会暂停,展开 GitHub 的日志，会看到一行类似 ssh xxx@tmate.io的 SSH 字符串,复制该字符串，粘贴到本地终端连接 SSH
<img width="1910" height="989" alt="截图_2026-07-17_11-01-10" src="https://github.com/user-attachments/assets/10690c19-498c-43b3-8bef-421afc72faa0" />

连接成功后,应该会有这样一段提示
```text
Tip: if you wish to use tmate only for remote access, run: tmate -F
To see the following messages again, run in a tmate session: tmate show-messages
Press <q> or <ctrl-c> to continue
```
我们按提示按下键盘上的 q 键（或按 Ctrl + C）退出 tmate 消息查看器，就能进入 workflows 的交互式 Linux 命令行,之后参考下面命令,minimal 可替换成自己的 profiles,运行 make menuconfig 后即可进入 openwrt 的图形交互界面。
```sh
cd openwrt
chmod +x scripts/prepare-myir-config.sh
./scripts/prepare-myir-config.sh "minimal"
sed -i "s|^CONFIG_EXTERNAL_KERNEL_TREE=.*|CONFIG_EXTERNAL_KERNEL_TREE=\"$GITHUB_WORKSPACE/rz_linux-cip\"|" .config
export TERM=xterm
make menuconfig
```
<img width="1454" height="465" alt="截图_2026-07-17_11-00-24-1" src="https://github.com/user-attachments/assets/8384d290-6711-4049-b41a-5729e7953706" />
调试确认完成后 SAVE 配置文件,退出交互界面,之后在终端输入"exit"断开连接,GitHub Actions 自动化工作流程就能够自动获取刚才的更改并继续构建固件。

## 6. 添加内核驱动、firmware 和 DTS

添加驱动前先分类，不能只把一个厂商 `.ko` 复制到 rootfs。

| 场景 | 修改位置 | 处理方式 |
| --- | --- | --- |
| OpenWrt 已有该驱动包 | OpenWrt 仓库 | 选择 `kmod-*`，加入设备包或 profile |
| 驱动已在外部内核中，但 OpenWrt 未打包 | 外部内核 + OpenWrt | 编进内核，或新增 `KernelPackage` |
| 厂商提供独立树外驱动源码 | `package/kernel/<name>/` | 用当前内核和工具链创建模块包 |
| 硬件需要 DTS 或二进制 firmware | 外部内核 DTS + firmware 包 | 添加节点并安装驱动请求的文件 |

### 6.1 使用 OpenWrt 已有的驱动

先搜索：

```sh
rg -n 'define KernelPackage/.*关键字|CONFIG_驱动符号' \
  package/kernel target/linux
```

板载 RTL8822CS 是本仓库中的真实例子：

- `kmod-rtw88-8822cs` 定义在 `package/kernel/mac80211/realtek.mk`
- 它会拉入 `kmod-rtw88-sdio` 和 `kmod-rtw88-8822c`
- `rtl8822ce-firmware` 提供驱动请求的 firmware

板级必需驱动加入：

```text
target/linux/renesas/image/armv8.mk
```

例如：

```make
DEVICE_PACKAGES += \
	kmod-rtw88-8822cs rtl8822ce-firmware
```

只在某个定制固件中使用的驱动加入 profile：

```config
CONFIG_PACKAGE_kmod-usb-net-rtl8152=y
```

然后重新生成配置：

```sh
./scripts/prepare-myir-config.sh my-custom
make defconfig
```

### 6.2 添加外部内核中已有的驱动

驱动源文件、Kconfig 和内核 Makefile 应放在 `myir-rz-linux-cip`。提交并推送外部内核后，让 Actions 的 `MYIR_KERNEL_REF` 指向固定 tag 或完整 commit。

启动、eMMC 或根文件系统必需的驱动适合内建：

```config
CONFIG_MYCHIP=y
```

用下面的命令维护板级内核配置，并检查最终差异：

```sh
make kernel_menuconfig CONFIG_TARGET=target
git diff -- target/linux/renesas/config-6.12
```

普通外设适合作为 kmod。可创建 `target/linux/renesas/modules.mk`：

```make
define KernelPackage/mychip
  SUBMENU:=Other modules
  TITLE:=MyChip device driver
  DEPENDS:=@TARGET_renesas_armv8 +kmod-i2c-core
  KCONFIG:=CONFIG_MYCHIP
  FILES:=$(LINUX_DIR)/drivers/misc/mychip.ko
  AUTOLOAD:=$(call AutoProbe,mychip)
endef

define KernelPackage/mychip/description
  Kernel driver for the MyChip device on MYiR MYS-RZG2L.
endef

$(eval $(call KernelPackage,mychip))
```

再把 `kmod-mychip` 加入 `DEVICE_PACKAGES` 或 profile。

`FILES` 必须和内核实际输出的 `.ko` 路径一致。选择模块包时，不要又在 `config-6.12` 中把相同符号强制设为 `y`，否则驱动会成为内建项而不是独立模块。

不要把当前的 `kmod-renesas-net-avb` 当作模块示例。本项目的 RAVB 实际由 `CONFIG_RAVB=y` 编进内核，现有同名 KernelPackage 受另一个 target 限制；manifest 中出现包名也不等于一定存在对应 `.ko`。

### 6.3 添加树外驱动

厂商只提供独立驱动仓库时，创建一个受版本控制的 OpenWrt 包：

```text
package/kernel/mychip/Makefile
package/kernel/mychip/patches/
```

示例：

```make
include $(TOPDIR)/rules.mk

PKG_NAME:=mychip
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/vendor/mychip-driver.git
PKG_SOURCE_DATE:=YYYY-MM-DD
PKG_SOURCE_VERSION:=完整的 Git commit
PKG_MIRROR_HASH:=下载源码归档的 SHA256

PKG_LICENSE:=GPL-2.0-only
PKG_LICENSE_FILES:=COPYING
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/package.mk

define KernelPackage/mychip
  SUBMENU:=Other modules
  TITLE:=MyChip out-of-tree driver
  DEPENDS:=@TARGET_renesas_armv8 +kmod-i2c-core +mychip-firmware
  FILES:=$(PKG_BUILD_DIR)/mychip.ko
  AUTOLOAD:=$(call AutoProbe,mychip)
endef

define Build/Compile
	+$(KERNEL_MAKE) $(PKG_JOBS) \
		M="$(PKG_BUILD_DIR)" \
		modules
endef

$(eval $(call KernelPackage,mychip))
```

要求：

- `PKG_SOURCE_VERSION` 固定完整 commit，不使用移动的 `master` 或 `main`
- `PKG_MIRROR_HASH` 使用真实哈希，不长期保留 `skip`
- 厂商 Makefile 支持标准的 `M=<目录> modules` 树外构建
- 6.12 内核 API 适配补丁放在 `package/kernel/mychip/patches/`
- 不安装其他固件或其他内核编译出的预制 `.ko`

先单包测试，再完整构建：

```sh
make package/kernel/mychip/clean
make package/kernel/mychip/compile V=s
make -j"$(nproc)" || make -j1 V=s
```

内核版本字符串、vermagic、编译器或配置不同都会导致模块拒绝加载。本项目的模块必须和内核、rootfs 在同一次 Actions 运行中生成。

### 6.4 添加驱动 firmware

从驱动源码或日志确认准确文件名：

```sh
dmesg | grep -i firmware
```

例如驱动中有：

```c
MODULE_FIRMWARE("vendor/mychip.bin");
```

最终文件必须位于：

```text
/lib/firmware/vendor/mychip.bin
```

优先使用 OpenWrt 已有 firmware 包。没有时可创建：

```text
package/firmware/mychip-firmware/Makefile
package/firmware/mychip-firmware/files/mychip.bin
```

最小 Makefile：

```make
include $(TOPDIR)/rules.mk

PKG_NAME:=mychip-firmware
PKG_RELEASE:=1
PKG_LICENSE:=Vendor-Firmware
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk

define Package/mychip-firmware
  SECTION:=firmware
  CATEGORY:=Firmware
  TITLE:=Firmware for MyChip devices
endef

define Build/Compile
endef

define Package/mychip-firmware/install
	$(INSTALL_DIR) $(1)/lib/firmware/vendor
	$(INSTALL_DATA) ./files/mychip.bin \
		$(1)/lib/firmware/vendor/mychip.bin
endef

$(eval $(call BuildPackage,mychip-firmware))
```

让驱动包依赖它，或把两者都加入 `DEVICE_PACKAGES`。发布第三方二进制 firmware 前必须确认许可证允许重新分发。

### 6.5 添加或修改 DTS

实际使用的设备树位于外部内核：

```text
arch/arm64/boot/dts/renesas/mys-rzg2l-smarc-base.dtsi
arch/arm64/boot/dts/renesas/mys-rzg2l-wifi.dts
arch/arm64/boot/dts/renesas/mys-rzg2l-sdcard.dts
```

通用电源、GPIO、pinctrl 和板级节点放在 `mys-rzg2l-smarc-base.dtsi`；WiFi 变体专用节点放在 `mys-rzg2l-wifi.dts`。新增 DTS 时还要在外部内核的 `arch/arm64/boot/dts/renesas/Makefile` 注册 DTB。

USB 和 PCIe 设备通常能自动枚举，不一定需要 DTS。SDIO、I2C、SPI 和 platform 设备通常需要正确的 `compatible`、regulator、clock、interrupt、reset 与 pinctrl。`compatible` 必须匹配驱动的 `of_device_id`。

如果增加的是另一种开发板，而不是当前板上的外设，必须同步修改：

- 外部内核 DTS 和 DTS Makefile
- OpenWrt `DEVICE_DTS` 与 `SUPPORTED_DEVICES`
- `board.d` 中的网络、LED 和兼容版本
- sysupgrade 的板型、归档目录和设备检查

不要随意改变当前 `myir,mys-rzg2l-wifi` compatible，否则可能让 sysupgrade 拒绝正确镜像，或错误接受其他板型镜像。

### 6.6 验证驱动和 DTS

检查 manifest：

```sh
MANIFEST=bin/targets/renesas/armv8/openwrt-renesas-armv8-myir_mys_rzg2l_wifi.manifest
grep -E '^(kmod-mychip|mychip-firmware) ' "$MANIFEST"
```

检查实际模块与 DTB：

```sh
find build_dir -type f -name 'mychip.ko' -print

DTB=bin/targets/renesas/armv8/openwrt-renesas-armv8-myir_mys_rzg2l_wifi-device-tree.dtb
dtc -I dtb -O dts -o /tmp/myir-rzg2l.dts "$DTB"
rg -n 'mychip|对应的 compatible' /tmp/myir-rzg2l.dts
```

刷写后检查：

```sh
uname -r
find "/lib/modules/$(uname -r)" -name '*mychip*.ko' -print
lsmod | grep mychip
modprobe mychip
dmesg | grep -iE 'mychip|firmware|probe|error|failed'
ls -l /lib/firmware/vendor/mychip.bin
```

内建驱动不会出现在 `lsmod`，应检查：

```sh
grep -i mychip "/lib/modules/$(uname -r)/modules.builtin"
dmesg | grep -i mychip
```

## 7. 使用 GitHub Actions 编译

### 7.1 Fork 并准备分支

可以在网页点击 Fork，也可以使用 GitHub CLI：

```sh
gh repo fork aierm/myir-openwrt --clone
cd myir-openwrt
git fetch upstream codex/myir-sysupgrade
git switch codex/myir-sysupgrade 2>/dev/null || \
  git switch -c codex/myir-sysupgrade \
    --track upstream/codex/myir-sysupgrade
git push -u origin codex/myir-sysupgrade
```

Fork 后，GitHub 可能要求在仓库的 Actions 页面手动启用工作流。

`gh repo fork` 可能让后续 `gh` 命令仍以源仓库为默认目标，因此命令中应明确指定自己的 fork：

```sh
OWNER="$(gh api user --jq .login)"
FORK="$OWNER/myir-openwrt"
gh workflow enable myir-rzg2l-build.yml --repo "$FORK"
```

### 7.2 外部内核变量

不改内核时，工作流默认使用：

```text
aierm/myir-rz-linux-cip@rz-6.12-cip7
```

如果也 Fork 了内核，在 OpenWrt fork 中设置仓库变量：

```sh
gh variable set MYIR_KERNEL_REPOSITORY \
  --repo "$FORK" --body "$OWNER/myir-rz-linux-cip"
gh variable set MYIR_KERNEL_REF \
  --repo "$FORK" --body '<内核 tag 或完整 commit>'
```

Release 应固定不可移动的内核 tag 或完整 SHA。只固定一个长期移动的分支名，无法保证以后复现相同内核。

### 7.3 手动启动构建

构建最小系统：

```sh
gh workflow run myir-rzg2l-build.yml \
  --repo "$FORK" \
  --ref codex/myir-sysupgrade \
  -f profile=minimal
```

构建中文代理 profile：

```sh
gh workflow run myir-rzg2l-build.yml \
  --repo "$FORK" \
  --ref codex/myir-sysupgrade \
  -f profile=proxy-zh
```

查看并等待最新运行：

```sh
RUN_ID="$(gh run list \
  --repo "$FORK" \
  --workflow myir-rzg2l-build.yml \
  --limit 1 \
  --json databaseId \
  --jq '.[0].databaseId')"

gh run watch "$RUN_ID" --repo "$FORK" --exit-status
gh run download "$RUN_ID" --repo "$FORK" --dir ./artifacts
```

网页路径是：

```text
Actions -> Build MYiR RZ/G2L Firmware -> Run workflow
```

工作流会完成：

1. 检出 OpenWrt 和外部内核。
2. 添加 profile 需要的 feed。
3. 生成 `.config` 并替换外部内核绝对路径。
4. 下载源码并完整编译。
5. 校验 MBR、FAT、ext4、sysupgrade 成员、内核和 DTB magic、元数据与 e2fsprogs 版本。
6. 生成厂商首次迁移所需的文件包。
7. 上传 Actions Artifact；tag 构建还会发布 GitHub Release。

普通 push 构建使用 `minimal`。手动运行使用页面选择的 profile。tag Release 默认使用 `minimal`，也可通过 `MYIR_RELEASE_PROFILE` 仓库变量改成 `proxy-zh`。

## 8. 认识构建产物

输出目录或 Artifact 中的文件用途如下：

| 文件 | 用途 | 是否可上传 LuCI |
| --- | --- | --- |
| `*-ext4-sysupgrade.tar.gz` | 在线升级归档，包含 CONTROL、Image、DTB、rootfs 和兼容元数据 | 是 |
| `*-ext4-sdcard.img.gz` | 完整 MBR + FAT + ext4 磁盘镜像 | 否 |
| `*-vendor-recovery-files.tar.gz` | 厂商首次恢复工具所需的替换文件，不含 BL2/FIP 和更新脚本 | 否 |
| `*-device-tree.dtb` | 独立设备树 | 否 |
| `*.manifest` | 最终固件包列表 | 否 |
| `sha256sums` | 标准 OpenWrt 产物哈希 | 否 |
| `*.buildinfo` | 配置、feed 和版本信息 | 否 |
| `profiles.json` | 机器可读的设备与镜像元数据 | 否 |

`sdcard.img.gz` 不等于 MYiR 厂商 SD 更新镜像。它没有厂商 `boot.scr`、更新 rootfs、BL2/FIP 和自动写 eMMC 脚本，不能替代第一次迁移流程。

## 9. 第一次从厂商系统或旧 OpenWrt 迁移

只有已经运行本分支平台脚本的系统才能安全执行本项目 sysupgrade。旧固件中没有 `/lib/upgrade/platform.sh` 的 MYiR 实现，或者缺少 `e2fsck`、`resize2fs`、`jsonfilter` 时，必须先走一次厂商 SD 更新流程。

此过程会重建 eMMC 分区并写入 BL2/FIP。先备份数据，接好 115200 波特率串口，并确认板卡供电稳定。

### 9.1 准备厂商更新文件

下载 Release 中的：

```text
openwrt-renesas-armv8-myir_mys_rzg2l_wifi-vendor-recovery-files.tar.gz
```

在已有的 `renesas-sd` 厂商工具中覆盖下面目录：

```sh
G2L=/path/to/renesas-sd/rootfs/home/root/g2l_images
tar -xzf openwrt-renesas-armv8-myir_mys_rzg2l_wifi-vendor-recovery-files.tar.gz \
  -C "$G2L"
```

文件包会写入：

```text
Image
mys-rzg2l-wifi.dtb
mys-rzg2l-sdcard.dtb
myir-image-full-myir-remi-1g.ext4
```

它不会提供厂商专有的 BL2/FIP、`Manifest` 或更新脚本。原目录中的 `DDR_1G/`、`Manifest` 与其他厂商文件必须保留。

### 9.2 修正厂商镜像工具的两个兼容问题

FAT 不支持 Unix owner/group。创建镜像时复制 FAT 文件应使用：

```sh
sudo cp -R "$FAT_FILES"/. "$MOUNT_DIR"/
```

不要使用会尝试保留所有权的 `cp -a`，否则会出现“无法保留所有权: 不允许的操作”。

新版本 e2fsprogs 默认创建的 `orphan_file` 特性会被恢复环境中的 e2fsck 1.45.7 显示为 `FEATURE_C12`。厂商 `create_image.sh` 创建恢复卡 ext4 时应禁用它：

```sh
sudo "mkfs.${EXT_TYPE}" -O '^orphan_file' \
  -L "$EXT_LABEL" "$LOOP_DEVICE"
```

厂商刷写脚本还常把 e2fsck 返回 `1` 当成失败。e2fsck 的 `1` 表示“已修复文件系统”，不是不可恢复错误。离线检查可写成：

```sh
e2fsck -f -y "$ROOTFS"
rc=$?
[ "$rc" -le 1 ] || exit "$rc"

e2fsck -f -y "$ROOTFS" || exit $?
```

板端 `flash_renesas.sh` 也要接受 `0` 和 `1`，随后再次检查并要求返回 `0`，再调用 `resize2fs`。不要忽略 `2` 及以上返回码。

### 9.3 生成和刷写恢复 SD 卡

在厂商工具中运行：

```sh
cd /path/to/renesas-sd/rzg2_bsp_scripts/image_creator
./create_image.sh myir_config.ini
```

按 `myir_config.ini` 的输出路径找到生成镜像，再按厂商说明写入 SD 卡。写卡前必须用 `lsblk` 再次确认目标设备；选错 `/dev/sdX` 会覆盖电脑磁盘。

启动更新卡时可观察串口：

```sh
screen /dev/ttyUSB0 115200
```

更新完成并关机后移除 SD 卡，再从 eMMC 启动。进入 OpenWrt 后先确认：

```sh
grep MYIR_IMAGE_BOARD /lib/upgrade/platform.sh
command -v e2fsck resize2fs jsonfilter fwtool gzip tar
grep -o 'root=[^ ]*' /proc/cmdline
```

预期根设备是：

```text
root=/dev/mmcblk0p2
```

完成这一次迁移后，后续不再需要重新生成厂商 SD 卡，直接使用第 10 节的 sysupgrade。

## 10. 以后使用 sysupgrade

### 10.1 备份配置

在板上生成备份：

```sh
sysupgrade -b /tmp/myir-config.tar.gz
```

下载到电脑：

```sh
scp root@192.168.3.1:/tmp/myir-config.tar.gz .
```

跨越较大版本或网络结构变化时，建议不要保留旧配置，升级后手工恢复必要部分。

### 10.2 上传到 `/tmp`

只使用文件名以 `-ext4-sysupgrade.tar.gz` 结尾的归档：

```sh
scp openwrt-renesas-armv8-myir_mys_rzg2l_wifi-ext4-sysupgrade.tar.gz \
  root@192.168.3.1:/tmp/myir-sysupgrade.tar.gz
```

不要先放到 `/root` 再执行。`sysupgrade` 会把不在 `/tmp` 的镜像复制一份，额外占用 rootfs 和 tmpfs，并显示：

```text
Image not in /tmp, copying...
```

上传前可检查空间：

```sh
df -h /tmp /
ls -lh /tmp/myir-sysupgrade.tar.gz
```

### 10.3 只校验，不刷写

```sh
sysupgrade -T -v /tmp/myir-sysupgrade.tar.gz
echo "rc=$?"
```

只有 `rc=0` 才继续。不要用 `-F`。

本分支的校验器只读取归档前 64 MiB 来检查成员和 magic，再在真正刷写前流式验证完整载荷。旧版本平台脚本曾重复解压扫描 512 MiB rootfs，校验约 108 秒，超过 LuCI 单次 RPC 的约 20 秒等待时间，因此网页会一直停在“正在检查固件文件”。这不是浏览器上传失败，也不是 400 MiB 存储显示错误。

如果 CLI `sysupgrade -T` 能返回 `0`，但旧 LuCI 一直转圈，说明当前运行固件仍是旧校验器。可在串口中使用 CLI 完成这一次升级；进入本分支的新固件后，后续 LuCI 校验即可正常结束。

### 10.4 执行升级

保留兼容配置：

```sh
sysupgrade -v /tmp/myir-sysupgrade.tar.gz
```

不保留配置：

```sh
sysupgrade -n -v /tmp/myir-sysupgrade.tar.gz
```

也可以打开：

```text
系统 -> 备份/升级 -> 刷写新的固件
```

上传同一个 `sysupgrade.tar.gz`。不要上传 `sdcard.img.gz` 或 vendor recovery 文件包。

升级会依次：

1. 核对板型、根设备、eMMC、分区格式和空间。
2. 校验归档结构、内核、DTB、ext4 magic 和完整载荷。
3. 写 `/dev/mmcblk0p2`，执行 `e2fsck`。
4. 把 ext4 扩展到第 2 分区可用容量，再次检查。
5. 原子替换 FAT 分区中的 DTB 和 `Image`。
6. 保存配置并重启。

过程中不要断电、拔存储设备或关闭串口。网络断开是重启的正常现象。

### 10.5 升级后检查

```sh
ubus call system board
grep -o 'root=[^ ]*' /proc/cmdline
df -h /
mount | grep mmcblk0
uname -a
logread | tail -100
dmesg | grep -iE 'mmc|ext4|error|failed'
```

## 11. 自动发布到 GitHub Releases

工作流只为 `myir-v*` tag 创建 Release，避免与上游 OpenWrt 的普通 `v*` tag 混淆。

### 11.1 固定 Release profile

默认 Release 使用 `minimal`。需要发布 `proxy-zh` 时，在自己的 fork 设置：

```sh
gh variable set MYIR_RELEASE_PROFILE \
  --repo "$FORK" --body proxy-zh
```

一个 tag 只对应一个 profile。不要在同一个 Release 下用另一个 profile 覆盖同名镜像，否则使用者无法判断文件对应的配置。

### 11.2 创建并推送 tag

确保 tag 指向已经审查的 `codex/myir-sysupgrade` commit：

```sh
git switch codex/myir-sysupgrade
git pull --ff-only origin codex/myir-sysupgrade
git status --short

TAG=myir-v2026.07.16-1
git tag -a "$TAG" -m 'MYiR MYS-RZG2L OpenWrt 6.12 release'
git push origin "$TAG"
```

只推送这一个 tag，不要使用 `git push --tags` 把无关标签全部发布。

tag push 会重新完整编译并校验，然后由 `softprops/action-gh-release` 创建 Release，自动生成更新说明并上传所有预期文件。查看状态：

```sh
gh run list \
  --repo "$FORK" \
  --workflow myir-rzg2l-build.yml \
  --limit 3

gh release view "$TAG" --repo "$FORK"
```

如果构建成功但发布步骤返回 `403`，到仓库：

```text
Settings -> Actions -> General -> Workflow permissions
```

确认允许 GitHub Actions 使用可写的 `GITHUB_TOKEN`。工作流本身已声明 `contents: write`。

### 11.3 手工发布已有的已验证 Artifact

只有在不想为旧的已验证 commit 重新编译时才使用手工方式：

```sh
gh release create "$TAG" ./artifacts/myir-rzg2l-*/* \
  --repo "$FORK" \
  --target '<已验证 OpenWrt commit>' \
  --title "MYiR RZ/G2L $TAG" \
  --generate-notes
```

发布前必须核对 `sha256sums`、Actions 结论、OpenWrt commit、外部内核 commit 和 profile。不要把本地来源不明的文件混进 Release。

## 12. 常见问题

### LuCI 一直显示“正在检查固件文件”

先把文件放到 `/tmp`，运行：

```sh
sysupgrade -T -v /tmp/myir-sysupgrade.tar.gz
echo $?
```

新平台脚本应很快完成。旧脚本会完整重复扫描 rootfs，可能超过 LuCI RPC 超时。用 CLI 完成一次升级后即可换到优化版本。

### `Image not in /tmp, copying...`

这是正常提示，说明镜像位于 `/root` 或其他位置。终止测试后把文件直接上传到 `/tmp`，避免重复占空间。

### `unsupported feature(s): FEATURE_C12`

恢复环境的 e2fsck 1.45.7 不认识新主机创建的 `orphan_file`。创建厂商恢复卡 ext4 时使用：

```sh
mkfs.ext4 -O '^orphan_file' ...
```

不要用旧 e2fsck 强行处理包含它的文件系统。

### `FILE SYSTEM WAS MODIFIED` 后厂商脚本报失败

e2fsck 返回 `1` 表示已修复。厂商脚本必须接受 `0` 和 `1`，再运行第二次检查确认返回 `0`。`2` 及以上仍应中止。

### `The image is not a MYIR MYS-RZG2L sysupgrade archive`

检查是否下载了本项目 `codex/myir-sysupgrade` 分支生成的 `*-ext4-sysupgrade.tar.gz`，文件是否完整，以及当前板型是否为 `myir,mys-rzg2l-wifi`。不要改名冒充，也不要强制刷写。

### `/tmp` 空间不足

检查：

```sh
df -h /tmp
du -ah /tmp | sort -h | tail
```

删除旧上传文件和不需要的临时文件。不要把同一个固件同时留在 `/root` 与 `/tmp`。

### 驱动包在 manifest 中，但板上没有 `.ko`

它可能已经内建，也可能 `FILES` 路径错误。检查：

```sh
grep -i '<driver>' "/lib/modules/$(uname -r)/modules.builtin"
find "/lib/modules/$(uname -r)" -iname '*driver*'
dmesg | grep -i '<driver>'
```

不要把包名存在当成模块文件存在的证明。

### 修改外部内核后 Actions 没变化

OpenWrt 仓库的 push 不会自动感知另一个仓库的新 commit。更新 `MYIR_KERNEL_REF` 后手动运行工作流，或提交一个 OpenWrt 侧的引用变更。Release 必须记录两边的 commit。

## 13. 发布前检查清单

- [ ] OpenWrt 基于 `codex/myir-sysupgrade`
- [ ] 外部内核使用已知 tag 或完整 SHA
- [ ] profile 和第三方源码全部固定版本
- [ ] `make defconfig` 后没有意外配置变化
- [ ] Actions 的 Build 与 Validate 步骤成功
- [ ] manifest 包含预期软件包、驱动和 firmware
- [ ] DTB 反编译后包含预期硬件节点
- [ ] `sha256sums` 与下载文件一致
- [ ] 在真实板上执行 `sysupgrade -T` 返回 `0`
- [ ] 串口观察真实升级和重启成功
- [ ] LAN、WAN、WiFi、存储和新增外设完成回归测试
- [ ] Release 标题或说明写明 profile、OpenWrt SHA 和内核 ref

## 14. 关键维护文件

OpenWrt 侧：

```text
.github/workflows/myir-rzg2l-build.yml
configs/myir-rzg2l/feeds/
configs/myir-rzg2l/profiles/
scripts/prepare-myir-config.sh
target/linux/renesas/config-6.12
target/linux/renesas/image/Makefile
target/linux/renesas/image/armv8.mk
target/linux/renesas/myir-mys-rzg2l-wifi-minimal.config
target/linux/renesas/armv8/base-files/etc/board.d/
target/linux/renesas/armv8/base-files/lib/upgrade/platform.sh
```

外部内核侧：

```text
arch/arm64/boot/dts/renesas/Makefile
arch/arm64/boot/dts/renesas/mys-rzg2l-smarc-base.dtsi
arch/arm64/boot/dts/renesas/mys-rzg2l-wifi.dts
arch/arm64/boot/dts/renesas/mys-rzg2l-sdcard.dts
```

不要提交 `build_dir/`、`staging_dir/`、`bin/`、`tmp/` 或包含本机绝对路径的顶层 `.config`。Release 保留 buildinfo、manifest 和哈希即可复核构建来源。

本项目是社区板级适配，不是 MYiR、Renesas 或 OpenWrt 的官方发布。刷写前保留可用的厂商恢复 SD 卡和串口访问；涉及 BL2/FIP、分区表或供电不稳定的操作都可能让设备暂时无法启动。
