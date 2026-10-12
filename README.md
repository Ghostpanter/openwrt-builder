# openwrt-builder

用 GitHub Actions 编译 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)（`master` 分支）固件，编译对象：

| 配置文件 | 机型 | target / subtarget / device |
|---|---|---|
| `configs/x86_64.config` | x86_64 软路由 / 虚拟机 | `x86/64` / `generic` |
| `configs/athena.config` | 京东云雅典娜 AX6600（RE-SS-01） | `qualcommax/ipq60xx` / `jdcloud_re-ss-01` |

两个机型并行编译，单个失败不影响另一个。

## 手动触发编译

1. 打开仓库的 **Actions** 页面 → 左侧选 **Build OpenWrt**
2. 右侧点 **Run workflow**
3. **第一次运行请勾选「上游没更新也强制编译」（force）**，然后点绿色的 Run workflow

流程：`check`（对比上游最新提交与最近一次 Release）→ `build`（x86_64、athena 两个并行）→ `release`（发布到 Release）。
上游没有新提交且没勾 force 时，`check` 之后会直接跳过编译。

首次编译约 2–3 小时；之后有 `dl/` 和 ccache 缓存会快一些。

## 产物在哪

- **Releases** 页面：tag 为 `build-<上游提交前 12 位>`，两个机型都编译成功才会发布
- 每次运行的 **Artifacts**（运行详情页底部，名为 `x86_64` / `athena`），即使只有一个机型成功也能下载

常用文件：

- x86_64：`*-generic-squashfs-combined-efi.img.gz`（写盘/虚拟机）等 `*.img.gz`
- 雅典娜：`*-jdcloud_re-ss-01-squashfs-sysupgrade.bin`（已刷 ImmortalWrt/OpenWrt 的机器用于升级）
- `sha256sums-*` 校验文件、`*.manifest` 包列表

## 加插件 / 改配置

`configs/*.config` 是 diffconfig 格式，只写需要的选项，`make defconfig` 会自动补全依赖。

- 加插件：在对应文件里加一行 `CONFIG_PACKAGE_包名=y`，例如 `CONFIG_PACKAGE_luci-app-ttyd=y`；中文包一般是 `luci-i18n-<名字>-zh-cn`
- 最省事的方法：本地拉 ImmortalWrt 源码，`make menuconfig` 选好后执行 `./scripts/diffconfig.sh > my.config`，把内容贴到对应 config 文件
- 想往固件里预置文件（如 `etc/config/network`），在仓库根目录建 `files/` 目录，按固件内路径放文件，编译时会自动复制进去
- 换上游分支：改 `.github/workflows/build.yml` 里的 `REPO_BRANCH`

## 开启每天自动检查

编辑 `.github/workflows/build.yml`，把开头这两行取消注释：

```yaml
  schedule:
    - cron: "0 19 * * *"
```

`0 19 * * *` 是 UTC 19:00，即香港时间每天凌晨 3:00。上游有新提交才会编译。

## ⚠️ 雅典娜首次刷机提醒

本仓库产出的雅典娜固件是 `sysupgrade.bin`，**只适用于已经刷过 ImmortalWrt / OpenWrt 的设备**。
原厂系统需要先按雅典娜刷机教程刷入 U-Boot（或对应的过渡固件），再用本固件升级，直接从原厂刷会失败甚至变砖。

升级后记得检查 ksmbd 共享目录和 SMB 密码（`ksmbd.adduser -a root`）是否还在。
