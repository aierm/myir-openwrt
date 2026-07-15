# MYiR MYS-RZG2L OpenWrt 6.12 适配记录

## 1. 目标与现状

本文记录 `MYiR MYS-RZG2L` 开发板从厂商内核/官方 Renesas 内核迁移到 `OpenWrt + 6.12 rz_linux-cip` 的实际适配过程，目标是让下次升级时可以快速复现，而不是重新从零摸索。

当前已验证通过的能力：

- OpenWrt 6.12 正常启动
- eMMC 启动正常
- 以 `CONFIG_EXTERNAL_KERNEL_TREE` 方式对接外部 `rz_linux-cip`
- `eth0/eth1` 正常识别
- PPPoE WAN 正常
- 板载 `RTL8822CS` SDIO WiFi 可工作
- AP 热点可正常拉起
- IPv4/IPv6 可用
- 可生成板级 `device-tree.dtb`
- 可生成 `sdcard.img.gz` 镜像

## 2. 当前源码基线

本次整理对应的源码基线：

- OpenWrt 树：`<workspace>/openwrt`
- OpenWrt commit：`a4a6a06c9f`
- 外部内核树：`<workspace>/rz_linux-cip`
- 内核树 commit：`03d16609f9f9`

当前最小板级配置中，外部内核树是通过下面的方式接入的：

```config
CONFIG_EXTERNAL_KERNEL_TREE="$(CURDIR)/../rz_linux-cip"
```

这里使用的是基于 OpenWrt 顶层目录展开的相对定位写法。默认假设 `openwrt/` 和 `rz_linux-cip/` 是同级目录；如果以后目录结构变化，再按实际位置调整它。

## 3. 两棵树的职责划分

这次移植不是只改 OpenWrt，也不是只改内核，而是两棵树分工：

### 3.1 OpenWrt 树负责

- 新增 `renesas` target
- 新增 `myir_mys_rzg2l_wifi` 设备定义
- 管理镜像生成规则
- 管理板级默认网络映射
- 管理要打进 rootfs 的 `kmod` 和用户态包
- 管理 `config-6.12`

### 3.2 外部内核树负责

- DTS / DTSI 迁移
- 板级外设使能
- SDIO WiFi 节点
- 以 `dtbs` 形式输出最终设备树

## 4. 必须长期保留的核心文件

这一节最重要。下次升级、换树、换机器时，优先保这些文件。

### 4.1 OpenWrt 侧必须保留

```text
target/linux/renesas/Makefile
target/linux/renesas/armv8/target.mk
target/linux/renesas/image/Makefile
target/linux/renesas/image/armv8.mk
target/linux/renesas/config-6.12
target/linux/renesas/myir-mys-rzg2l-wifi-minimal.config
target/linux/renesas/patches-6.12/net-permit-ieee80211_ptr-even-with-no-CFG82111-suppo.patch
target/linux/renesas/armv8/base-files/etc/board.d/01_leds
target/linux/renesas/armv8/base-files/etc/board.d/02_network
target/linux/renesas/armv8/base-files/etc/board.d/05_compat-version
```

其中最关键的是：

- `target/linux/renesas/image/armv8.mk`
  这里定义了设备 `myir_mys_rzg2l_wifi`、对应 DTS、输出镜像类型、默认打包的驱动和工具。
- `target/linux/renesas/myir-mys-rzg2l-wifi-minimal.config`
  这是下次最有价值的“最小可复现配置”。
- `target/linux/renesas/config-6.12`
  这是内核目标配置，已经整理过，适合长期维护。
- `target/linux/renesas/armv8/base-files/etc/board.d/02_network`
  这里决定了网口角色，当前是：

```sh
ucidef_set_interfaces_lan_wan "eth1" "eth0"
```

也就是：

- `eth1` 作为 `lan`
- `eth0` 作为 `wan`

### 4.2 内核侧必须保留

```text
arch/arm64/boot/dts/renesas/Makefile
arch/arm64/boot/dts/renesas/mys-rzg2l-smarc-base.dtsi
arch/arm64/boot/dts/renesas/mys-rzg2l-wifi.dts
arch/arm64/boot/dts/renesas/mys-rzg2l-sdcard.dts
```

