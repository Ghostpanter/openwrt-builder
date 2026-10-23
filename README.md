# openwrt-builder

用 GitHub Actions **双上游**编译三台设备的固件：

| 机型 | 配置文件 | 上游 | target / device id | SoC |
|---|---|---|---|---|
| x86_64 软路由 / 虚拟机 | `configs/x86_64.config` | [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) `master` | `x86/64` / `generic` | x86_64 |
| 京东云 雅典娜 AX6600（RE-CS-02） | `configs/athena.config` | [LibWrt](https://github.com/LiBwrt/LibWrt) `25.12-nss`（满血 NSS） | `qualcommax/ipq60xx` / `jdcloud_re-cs-02` | 高通 IPQ6010（+ QCN9074 5G 射频） |
| 京东云 亚瑟 AX1800 Pro（RE-SS-01） | `configs/arthur.config` | [LibWrt](https://github.com/LiBwrt/LibWrt) `25.12-nss`（满血 NSS） | `qualcommax/ipq60xx` / `jdcloud_re-ss-01` | 高通 IPQ6000 |

三个机型并行编译；单个失败不影响其它机型的 Artifacts，但只有三台都成功才发 Release。

## ⚠️ 雅典娜机型名更正

本仓库**早期版本的 `athena.config` 用的是 `jdcloud_re-ss-01`，那其实是亚瑟（AX1800 Pro）**，不是雅典娜。现已更正：

- 雅典娜 AX6600 → `jdcloud_re-cs-02`
- 亚瑟 AX1800 Pro → `jdcloud_re-ss-01`

依据 LibWrt `target/linux/qualcommax/image/ipq60xx.mk`：`jdcloud_re-ss-01` 为 `SOC := ipq6000`，`jdcloud_re-cs-02` 为 `SOC := ipq6010` 且带 `ath11k-firmware-qcn9074`（雅典娜的三频 5G 射频）。

**如果你之前下载过旧版 “athena” 产物（文件名里是 `re-ss-01`），不要刷到雅典娜上。** 文件名里都带 device id，刷之前核对一遍。

## 为什么雅典娜、亚瑟用 LibWrt？

原版 ImmortalWrt 主线对 IPQ60xx **没有满血 NSS**。LibWrt（`25.12-nss`）在 ImmortalWrt 插件生态基础上合入了 NSS 网络卸载（NAT、PPPoE、桥接、Wi‑Fi offload 等）。选中 `ipq60xx` 后，NSS 相关包（`kmod-qca-nss-drv`、`kmod-qca-nss-ecm`、`nss-firmware-ipq60xx`、`kmod-qca-nss-crypto` 等）由上游 `target/linux/qualcommax/Makefile` 和 `ipq60xx/target.mk` 的 `DEFAULT_PACKAGES` 自动带入。

## 关于 128G eMMC

雅典娜和亚瑟这两台都是 **128G eMMC**。eMMC 容量**不影响**编出来的固件：上游没有区分 64G / 128G 的 device，同一个 `factory.bin` / `sysupgrade.bin` 通用。容量只和 **GPT 分区表**有关：

- **第一次从原厂刷机**：先刷 eMMC 版 U-Boot，再刷**和你机型、容量匹配的 GPT 分区表**（128G 用 128G 的表，或者刷机包里不限容量的 `no-last-partition` 版本），最后在 U-Boot 网页刷 `*-factory.bin`。
- **不要拿 64G 的 GPT 刷 128G 的机器**，否则后半段空间用不上，或分区错位。雅典娜和亚瑟的 GPT 也不能混用。
- 刷完后多出来的空间可以在系统里新建分区，用「挂载点」挂上给 ksmbd 共享。

常用刷机资料：[lgs2007m 京东云亚瑟/雅典娜刷机救砖教程](https://github.com/lgs2007m/Actions-OpenWrt/releases/tag/Router-Flashing-Files)、[chenxin527 eMMC U-Boot](https://github.com/chenxin527/uboot-ipq60xx-emmc-build)。

## 手动触发编译

1. 打开仓库 **Actions** → 左侧 **Build OpenWrt**
2. 点 **Run workflow**
3. **第一次请勾选 force（上游没更新也强制编译）**

流程：`check`（对比 ImmortalWrt + LibWrt 两个上游短 SHA 与最近 Release）→ `build`（x86_64 / athena / arthur 并行）→ `release`。

当前 **仅启用 `workflow_dispatch`**；每天定时检查在 workflow 里默认注释掉，需要时自行打开。

首次编译约 2–3 小时；之后有 `dl/` 和 ccache 缓存会快一些。

## 产物在哪

- **Releases**：tag 为 `build-<immortal短SHA>-<libwrt短SHA>`，三台都成功才发 Release
- 每次运行的 **Artifacts**（`x86_64` / `athena` / `arthur`），只成功一部分也能下

常用文件：

- x86_64：`*-generic-squashfs-combined-efi.img.gz` 等
- 雅典娜：`*-jdcloud_re-cs-02-squashfs-factory.bin`（U-Boot 网页首刷）/ `*-sysupgrade.bin`（已刷 OpenWrt 后升级）
- 亚瑟：`*-jdcloud_re-ss-01-squashfs-factory.bin` / `*-sysupgrade.bin`
- 校验：`sha256sums-x86_64`、`sha256sums-athena`、`sha256sums-arthur`；以及 `*.manifest`

## 加插件 / 改配置

`configs/*.config` 是 diffconfig，只写需要的选项。

- 加包：`CONFIG_PACKAGE_包名=y`
- 本地：对对应上游源码 `make menuconfig` → `./scripts/diffconfig.sh`
- 预置文件：仓库根目录建 `files/`
- 换上游：改 `.github/workflows/build.yml` 里 matrix 的 `repo_url` / `repo_branch`

## 开启每天自动检查

编辑 `.github/workflows/build.yml`，取消注释：

```yaml
  schedule:
    - cron: "0 19 * * *"
```

UTC 19:00 = 香港时间每天凌晨 3:00。任一上游有新提交（tag 变化）才会编译。

## ⚠️ 首次刷机提醒

原厂系统 **不要** 直接刷本仓库产物。顺序是：开 SSH → 备份原厂分区 → 刷 eMMC U-Boot → 刷匹配 128G 的 GPT → U-Boot 网页刷 `factory.bin`。

已刷 OpenWrt / ImmortalWrt / LibWrt 的机器可用对应 `sysupgrade.bin` 升级。升级后检查 ksmbd 共享与 SMB 密码（`ksmbd.adduser -a root`）。
