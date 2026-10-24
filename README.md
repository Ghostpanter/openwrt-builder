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

## x86 首次开机自动分区

x86 固件里带了首次开机脚本 `files/x86_64/etc/uci-defaults/99-auto-data-partition`（只打进 x86 固件）：

- 刷整盘镜像后首次开机，用系统盘剩余空间新建第 3 个分区，格式化为 ext4（卷标 `data`），挂载到 **`/opt/data`**
- 只在空闲空间上新建分区，不动引导分区和根分区；第 3 个分区已存在且是 ext4 时只补挂载配置、不格式化
- 装了 Docker 时，把 Docker 数据目录指到 `/opt/data/docker`
- 日志：`/root/auto-data-partition.log`

注意：sysupgrade 升级一般会保留这个分区；用整盘镜像重新写盘会覆盖它。

## x86_64 插件清单（旁路由全功能版）

面向 Intel 3965U / 16G / 64G 旁路由。除 MosDNS、Tailscale、Lucky、EasyTier 外，全部来自 ImmortalWrt 自带的 `packages` / `luci` feeds；这四个由 `scripts/x86_64-extra-packages.sh` 在编译时拉取（只对 x86_64 生效）。Docker 里的应用（Jellyfin、Home Assistant 等）不集成进固件，刷机后自己在 Docker 里装。