其中：

- `mys-rzg2l-smarc-base.dtsi` 是板级公共底座
- `mys-rzg2l-wifi.dts` 是 WiFi 变体
- `mys-rzg2l-sdcard.dts` 是 SD 卡启动/镜像适配变体
- `Makefile` 负责把这些 DTS 编进 `dtbs`

### 4.3 建议另外保留的运行期配置

这些不一定要写死进固件，但最好备份一份，方便下次快速恢复现场：

```text
/etc/config/network
/etc/config/wireless
/etc/config/firewall
/etc/config/dhcp
```

如果下次只想快速恢复“能上网、能开 AP、能发 IPv6”的运行状态，这几份运行期配置很有价值。

## 5. 哪些文件不是核心资料

以下内容不要当作长期维护依据：

```text
.config
build_dir/
staging_dir/
bin/
tmp/
.vscode/
```

说明：

- 顶层 `.config` 可以留一份快照，但不要把它当唯一真相
- 真正应该长期维护的是 `myir-mys-rzg2l-wifi-minimal.config + config-6.12 + DTS`
- `bin/`、`build_dir/` 只是构建产物，能重建

## 6. 为什么 `config-6.12` 里找不到 rtw88 / mac80211 / cfg80211

这是这次很容易误判的点，建议明确写进教程。

本项目里：

- `MMC / RAVB / Renesas SoC` 这类基础能力由内核 `config-6.12` 提供
- `cfg80211 / mac80211 / rtw88 / rt2800-usb` 这类无线模块，主要通过 OpenWrt 的 `kmod` 包和 backports 体系来构建

所以：

- 在 `target/linux/renesas/config-6.12` 里看不到 `CONFIG_RTW88=y` 是正常现象
- 真正决定是否编译进固件的是 `myir-mys-rzg2l-wifi-minimal.config` 里选的包，例如：

```config
CONFIG_PACKAGE_kmod-cfg80211=y
CONFIG_PACKAGE_kmod-mac80211=y
CONFIG_PACKAGE_kmod-rtw88=y
CONFIG_PACKAGE_kmod-rtw88-sdio=y
CONFIG_PACKAGE_kmod-rtw88-8822c=y
CONFIG_PACKAGE_kmod-rtw88-8822cs=y
CONFIG_PACKAGE_rtl8822ce-firmware=y
CONFIG_PACKAGE_kmod-rt2800-usb=y
```

## 7. 以后升级时的推荐流程

建议以后都按下面的顺序做，不要直接上来改 `.config`。

### 7.1 准备两棵树

```sh
cd <workspace>/openwrt
git status

cd <workspace>/rz_linux-cip
git status
```

先确认你是基于哪个 commit 开始改的，避免把旧实验残留也带进去。

### 7.2 先迁移 DTS

优先保证下面几件事：

- eMMC/SD 启动链路正常
- 串口正常
- `eth0/eth1` 正常
- `sdhi1` 上的 `RTL8822CS` 节点正常
- USB 正常

这一步主要维护内核树中的：

```text
arch/arm64/boot/dts/renesas/mys-rzg2l-smarc-base.dtsi
arch/arm64/boot/dts/renesas/mys-rzg2l-wifi.dts
arch/arm64/boot/dts/renesas/mys-rzg2l-sdcard.dts
```

### 7.3 再接 OpenWrt target

重点维护：

```text
target/linux/renesas/Makefile
target/linux/renesas/armv8/target.mk
target/linux/renesas/image/Makefile
target/linux/renesas/image/armv8.mk
```

其中 `armv8.mk` 里定义的设备名是：

```make
define Device/myir_mys_rzg2l_wifi
```

对应 DTS：

```make
DEVICE_DTS := renesas/mys-rzg2l-wifi
SUPPORTED_DEVICES := myir,mys-rzg2l-wifi
```

### 7.4 恢复最小配置

建议不要手工重新点大量菜单，直接导入板级最小配置：

```sh
cd <workspace>/openwrt
cp target/linux/renesas/myir-mys-rzg2l-wifi-minimal.config .config
make defconfig
```

