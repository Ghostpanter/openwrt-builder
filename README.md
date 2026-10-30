# openwrt-builder

三台设备固件配置仓库：x86_64 用 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) `master`；雅典娜 / 亚瑟用 [LibWrt](https://github.com/LiBwrt/LibWrt) `25.12-nss`。配置见 `configs/*.config`。本文档**只保留软件包清单**（显式 `CONFIG_PACKAGE_*=y`，不含自动依赖）。编译：Actions `workflow_dispatch` 或 `scripts/local-build.sh`。

| 机型 | 配置 | 上游 | target / device |
|---|---|---|---|
| x86_64 | `configs/x86_64.config` | ImmortalWrt `master` | `x86/64` / `generic` |
| 雅典娜 AX6600（RE-CS-02） | `configs/athena.config` | LibWrt `25.12-nss` | `qualcommax/ipq60xx` / `jdcloud_re-cs-02` |
| 亚瑟 AX1800 Pro（RE-SS-01） | `configs/arthur.config` | LibWrt `25.12-nss` | `qualcommax/ipq60xx` / `jdcloud_re-ss-01` |

说明：

- 网络共享用 **Samba4**（不用 ksmbd）；不装 attendedsysupgrade / frp / nps / keepalived。
- 代理类（OpenClash / PassWall / Nikki / AdGuard Home）三台都可编进；**运行时同一时间只开一个代理栈**。
- 亚瑟 **512MB** 内存：PassWall / qBittorrent / Transmission / OpenList / OpenClash 等同开会吃紧，不用时在启动项关掉。
- x86 第三方由 `scripts/x86_64-extra-packages.sh` 拉取：MosDNS、Lucky、定时控制、Nikki、clash-exporter、**Home Assistant**（`luci-app-homeassistant` + istore `taskd`/`luci-lib-taskd`/`luci-lib-xterm`；Docker 跑 `homeassistant/home-assistant:latest`，脚本仍含 EasyTier，配置未选）。Tailscale 改用上游官方 `luci-app-tailscale-community`。
- 雅典娜 / 亚瑟第三方由 `scripts/jd-extra-packages.sh` 拉取：MosDNS；雅典娜另含 LED（`athena-led` / `luci-app-athena-led`，unraveloop）。**不编 Home Assistant**（内存/存储不够跑 HA 容器）。
- 显式包数量：x86_64 **290** · 雅典娜 **137** · 亚瑟 **135**。

## x86_64（290）

| 分类 | 包名 | 中文名 | 来源 |
|---|---|---|---|
| 系统 / 界面 | `acpid` | ACPI 事件守护 | ImmortalWrt packages |
| 系统 / 界面 | `default-settings-chn` | 国内默认设置（上海时区 / NTP / 镜像） | ImmortalWrt 主仓库 |
| 系统 / 界面 | `input-support` | 输入设备支持（配合 acpid） | ImmortalWrt 主仓库 |
| 系统 / 界面 | `irqbalance` | 中断均衡 | ImmortalWrt packages |
| 系统 / 界面 | `luci-app-autoreboot` | 定时重启 | ImmortalWrt luci |
| 系统 / 界面 | `luci-app-commands` | 自定义命令 | ImmortalWrt luci |
| 系统 / 界面 | `luci-app-irqbalance` | 中断均衡界面 | ImmortalWrt luci |
| 系统 / 界面 | `luci-app-ramfree` | 释放内存 | ImmortalWrt luci |
| 系统 / 界面 | `luci-i18n-autoreboot-zh-cn` | 定时重启 · 简体中文 | ImmortalWrt luci |
| 系统 / 界面 | `luci-i18n-commands-zh-cn` | 自定义命令 · 简体中文 | ImmortalWrt luci |
| 系统 / 界面 | `luci-i18n-firewall-zh-cn` | 防火墙 · 简体中文 | ImmortalWrt luci |
| 系统 / 界面 | `luci-i18n-irqbalance-zh-cn` | 中断均衡界面 · 简体中文 | ImmortalWrt luci |
| 系统 / 界面 | `luci-i18n-ramfree-zh-cn` | 释放内存 · 简体中文 | ImmortalWrt luci |
| 系统 / 界面 | `luci-theme-argon` | Argon 主题 | ImmortalWrt luci |
| 系统 / 界面 | `zram-swap` | zram 压缩内存交换 | ImmortalWrt 主仓库 |
| 网络工具 | `arp-scan` | 局域网 ARP 扫描 | ImmortalWrt packages |
| 网络工具 | `ip-full` | 完整 ip 命令 | ImmortalWrt packages |
| 网络工具 | `luci-app-arpbind` | IP/MAC 绑定 | ImmortalWrt luci |
| 网络工具 | `luci-app-wol` | 网络唤醒 | ImmortalWrt luci |
| 网络工具 | `luci-i18n-arpbind-zh-cn` | IP/MAC 绑定 · 简体中文 | ImmortalWrt luci |
| 网络工具 | `luci-i18n-wol-zh-cn` | 网络唤醒 · 简体中文 | ImmortalWrt luci |
| 网络工具 | `ncat` | ncat | ImmortalWrt packages |
| 系统工具 | `bash` | Bash | ImmortalWrt packages |
| 系统工具 | `coreutils` | GNU coreutils 元包 | ImmortalWrt packages |
| 系统工具 | `coreutils-base64` | GNU coreutils base64（Base64 编解码） | ImmortalWrt packages |
| 系统工具 | `coreutils-cp` | GNU coreutils cp（复制文件） | ImmortalWrt packages |
| 系统工具 | `coreutils-cut` | GNU coreutils cut（按列截取文本） | ImmortalWrt packages |
| 系统工具 | `coreutils-date` | GNU coreutils date（显示/设置日期） | ImmortalWrt packages |
| 系统工具 | `coreutils-dd` | GNU coreutils dd（块拷贝） | ImmortalWrt packages |
| 系统工具 | `coreutils-df` | GNU coreutils df（磁盘空间） | ImmortalWrt packages |
| 系统工具 | `coreutils-du` | GNU coreutils du（目录占用） | ImmortalWrt packages |
| 系统工具 | `coreutils-env` | GNU coreutils env（环境变量运行） | ImmortalWrt packages |
| 系统工具 | `coreutils-head` | GNU coreutils head（显示文件开头） | ImmortalWrt packages |
| 系统工具 | `coreutils-ls` | GNU coreutils ls（列目录） | ImmortalWrt packages |
| 系统工具 | `coreutils-md5sum` | GNU coreutils md5sum（MD5 校验） | ImmortalWrt packages |
| 系统工具 | `coreutils-mktemp` | GNU coreutils mktemp（创建临时文件） | ImmortalWrt packages |
| 系统工具 | `coreutils-mv` | GNU coreutils mv（移动/重命名） | ImmortalWrt packages |
| 系统工具 | `coreutils-nohup` | GNU coreutils nohup（后台免挂断运行） | ImmortalWrt packages |
| 系统工具 | `coreutils-nproc` | GNU coreutils nproc（CPU 核数） | ImmortalWrt packages |
| 系统工具 | `coreutils-readlink` | GNU coreutils readlink（解析链接） | ImmortalWrt packages |
| 系统工具 | `coreutils-realpath` | GNU coreutils realpath（绝对路径） | ImmortalWrt packages |
| 系统工具 | `coreutils-rm` | GNU coreutils rm（删除文件） | ImmortalWrt packages |
| 系统工具 | `coreutils-seq` | GNU coreutils seq（生成序列） | ImmortalWrt packages |
| 系统工具 | `coreutils-sha256sum` | GNU coreutils sha256sum（SHA256 校验） | ImmortalWrt packages |
| 系统工具 | `coreutils-sort` | GNU coreutils sort（排序） | ImmortalWrt packages |
| 系统工具 | `coreutils-split` | GNU coreutils split（切分文件） | ImmortalWrt packages |
| 系统工具 | `coreutils-stat` | GNU coreutils stat（文件状态） | ImmortalWrt packages |
| 系统工具 | `coreutils-stdbuf` | GNU coreutils stdbuf（调整 IO 缓冲） | ImmortalWrt packages |
| 系统工具 | `coreutils-tail` | GNU coreutils tail（显示文件末尾） | ImmortalWrt packages |
| 系统工具 | `coreutils-tee` | GNU coreutils tee（输出分流） | ImmortalWrt packages |
| 系统工具 | `coreutils-timeout` | GNU coreutils timeout（限时运行） | ImmortalWrt packages |
| 系统工具 | `coreutils-touch` | GNU coreutils touch（修改时间戳/创建文件） | ImmortalWrt packages |
| 系统工具 | `coreutils-tr` | GNU coreutils tr（字符替换） | ImmortalWrt packages |
| 系统工具 | `coreutils-truncate` | GNU coreutils truncate（截断文件） | ImmortalWrt packages |
| 系统工具 | `coreutils-uniq` | GNU coreutils uniq（去重） | ImmortalWrt packages |
| 系统工具 | `coreutils-wc` | GNU coreutils wc（字数统计） | ImmortalWrt packages |
| 系统工具 | `curl` | curl | ImmortalWrt packages |
| 系统工具 | `diffutils` | GNU diffutils | ImmortalWrt packages |
| 系统工具 | `dmidecode` | 硬件信息 | ImmortalWrt packages |
| 系统工具 | `file` | file 文件类型 | ImmortalWrt packages |
| 系统工具 | `findutils` | GNU findutils | ImmortalWrt packages |
| 系统工具 | `git` | Git | ImmortalWrt packages |
| 系统工具 | `git-http` | Git HTTP/HTTPS 支持 | ImmortalWrt packages |
| 系统工具 | `grep` | GNU grep | ImmortalWrt packages |
| 系统工具 | `less` | less 分页 | ImmortalWrt packages |
| 系统工具 | `nano` | nano 编辑器 | ImmortalWrt packages |
| 系统工具 | `pciutils` | lspci | ImmortalWrt packages |
| 系统工具 | `procps-ng` | procps-ng 元包 | ImmortalWrt packages |
| 系统工具 | `procps-ng-free` | procps-ng free（内存使用） | ImmortalWrt packages |
| 系统工具 | `procps-ng-pgrep` | procps-ng pgrep（按名查找进程） | ImmortalWrt packages |
| 系统工具 | `procps-ng-pkill` | procps-ng pkill（按名结束进程） | ImmortalWrt packages |
| 系统工具 | `procps-ng-pmap` | procps-ng pmap（进程内存映射） | ImmortalWrt packages |
| 系统工具 | `procps-ng-ps` | procps-ng ps（进程列表） | ImmortalWrt packages |
| 系统工具 | `procps-ng-pwdx` | procps-ng pwdx（进程工作目录） | ImmortalWrt packages |
| 系统工具 | `procps-ng-slabtop` | procps-ng slabtop（内核 slab 缓存） | ImmortalWrt packages |
| 系统工具 | `procps-ng-top` | procps-ng top（实时进程监视） | ImmortalWrt packages |
| 系统工具 | `procps-ng-uptime` | procps-ng uptime（运行时长与负载） | ImmortalWrt packages |
| 系统工具 | `procps-ng-vmstat` | procps-ng vmstat（虚拟内存统计） | ImmortalWrt packages |
| 系统工具 | `procps-ng-w` | procps-ng w（登录用户） | ImmortalWrt packages |
| 系统工具 | `procps-ng-watch` | procps-ng watch（周期执行命令） | ImmortalWrt packages |
| 系统工具 | `tree` | tree 目录树 | ImmortalWrt packages |
| 系统工具 | `wget-ssl` | wget（SSL） | ImmortalWrt packages |
| 共享 / 文件 | `luci-app-rclone` | Rclone | ImmortalWrt luci |
| 共享 / 文件 | `luci-app-syncthing` | Syncthing | ImmortalWrt luci |
| 共享 / 文件 | `luci-i18n-rclone-zh-cn` | Rclone · 简体中文 | ImmortalWrt luci |
| 共享 / 文件 | `luci-i18n-syncthing-zh-cn` | Syncthing · 简体中文 | ImmortalWrt luci |
| 共享 / 文件 | `samba4-server` | Samba 4 服务端 | ImmortalWrt packages |
| 监控 | `clash-exporter` | OpenClash/Mihomo Prometheus 指标导出 | vfreex/clash-exporter |
| 监控 | `luci-app-lldpd` | LLDP 邻居发现 | ImmortalWrt luci |
| 监控 | `luci-i18n-lldpd-zh-cn` | LLDP 邻居发现 · 简体中文 | ImmortalWrt luci |
| 代理 | `kmod-nft-socket` | 内核模块：nftables socket 匹配 | ImmortalWrt 主仓库 |
| 代理 | `kmod-nft-tproxy` | 内核模块：nftables 透明代理 TPROXY | ImmortalWrt 主仓库 |
| 代理 | `kmod-tun` | 内核模块：TUN/TAP 虚拟网卡 | ImmortalWrt 主仓库 |
| 代理 | `luci-app-nikki` | Nikki（mihomo 透明代理） | nikkinikki-org/OpenWrt-nikki |
| 代理 | `luci-i18n-nikki-zh-cn` | Nikki（mihomo 透明代理） · 简体中文 | nikkinikki-org/OpenWrt-nikki |
| 代理 | `mihomo-meta` | Mihomo Meta 内核（Nikki） | ImmortalWrt packages |
| DNS | `luci-app-smartdns` | SmartDNS | ImmortalWrt luci |
| DNS | `luci-i18n-smartdns-zh-cn` | SmartDNS · 简体中文 | ImmortalWrt luci |
| DDNS / 证书 / 穿透 | `luci-app-acme` | ACME 证书 | ImmortalWrt luci |
| DDNS / 证书 / 穿透 | `luci-app-ddns` | 动态域名 | ImmortalWrt luci |
| DDNS / 证书 / 穿透 | `luci-app-lucky` | Lucky（DDNS/转发/穿透） | gdy666/lucky |
| DDNS / 证书 / 穿透 | `luci-i18n-acme-zh-cn` | ACME 证书 · 简体中文 | ImmortalWrt luci |
| DDNS / 证书 / 穿透 | `luci-i18n-ddns-zh-cn` | 动态域名 · 简体中文 | ImmortalWrt luci |
| DDNS / 证书 / 穿透 | `luci-i18n-lucky-zh-cn` | Lucky（DDNS/转发/穿透） · 简体中文 | gdy666/lucky |
| 核显 / CPU | `i915-firmware-dmc` | Intel 核显 DMC 固件 | ImmortalWrt 主仓库 |
| 核显 / CPU | `i915-firmware-guc` | Intel 核显 GuC 固件 | ImmortalWrt 主仓库 |
| 核显 / CPU | `i915-firmware-huc` | Intel 核显 HuC 固件 | ImmortalWrt 主仓库 |
| 核显 / CPU | `intel-microcode` | Intel CPU 微码 | ImmortalWrt 主仓库 |
| 核显 / CPU | `kmod-drm-i915` | 内核模块：Intel 核显 DRM 驱动 | ImmortalWrt 主仓库 |
| 核显 / CPU | `kmod-hwmon-coretemp` | 内核模块：Intel CPU 温度传感器 | ImmortalWrt 主仓库 |
| 核显 / CPU | `kmod-i2c-i801` | 内核模块：Intel SMBus（i801）驱动 | ImmortalWrt 主仓库 |
| 磁盘 / 存储 | `fdisk` | fdisk 分区 | ImmortalWrt 主仓库 |
| 磁盘 / 存储 | `kmod-ata-ahci` | 内核模块：SATA AHCI 控制器驱动 | ImmortalWrt 主仓库 |
| 磁盘 / 存储 | `kmod-fs-vfat` | 内核模块：FAT/VFAT 文件系统 | ImmortalWrt 主仓库 |
| 磁盘 / 存储 | `kmod-loop` | 内核模块：回环块设备 | ImmortalWrt 主仓库 |
| 磁盘 / 存储 | `kmod-nbd` | 内核模块：网络块设备 NBD | ImmortalWrt 主仓库 |
| 磁盘 / 存储 | `kmod-nvme` | 内核模块：NVMe 固态硬盘驱动 | ImmortalWrt 主仓库 |
| 磁盘 / 存储 | `kmod-usb-storage-uas` | 内核模块：USB UAS 高速存储协议 | ImmortalWrt 主仓库 |
| 磁盘 / 存储 | `losetup` | 回环设备 | ImmortalWrt 主仓库 |
| 磁盘 / 存储 | `mdadm` | 软 RAID | ImmortalWrt 主仓库 |
| 磁盘 / 存储 | `nvme-cli` | NVMe 管理 | ImmortalWrt packages |
| 磁盘 / 存储 | `parted` | 分区工具 | ImmortalWrt packages |
| 磁盘 / 存储 | `smartmontools` | 硬盘健康 SMART | ImmortalWrt packages |
| 流量 / QoS | `kmod-netem` | 内核模块：网络损伤模拟（延迟/丢包） | ImmortalWrt 主仓库 |
| 流量 / QoS | `kmod-sched` | 内核模块：流量调度器（扩展） | ImmortalWrt 主仓库 |
| 流量 / QoS | `kmod-sched-act-vlan` | 内核模块：tc VLAN 动作 | ImmortalWrt 主仓库 |
| 流量 / QoS | `kmod-sched-bpf` | 内核模块：tc BPF 分类器 | ImmortalWrt 主仓库 |
| 流量 / QoS | `kmod-sched-connmark` | 内核模块：tc connmark 动作 | ImmortalWrt 主仓库 |
| 流量 / QoS | `kmod-sched-ctinfo` | 内核模块：tc ctinfo 动作（DSCP 还原） | ImmortalWrt 主仓库 |
| 流量 / QoS | `kmod-sched-drr` | 内核模块：DRR 队列调度 | ImmortalWrt 主仓库 |
| 流量 / QoS | `kmod-sched-flower` | 内核模块：tc flower 分类器 | ImmortalWrt 主仓库 |
| 流量 / QoS | `kmod-sched-mqprio` | 内核模块：多队列优先级调度 mqprio | ImmortalWrt 主仓库 |
| 流量 / QoS | `kmod-sched-prio` | 内核模块：PRIO 优先级队列 | ImmortalWrt 主仓库 |
| 流量 / QoS | `kmod-tcp-bbr` | 内核模块：TCP BBR 拥塞控制 | ImmortalWrt 主仓库 |
| 流量 / QoS | `luci-app-appfilter` | 应用过滤（OAF） | ImmortalWrt luci |
| 流量 / QoS | `luci-app-syncdial` | 多线多拨 | ImmortalWrt luci |
| 流量 / QoS | `luci-app-timecontrol` | 定时上网控制 | gaobin89/luci-app-timecontrol |
| 流量 / QoS | `luci-i18n-appfilter-zh-cn` | 应用过滤（OAF） · 简体中文 | ImmortalWrt luci |
| 流量 / QoS | `tc-full` | 完整 tc 命令 | ImmortalWrt 主仓库 |
| Docker | `docker` | Docker 客户端 | ImmortalWrt packages |
| Docker | `docker-compose` | Docker Compose | ImmortalWrt packages |
| Docker | `dockerd` | Docker 守护进程 | ImmortalWrt packages |
| Docker | `luci-app-dockerman` | Docker 管理 | ImmortalWrt luci |
| Docker | `luci-app-homeassistant` | Home Assistant（Docker 官方镜像） | linkease openwrt-app-actions |
| Docker | `luci-i18n-dockerman-zh-cn` | Docker 管理 · 简体中文 | ImmortalWrt luci |
| Docker | `luci-lib-taskd` | taskd LuCI 库（HA / iStore 任务） | linkease istore |
| Docker | `luci-lib-xterm` | xterm.js 库（taskd 终端） | linkease istore |
| Docker | `taskd` | 简易任务管理（procd） | linkease istore |
| 内核 / 隧道 | `kmod-bonding` | 内核模块：网卡绑定（bonding） | ImmortalWrt 主仓库 |
| 内核 / 隧道 | `kmod-gre` | 内核模块：GRE 隧道 | ImmortalWrt 主仓库 |
| 内核 / 隧道 | `kmod-ip6-tunnel` | 内核模块：IPv6 隧道 | ImmortalWrt 主仓库 |
| 内核 / 隧道 | `kmod-ipvlan` | 内核模块：IPVLAN 虚拟网卡 | ImmortalWrt 主仓库 |
| 内核 / 隧道 | `kmod-l2tp` | 内核模块：L2TP 隧道 | ImmortalWrt 主仓库 |
| 内核 / 隧道 | `kmod-macvlan` | 内核模块：MACVLAN 虚拟网卡 | ImmortalWrt 主仓库 |
| 内核 / 隧道 | `kmod-nf-nathelper` | 内核模块：NAT 协议助手（FTP 等） | ImmortalWrt 主仓库 |
| 内核 / 隧道 | `kmod-nf-nathelper-extra` | 内核模块：NAT 协议助手（扩展：SIP/PPTP 等） | ImmortalWrt 主仓库 |
| 内核 / 隧道 | `kmod-nft-arp` | 内核模块：nftables ARP 过滤 | ImmortalWrt 主仓库 |
| 内核 / 隧道 | `kmod-nft-bridge` | 内核模块：nftables 网桥过滤 | ImmortalWrt 主仓库 |
| 内核 / 隧道 | `kmod-nft-netdev` | 内核模块：nftables netdev 过滤 | ImmortalWrt 主仓库 |
| 内核 / 隧道 | `kmod-tls` | 内核模块：内核 TLS 加速 | ImmortalWrt 主仓库 |
| 内核 / 隧道 | `kmod-veth` | 内核模块：veth 虚拟网卡对 | ImmortalWrt 主仓库 |
| 内核 / 隧道 | `kmod-vrf` | 内核模块：VRF 虚拟路由转发 | ImmortalWrt 主仓库 |
| 内核 / 隧道 | `kmod-vxlan` | 内核模块：VXLAN 隧道 | ImmortalWrt 主仓库 |
| 内核 / 隧道 | `proto-bonding` | Bonding 接口协议 | ImmortalWrt packages |
| 网卡 / USB 网卡 | `kmod-e1000e` | 内核模块：Intel 千兆网卡驱动 e1000e | ImmortalWrt 主仓库 |
| 网卡 / USB 网卡 | `kmod-igb` | 内核模块：Intel 千兆网卡驱动 igb | ImmortalWrt 主仓库 |
| 网卡 / USB 网卡 | `kmod-igc` | 内核模块：Intel 2.5G 网卡驱动 igc（I225/I226） | ImmortalWrt 主仓库 |
| 网卡 / USB 网卡 | `kmod-r8125` | 内核模块：Realtek 2.5G 网卡驱动 r8125 | ImmortalWrt 主仓库 |
| 网卡 / USB 网卡 | `kmod-r8168` | 内核模块：Realtek 千兆网卡驱动 r8168 | ImmortalWrt 主仓库 |
| 网卡 / USB 网卡 | `kmod-usb-net-asix-ax88179` | 内核模块：ASIX AX88179 USB 千兆网卡 | ImmortalWrt 主仓库 |
| 网卡 / USB 网卡 | `kmod-usb-net-cdc-ether` | 内核模块：USB CDC 以太网 | ImmortalWrt 主仓库 |
| 网卡 / USB 网卡 | `kmod-usb-net-cdc-ncm` | 内核模块：USB CDC NCM 网卡 | ImmortalWrt 主仓库 |
| 网卡 / USB 网卡 | `kmod-usb-net-ipheth` | 内核模块：iPhone USB 共享网络 | ImmortalWrt 主仓库 |
| 网卡 / USB 网卡 | `kmod-usb-net-rndis` | 内核模块：RNDIS USB 共享网络（安卓） | ImmortalWrt 主仓库 |
| 网卡 / USB 网卡 | `kmod-usb-net-rtl8152` | 内核模块：Realtek RTL8152/8153 USB 网卡 | ImmortalWrt 主仓库 |
| 外设 | `luci-app-p910nd` | 网络打印 | ImmortalWrt luci |
| 外设 | `luci-i18n-p910nd-zh-cn` | 网络打印 · 简体中文 | ImmortalWrt luci |
| 工具 | `bind-dig` | dig DNS 查询 | ImmortalWrt packages |
| 工具 | `btop` | btop 资源监视 | ImmortalWrt packages |
| 工具 | `conntrack` | 连接跟踪工具 | ImmortalWrt packages |
| 工具 | `conntrackd` | 连接跟踪同步守护 | ImmortalWrt packages |
| 工具 | `drill` | drill DNS 查询 | ImmortalWrt packages |
| 工具 | `ethtool-full` | 完整 ethtool | ImmortalWrt packages |
| 工具 | `htop` | htop 进程监视 | ImmortalWrt packages |
| 工具 | `iftop` | iftop 实时流量 | ImmortalWrt packages |
| 工具 | `iotop` | iotop IO 监视 | ImmortalWrt packages |
| 工具 | `iperf3-ssl` | iperf3 测速（SSL） | ImmortalWrt packages |
| 工具 | `lm-sensors` | 温度传感器 | ImmortalWrt packages |
| 工具 | `lsof` | lsof | ImmortalWrt packages |
| 工具 | `mtr-json` | mtr 路由追踪 | ImmortalWrt packages |
| 工具 | `nload` | nload 实时流量 | ImmortalWrt packages |
| 工具 | `openssh-sftp-server` | SFTP 服务端 | ImmortalWrt packages |
| 工具 | `rsync` | rsync | ImmortalWrt packages |
| 工具 | `rsyncd` | rsync 服务端 | ImmortalWrt packages |
| 工具 | `screen` | screen 终端复用 | ImmortalWrt packages |
| 工具 | `socat` | socat | ImmortalWrt packages |
| 工具 | `speedtest-go` | 公网测速 | ImmortalWrt packages |
| 工具 | `sysstat` | sysstat（sar/iostat） | ImmortalWrt packages |
| 工具 | `tcpdump` | tcpdump 抓包 | ImmortalWrt packages |
| 工具 | `tmux` | tmux 终端复用 | ImmortalWrt packages |
| 工具 | `usbutils` | lsusb | ImmortalWrt packages |
| 工具 | `vim-full` | Vim 完整版 | ImmortalWrt packages |
| 系统 / 存储 | `block-mount` | 挂载点管理 | ImmortalWrt 主仓库 |
| 系统 / 存储 | `chrony` | Chrony 时间同步 | ImmortalWrt packages |
| 系统 / 存储 | `dnsmasq-full` | 完整版 DNS/DHCP | ImmortalWrt 主仓库 |
| 系统 / 存储 | `e2fsprogs` | ext 文件系统工具 | ImmortalWrt 主仓库 |
| 系统 / 存储 | `f2fs-tools` | F2FS 工具 | ImmortalWrt packages |
| 系统 / 存储 | `filebrowser` | Filebrowser 网页文件管理 | ImmortalWrt packages |
| 系统 / 存储 | `hdparm` | 硬盘参数 | ImmortalWrt packages |
| 系统 / 存储 | `lsblk` | 列出块设备 | ImmortalWrt 主仓库 |
| 系统 / 存储 | `lvm2` | LVM 逻辑卷 | ImmortalWrt packages |
| 系统 / 存储 | `ntfs-3g` | NTFS（FUSE） | ImmortalWrt packages |
| 系统 / 存储 | `qrencode` | 二维码生成（WireGuard） | ImmortalWrt packages |
| 系统 / 存储 | `resize2fs` | ext 分区扩容 | ImmortalWrt 主仓库 |
| 系统 / 存储 | `usbmuxd` | iPhone USB 连接 | ImmortalWrt packages |
| 系统 / 存储 | `wireguard-tools` | WireGuard 工具 | ImmortalWrt packages |
| 系统 / 存储 | `xfs-mkfs` | XFS 格式化 | ImmortalWrt packages |
| 内核 / 监控 | `kmod-fs-autofs4` | 内核模块：autofs 自动挂载文件系统 | ImmortalWrt 主仓库 |
| 内核 / 监控 | `kmod-fs-btrfs` | 内核模块：Btrfs 文件系统 | ImmortalWrt 主仓库 |
| 内核 / 监控 | `kmod-fs-exfat` | 内核模块：exFAT 文件系统 | ImmortalWrt 主仓库 |
| 内核 / 监控 | `kmod-fs-ext4` | 内核模块：ext4 文件系统 | ImmortalWrt 主仓库 |
| 内核 / 监控 | `kmod-fs-f2fs` | 内核模块：F2FS 文件系统 | ImmortalWrt 主仓库 |
| 内核 / 监控 | `kmod-fs-ntfs3` | 内核模块：NTFS3 内核读写驱动 | ImmortalWrt 主仓库 |
| 内核 / 监控 | `kmod-fs-xfs` | 内核模块：XFS 文件系统 | ImmortalWrt 主仓库 |
| 内核 / 监控 | `kmod-usb-storage` | 内核模块：USB 存储 | ImmortalWrt 主仓库 |
| 内核 / 监控 | `kmod-usb3` | 内核模块：USB 3.0 控制器 | ImmortalWrt 主仓库 |
| 界面 | `luci` | LuCI 网页界面 | ImmortalWrt luci |
| 界面 | `luci-i18n-banip-zh-cn` | IP 黑名单 · 简体中文 | ImmortalWrt luci |
| 界面 | `luci-i18n-base-zh-cn` | LuCI 基础界面 · 简体中文 | ImmortalWrt luci |
| 界面 | `luci-i18n-chrony-zh-cn` | Chrony 界面 · 简体中文 | ImmortalWrt luci |
| 界面 | `luci-i18n-cifs-mount-zh-cn` | 挂载远程 SMB/CIFS · 简体中文 | ImmortalWrt luci |
| 界面 | `luci-i18n-diskman-zh-cn` | 磁盘管理 · 简体中文 | ImmortalWrt luci |
| 界面 | `luci-i18n-hd-idle-zh-cn` | 硬盘休眠 · 简体中文 | ImmortalWrt luci |
| 界面 | `luci-i18n-mosdns-zh-cn` | MosDNS 分流 DNS · 简体中文 | sbwml/luci-app-mosdns |
| 界面 | `luci-i18n-mwan3-zh-cn` | 多线负载均衡 · 简体中文 | ImmortalWrt luci |
| 界面 | `luci-i18n-natmap-zh-cn` | NATMap 端口映射 · 简体中文 | ImmortalWrt luci |
| 界面 | `luci-i18n-nlbwmon-zh-cn` | 网络带宽监视 · 简体中文 | ImmortalWrt luci |
| 界面 | `luci-i18n-pbr-zh-cn` | 策略路由 · 简体中文 | ImmortalWrt luci |
| 界面 | `luci-i18n-samba4-zh-cn` | Samba4 网络共享 · 简体中文 | ImmortalWrt luci |
| 界面 | `luci-i18n-sqm-zh-cn` | SQM 智能队列 · 简体中文 | ImmortalWrt luci |
| 界面 | `luci-i18n-statistics-zh-cn` | 实时统计（collectd） · 简体中文 | ImmortalWrt luci |
| 界面 | `luci-i18n-upnp-zh-cn` | UPnP / NAT-PMP · 简体中文 | ImmortalWrt luci |
| 界面 | `luci-i18n-watchcat-zh-cn` | 网络看门狗 · 简体中文 | ImmortalWrt luci |
| 界面 | `luci-i18n-wechatpush-zh-cn` | 微信推送 · 简体中文 | ImmortalWrt luci |
| LuCI 应用 | `luci-app-adguardhome` | AdGuard Home | ImmortalWrt luci |
| LuCI 应用 | `luci-app-banip` | IP 黑名单 | ImmortalWrt luci |
| LuCI 应用 | `luci-app-chrony` | Chrony 界面 | ImmortalWrt luci |
| LuCI 应用 | `luci-app-cifs-mount` | 挂载远程 SMB/CIFS | ImmortalWrt luci |
| LuCI 应用 | `luci-app-cloudflared` | Cloudflare Tunnel 内网穿透 | ImmortalWrt luci |
| LuCI 应用 | `luci-app-ddns-go` | DDNS-Go 动态域名 | ImmortalWrt luci |
| LuCI 应用 | `luci-app-diskman` | 磁盘管理 | ImmortalWrt luci |
| LuCI 应用 | `luci-app-filebrowser` | 文件浏览器 | ImmortalWrt luci |
| LuCI 应用 | `luci-app-filebrowser-go` | FileBrowser 网页文件管理 | ImmortalWrt luci |
| LuCI 应用 | `luci-app-hd-idle` | 硬盘休眠 | ImmortalWrt luci |
| LuCI 应用 | `luci-app-mosdns` | MosDNS 分流 DNS | sbwml/luci-app-mosdns |
| LuCI 应用 | `luci-app-mwan3` | 多线负载均衡 | ImmortalWrt luci |
| LuCI 应用 | `luci-app-natmap` | NATMap 端口映射 | ImmortalWrt luci |
| LuCI 应用 | `luci-app-nlbwmon` | 网络带宽监视 | ImmortalWrt luci |
| LuCI 应用 | `luci-app-openclash` | OpenClash | ImmortalWrt luci |
| LuCI 应用 | `luci-app-openlist` | OpenList 网盘挂载/列表程序 | ImmortalWrt luci |
| LuCI 应用 | `luci-app-package-manager` | 软件包管理（安装/卸载） | ImmortalWrt luci |
| LuCI 应用 | `luci-app-passwall` | PassWall | ImmortalWrt luci |
| LuCI 应用 | `luci-app-pbr` | 策略路由 | ImmortalWrt luci |
| LuCI 应用 | `luci-app-qbittorrent` | qBittorrent | ImmortalWrt luci |
| LuCI 应用 | `luci-app-samba4` | Samba4 网络共享 | ImmortalWrt luci |
| LuCI 应用 | `luci-app-sqm` | SQM 智能队列 | ImmortalWrt luci |
| LuCI 应用 | `luci-app-statistics` | 实时统计（collectd） | ImmortalWrt luci |
| LuCI 应用 | `luci-app-tailscale-community` | Tailscale 组网（社区版界面） | ImmortalWrt luci |
| LuCI 应用 | `luci-app-transmission` | Transmission BT 下载 | ImmortalWrt luci |
| LuCI 应用 | `luci-app-ttyd` | 网页终端 | ImmortalWrt luci |
| LuCI 应用 | `luci-app-upnp` | UPnP / NAT-PMP | ImmortalWrt luci |
| LuCI 应用 | `luci-app-watchcat` | 网络看门狗 | ImmortalWrt luci |
| LuCI 应用 | `luci-app-wechatpush` | 微信推送 | ImmortalWrt luci |
| LuCI 应用 | `luci-app-wifihistory` | Wi-Fi 终端连接历史 | ImmortalWrt luci |
| LuCI 应用 | `luci-app-zerotier` | ZeroTier 虚拟局域网 | ImmortalWrt luci |
| LuCI 应用 | `luci-proto-wireguard` | WireGuard 接口协议 | ImmortalWrt luci |
| 中文 | `luci-i18n-adguardhome-zh-cn` | AdGuard Home · 简体中文 | ImmortalWrt luci |
| 中文 | `luci-i18n-cloudflared-zh-cn` | Cloudflare Tunnel · 简体中文 | ImmortalWrt luci |
| 中文 | `luci-i18n-ddns-go-zh-cn` | DDNS-Go · 简体中文 | ImmortalWrt luci |
| 中文 | `luci-i18n-filebrowser-go-zh-cn` | FileBrowser · 简体中文 | ImmortalWrt luci |
| 中文 | `luci-i18n-filebrowser-zh-cn` | 文件浏览器 · 简体中文 | ImmortalWrt luci |
| 中文 | `luci-i18n-openlist-zh-cn` | OpenList · 简体中文 | ImmortalWrt luci |
| 中文 | `luci-i18n-package-manager-zh-cn` | 软件包管理 · 简体中文 | ImmortalWrt luci |
| 中文 | `luci-i18n-passwall-zh-cn` | PassWall · 简体中文 | ImmortalWrt luci |
| 中文 | `luci-i18n-qbittorrent-zh-cn` | qBittorrent · 简体中文 | ImmortalWrt luci |
| 中文 | `luci-i18n-tailscale-community-zh-cn` | Tailscale 组网 · 简体中文 | ImmortalWrt luci |
| 中文 | `luci-i18n-transmission-zh-cn` | Transmission · 简体中文 | ImmortalWrt luci |
| 中文 | `luci-i18n-ttyd-zh-cn` | 网页终端 · 简体中文 | ImmortalWrt luci |
| 中文 | `luci-i18n-wifihistory-zh-cn` | Wi-Fi 终端连接历史 · 简体中文 | ImmortalWrt luci |
| 中文 | `luci-i18n-zerotier-zh-cn` | ZeroTier · 简体中文 | ImmortalWrt luci |

## 雅典娜（137）

NSS / Wi-Fi 等由 target `DEFAULT_PACKAGES` 自动带入，不在此列。含雅典娜点阵屏 LED。

| 分类 | 包名 | 中文名 |
|---|---|---|
| 界面 | `luci` | LuCI 网页界面 |
| 界面 | `luci-i18n-banip-zh-cn` | IP 黑名单 · 简体中文 |
| 界面 | `luci-i18n-base-zh-cn` | LuCI 基础界面 · 简体中文 |
| 界面 | `luci-i18n-chrony-zh-cn` | Chrony 界面 · 简体中文 |
| 界面 | `luci-i18n-cifs-mount-zh-cn` | 挂载远程 SMB/CIFS · 简体中文 |
| 界面 | `luci-i18n-diskman-zh-cn` | 磁盘管理 · 简体中文 |
| 界面 | `luci-i18n-hd-idle-zh-cn` | 硬盘休眠 · 简体中文 |
| 界面 | `luci-i18n-mosdns-zh-cn` | MosDNS 分流 DNS · 简体中文 |
| 界面 | `luci-i18n-mwan3-zh-cn` | 多线负载均衡 · 简体中文 |
| 界面 | `luci-i18n-natmap-zh-cn` | NATMap 端口映射 · 简体中文 |
| 界面 | `luci-i18n-nlbwmon-zh-cn` | 网络带宽监视 · 简体中文 |
| 界面 | `luci-i18n-pbr-zh-cn` | 策略路由 · 简体中文 |
| 界面 | `luci-i18n-samba4-zh-cn` | Samba4 网络共享 · 简体中文 |
| 界面 | `luci-i18n-sqm-zh-cn` | SQM 智能队列 · 简体中文 |
| 界面 | `luci-i18n-statistics-zh-cn` | 实时统计（collectd） · 简体中文 |
| 界面 | `luci-i18n-upnp-zh-cn` | UPnP / NAT-PMP · 简体中文 |
| 界面 | `luci-i18n-watchcat-zh-cn` | 网络看门狗 · 简体中文 |
| 界面 | `luci-i18n-wechatpush-zh-cn` | 微信推送 · 简体中文 |
| LuCI 应用 | `luci-app-adguardhome` | AdGuard Home |
| LuCI 应用 | `luci-app-athena-led` | luci-app-athena-led |
| LuCI 应用 | `luci-app-autoreboot` | 定时重启 |
| LuCI 应用 | `luci-app-banip` | IP 黑名单 |
| LuCI 应用 | `luci-app-chrony` | Chrony 界面 |
| LuCI 应用 | `luci-app-cifs-mount` | 挂载远程 SMB/CIFS |
| LuCI 应用 | `luci-app-cloudflared` | Cloudflare Tunnel 内网穿透 |
| LuCI 应用 | `luci-app-ddns-go` | DDNS-Go 动态域名 |
| LuCI 应用 | `luci-app-diskman` | 磁盘管理 |
| LuCI 应用 | `luci-app-filebrowser` | 文件浏览器 |
| LuCI 应用 | `luci-app-filebrowser-go` | FileBrowser 网页文件管理 |
| LuCI 应用 | `luci-app-hd-idle` | 硬盘休眠 |
| LuCI 应用 | `luci-app-irqbalance` | 中断均衡界面 |
| LuCI 应用 | `luci-app-mosdns` | MosDNS 分流 DNS |
| LuCI 应用 | `luci-app-mwan3` | 多线负载均衡 |
| LuCI 应用 | `luci-app-natmap` | NATMap 端口映射 |
| LuCI 应用 | `luci-app-nlbwmon` | 网络带宽监视 |
| LuCI 应用 | `luci-app-openclash` | OpenClash |
| LuCI 应用 | `luci-app-openlist` | OpenList 网盘挂载/列表程序 |
| LuCI 应用 | `luci-app-package-manager` | 软件包管理（安装/卸载） |
| LuCI 应用 | `luci-app-passwall` | PassWall |
| LuCI 应用 | `luci-app-pbr` | 策略路由 |
| LuCI 应用 | `luci-app-qbittorrent` | qBittorrent |
| LuCI 应用 | `luci-app-ramfree` | 释放内存 |
| LuCI 应用 | `luci-app-samba4` | Samba4 网络共享 |
| LuCI 应用 | `luci-app-sqm` | SQM 智能队列 |
| LuCI 应用 | `luci-app-statistics` | 实时统计（collectd） |
| LuCI 应用 | `luci-app-tailscale-community` | Tailscale 组网（社区版界面） |
| LuCI 应用 | `luci-app-transmission` | Transmission BT 下载 |
| LuCI 应用 | `luci-app-ttyd` | 网页终端 |
| LuCI 应用 | `luci-app-upnp` | UPnP / NAT-PMP |
| LuCI 应用 | `luci-app-watchcat` | 网络看门狗 |
| LuCI 应用 | `luci-app-wechatpush` | 微信推送 |
| LuCI 应用 | `luci-app-wifihistory` | Wi-Fi 终端连接历史 |
| LuCI 应用 | `luci-app-wifischedule` | WiFi 定时开关 |
| LuCI 应用 | `luci-app-zerotier` | ZeroTier 虚拟局域网 |
| LuCI 应用 | `luci-proto-wireguard` | WireGuard 接口协议 |
| 中文 | `luci-i18n-adguardhome-zh-cn` | AdGuard Home · 简体中文 |
| 中文 | `luci-i18n-autoreboot-zh-cn` | 定时重启 · 简体中文 |
| 中文 | `luci-i18n-cloudflared-zh-cn` | Cloudflare Tunnel · 简体中文 |
| 中文 | `luci-i18n-ddns-go-zh-cn` | DDNS-Go · 简体中文 |
| 中文 | `luci-i18n-filebrowser-go-zh-cn` | FileBrowser · 简体中文 |
| 中文 | `luci-i18n-filebrowser-zh-cn` | 文件浏览器 · 简体中文 |
| 中文 | `luci-i18n-irqbalance-zh-cn` | 中断均衡界面 · 简体中文 |
| 中文 | `luci-i18n-openlist-zh-cn` | OpenList · 简体中文 |
| 中文 | `luci-i18n-package-manager-zh-cn` | 软件包管理 · 简体中文 |
| 中文 | `luci-i18n-passwall-zh-cn` | PassWall · 简体中文 |
| 中文 | `luci-i18n-qbittorrent-zh-cn` | qBittorrent · 简体中文 |
| 中文 | `luci-i18n-ramfree-zh-cn` | 释放内存 · 简体中文 |
| 中文 | `luci-i18n-tailscale-community-zh-cn` | Tailscale 组网 · 简体中文 |
| 中文 | `luci-i18n-transmission-zh-cn` | Transmission · 简体中文 |
| 中文 | `luci-i18n-ttyd-zh-cn` | 网页终端 · 简体中文 |
| 中文 | `luci-i18n-wifihistory-zh-cn` | Wi-Fi 终端连接历史 · 简体中文 |
| 中文 | `luci-i18n-wifischedule-zh-cn` | WiFi 定时开关 · 简体中文 |
| 中文 | `luci-i18n-zerotier-zh-cn` | ZeroTier · 简体中文 |
| 系统 / 存储 | `athena-led` | athena-led |
| 系统 / 存储 | `block-mount` | 挂载点管理 |
| 系统 / 存储 | `chrony` | Chrony 时间同步 |
| 系统 / 存储 | `dnsmasq-full` | 完整版 DNS/DHCP |
| 系统 / 存储 | `e2fsprogs` | ext 文件系统工具 |
| 系统 / 存储 | `f2fs-tools` | F2FS 工具 |
| 系统 / 存储 | `filebrowser` | Filebrowser 网页文件管理 |
| 系统 / 存储 | `hdparm` | 硬盘参数 |
| 系统 / 存储 | `irqbalance` | 中断均衡 |
| 系统 / 存储 | `lsblk` | 列出块设备 |
| 系统 / 存储 | `lvm2` | LVM 逻辑卷 |
| 系统 / 存储 | `ntfs-3g` | NTFS（FUSE） |
| 系统 / 存储 | `qrencode` | 二维码生成（WireGuard） |
| 系统 / 存储 | `resize2fs` | ext 分区扩容 |
| 系统 / 存储 | `usbmuxd` | iPhone USB 连接 |
| 系统 / 存储 | `wifischedule` | WiFi 定时开关（后端） |
| 系统 / 存储 | `wireguard-tools` | WireGuard 工具 |
| 系统 / 存储 | `xfs-mkfs` | XFS 格式化 |
| 系统 / 存储 | `zram-swap` | zram 压缩内存交换 |
| 内核 / 监控 | `kmod-fs-autofs4` | 内核模块：autofs 自动挂载文件系统 |
| 内核 / 监控 | `kmod-fs-btrfs` | 内核模块：Btrfs 文件系统 |
| 内核 / 监控 | `kmod-fs-exfat` | 内核模块：exFAT 文件系统 |
| 内核 / 监控 | `kmod-fs-ext4` | 内核模块：ext4 文件系统 |
| 内核 / 监控 | `kmod-fs-f2fs` | 内核模块：F2FS 文件系统 |
| 内核 / 监控 | `kmod-fs-ntfs3` | 内核模块：NTFS3 内核读写驱动 |
| 内核 / 监控 | `kmod-fs-vfat` | 内核模块：FAT/VFAT 文件系统 |
| 内核 / 监控 | `kmod-fs-xfs` | 内核模块：XFS 文件系统 |
| 内核 / 监控 | `kmod-tcp-bbr` | 内核模块：TCP BBR 拥塞控制 |
| 内核 / 监控 | `kmod-usb-storage` | 内核模块：USB 存储 |
| 内核 / 监控 | `kmod-usb-storage-uas` | 内核模块：USB UAS 高速存储协议 |
| 内核 / 监控 | `kmod-usb3` | 内核模块：USB 3.0 控制器 |
| 内核 / 监控 | `prometheus-node-exporter-lua` | Prometheus 节点导出（lua） |
| 内核 / 监控 | `prometheus-node-exporter-lua-nat_traffic` | Prometheus 采集器：NAT 流量 |
| 内核 / 监控 | `prometheus-node-exporter-lua-netstat` | Prometheus 采集器：网络统计 |
| 内核 / 监控 | `prometheus-node-exporter-lua-openwrt` | Prometheus 采集器：OpenWrt 系统信息 |
| 内核 / 监控 | `prometheus-node-exporter-lua-thermal` | Prometheus 采集器：温度 |
| 内核 / 监控 | `prometheus-node-exporter-lua-uci_dhcp_host` | Prometheus 采集器：DHCP 静态主机 |
| 内核 / 监控 | `prometheus-node-exporter-lua-wifi` | Prometheus 采集器：Wi-Fi |
| 内核 / 监控 | `prometheus-node-exporter-lua-wifi_stations` | Prometheus 采集器：Wi-Fi 终端 |
| 工具 | `bind-dig` | dig DNS 查询 |
| 工具 | `btop` | btop 资源监视 |
| 工具 | `conntrack` | 连接跟踪工具 |
| 工具 | `conntrackd` | 连接跟踪同步守护 |
| 工具 | `drill` | drill DNS 查询 |
| 工具 | `ethtool-full` | 完整 ethtool |
| 工具 | `htop` | htop 进程监视 |
| 工具 | `iftop` | iftop 实时流量 |
| 工具 | `iotop` | iotop IO 监视 |
| 工具 | `iperf3-ssl` | iperf3 测速（SSL） |
| 工具 | `lm-sensors` | 温度传感器 |
| 工具 | `lsof` | lsof |
| 工具 | `mtr-json` | mtr 路由追踪 |
| 工具 | `nload` | nload 实时流量 |
| 工具 | `openssh-sftp-server` | SFTP 服务端 |
| 工具 | `rsync` | rsync |
| 工具 | `rsyncd` | rsync 服务端 |
| 工具 | `screen` | screen 终端复用 |
| 工具 | `socat` | socat |
| 工具 | `speedtest-go` | 公网测速 |
| 工具 | `sysstat` | sysstat（sar/iostat） |
| 工具 | `tcpdump` | tcpdump 抓包 |
| 工具 | `tmux` | tmux 终端复用 |
| 工具 | `usbutils` | lsusb |
| 工具 | `vim-full` | Vim 完整版 |

## 亚瑟（135）

NSS / Wi-Fi 等由 target `DEFAULT_PACKAGES` 自动带入，不在此列。亚瑟 512MB，偏重应用不用时请关掉。

| 分类 | 包名 | 中文名 |
|---|---|---|
| 界面 | `luci` | LuCI 网页界面 |
| 界面 | `luci-i18n-banip-zh-cn` | IP 黑名单 · 简体中文 |
| 界面 | `luci-i18n-base-zh-cn` | LuCI 基础界面 · 简体中文 |
| 界面 | `luci-i18n-chrony-zh-cn` | Chrony 界面 · 简体中文 |
| 界面 | `luci-i18n-cifs-mount-zh-cn` | 挂载远程 SMB/CIFS · 简体中文 |
| 界面 | `luci-i18n-diskman-zh-cn` | 磁盘管理 · 简体中文 |
| 界面 | `luci-i18n-hd-idle-zh-cn` | 硬盘休眠 · 简体中文 |
| 界面 | `luci-i18n-mosdns-zh-cn` | MosDNS 分流 DNS · 简体中文 |
| 界面 | `luci-i18n-mwan3-zh-cn` | 多线负载均衡 · 简体中文 |
| 界面 | `luci-i18n-natmap-zh-cn` | NATMap 端口映射 · 简体中文 |
| 界面 | `luci-i18n-nlbwmon-zh-cn` | 网络带宽监视 · 简体中文 |
| 界面 | `luci-i18n-pbr-zh-cn` | 策略路由 · 简体中文 |
| 界面 | `luci-i18n-samba4-zh-cn` | Samba4 网络共享 · 简体中文 |
| 界面 | `luci-i18n-sqm-zh-cn` | SQM 智能队列 · 简体中文 |
| 界面 | `luci-i18n-statistics-zh-cn` | 实时统计（collectd） · 简体中文 |
| 界面 | `luci-i18n-upnp-zh-cn` | UPnP / NAT-PMP · 简体中文 |
| 界面 | `luci-i18n-watchcat-zh-cn` | 网络看门狗 · 简体中文 |
| 界面 | `luci-i18n-wechatpush-zh-cn` | 微信推送 · 简体中文 |
| LuCI 应用 | `luci-app-adguardhome` | AdGuard Home |
| LuCI 应用 | `luci-app-autoreboot` | 定时重启 |
| LuCI 应用 | `luci-app-banip` | IP 黑名单 |
| LuCI 应用 | `luci-app-chrony` | Chrony 界面 |
| LuCI 应用 | `luci-app-cifs-mount` | 挂载远程 SMB/CIFS |
| LuCI 应用 | `luci-app-cloudflared` | Cloudflare Tunnel 内网穿透 |
| LuCI 应用 | `luci-app-ddns-go` | DDNS-Go 动态域名 |
| LuCI 应用 | `luci-app-diskman` | 磁盘管理 |
| LuCI 应用 | `luci-app-filebrowser` | 文件浏览器 |
| LuCI 应用 | `luci-app-filebrowser-go` | FileBrowser 网页文件管理 |
| LuCI 应用 | `luci-app-hd-idle` | 硬盘休眠 |
| LuCI 应用 | `luci-app-irqbalance` | 中断均衡界面 |
| LuCI 应用 | `luci-app-mosdns` | MosDNS 分流 DNS |
| LuCI 应用 | `luci-app-mwan3` | 多线负载均衡 |
| LuCI 应用 | `luci-app-natmap` | NATMap 端口映射 |
| LuCI 应用 | `luci-app-nlbwmon` | 网络带宽监视 |
| LuCI 应用 | `luci-app-openclash` | OpenClash |
| LuCI 应用 | `luci-app-openlist` | OpenList 网盘挂载/列表程序 |
| LuCI 应用 | `luci-app-package-manager` | 软件包管理（安装/卸载） |
| LuCI 应用 | `luci-app-passwall` | PassWall |
| LuCI 应用 | `luci-app-pbr` | 策略路由 |
| LuCI 应用 | `luci-app-qbittorrent` | qBittorrent |
| LuCI 应用 | `luci-app-ramfree` | 释放内存 |
| LuCI 应用 | `luci-app-samba4` | Samba4 网络共享 |
| LuCI 应用 | `luci-app-sqm` | SQM 智能队列 |
| LuCI 应用 | `luci-app-statistics` | 实时统计（collectd） |
| LuCI 应用 | `luci-app-tailscale-community` | Tailscale 组网（社区版界面） |
| LuCI 应用 | `luci-app-transmission` | Transmission BT 下载 |
| LuCI 应用 | `luci-app-ttyd` | 网页终端 |
| LuCI 应用 | `luci-app-upnp` | UPnP / NAT-PMP |
| LuCI 应用 | `luci-app-watchcat` | 网络看门狗 |
| LuCI 应用 | `luci-app-wechatpush` | 微信推送 |
| LuCI 应用 | `luci-app-wifihistory` | Wi-Fi 终端连接历史 |
| LuCI 应用 | `luci-app-wifischedule` | WiFi 定时开关 |
| LuCI 应用 | `luci-app-zerotier` | ZeroTier 虚拟局域网 |
| LuCI 应用 | `luci-proto-wireguard` | WireGuard 接口协议 |
| 中文 | `luci-i18n-adguardhome-zh-cn` | AdGuard Home · 简体中文 |
| 中文 | `luci-i18n-autoreboot-zh-cn` | 定时重启 · 简体中文 |
| 中文 | `luci-i18n-cloudflared-zh-cn` | Cloudflare Tunnel · 简体中文 |
| 中文 | `luci-i18n-ddns-go-zh-cn` | DDNS-Go · 简体中文 |
| 中文 | `luci-i18n-filebrowser-go-zh-cn` | FileBrowser · 简体中文 |
| 中文 | `luci-i18n-filebrowser-zh-cn` | 文件浏览器 · 简体中文 |
| 中文 | `luci-i18n-irqbalance-zh-cn` | 中断均衡界面 · 简体中文 |
| 中文 | `luci-i18n-openlist-zh-cn` | OpenList · 简体中文 |
| 中文 | `luci-i18n-package-manager-zh-cn` | 软件包管理 · 简体中文 |
| 中文 | `luci-i18n-passwall-zh-cn` | PassWall · 简体中文 |
| 中文 | `luci-i18n-qbittorrent-zh-cn` | qBittorrent · 简体中文 |
| 中文 | `luci-i18n-ramfree-zh-cn` | 释放内存 · 简体中文 |
| 中文 | `luci-i18n-tailscale-community-zh-cn` | Tailscale 组网 · 简体中文 |
| 中文 | `luci-i18n-transmission-zh-cn` | Transmission · 简体中文 |
| 中文 | `luci-i18n-ttyd-zh-cn` | 网页终端 · 简体中文 |
| 中文 | `luci-i18n-wifihistory-zh-cn` | Wi-Fi 终端连接历史 · 简体中文 |
| 中文 | `luci-i18n-wifischedule-zh-cn` | WiFi 定时开关 · 简体中文 |
| 中文 | `luci-i18n-zerotier-zh-cn` | ZeroTier · 简体中文 |
| 系统 / 存储 | `block-mount` | 挂载点管理 |
| 系统 / 存储 | `chrony` | Chrony 时间同步 |
| 系统 / 存储 | `dnsmasq-full` | 完整版 DNS/DHCP |
| 系统 / 存储 | `e2fsprogs` | ext 文件系统工具 |
| 系统 / 存储 | `f2fs-tools` | F2FS 工具 |
| 系统 / 存储 | `filebrowser` | Filebrowser 网页文件管理 |
| 系统 / 存储 | `hdparm` | 硬盘参数 |
| 系统 / 存储 | `irqbalance` | 中断均衡 |
| 系统 / 存储 | `lsblk` | 列出块设备 |
| 系统 / 存储 | `lvm2` | LVM 逻辑卷 |
| 系统 / 存储 | `ntfs-3g` | NTFS（FUSE） |
| 系统 / 存储 | `qrencode` | 二维码生成（WireGuard） |
| 系统 / 存储 | `resize2fs` | ext 分区扩容 |
| 系统 / 存储 | `usbmuxd` | iPhone USB 连接 |
| 系统 / 存储 | `wifischedule` | WiFi 定时开关（后端） |
| 系统 / 存储 | `wireguard-tools` | WireGuard 工具 |
| 系统 / 存储 | `xfs-mkfs` | XFS 格式化 |
| 系统 / 存储 | `zram-swap` | zram 压缩内存交换 |
| 内核 / 监控 | `kmod-fs-autofs4` | 内核模块：autofs 自动挂载文件系统 |
| 内核 / 监控 | `kmod-fs-btrfs` | 内核模块：Btrfs 文件系统 |
| 内核 / 监控 | `kmod-fs-exfat` | 内核模块：exFAT 文件系统 |
| 内核 / 监控 | `kmod-fs-ext4` | 内核模块：ext4 文件系统 |
| 内核 / 监控 | `kmod-fs-f2fs` | 内核模块：F2FS 文件系统 |
| 内核 / 监控 | `kmod-fs-ntfs3` | 内核模块：NTFS3 内核读写驱动 |
| 内核 / 监控 | `kmod-fs-vfat` | 内核模块：FAT/VFAT 文件系统 |
| 内核 / 监控 | `kmod-fs-xfs` | 内核模块：XFS 文件系统 |
| 内核 / 监控 | `kmod-tcp-bbr` | 内核模块：TCP BBR 拥塞控制 |
| 内核 / 监控 | `kmod-usb-storage` | 内核模块：USB 存储 |
| 内核 / 监控 | `kmod-usb-storage-uas` | 内核模块：USB UAS 高速存储协议 |
| 内核 / 监控 | `kmod-usb3` | 内核模块：USB 3.0 控制器 |
| 内核 / 监控 | `prometheus-node-exporter-lua` | Prometheus 节点导出（lua） |
| 内核 / 监控 | `prometheus-node-exporter-lua-nat_traffic` | Prometheus 采集器：NAT 流量 |
| 内核 / 监控 | `prometheus-node-exporter-lua-netstat` | Prometheus 采集器：网络统计 |
| 内核 / 监控 | `prometheus-node-exporter-lua-openwrt` | Prometheus 采集器：OpenWrt 系统信息 |
| 内核 / 监控 | `prometheus-node-exporter-lua-thermal` | Prometheus 采集器：温度 |
| 内核 / 监控 | `prometheus-node-exporter-lua-uci_dhcp_host` | Prometheus 采集器：DHCP 静态主机 |
| 内核 / 监控 | `prometheus-node-exporter-lua-wifi` | Prometheus 采集器：Wi-Fi |
| 内核 / 监控 | `prometheus-node-exporter-lua-wifi_stations` | Prometheus 采集器：Wi-Fi 终端 |
| 工具 | `bind-dig` | dig DNS 查询 |
| 工具 | `btop` | btop 资源监视 |
| 工具 | `conntrack` | 连接跟踪工具 |
| 工具 | `conntrackd` | 连接跟踪同步守护 |
| 工具 | `drill` | drill DNS 查询 |
| 工具 | `ethtool-full` | 完整 ethtool |
| 工具 | `htop` | htop 进程监视 |
| 工具 | `iftop` | iftop 实时流量 |
| 工具 | `iotop` | iotop IO 监视 |
| 工具 | `iperf3-ssl` | iperf3 测速（SSL） |
| 工具 | `lm-sensors` | 温度传感器 |
| 工具 | `lsof` | lsof |
| 工具 | `mtr-json` | mtr 路由追踪 |
| 工具 | `nload` | nload 实时流量 |
| 工具 | `openssh-sftp-server` | SFTP 服务端 |
| 工具 | `rsync` | rsync |
| 工具 | `rsyncd` | rsync 服务端 |
| 工具 | `screen` | screen 终端复用 |
| 工具 | `socat` | socat |
| 工具 | `speedtest-go` | 公网测速 |
| 工具 | `sysstat` | sysstat（sar/iostat） |
| 工具 | `tcpdump` | tcpdump 抓包 |
| 工具 | `tmux` | tmux 终端复用 |
| 工具 | `usbutils` | lsusb |
| 工具 | `vim-full` | Vim 完整版 |
