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

雅典娜和亚瑟的配置只加了少量插件：LuCI 中文、在线升级、Samba 4 网络共享、chrony 时间同步、USB 存储 / ext4 / 挂载点（完整清单见下面「固件内容清单」）。

- **SMB 也改成了 Samba 4**（不再用 ksmbd）。亚瑟只有 512 MB 内存，smbd 运行时大约占 30–60 MB（传文件时更多），NSS 本身也要预留一部分内存；不用共享时可以在「系统 → 启动项」里把 samba4 停掉。闪存多占约 30–40 MB（未压缩），eMMC 不缺这点空间。
- **时间同步也由 chrony 接管**，和 x86 用同一个脚本（见 x86 说明里的「时间同步」）。

## 关于 128G eMMC

雅典娜和亚瑟这两台都是 **128G eMMC**。eMMC 容量**不影响**编出来的固件：上游没有区分 64G / 128G 的 device，同一个 `factory.bin` / `sysupgrade.bin` 通用。容量只和 **GPT 分区表**有关：

- **第一次从原厂刷机**：先刷 eMMC 版 U-Boot，再刷**和你机型、容量匹配的 GPT 分区表**（128G 用 128G 的表，或者刷机包里不限容量的 `no-last-partition` 版本），最后在 U-Boot 网页刷 `*-factory.bin`。
- **不要拿 64G 的 GPT 刷 128G 的机器**，否则后半段空间用不上，或分区错位。雅典娜和亚瑟的 GPT 也不能混用。
- 刷完后多出来的空间可以在系统里新建分区，用「挂载点」挂上给 Samba 共享。

