# openwrt-builder

用 GitHub Actions **双上游**编译固件：

| 配置文件 | 机型 | 上游 | target / device |
|---|---|---|---|
| `configs/x86_64.config` | x86_64 软路由 / 虚拟机 | [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) `master` | `x86/64` / `generic` |
| `configs/athena.config` | 京东云 RE-SS-01（雅典娜系列 IPQ60xx） | [LibWrt](https://github.com/LiBwrt/LibWrt) `25.12-nss`（满血 NSS） | `qualcommax/ipq60xx` / `jdcloud_re-ss-01` |

两个机型并行编译，各自拉不同源码树；单个失败不影响另一个。

## 为什么雅典娜用 LibWrt？

原版 ImmortalWrt 主线对 IPQ60xx **没有满血 NSS**。LibWrt（`25.12-nss`）在 ImmortalWrt 插件生态基础上合入了 IPQ60/807x 的 NSS 网络卸载（NAT、PPPoE、桥接、Wi‑Fi offload 等）。选中 `ipq60xx` 后，NSS 相关包由上游 `target.mk` 的 `DEFAULT_PACKAGES` 自动带入。

> LibWrt 同树还有 `jdcloud_re-cs-02`（IPQ6010 + QCN9074）。刷机前请确认外壳/后台型号是 **RE-SS-01** 还是 **RE-CS-02**，不要刷错。

## 手动触发编译

1. 打开仓库 **Actions** → 左侧 **Build OpenWrt**
2. 点 **Run workflow**
3. **第一次请勾选 force（上游没更新也强制编译）**

流程：`check`（对比 ImmortalWrt + LibWrt 两个上游短 SHA 与最近 Release）→ `build`（x86 / athena 并行）→ `release`。

当前 **仅启用 `workflow_dispatch`**；每天定时检查在 workflow 里默认注释掉，需要时自行打开。

首次编译约 2–3 小时；之后有 `dl/` 和 ccache 缓存会快一些。

## 产物在哪

- **Releases**：tag 为 `build-<immortal短SHA>-<libwrt短SHA>`，两个机型都成功才会发 Release
- 每次运行的 **Artifacts**（`x86_64` / `athena`），只成功一台也能下

常用文件：

- x86_64：`*-generic-squashfs-combined-efi.img.gz` 等
- 雅典娜（LibWrt eMMC）：`*-jdcloud_re-ss-01-*-sysupgrade.bin` / `*-factory.bin`
- `sha256sums-*`、`*.manifest`

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

## ⚠️ 雅典娜首次刷机提醒

原厂系统 **不要** 直接刷本仓库产物。请先按京东云雅典娜 / RE-SS-01 刷机教程完成 U-Boot 或过渡固件，再用 `sysupgrade` / LuCI 升级。

已刷 OpenWrt / ImmortalWrt / LibWrt 的机器可用对应 `sysupgrade.bin` 升级。升级后检查 ksmbd 共享与 SMB 密码（`ksmbd.adduser -a root`）。