| 分类 | 包名 | 中文名 | 来源 |
|---|---|---|---|
| 系统 | `luci` + `luci-i18n-base-zh-cn` | LuCI 网页界面（简体中文） | ImmortalWrt luci |
| 系统 | `default-settings-chn` | 国内默认设置（上海时区、国内 NTP 和软件源镜像） | ImmortalWrt 主仓库 |
| 系统 | `luci-i18n-firewall-zh-cn` | 防火墙（中文） | ImmortalWrt luci |
| 系统 | `luci-theme-argon` | Argon 主题 | ImmortalWrt luci |
| 系统 | `luci-app-attendedsysupgrade` | 在线升级 | ImmortalWrt luci |
| 系统 | `luci-app-ttyd` | 网页终端 | ImmortalWrt luci |
| 系统 | `htop` `nano` `curl` `wget-ssl` `bash` `openssh-sftp-server` | 常用命令行工具 / SFTP | ImmortalWrt packages |
| 核显 / CPU | `kmod-drm-i915` | Intel 核显驱动（提供 `/dev/dri`） | ImmortalWrt 主仓库 |
| 核显 / CPU | `i915-firmware-dmc` `i915-firmware-guc` `i915-firmware-huc` | 核显固件 | ImmortalWrt 主仓库 |
| 核显 / CPU | `intel-microcode` | Intel CPU 微码 | ImmortalWrt 主仓库 |
| 磁盘 | `luci-app-diskman` | 磁盘管理 | ImmortalWrt luci |
| 磁盘 | `parted` `e2fsprogs` `block-mount` `kmod-fs-ext4` `lsblk` | 分区 / 格式化 / 挂载点（首次开机自动分区要用） | ImmortalWrt 主仓库 / packages |
| 磁盘 | `kmod-usb3` `kmod-usb-storage(-uas)` `kmod-fs-ntfs3` `kmod-fs-exfat` `kmod-fs-vfat` | USB 3.0 存储、NTFS/exFAT/FAT 支持 | ImmortalWrt 主仓库 |
| DNS | `dnsmasq-full`（替换 `dnsmasq`） | 完整版 DNS/DHCP（OpenClash、PassWall 必需） | ImmortalWrt 主仓库 |
| DNS | `luci-app-adguardhome` | AdGuard Home 广告过滤 | ImmortalWrt luci |
| DNS | `luci-app-mosdns`（含 `mosdns` `geo2txt`） | MosDNS 分流 DNS | [sbwml/luci-app-mosdns](https://github.com/sbwml/luci-app-mosdns) `v5` |
| 代理 | `luci-app-openclash` | OpenClash（nftables 版，界面自带中文） | ImmortalWrt luci |
| 代理 | `luci-app-passwall` | PassWall（nftables 版；默认带 Xray、sing-box、Haproxy 等） | ImmortalWrt luci |
| 组网 | `luci-proto-wireguard` `wireguard-tools` `qrencode` | WireGuard（在「网络 → 接口」里添加，可生成二维码） | ImmortalWrt luci / 主仓库 / packages |
| 组网 | `luci-app-tailscale` | Tailscale 异地组网 | [asvow/luci-app-tailscale](https://github.com/asvow/luci-app-tailscale) |
| 组网 | `luci-app-zerotier` | ZeroTier 异地组网 | ImmortalWrt luci |
| 流量 | `luci-app-sqm` | SQM 智能队列 / 限速 | ImmortalWrt luci |
| 流量 | `luci-app-mwan3` | 多线多拨负载均衡 | ImmortalWrt luci |
| 共享 | `luci-app-ksmbd` | 网络共享（SMB，只用 ksmbd，不装 samba4） | ImmortalWrt luci |
| 共享 | `luci-app-nfs` | NFS 共享 | ImmortalWrt luci |
| Docker | `luci-app-dockerman` `dockerd` `docker` `docker-compose` | Docker 及管理界面 | ImmortalWrt luci / packages |
| 下载 | `luci-app-aria2` | Aria2 下载 | ImmortalWrt luci |
| 下载 | `luci-app-qbittorrent` | qBittorrent 下载 | ImmortalWrt luci |
| 多媒体 / 开发 | `ffmpeg` `ffprobe` | 音视频处理 | ImmortalWrt packages |
| 多媒体 / 开发 | `python3` `python3-pip` | Python 3 | ImmortalWrt packages |
| 代理 | `luci-app-homeproxy` | HomeProxy（sing-box，nftables） | ImmortalWrt luci |
| 监控 | `luci-app-nlbwmon` | 网络带宽监视（按设备统计流量） | ImmortalWrt luci |
| 监控 | `luci-app-netdata` | Netdata 实时监控 | ImmortalWrt luci |
| 监控 | `luci-app-statistics` | 实时统计 / 历史图表（collectd） | ImmortalWrt luci |
| 网络工具 | `luci-app-wol` | 网络唤醒 | ImmortalWrt luci |
| 网络工具 | `iperf3-ssl` `tcpdump` `ethtool-full` `mtr-json` | 测速 / 抓包 / 网卡工具 / 路由追踪 | ImmortalWrt 主仓库 / packages |
| 守护 | `luci-app-watchcat` | 网络看门狗（断网自动重启接口或设备） | ImmortalWrt luci |
| 守护 | `luci-app-autoreboot` | 定时重启 | ImmortalWrt luci |
| DDNS / 穿透 | `luci-app-ddns-go` | DDNS-GO 动态域名 | ImmortalWrt luci |
| DDNS / 穿透 | `luci-app-frpc` | FRP 内网穿透客户端 | ImmortalWrt luci |
| DDNS / 穿透 | `luci-app-lucky`（含 `lucky`） | Lucky（DDNS、端口转发、反向代理、STUN 穿透等） | [gdy666/luci-app-lucky](https://github.com/gdy666/luci-app-lucky) |
| 证书 | `luci-app-acme` | ACME 证书自动申请（acme.sh） | ImmortalWrt luci |
| 网盘 / 文件 | `luci-app-openlist` | OpenList 网盘挂载（AList 社区分支） | ImmortalWrt luci |
| 网盘 / 文件 | `luci-app-filebrowser` | LuCI 文件浏览 | ImmortalWrt luci |
| 网盘 / 文件 | `filebrowser` | Filebrowser 网页文件管理（默认关闭，端口 8989） | ImmortalWrt packages |
| 网盘 / 文件 | `luci-app-filemanager` | LuCI 文件管理器（和上面的文件浏览、Filebrowser 功能有重叠，挑顺手的用） | ImmortalWrt luci |
| 内核 | `kmod-tcp-bbr` | BBR 拥塞控制（默认启用） | ImmortalWrt 主仓库 |
| 内核 | `kmod-tun` `kmod-nft-tproxy` `kmod-nft-socket` | 代理用的 TUN / 透明代理模块 | ImmortalWrt 主仓库 |
| 内核 | `kmod-vxlan` `kmod-macvlan` `kmod-veth` | VXLAN / macvlan / veth（Docker、虚拟网络） | ImmortalWrt 主仓库 |
| 网卡驱动 | `kmod-igc` `kmod-igb` `kmod-e1000e` | Intel 2.5G / 千兆网卡 | ImmortalWrt 主仓库 |
| 网卡驱动 | `kmod-r8125` `kmod-r8168` | Realtek 2.5G / 千兆网卡（厂商驱动，不装 r8169） | ImmortalWrt 主仓库 |
| USB 网卡 | `kmod-usb-net-rtl8152` `kmod-usb-net-asix-ax88179` | Realtek / ASIX USB 网卡 | ImmortalWrt 主仓库 |
| USB 网卡 | `kmod-usb-net-cdc-ether` `kmod-usb-net-cdc-ncm` `kmod-usb-net-rndis` | 手机 USB 共享网络（安卓） | ImmortalWrt 主仓库 |
| USB 网卡 | `kmod-usb-net-ipheth` `usbmuxd` | 手机 USB 共享网络（iPhone） | ImmortalWrt 主仓库 / packages |
| 存储驱动 | `kmod-nvme` `kmod-ata-ahci` | NVMe / SATA 硬盘 | ImmortalWrt 主仓库 |
| 系统 | `irqbalance` | 中断均衡（默认开启） | ImmortalWrt packages |
| 系统 | `zram-swap` | 压缩内存交换（zram） | ImmortalWrt 主仓库 |
| 系统工具 | `smartmontools` `hdparm` `lm-sensors` | 硬盘健康 / 硬盘参数 / 温度传感器 | ImmortalWrt packages |
| 系统工具 | `pciutils` `usbutils` | lspci / lsusb | ImmortalWrt packages |
| 系统工具 | `fdisk` `resize2fs` `losetup` | 分区 / 扩容 ext4 / 回环设备 | ImmortalWrt 主仓库 |
| 系统工具 | `coreutils-*`（ls、cp、sort、timeout 等 33 个） `findutils` `grep` `diffutils` | GNU 版命令行工具（替换 busybox 的同名命令） | ImmortalWrt packages |
| 网络诊断 | `ip-full` `bind-dig` `conntrack` `iftop` `nload` | 完整 ip 命令 / DNS 查询 / 连接跟踪 / 实时流量 | ImmortalWrt 主仓库 / packages |
| 网络诊断 | `speedtest-go` | 命令行测速（speedtest.net 节点） | ImmortalWrt packages |
| 界面 | `luci-app-upnp` | UPnP / NAT-PMP（默认关闭） | ImmortalWrt luci |
| 界面 | `luci-app-commands` | 自定义命令 | ImmortalWrt luci |
| 硬件 | `kmod-hwmon-coretemp` `kmod-i2c-i801` | CPU 温度 / 主板 SMBus（配合 lm-sensors） | ImmortalWrt 主仓库 |
| 文件系统 | `kmod-fs-btrfs` `kmod-fs-xfs` `kmod-fs-f2fs` `ntfs-3g` | Btrfs / XFS / F2FS / NTFS（FUSE 版，和 ntfs3 内核驱动并存） | ImmortalWrt 主仓库 / packages |
| 存储 | `mdadm` `lvm2` | 软 RAID / LVM 逻辑卷 | ImmortalWrt packages |
| 内核 | `kmod-sched-bpf` `bpftool-minimal` | eBPF 流量调度 / bpftool | ImmortalWrt 主仓库 |
| DNS | `luci-app-smartdns` | SmartDNS | ImmortalWrt luci |
| 分流 | `luci-app-pbr` | 策略路由（和 mwan3 功能重叠，规则别重复） | ImmortalWrt luci |
| 限速 | `luci-app-eqos` | 按 IP 限速 | ImmortalWrt luci |
| 组网 / 穿透 | `luci-app-easytier`（含 `easytier`） | EasyTier 去中心化组网 | [EasyTier/luci-app-easytier](https://github.com/EasyTier/luci-app-easytier) |
| 组网 / 穿透 | `luci-app-cloudflared` | Cloudflare Tunnel | ImmortalWrt luci |
| 组网 / 穿透 | `luci-app-natmap` | NATMap（NAT1 打洞端口映射） | ImmortalWrt luci |
| VPN 服务端 | `luci-app-openvpn-server` | OpenVPN 服务器 | ImmortalWrt luci |
| VPN 服务端 | `luci-app-ipsec-vpnd` | IPsec VPN 服务器（strongSwan） | ImmortalWrt luci |
| IPTV | `luci-app-udpxy` `luci-app-msd_lite` `luci-app-omcproxy` | IPTV 组播转 HTTP / 组播代理 | ImmortalWrt luci |
| 安全 | `luci-app-banip` | IP 黑名单封禁 | ImmortalWrt luci |
| 存储 / 服务 | `luci-app-hd-idle` | 硬盘休眠 | ImmortalWrt luci |
| 存储 / 服务 | `luci-app-rclone` | Rclone 网盘挂载 / 同步（含两个网页界面） | ImmortalWrt luci |
| 存储 / 服务 | `luci-app-vsftpd` | FTP 服务器 | ImmortalWrt luci |
| 存储 / 服务 | `luci-app-minidlna` | DLNA 媒体服务器 | ImmortalWrt luci |
| 存储 / 服务 | `luci-app-p910nd` | 网络打印服务器（打印机直通） | ImmortalWrt luci |
| 存储 / 服务 | `luci-app-nut` `nut-driver-usbhid-ups` | UPS 管理（NUT，带常见 USB UPS 驱动） | ImmortalWrt luci / packages |
| 存储 / 服务 | `luci-app-vlmcsd` | KMS 激活服务器 | ImmortalWrt luci |

带中文翻译的插件都同时选了对应的 `luci-i18n-*-zh-cn`。注意配置里必须有 `CONFIG_LUCI_LANG_zh_Hans=y`，否则 `make defconfig` 会把所有中文包悄悄去掉。workflow 在 `make defconfig` 之后会检查配置里写成 `=y` 的项是否都还在，x86_64 缺了任何一项会直接报错。

说明：

- **SMB 只用 ksmbd**：ksmbd 在内核里跑，占用小、速度快，已经够家用；samba4 和它都要占 445 端口，两个一起装会冲突，所以不装 samba4。
- **核显**：编进了 i915 驱动和固件，Docker 里的 Jellyfin 等容器可以把 `/dev/dri` 映射进去做硬件转码（容器自带 VAAPI 驱动）。OpenWrt 本身没有 Intel VAAPI 用户态驱动，宿主机上的 `ffmpeg` 只能软解。
- **代理插件**：OpenClash、PassWall、HomeProxy 都装了，但同一时间只开一个，否则透明代理规则会互相打架。
- **DNS 插件**：AdGuard Home、MosDNS、SmartDNS 都装了，用哪个就让哪个接上游，注意别抢同一个端口（dnsmasq 占 53）。
- **默认行为变化**：
  - BBR：`kmod-tcp-bbr` 自带 `/etc/sysctl.d/12-tcp-bbr.conf`，本机发起的 TCP 默认用 BBR（下载、Docker、qBittorrent 等），转发流量不受影响；默认队列 `fq_codel` 没改成 `fq`，所以不会和 SQM（它自己在接口上设 cake/fq_codel）冲突。
  - irqbalance：包里默认关闭，首次开机脚本 `files/x86_64/etc/uci-defaults/98-enable-irqbalance` 会打开。
  - zram-swap：默认开启，大小是内存的一半；可用 `uci set system.@system[0].zram_size_mb=大小` 调整，不想要就 `/etc/init.d/zram disable`。
  - UPnP：装了但默认关闭，要用去「服务 → UPnP」里开。
- **没装的**：`luci-app-cpufreq`（它依赖的 `cpufreq` 只支持 ARM，x86 由内核 intel_pstate 自动调频）；`kmod-8021q` 不存在，802.1Q VLAN 已经编进内核；`coreutils-full` 不存在，改成按命令选的 `coreutils-*`；`luci-app-cupsd` 在 ImmortalWrt 里不存在，打印只用 p910nd；KVM / qemu-ga、iStore、Intel 无线网卡驱动按要求不装。
- **Lucky、EasyTier**：这两个包下载的都是作者 / 官方 GitHub Release 的预编译二进制（不是源码编译）。
- **首次开机后要自己配置的**：OpenClash 内核和订阅、PassWall 节点、AdGuard Home 初始化、MosDNS 规则、Tailscale 登录、ZeroTier 网络 ID、WireGuard 接口、DDNS-GO / Lucky / frpc、ACME 证书、OpenList 存储、EasyTier / Cloudflare Tunnel、VPN 服务端、SmartDNS、NUT。OpenClash、AdGuard Home 等运行时下载的内核和规则都放在根分区，4 GB 足够。

## 加插件 / 改配置

`configs/*.config` 是 diffconfig，只写需要的选项。

- 加包：`CONFIG_PACKAGE_包名=y`
- 本地：对对应上游源码 `make menuconfig` → `./scripts/diffconfig.sh`
- 预置文件：`files/common/` 给所有机型，`files/<机型>/` 只给对应机型
- x86_64 额外插件源：`scripts/x86_64-extra-packages.sh`
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