如果以后又新增了包，想把新的完整 `.config` 再反整理成最小配置，可以这样做：

```sh
./scripts/diffconfig.sh > target/linux/renesas/myir-mys-rzg2l-wifi-minimal.config
```

### 7.5 编译

```sh
cd <workspace>/openwrt
make -j12 V=s
```

如果要定位首个坏包：

```sh
make -j1 V=s
```

## 8. 关键产物

当前设备定义期望输出：

- `sdcard.img.gz`
- `sysupgrade.tar.gz`
- `device-tree.dtb`

按当前设备名，产物路径应为：

```text
bin/targets/renesas/armv8/openwrt-renesas-armv8-myir_mys_rzg2l_wifi-ext4-sdcard.img.gz
bin/targets/renesas/armv8/openwrt-renesas-armv8-myir_mys_rzg2l_wifi-ext4-sysupgrade.tar.gz
bin/targets/renesas/armv8/openwrt-renesas-armv8-myir_mys_rzg2l_wifi-device-tree.dtb
```

### 8.1 在线升级

只有文件名包含 `sysupgrade` 的压缩 tar 包可以上传到 LuCI 的固件升级页面：

```text
openwrt-renesas-armv8-myir_mys_rzg2l_wifi-ext4-sysupgrade.tar.gz
```

不要把 `sdcard.img.gz` 上传给 `sysupgrade`。它是完整磁盘镜像，不是在线升级包。
当前厂商 U-Boot 从 SD 启动时还要求 SD 分区中存在 `boot.scr`；这里的
`sdcard.img.gz` 不包含厂商恢复脚本，不能替代原来的恢复 SD 卡。

MYIR eMMC 的运行布局是：

```text
eMMC boot0  BL2 + FIP/U-Boot
eMMC p1     FAT32，保存 Image 和 mys-rzg2l-wifi.dtb
eMMC p2     ext4 rootfs
```

板级在线升级只更新 p1 中的内核/DTB 和 p2 中的 rootfs，不覆盖 MBR、BL2、FIP 或 U-Boot。升级脚本会先切换到 ramfs，再按 rootfs、DTB、kernel 的顺序写入，并在重启前检查和扩展 ext4。

注意首次迁移：执行升级的是当前固件中的 `/lib/upgrade/platform.sh`，不是升级包内的新脚本。从旧版本首次启用该功能时，必须最后使用一次厂商恢复 SD 卡流程，把包含新升级脚本的固件写入 eMMC。成功启动该版本以后，后续更新即可一直使用 LuCI 或命令行：

```sh
sysupgrade /tmp/openwrt-renesas-armv8-myir_mys_rzg2l_wifi-ext4-sysupgrade.tar.gz
```

日常升级不会更新 boot0。需要更换 BL2、FIP 或 U-Boot 时，仍应使用恢复 SD 卡。

如果手工解压镜像，还会看到：

```text
bin/targets/renesas/armv8/openwrt-renesas-armv8-myir_mys_rzg2l_wifi-ext4-sdcard.img
```

## 9. 怎么查看“我相对于官方源码到底改了什么”

这是最应该养成习惯的部分。

### 9.1 不要直接全仓库 `git diff`

因为两棵树里可能混有无关实验改动，直接全仓库导出会把噪音也带进去。

更稳的做法是按路径导出。

### 9.2 导出 OpenWrt 板级 patch

```sh
git -C <workspace>/openwrt diff --stat -- target/linux/renesas
git -C <workspace>/openwrt diff -- target/linux/renesas \
  > openwrt-renesas-board.patch
```

如果要连同无线/backports 兼容修复一起导出：

```sh
git -C <workspace>/openwrt diff -- \
  target/linux/renesas \
  package/kernel/mac80211/patches/build \
  package/kernel/linux/modules/video.mk \
  > openwrt-myir-rzg2l-full.patch
```

### 9.3 导出内核 DTS patch

```sh
git -C <workspace>/rz_linux-cip diff --stat -- arch/arm64/boot/dts/renesas
git -C <workspace>/rz_linux-cip diff -- arch/arm64/boot/dts/renesas \
  > kernel-mys-rzg2l-dts.patch
```

