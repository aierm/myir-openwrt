# MYiR MYS-RZG2L OpenWrt 6.12

[![Build MYiR RZ/G2L Firmware](https://github.com/aierm/myir-openwrt/actions/workflows/myir-rzg2l-build.yml/badge.svg?branch=codex%2Fmyir-sysupgrade)](https://github.com/aierm/myir-openwrt/actions/workflows/myir-rzg2l-build.yml)
[![Releases](https://img.shields.io/github/v/release/aierm/myir-openwrt?display_name=tag)](https://github.com/aierm/myir-openwrt/releases)

这是面向 MYiR MYS-RZG2L WiFi 开发板的 OpenWrt 6.12 适配项目。项目使用 Renesas CIP 外部内核，支持板载 RTL8822CS、eMMC 启动、完整 SD/eMMC 磁盘镜像，以及针对厂商分区布局实现的安全 sysupgrade。

> 当前应使用 **`codex/myir-sysupgrade`** 分支。仓库的旧 `master` 基线不包含本项目的 sysupgrade 实现，不要用旧分支生成在线升级包。

完整的源码编译、软件包、驱动、DTS、首次刷机、sysupgrade 和 GitHub Releases 教程见：

**[MYiR MYS-RZG2L OpenWrt 6.12 完整使用与定制指南](README-MyIR-RZG2L-OpenWrt-6.12.md)**

已在真实开发板完成升级的首个发布：[myir-v2026.07.16-1（proxy-zh）](https://github.com/aierm/myir-openwrt/releases/tag/myir-v2026.07.16-1)

## 已验证功能

- MYiR MYS-RZG2L WiFi 开发板从 eMMC 启动
- Linux 6.12 Renesas CIP 外部内核
- `eth0` LAN，默认地址 `192.168.3.1`
- `eth1` PPPoE WAN
- 板载 RTL8822CS SDIO WiFi 和 AP 模式
- FAT 启动分区中的 `Image` 与 `mys-rzg2l-wifi.dtb`
- ext4 rootfs 自动检查并扩展到 eMMC 分区容量
- LuCI 和命令行 sysupgrade
- GitHub Actions 构建、校验、Artifacts 和 Releases

首次启动的 LuCI 地址为 `http://192.168.3.1/`。OpenWrt 初始状态通常没有 root 密码，请登录后立即设置密码。

## 选择正确的文件

| 文件 | 用途 |
| --- | --- |
| `*-ext4-sysupgrade.tar.gz` | 已经运行本分支固件的开发板，在 LuCI 或 `sysupgrade` 命令中升级 |
| `*-ext4-sdcard.img.gz` | 完整 MBR + FAT + ext4 磁盘镜像，用于块设备写入和开发测试 |
| `*-vendor-recovery-files.tar.gz` | 首次迁移时覆盖到厂商 SD 更新工具中的内核、DTB 和 rootfs 文件 |
| `*-device-tree.dtb` | 独立导出的设备树 |
| `*.manifest`、`*.buildinfo`、`sha256sums` | 核对包版本、源码配置和文件完整性 |

`sdcard.img.gz` 不是厂商恢复卡镜像：它不包含厂商更新脚本、`boot.scr` 或板载 eMMC 所需的原始 BL2/FIP。第一次从厂商系统或不支持 sysupgrade 的旧 OpenWrt 迁移时，仍需使用厂商 SD 更新流程；成功迁移一次后，后续只使用 `sysupgrade.tar.gz`。

## 快速构建

OpenWrt 和外部内核必须放在同一级目录：

```sh
mkdir -p ~/myir-rzg2l
cd ~/myir-rzg2l
git clone --branch codex/myir-sysupgrade --single-branch \
  https://github.com/aierm/myir-openwrt.git openwrt
git clone --branch rz-6.12-cip7 --single-branch \
  https://github.com/aierm/myir-rz-linux-cip.git rz_linux-cip

cd openwrt
./scripts/feeds update -a
./scripts/feeds install -a
./scripts/prepare-myir-config.sh minimal
make defconfig
make download -j"$(nproc)"
make -j"$(nproc)" || make -j1 V=s
```

输出位于：

```text
bin/targets/renesas/armv8/
```

也可以在仓库的 **Actions -> Build MYiR RZ/G2L Firmware -> Run workflow** 中选择 `minimal` 或 `proxy-zh`，不需要本地准备编译环境。

## 安全提示

- sysupgrade 前先运行 `sysupgrade -T -v <文件>`，返回码必须为 `0`。
- 不要把 `sdcard.img.gz` 上传到 LuCI，也不要使用 `sysupgrade -F` 强制绕过板型检查。
- 在线升级不会修改 MBR、分区表、BL2 或 FIP，只更新 eMMC 第 2 分区 rootfs 和第 1 分区中的内核、DTB。
- 第三方内核模块必须和当前内核在同一次构建中生成，不能混用其他固件的 `.ko` 或 kmod 包。

本项目是 OpenWrt 的板级适配分支，不是 OpenWrt 官方发布。上游项目与通用文档请访问 [openwrt/openwrt](https://github.com/openwrt/openwrt) 和 [OpenWrt Documentation](https://openwrt.org/docs/start)。