常用刷机资料：[lgs2007m 京东云亚瑟/雅典娜刷机救砖教程](https://github.com/lgs2007m/Actions-OpenWrt/releases/tag/Router-Flashing-Files)、[chenxin527 eMMC U-Boot](https://github.com/chenxin527/uboot-ipq60xx-emmc-build)。

## 手动触发编译

1. 打开仓库 **Actions** → 左侧 **Build OpenWrt**
2. 点 **Run workflow**
3. **第一次请勾选 force（上游没更新也强制编译）**

流程：`check`（对比 ImmortalWrt + LibWrt 两个上游短 SHA 与最近 Release）→ `build`（x86_64 / athena / arthur 并行）→ `release`。

当前 **仅启用 `workflow_dispatch`**；每天定时检查在 workflow 里默认注释掉，需要时自行打开。

首次编译约 3–4 小时（x86 插件多，含 Node.js、perf、gdb、samba4 等）；之后有 `dl/` 和 ccache 缓存会快一些。

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

面向 Intel 3965U / 16G / 64G 旁路由。除 MosDNS、Tailscale、Lucky、EasyTier、定时控制、Nikki 外，全部来自 ImmortalWrt 自带的 `packages` / `luci` feeds；这六个由 `scripts/x86_64-extra-packages.sh` 在编译时拉取（只对 x86_64 生效）。Docker 里的应用（Jellyfin、Home Assistant 等）不集成进固件，刷机后自己在 Docker 里装。

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
| 共享 | `luci-app-samba4` `samba4-server` | 网络共享（SMB，Samba 4；不装 ksmbd） | ImmortalWrt luci / packages |
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
| 系统 | `zram-swap` | 压缩内存交换（zram，默认 zstd 压缩） | ImmortalWrt 主仓库 |
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
| 代理 | `luci-app-daed` | daed（eBPF 透明代理，带网页面板） | ImmortalWrt luci |
| 家长控制 | `luci-app-appfilter` | 应用过滤（OpenAppFilter） | ImmortalWrt luci |
| 家长控制 | `luci-app-timecontrol` | 定时控制（按设备 MAC 和时段断网） | gaobin89/luci-app-timecontrol |
| 通知 / 高可用 | `luci-app-wechatpush` | 微信推送（设备上下线、IP 变化等通知） | ImmortalWrt luci |
| 通知 / 高可用 | `luci-app-keepalived` | Keepalived（VRRP 主备高可用） | ImmortalWrt luci |
| 组网 / VPN | `luci-app-n2n` | N2N（P2P 虚拟局域网） | ImmortalWrt luci |
| 组网 / VPN | `luci-app-softethervpn` | SoftEther VPN 服务器 | ImmortalWrt luci |
| 组网 / VPN | `luci-app-3cat` `socat` | 端口转发（替代 luci-app-socat）+ socat 命令行 | ImmortalWrt luci / packages |
| 同步 / 下载 | `luci-app-syncthing` | Syncthing 文件同步 | ImmortalWrt luci |
| 同步 / 下载 | `luci-app-transmission` | Transmission BT 下载 | ImmortalWrt luci |
| 同步 / 下载 | `luci-app-dufs` | Dufs 文件服务器（WebDAV） | ImmortalWrt luci |
| 娱乐 | `luci-app-unblockneteasemusic` | 解锁网易云音乐灰色歌曲 | ImmortalWrt luci |
| 代理 | `luci-app-v2raya` | v2rayA（xray 网页客户端） | ImmortalWrt luci |
| 代理 | `luci-app-nikki` `mihomo-meta` | Nikki（mihomo 透明代理） | nikkinikki-org/OpenWrt-nikki |
| 广告过滤 / 防检测 | `luci-app-adblock-fast` | 广告过滤（基于 dnsmasq） | ImmortalWrt luci |
| 广告过滤 / 防检测 | `luci-app-ua2f` | UA2F（改写 UA，校园网防检测） | ImmortalWrt luci |
| 组网 / VPN | `luci-app-nps` | NPS 内网穿透客户端（npc） | ImmortalWrt luci |
| 流量统计 | `luci-app-vnstat2` | vnStat 流量统计（按接口、按月） | ImmortalWrt luci |
| 存储 / 服务 | `luci-app-cifs-mount` | 挂载远程 SMB/CIFS 共享 | ImmortalWrt luci |
| 蜂窝网络 | `luci-proto-modemmanager` + USB 模块驱动 | 4G/5G 模块拨号（ModemManager，QMI / MBIM / NCM / 串口） | ImmortalWrt luci / packages |
| 内核 | `KERNEL_PSI` `KERNEL_TASKSTATS` | 资源压力统计 / 按进程 IO 统计（iotop 要用） | 内核选项 |
| 内核 | `KERNEL_DETECT_HUNG_TASK` `KERNEL_SOFTLOCKUP_DETECTOR` | 卡死任务 / 软死锁检测 | 内核选项 |
| 内核 | `KERNEL_CGROUP_NET_CLASSID` | cgroup 流量标记（net_cls） | 内核选项 |
| 内核 | `KERNEL_ZRAM_BACKEND_ZSTD` `KERNEL_ZRAM_DEF_COMP_ZSTD` | zram 支持 zstd 并设为默认（保留 lzo） | 内核选项 |
| 流量控制 | `kmod-sched` `kmod-sched-ctinfo` `kmod-sched-connmark` `kmod-sched-flower` `kmod-sched-act-vlan` `kmod-sched-drr` `kmod-sched-prio` `kmod-sched-mqprio` `kmod-netem` | 更多 tc 队列 / 分类器 / 动作，netem 网络损伤模拟 | ImmortalWrt 主仓库 |
| 流量控制 | `tc-full` | 完整版 tc 命令 | ImmortalWrt 主仓库 |
| 内核 | `kmod-bonding` `proto-bonding` | 多网口聚合（在「网络 → 接口」里建 Bonding 接口） | ImmortalWrt 主仓库 |
| 内核 | `kmod-nf-nathelper` `kmod-nf-nathelper-extra` | FTP / SIP / PPTP / H.323 等 NAT 辅助 | ImmortalWrt 主仓库 |
| 内核 | `kmod-gre` `kmod-ip6-tunnel` `kmod-l2tp` `kmod-ipvlan` `kmod-vrf` | GRE / IPv6 隧道 / L2TP / ipvlan / VRF | ImmortalWrt 主仓库 |
| 内核 | `kmod-nft-bridge` `kmod-nft-netdev` `kmod-nft-arp` | nftables 桥接 / netdev / ARP 扩展 | ImmortalWrt 主仓库 |
| 内核 | `kmod-tls` | 内核 TLS | ImmortalWrt 主仓库 |
| 存储驱动 | `kmod-loop` `kmod-nbd` `kmod-fs-autofs4` | 回环设备 / 网络块设备 / autofs | ImmortalWrt 主仓库 |
| 蜂窝网络 | `kmod-mhi-net` `kmod-mhi-wwan-ctrl` `kmod-mtk-t7xx`（含 `kmod-wwan`） | PCIe 5G 模块（高通 MHI、联发科 T700） | ImmortalWrt 主仓库 |
| 蜂窝网络 | `luci-app-3ginfo-lite` `luci-app-modemband` `luci-app-sms-tool-js` | 信号信息 / 锁频段 / 短信 | ImmortalWrt luci |
| 调试工具 | `strace` `gdb` `perf` `lsof` `iotop` `sysstat` `btop` | 系统调用跟踪 / 调试器 / 性能分析 / 打开文件 / IO 监控 / sar 等 / 资源监控 | ImmortalWrt 主仓库 / packages |
| 系统工具 | `tmux` `screen` `vim-full` `zsh` `less` `tree` `file` | 终端复用 / 编辑器 / Shell / 常用小工具 | ImmortalWrt packages |
| 系统工具 | `procps-ng-*`（ps、top、free、vmstat、watch、pgrep、pkill、pmap、pwdx、slabtop、uptime、w） | 完整版进程工具（替换 busybox 同名命令） | ImmortalWrt packages |
| 系统工具 | `git` `git-http` `rsync` `rsyncd` | Git / rsync 及 rsync 服务端 | ImmortalWrt packages |
| 系统工具 | `nvme-cli` `dmidecode` `acpid` `kexec-tools` `f2fs-tools` `xfs-mkfs` | NVMe 管理 / 硬件信息 / ACPI 电源键 / kexec / F2FS、XFS 格式化 | ImmortalWrt 主仓库 / packages |
| 网络工具 | `nmap` `ncat` `arp-scan` `drill` | 端口扫描 / netcat / 局域网扫描 / DNS 查询 | ImmortalWrt packages |
| 网络工具 | `conntrackd` `ipvsadm` | 连接跟踪同步（默认关闭）/ IPVS 负载均衡 | ImmortalWrt packages |
| 系统 | `luci-app-irqbalance` | 中断均衡界面 | ImmortalWrt luci |
| 时间同步 | `chrony` `luci-app-chrony` | Chrony 时间同步（替代 busybox sysntpd） | ImmortalWrt packages / luci |
| 系统 | `luci-app-cpulimit` `luci-app-ramfree` | 进程 CPU 限制 / 释放内存 | ImmortalWrt luci |
| DDNS / 穿透 | `luci-app-ddns` | 动态域名（官方 ddns-scripts） | ImmortalWrt luci |
| DDNS / 穿透 | `luci-app-frps` | FRP 服务端 | ImmortalWrt luci |
| DNS | `luci-app-https-dns-proxy` | DoH 代理（默认关闭） | ImmortalWrt luci |
| DNS | `luci-app-unbound` | Unbound 递归 DNS（默认关闭，端口 5335） | ImmortalWrt luci |
| 流量控制 | `luci-app-qosify` | qosify（eBPF DSCP 标记 + cake） | ImmortalWrt luci |
| 流量控制 | `luci-app-syncdial` | 多线多拨（依赖 mwan3 + macvlan，界面自带中文） | ImmortalWrt luci |
| 网络工具 | `luci-app-arpbind` | IP / MAC 绑定 | ImmortalWrt luci |
| 代理 | `luci-app-gost` `luci-app-microsocks` | GOST 隧道 / 轻量 SOCKS5 服务端 | ImmortalWrt luci |
| IPTV | `luci-app-rtp2httpd` | IPTV 组播 / RTSP 转 HTTP | ImmortalWrt luci |
| 多媒体 | `luci-app-airplay2` | AirPlay 2 音频接收（shairport-sync，需要 USB 声卡等输出设备） | ImmortalWrt luci |
| 物联网 | `luci-app-mosquitto` | MQTT 服务器 | ImmortalWrt luci |
| 安全 | `luci-app-crowdsec-firewall-bouncer` | CrowdSec 防火墙封禁端（只有 bouncer，不含引擎） | ImmortalWrt luci |
| 监控 | `luci-app-snmpd` `luci-app-lldpd` | SNMP（默认关闭）/ LLDP 邻居发现 | ImmortalWrt luci |

带中文翻译的插件都同时选了对应的 `luci-i18n-*-zh-cn`。注意配置里必须有 `CONFIG_LUCI_LANG_zh_Hans=y`，否则 `make defconfig` 会把所有中文包悄悄去掉。workflow 在 `make defconfig` 之后会检查配置里写成 `=y` 的项是否都还在，x86_64 缺了任何一项会直接报错。

说明：

- **SMB 改用 Samba 4（三台都是）**：samba4 兼容性最好（权限、macOS 时间机器、Windows 网络发现 wsdd2 都有）。ksmbd 和它都要占 445 端口，所以配置里显式写了 `# CONFIG_PACKAGE_ksmbd-server is not set` / `# CONFIG_PACKAGE_luci-app-ksmbd is not set`，不会被带回来；没有其他包依赖 ksmbd。共享设置在「服务 → 网络共享」，SMB 用户密码用 `smbpasswd -a root` 添加。代价是比 ksmbd 大：闪存多约 30–40 MB（未压缩，`samba4-libs` 占大头），smbd 运行时约 30–60 MB 内存。
- **核显**：编进了 i915 驱动和固件，Docker 里的 Jellyfin 等容器可以把 `/dev/dri` 映射进去做硬件转码（容器自带 VAAPI 驱动）。OpenWrt 本身没有 Intel VAAPI 用户态驱动，宿主机上的 `ffmpeg` 只能软解。
- **代理插件**：OpenClash、PassWall、HomeProxy、daed、v2rayA、Nikki 都装了，但同一时间只开一个，否则透明代理规则会互相打架。
- **daed**：要求内核带 BTF，所以 x86_64 打开了 `CONFIG_KERNEL_DEBUG_INFO_BTF`（连带完整内核调试信息），eBPF 程序用 workflow 已装的宿主机 clang/llvm 编译（`CONFIG_BPF_TOOLCHAIN_HOST`）。代价：内核编译更慢、占用编译机更多磁盘，内核镜像大几 MB（内核分区 32 MB，够用）。daed 和 OpenClash / PassWall / HomeProxy 一样，同一时间只开一个。
- **应用过滤（OAF）**：ImmortalWrt 默认开着软件 / 硬件流量卸载（`flow_offloading`），OAF 要关掉才能识别应用，插件页面里有一键关闭的按钮；做旁路由时，只有网关指向本机的设备才会被过滤。定时控制同理，只管经过本机的设备。
- **BT 下载**：qBittorrent 网页 8080、Transmission 网页 9091，网页端口不冲突；Transmission 监听 51413，qBittorrent 的监听端口在它自己的设置里改成别的就行，两个同时开注意下载目录分开。
- **其他默认端口**：Syncthing 8384、Dufs 5000。
- **网易云解锁**：依赖 Node.js，编译时要从源码交叉编译 node，整体编译时间会明显变长，固件也会大几十 MB；它的核心程序首次启动时在线下载。
- **防火墙**：用的是 firewall4（nftables），没有装旧的 firewall（iptables）。Docker、mwan3、strongSwan 依赖 `iptables` 命令，装进来的是走 nftables 的兼容版 `iptables-nft` / `ip6tables-nft`，没有 legacy 版。ImmortalWrt 默认打开 FullCone NAT（`kmod-nft-fullcone`，IPv4 开、IPv6 关）和软件 / 硬件流量卸载（x86 网卡一般不支持硬件卸载，实际只有软件卸载生效）。
- **广告过滤**：adblock-fast 和 AdGuard Home 选一个用就行。
- **Unbound**：默认要监听 53 端口，和 dnsmasq 冲突。首次开机脚本 `97-x86-service-defaults` 把它改到 **5335** 端口并关闭；要用就在 LuCI 里打开，再把 dnsmasq（或 MosDNS / AdGuard Home）的上游指向 `127.0.0.1#5335`。
- **https-dns-proxy**：默认会强制劫持局域网 53 端口并改写 dnsmasq 上游，和 MosDNS / AdGuard Home 打架，所以默认关闭。
- **CrowdSec**：只装了防火墙封禁端（`crowdsec-firewall-bouncer`），没有 CrowdSec 引擎（太大）。要用得在别的机器（例如 Docker）跑 CrowdSec，再把它的本地 API 地址和 bouncer key 填到插件里；没配之前保持关闭即可。
- **多拨（syncdial）**：会带上 mwan3 和 macvlan，和 `luci-app-mwan3` 共用 mwan3，规则别重复配。
- **tc**：选了 `tc-full`，SQM 等依赖的 `tc` 由它提供，`tc-tiny` 自动不再编入。
- **AirPlay 2**：需要声卡（例如 USB 声卡），没有音频输出设备时装着也不起作用；中文包是 `luci-i18n-airplay2-zh-cn`。
- **perf / gdb / BTF**：perf 跟内核一起编译，gdb 体积较大；都只是排障工具，不影响日常运行。
- **UA2F**：靠 nfqueue 改包，开着流量卸载时已建立的连接会绕过它，用之前把流量卸载关掉。
- **4G/5G 模块**：在「网络 → 接口」新建 ModemManager 协议的接口即可。`uqmi` / `umbim` 只是命令行调试工具。
- **DNS 插件**：AdGuard Home、MosDNS、SmartDNS 都装了，用哪个就让哪个接上游，注意别抢同一个端口（dnsmasq 占 53）。
- **默认行为变化**：
  - BBR：`kmod-tcp-bbr` 自带 `/etc/sysctl.d/12-tcp-bbr.conf`，本机发起的 TCP 默认用 BBR（下载、Docker、qBittorrent 等），转发流量不受影响；默认队列 `fq_codel` 没改成 `fq`，所以不会和 SQM（它自己在接口上设 cake/fq_codel）冲突。
  - irqbalance：包里默认关闭，首次开机脚本 `files/x86_64/etc/uci-defaults/98-enable-irqbalance` 会打开。
  - zram-swap：默认开启，大小是内存的一半；压缩算法由首次开机脚本 `97-zram-zstd` 设成 **zstd**（内核默认算法也改成了 zstd，保留 lzo 兜底；已经手动设过的不动）。可用 `uci set system.@system[0].zram_size_mb=大小` 调整，不想要就 `/etc/init.d/zram disable`。
  - 时间同步：**chrony 接管**。三台共用的首次开机脚本 `files/common/etc/uci-defaults/99-zz-chrony-ntp`（没装 chrony 的固件自动跳过）会：把 chrony 服务器换成 `ntp.tencent.com`、`ntp1.aliyun.com`、`ntp.ntsc.ac.cn`、`cn.ntp.org.cn` + `cn.pool.ntp.org`（只在第一次写入，之后升级不会覆盖你改过的服务器）；把「系统 → 时间同步」里的 busybox NTP 客户端和服务端都关掉并禁用 `sysntpd`；启用 `chronyd`。选这种做法是因为它最稳：不删 busybox 的 ntpd，LuCI 系统页面照常能用，想换回来只要在那里重新勾选并关掉 chronyd。chrony 默认还会给 LAN 提供 NTP 服务（`allow` lan）。
  - 默认关闭的服务（`97-x86-service-defaults`，每次刷新固件后首次开机都会执行，因为升级不保留服务的自启状态）：unbound（同时改到 5335 端口）、https-dns-proxy、conntrackd（没有主备同步配置时没用）、snmpd（默认团体名是 public，改了再开）。
  - UPnP：装了但默认关闭，要用去「服务 → UPnP」里开。
- **没装的**：`luci-app-cpufreq`（它依赖的 `cpufreq` 只支持 ARM，x86 由内核 intel_pstate 自动调频）；`kmod-8021q` 不存在，802.1Q VLAN 已经编进内核；`coreutils-full` 不存在，改成按命令选的 `coreutils-*`；`luci-app-cupsd` 在 ImmortalWrt 里不存在，打印只用 p910nd；KVM / qemu-ga、iStore、Intel 无线网卡驱动按要求不装；`luci-app-rustdesk-server`、`luci-app-ocserv`、`luci-app-pppoe-server`、`luci-app-dae`、`luci-app-lxc`、`kmod-crypto-hw-ccp` 按要求不装；`luci-app-syncdial` 没有单独的中文包。
- **定时控制**：ImmortalWrt feeds 里没有，用的是 gaobin89 的 JS 版（自动适配 fw4 / nftables），中文翻译直接打包在插件里，没有单独的 `luci-i18n-timecontrol-zh-cn`。
- **Lucky、EasyTier**：这两个包下载的都是作者 / 官方 GitHub Release 的预编译二进制（不是源码编译）。
- **首次开机后要自己配置的**：OpenClash 内核和订阅、PassWall 节点、AdGuard Home 初始化、MosDNS 规则、Tailscale 登录、ZeroTier 网络 ID、WireGuard 接口、DDNS-GO / Lucky / frpc、ACME 证书、OpenList 存储、EasyTier / Cloudflare Tunnel、VPN 服务端、SmartDNS、NUT、daed、微信推送、Keepalived、N2N、SoftEther、Syncthing、Transmission、Dufs、v2rayA / Nikki 订阅、NPS 客户端、CIFS 挂载、蜂窝接口、Samba 共享和 SMB 密码、FRP 服务端、DDNS、Unbound / https-dns-proxy（要用时）、CrowdSec 本地 API、MQTT、GOST / microsocks、rtp2httpd。OpenClash、AdGuard Home 等运行时下载的内核和规则都放在根分区，4 GB 足够。

## 固件内容清单（按层级）

根据 `configs/*.config` 和 `make defconfig` 的结果整理。只列配置里**显式选中**的项；依赖自动带进来的包（例如 `samba4-libs`、`mwan3`、`kmod-wwan` 的下级依赖）不单独列。带中文翻译的插件都同时装了对应的 `luci-i18n-*-zh-cn`（x86 共 90 个中文包）。

### x86_64（ImmortalWrt master）

| 层级 | 包名 / 选项 → 中文名 |
|---|---|
| 内核选项 | `TARGET_ROOTFS_PARTSIZE=4096` 根分区 4 GB；`GRUB_EFI_IMAGES` EFI 启动镜像；`DEVEL` 高级编译选项；`CCACHE` 编译缓存；`KERNEL_DEBUG_INFO` + `KERNEL_DEBUG_INFO_BTF`（关闭 `DEBUG_INFO_REDUCED`）内核调试信息 / BTF（daed 要用）；`KERNEL_BPF_EVENTS` BPF 事件；`KERNEL_CGROUPS` `KERNEL_CGROUP_BPF` cgroup 及 cgroup BPF；`KERNEL_XDP_SOCKETS` XDP 套接字；`BPF_TOOLCHAIN_HOST` 用编译机 clang 编 eBPF；`KERNEL_PSI` 资源压力统计；`KERNEL_TASKSTATS`（连带 `TASK_DELAY_ACCT` `TASK_IO_ACCOUNTING` `TASK_XACCT`）按进程统计；`KERNEL_DETECT_HUNG_TASK` 卡死任务检测；`KERNEL_SOFTLOCKUP_DETECTOR` 软死锁检测；`KERNEL_CGROUP_NET_CLASSID` cgroup 流量标记；`KERNEL_ZRAM_BACKEND_LZO` `KERNEL_ZRAM_BACKEND_ZSTD` `KERNEL_ZRAM_DEF_COMP_ZSTD` zram 压缩后端（默认 zstd） |
| 内核模块与驱动 | `kmod-tcp-bbr` BBR 拥塞控制；`kmod-tun` TUN；`kmod-nft-tproxy` `kmod-nft-socket` 透明代理；`kmod-vxlan` VXLAN；`kmod-macvlan` macvlan；`kmod-veth` veth；`kmod-ipvlan` ipvlan；`kmod-vrf` VRF；`kmod-gre` GRE 隧道；`kmod-ip6-tunnel` IPv6 隧道；`kmod-l2tp` L2TP；`kmod-bonding` + `proto-bonding` 网口聚合；`kmod-nf-nathelper` `kmod-nf-nathelper-extra` NAT 辅助（FTP/SIP/PPTP 等）；`kmod-nft-bridge` `kmod-nft-netdev` `kmod-nft-arp` nftables 扩展；`kmod-tls` 内核 TLS；`kmod-igc` `kmod-igb` `kmod-e1000e` Intel 网卡；`kmod-r8125` `kmod-r8168` Realtek 网卡（不装 `kmod-r8169`）；`kmod-usb-net-rtl8152` `kmod-usb-net-asix-ax88179` USB 网卡；`kmod-usb-net-cdc-ether` `kmod-usb-net-cdc-ncm` `kmod-usb-net-rndis` 安卓 USB 共享网络；`kmod-usb-net-ipheth` iPhone USB 共享网络；`kmod-drm-i915` 核显驱动；`i915-firmware-dmc` `i915-firmware-guc` `i915-firmware-huc` 核显固件；`intel-microcode` CPU 微码；`kmod-hwmon-coretemp` CPU 温度；`kmod-i2c-i801` 主板 SMBus；`kmod-nvme` NVMe；`kmod-ata-ahci` SATA；`kmod-usb3` USB 3.0；`kmod-usb-storage` `kmod-usb-storage-uas` USB 存储；`kmod-fs-ext4` `kmod-fs-ntfs3` `kmod-fs-exfat` `kmod-fs-vfat` `kmod-fs-btrfs` `kmod-fs-xfs` `kmod-fs-f2fs` 文件系统；`kmod-fs-autofs4` autofs；`kmod-loop` 回环设备；`kmod-nbd` 网络块设备 |
| 系统与工具 | `luci` LuCI；`default-settings-chn` 国内默认设置；`zram-swap` 压缩内存交换；`irqbalance` 中断均衡；`chrony` 时间同步；`htop` `btop` 资源监控；`nano` `vim-full` 编辑器；`bash` `zsh` Shell；`tmux` `screen` 终端复用；`less` `tree` `file` 常用小工具；`curl` `wget-ssl` 下载工具；`openssh-sftp-server` SFTP；`coreutils` + 33 个 `coreutils-*`（base64 cp cut date dd df du env head ls md5sum mktemp mv nohup nproc readlink realpath rm seq sha256sum sort split stat stdbuf tail tee timeout touch tr truncate uniq wc）GNU 命令；`findutils` `grep` `diffutils` GNU 查找 / 搜索 / 比较；`procps-ng` + `procps-ng-ps` `-top` `-free` `-vmstat` `-watch` `-pgrep` `-pkill` `-pmap` `-pwdx` `-slabtop` `-uptime` `-w` 完整进程工具；`strace` 系统调用跟踪；`gdb` 调试器；`perf` 性能分析；`lsof` 打开文件；`iotop` IO 监控；`sysstat` sar/iostat；`git` `git-http` Git；`rsync` `rsyncd` rsync 及服务端；`python3` `python3-pip` Python；`ffmpeg` `ffprobe` 音视频处理；`pciutils` `usbutils` lspci / lsusb；`dmidecode` 硬件信息；`lm-sensors` 温度传感器；`acpid`（+ `input-support`）ACPI 电源键；`kexec-tools` kexec |
| 网络工具 | `ip-full` 完整 ip；`tc-full` 完整 tc；`bind-dig` `drill` DNS 查询；`conntrack` 连接跟踪；`conntrackd` 连接跟踪同步；`ipvsadm` IPVS；`iftop` `nload` 实时流量；`iperf3-ssl` 测速；`speedtest-go` 公网测速；`tcpdump` 抓包；`ethtool-full` 网卡工具；`mtr-json` 路由追踪；`nmap` 端口扫描；`ncat` netcat；`arp-scan` 局域网扫描；`socat` 端口转发命令行；`luci-app-wol` 网络唤醒；`luci-app-arpbind` IP/MAC 绑定 |
| DNS | `dnsmasq-full`（替换 `dnsmasq`）完整 DNS/DHCP；`luci-app-adguardhome` AdGuard Home；`luci-app-mosdns` MosDNS；`luci-app-smartdns` SmartDNS；`luci-app-https-dns-proxy` DoH 代理；`luci-app-unbound` Unbound 递归 DNS；`luci-app-adblock-fast` 广告过滤 |
| 代理 | `luci-app-openclash` OpenClash；`luci-app-passwall` PassWall；`luci-app-homeproxy` HomeProxy；`luci-app-daed` daed；`luci-app-v2raya` v2rayA；`luci-app-nikki` + `mihomo-meta` Nikki；`luci-app-gost` GOST；`luci-app-microsocks` SOCKS5 服务端；`luci-app-ua2f` UA2F；`luci-app-unblockneteasemusic` 网易云解锁 |
| 组网与VPN | `luci-proto-wireguard` `wireguard-tools` `qrencode` WireGuard；`luci-app-tailscale` Tailscale；`luci-app-zerotier` ZeroTier；`luci-app-easytier` + `easytier` EasyTier；`luci-app-n2n` N2N；`luci-app-openvpn-server` OpenVPN 服务器；`luci-app-ipsec-vpnd` IPsec 服务器；`luci-app-softethervpn` SoftEther；`luci-app-keepalived` VRRP 高可用 |
| 远程访问 | `luci-app-ttyd` 网页终端；`luci-app-frpc` FRP 客户端；`luci-app-frps` FRP 服务端；`luci-app-nps` NPS 客户端；`luci-app-cloudflared` Cloudflare Tunnel；`luci-app-natmap` NATMap；`luci-app-lucky` Lucky；`luci-app-ddns-go` DDNS-GO；`luci-app-ddns` 动态域名；`luci-app-3cat` 端口转发；`luci-app-upnp` UPnP；`luci-app-acme` ACME 证书 |
| 流量控制 | `luci-app-sqm` SQM；`luci-app-qosify` qosify；`luci-app-eqos` 按 IP 限速；`luci-app-mwan3` 多线负载均衡；`luci-app-syncdial` 多拨；`luci-app-pbr` 策略路由；`kmod-sched` `kmod-sched-ctinfo` `kmod-sched-connmark` `kmod-sched-flower` `kmod-sched-act-vlan` `kmod-sched-drr` `kmod-sched-prio` `kmod-sched-mqprio` tc 扩展；`kmod-sched-bpf` + `bpftool-minimal` eBPF 调度；`kmod-netem` 网络损伤模拟；`luci-app-appfilter` 应用过滤；`luci-app-timecontrol` 定时控制；`luci-app-banip` IP 封禁；`luci-app-crowdsec-firewall-bouncer` CrowdSec 封禁端 |
| 存储与共享 | `luci-app-samba4` + `samba4-server` Samba 4 共享（`ksmbd-server` / `luci-app-ksmbd` 显式不装）；`luci-app-nfs` NFS；`luci-app-vsftpd` FTP；`luci-app-dufs` WebDAV；`luci-app-minidlna` DLNA；`luci-app-cifs-mount` 挂载远程 SMB；`luci-app-rclone` Rclone；`luci-app-openlist` OpenList；`luci-app-syncthing` Syncthing；`luci-app-filebrowser` `filebrowser` `luci-app-filemanager` 文件管理；`luci-app-diskman` 磁盘管理；`luci-app-hd-idle` 硬盘休眠；`parted` `fdisk` `lsblk` 分区；`e2fsprogs` `resize2fs` ext4 工具；`f2fs-tools` F2FS 工具；`xfs-mkfs` XFS 格式化；`ntfs-3g` NTFS（FUSE）；`block-mount` 挂载点；`losetup` 回环设备；`mdadm` 软 RAID；`lvm2` LVM；`smartmontools` 硬盘健康；`hdparm` 硬盘参数；`nvme-cli` NVMe 管理 |
| 下载 | `luci-app-aria2` Aria2；`luci-app-qbittorrent` qBittorrent；`luci-app-transmission` Transmission |
| 监控 | `luci-app-netdata` Netdata；`luci-app-statistics` 统计图表；`luci-app-nlbwmon` 按设备流量；`luci-app-vnstat2` vnStat；`luci-app-snmpd` SNMP；`luci-app-lldpd` LLDP；`luci-app-watchcat` 网络看门狗；`luci-app-wechatpush` 微信推送 |
| IPTV | `luci-app-udpxy` udpxy；`luci-app-msd_lite` msd_lite；`luci-app-omcproxy` 组播代理；`luci-app-rtp2httpd` rtp2httpd |
| 4G5G | `luci-proto-modemmanager` + `modemmanager` 拨号；`kmod-usb-serial-option` `kmod-usb-acm` `kmod-usb-wdm` USB 串口 / 控制口；`kmod-usb-net-qmi-wwan` `kmod-usb-net-cdc-mbim` `kmod-usb-net-huawei-cdc-ncm` QMI / MBIM / 华为 NCM；`uqmi` `umbim` 命令行；`kmod-wwan` `kmod-mhi-net` `kmod-mhi-wwan-ctrl` `kmod-mtk-t7xx` PCIe 5G 模块；`luci-app-3ginfo-lite` 信号信息；`luci-app-modemband` 锁频段；`luci-app-sms-tool-js` 短信 |
| 外设 | `usbmuxd` iPhone 连接；`luci-app-p910nd` 网络打印；`luci-app-nut` + `nut-driver-usbhid-ups` UPS；`luci-app-airplay2`（+ `audio-support`）AirPlay 2 音频接收；`luci-app-mosquitto` MQTT 服务器；`luci-app-vlmcsd` KMS 激活 |
| Docker | `luci-app-dockerman` 管理界面；`dockerd` `docker` `docker-compose` Docker 本体（Docker 里的应用不集成） |
| 界面 | `luci-theme-argon` Argon 主题；`LUCI_LANG_zh_Hans` 中文语言；`luci-app-attendedsysupgrade` 在线升级；`luci-app-commands` 自定义命令；`luci-app-autoreboot` 定时重启；`luci-app-irqbalance` 中断均衡；`luci-app-chrony` 时间同步；`luci-app-cpulimit` CPU 限制；`luci-app-ramfree` 释放内存 |

显式不装：`dnsmasq`（被 `dnsmasq-full` 替换）、`kmod-r8169`、`ksmbd-server`、`luci-app-ksmbd`、`luci-i18n-ksmbd-zh-cn`。`make defconfig` 后 x86 共 1152 个包，`tc-tiny` 自动不再选中。

### 雅典娜 AX6600 / 亚瑟 AX1800 Pro（LibWrt 25.12-nss）

两台配置一样，只差机型（雅典娜多一个 QCN9074 5G 射频固件 `ath11k-firmware-qcn9074`）。

| 层级 | 包名 → 中文名 |
|---|---|
| 内核选项 | 没有改内核选项；`CCACHE=y` 写在配置里，但 LibWrt 的 `make defconfig` 会把它去掉（不影响编译结果） |
| 内核模块与驱动 | 显式：`kmod-usb-storage` USB 存储、`kmod-fs-ext4` ext4。上游自动带入的 NSS：`kmod-qca-nss-dp` `kmod-qca-nss-drv`（含 bridge-mgr、vlan-mgr、lag-mgr、pppoe、pptp、gre、map-t、vxlanmgr、qdisc、igs、wifi-meshmgr 等子模块）`kmod-qca-nss-ecm` `kmod-qca-nss-crypto` `nss-firmware-ipq60xx`；Wi‑Fi：`kmod-ath11k`（ahb / pci）`ath11k-firmware-ipq6018`、雅典娜另有 `ath11k-firmware-qcn9074`；另外上游默认带 USB 3.0、exFAT / NTFS3 / F2FS / FAT、`kmod-nft-fullcone` |
| 系统与工具 | 显式：`chrony` 时间同步、`block-mount` 挂载点；上游默认：`default-settings-chn` 国内默认设置、`automount` 自动挂载、`e2fsprogs`、`uboot-envtools`、`wpad-openssl`、`dnsmasq-full`、`firewall4` |
| 存储与共享 | `luci-app-samba4` Samba 4 网络共享（自动带 `samba4-server` `wsdd2`；`ksmbd-server` / `luci-app-ksmbd` 显式不装） |
| 界面 | `luci` + `luci-i18n-base-zh-cn` LuCI 中文；`luci-app-attendedsysupgrade` 在线升级；`luci-app-chrony` 时间同步；上游默认还带 `luci-app-cpufreq` 调频、`luci-app-package-manager` 软件包、`luci-theme-bootstrap` |
| 其余层级 | 网络工具、DNS、代理、组网与VPN、远程访问、流量控制、下载、监控、IPTV、4G5G、外设、Docker：都没有额外加，保持上游默认 |

`make defconfig` 后雅典娜 333 个包、亚瑟 332 个包。

### 默认开启 / 默认关闭

| 项目 | x86_64 | 雅典娜 / 亚瑟 |
|---|---|---|
| 首次开机自动分区（`99-auto-data-partition`） | 开（剩余空间建 ext4 挂 `/opt/data`） | 无 |
| BBR | 开（`kmod-tcp-bbr` 自带 sysctl） | 未装 |
| irqbalance | 开（`98-enable-irqbalance`） | 未装 |
| zram-swap | 开，zstd 压缩（`97-zram-zstd`） | 未装 |
| chrony 时间同步 | 开，国内服务器，sysntpd 关闭（`99-zz-chrony-ntp`） | 同左（同一个脚本） |
| FullCone NAT | 开（IPv4） | 开（IPv4） |
| 流量卸载 | 软件 + 硬件卸载开（x86 实际只有软件卸载生效） | 关（由 NSS ECM 硬件加速） |
| SMB（Samba 4） | 装好，按需添加共享 | 同左 |
| 默认关闭 | unbound（改到 5335）、https-dns-proxy、conntrackd、snmpd（`97-x86-service-defaults`）；UPnP；filebrowser；各代理 / 组网插件都要自己配置后才启用 | 无额外服务 |

## 包管理器：apk（不是 opkg）

三个机型都一样：ImmortalWrt master 和 LibWrt 25.12-nss 的 `config/Config-build.in` 里 `CONFIG_USE_APK` 默认就是 `y`，本仓库的配置也没改它，所以固件里是 `apk`，没有 `opkg`。

| 做什么 | 命令 |
| --- | --- |
| 更新软件源 | `apk update` |
| 安装 | `apk add 包名` |
| 卸载 | `apk del 包名` |
| 搜索 | `apk search 关键词` |
| 查看已装 / 包信息 | `apk info` / `apk info 包名` |
| 升级已装的包 | `apk upgrade` |
| 装本地 .apk 文件 | `apk add --allow-untrusted ./xxx.apk` |

注意：

- 以前的 `.ipk` 包装不了，第三方插件要找 `.apk` 版本，或者加进配置重新编译固件。
- LuCI「系统 → 软件包」由 `luci-app-package-manager` 提供（已带中文），可以在网页里搜索、安装、上传 `.apk`。
- 在线装包要求软件源和固件的内核版本、架构对得上；自己编的固件内核 hash 和官方源不一定一致，`kmod-*` 最好直接编进固件。

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

已刷 OpenWrt / ImmortalWrt / LibWrt 的机器可用对应 `sysupgrade.bin` 升级。从旧版（ksmbd）升级上来后，SMB 共享要在「服务 → 网络共享」（Samba 4）里重新添加，SMB 密码用 `smbpasswd -a root` 重新设置。