### 9.4 只看改了哪些文件

```sh
git -C <workspace>/openwrt status --short
git -C <workspace>/rz_linux-cip status --short
```

### 9.5 只看某个文件具体改了什么

```sh
git -C <workspace>/openwrt diff -- target/linux/renesas/image/armv8.mk
git -C <workspace>/rz_linux-cip diff -- arch/arm64/boot/dts/renesas/mys-rzg2l-wifi.dts
```

## 10. 怎么把这次成果长期保存下来

推荐至少做两层留档：

### 10.1 第一层：保存 patch

保存：

- `openwrt-renesas-board.patch`
- `openwrt-myir-rzg2l-full.patch`
- `kernel-mys-rzg2l-dts.patch`

### 10.2 第二层：保存核心源文件原件

可以建一个归档目录：

```sh
mkdir -p ~/myir-rzg2l-port-doc/{openwrt,kernel,patches}
```

然后把这些内容复制进去：

- `target/linux/renesas/`
- `arch/arm64/boot/dts/renesas/mys-rzg2l-*`
- 上面导出的 patch 文件

### 10.3 第三层：保存运行期配置

如果想把“可上网、可开热点、可发 IPv6”的状态也一并留住，建议额外备份：

```sh
cp /etc/config/network ~/myir-rzg2l-port-doc/
cp /etc/config/wireless ~/myir-rzg2l-port-doc/
cp /etc/config/firewall ~/myir-rzg2l-port-doc/
cp /etc/config/dhcp ~/myir-rzg2l-port-doc/
```

或者在板子上直接执行：

```sh
sysupgrade -b /tmp/myir-rzg2l-backup.tar.gz
```

## 11. 上板验证清单

每次升级后至少检查下面这些点：

### 11.1 启动

- 能正常进入 U-Boot
- 能正常加载内核
- 能正常挂载 rootfs

### 11.2 有线网络

- `eth0/eth1` 都能识别
- 对应 PHY 能正常探测
- `lan/wan` 角色符合预期
- PPPoE 可成功拨号

### 11.3 WiFi

- `mmc1:0001:1` 能被识别为 SDIO 设备
- `rtw88_8822cs` 能正常绑定
- `iw phy` 能看到 `phy0`
- AP 能正常拉起并可关联

### 11.4 IPv6

- `wan_6` 正常拿到前缀委派
- `lan/AP` 下发 GUA
- 终端既能解析 AAAA，也能直连 IPv6 站点

## 12. 最后的维护建议

以后如果再升级到新的 Renesas 内核或新的 OpenWrt 基线，优先复用的是下面三类东西：

1. `target/linux/renesas/` 里的板级 target 文件
2. `arch/arm64/boot/dts/renesas/mys-rzg2l-*` 里的 DTS
3. 路径受控导出的 patch

不要优先依赖顶层 `.config`，也不要依赖 `build_dir/` 里的中间产物。  
真正适合长期维护、也最容易跨版本迁移的，就是上面这三类内容。

## 13. GitHub 发布建议

建议把 OpenWrt 和外部 kernel 保持为两个独立仓库，各自保留上游历史：

```sh
cd <workspace>/openwrt
git remote rename origin upstream
git remote add origin git@github.com:<user>/myir-openwrt.git

cd <workspace>/rz_linux-cip
git remote rename origin upstream
git remote add origin git@github.com:<user>/myir-rz-linux-cip.git
```

源码仓库只提交源码、配置、patch 和文档；不要提交 `bin/`、`build_dir/`、`staging_dir/`、`tmp/`、`dl/`、`.config`、签名 key 或镜像压缩包。固件产物建议通过 GitHub Actions artifact 或 GitHub Release 发布。

当前最小配置默认假设目录结构如下：

```text
<workspace>/openwrt
<workspace>/rz_linux-cip
```

如果目录结构不同，需要同步调整：

```config
CONFIG_EXTERNAL_KERNEL_TREE="$(CURDIR)/../rz_linux-cip"
```
