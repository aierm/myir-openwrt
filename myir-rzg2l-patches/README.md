# MYiR RZG2L Patch Set

这组 patch 是从当前工作区按功能拆分导出的，目标是方便以后在干净源码树里按需恢复。

这个目录默认只建议提交整理好的 `*.patch`、说明文档和最小配置；其余复制出来的源码快照或构建残留会由目录内的 `.gitignore` 留在本地，避免误传到 GitHub。

## 基线

- OpenWrt tree: `<workspace>/openwrt`
- OpenWrt commit: `a4a6a06c9f`
- Kernel tree: `<workspace>/rz_linux-cip`
- Kernel commit: `03d16609f9f9`

## patch 列表

### 必需

1. `openwrt-myir-rzg2l-target.patch`
   - 新增整个 `target/linux/renesas/`
   - 包含 target 定义、镜像规则、`config-6.12`、最小板级配置、board.d、target patch

2. `openwrt-myir-rzg2l-build-fixes.patch`
   - OpenWrt 侧构建兼容修复
   - 包含 `include/kernel-defaults.mk`
   - 包含 `video.mk`、mac80211/backports、netifd、ubus 相关补丁

3. `kernel-myir-rzg2l-dts.patch`
   - 内核 DTS 适配
   - 包含 `mys-rzg2l-smarc-base.dtsi`
   - 包含 `mys-rzg2l-wifi.dts`
   - 包含 `mys-rzg2l-sdcard.dts`
   - 包含 `arch/arm64/boot/dts/renesas/Makefile` 更新

4. `kernel-myir-rzg2l-build-fixes.patch`
   - 外部内核树中的非 DTS 修复
   - 包含 display/headless、wireless/backports、IRQC、I3C 头文件相关改动

### 可选

5. `openwrt-custom-feeds.patch`
   - 自定义 feeds
   - 当前只包含 `feeds.conf.default` 的 `kenzo` / `small` feed 变更

6. `openwrt-local-qol.patch`
   - 本地便利性修复
   - 当前只包含 `rules.mk`
   - 作用是让 `sha256sums` 处理带空格文件名时更稳

## 建议应用顺序

如果以后在干净树里恢复，建议顺序如下：

1. 应用 `openwrt-myir-rzg2l-target.patch`
2. 应用 `openwrt-myir-rzg2l-build-fixes.patch`
3. 应用 `kernel-myir-rzg2l-dts.patch`
4. 应用 `kernel-myir-rzg2l-build-fixes.patch`
5. 按需应用 `openwrt-custom-feeds.patch`
6. 按需应用 `openwrt-local-qol.patch`

## 本次未纳入的内容

以下内容没有放进这组 patch：

- `target/linux/armsr/image/Makefile`
  - 这是早期尝试/参考改动，不是当前 `renesas` target 的核心组成

- `toolchain/info.mk`
  - 这是构建后生成的本地工具链信息，不适合作为长期 patch 保存

- 构建产物和临时文件
  - `.dtb`
  - `.cmd`
  - `.tmp`
  - `user_headers/`
  - `.vscode/`

如果后面你想把“工作区所有脏改动”也完整打成一个大快照 patch，我可以再额外导出一份 `workspace-snapshot.patch`。
