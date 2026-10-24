#!/bin/bash
# x86_64 专用：在 ./scripts/feeds update -a 之后、feeds install -a 之前执行（工作目录为 openwrt 源码根目录）
# ImmortalWrt 自带的 luci/packages 已经有 OpenClash、PassWall、AdGuard Home、ZeroTier、DiskMan、Docker 等，
# 这里只补上游没有的：MosDNS（sbwml）、Tailscale（asvow）、Lucky（gdy666）、EasyTier（EasyTier 官方）、定时控制（gaobin89）、Nikki（nikkinikki-org）。
set -euo pipefail

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# MosDNS：luci-app-mosdns 需要 sbwml 打过补丁的 mosdns，且两边都带 /etc/init.d/mosdns，
# 所以删掉 feeds 里的 mosdns，换成 sbwml 的 mosdns + geo2txt + luci-app-mosdns；
# v2ray-geoip / v2ray-geosite 继续用 ImmortalWrt 自带的（PassWall 也用它）。
rm -rf feeds/packages/net/mosdns package/feeds/packages/mosdns
git clone --depth 1 -b v5 https://github.com/sbwml/luci-app-mosdns "$TMP/mosdns"
rm -rf package/extra/mosdns package/extra/geo2txt package/extra/luci-app-mosdns
mkdir -p package/extra
cp -r "$TMP/mosdns/mosdns" "$TMP/mosdns/geo2txt" "$TMP/mosdns/luci-app-mosdns" package/extra/

# Tailscale：按 asvow/luci-app-tailscale 的说明，去掉 tailscale 包自带的启动脚本和配置，改用 LuCI 插件提供的
sed -i '/\/etc\/init\.d\/tailscale/d;/\/etc\/config\/tailscale/d;' feeds/packages/net/tailscale/Makefile
rm -rf package/extra/luci-app-tailscale
git clone --depth 1 https://github.com/asvow/luci-app-tailscale package/extra/luci-app-tailscale
rm -rf package/extra/luci-app-tailscale/.git

# Lucky：ImmortalWrt feeds 里没有，用 gdy666 官方的 lucky + luci-app-lucky
# （lucky 包下载的是作者发布的预编译二进制）
rm -rf "$TMP/lucky" package/extra/lucky package/extra/luci-app-lucky
git clone --depth 1 https://github.com/gdy666/luci-app-lucky "$TMP/lucky"
cp -r "$TMP/lucky/lucky" "$TMP/lucky/luci-app-lucky" package/extra/

# EasyTier：ImmortalWrt feeds 里没有，用 EasyTier 官方的 easytier + luci-app-easytier
# （easytier 包下载的是官方 GitHub Release 的预编译二进制；Makefile 引用上一级的 version.mk，所以整体放进一个目录）
rm -rf "$TMP/easytier" package/extra/easytier
git clone --depth 1 https://github.com/EasyTier/luci-app-easytier "$TMP/easytier"
mkdir -p package/extra/easytier
cp -r "$TMP/easytier/version.mk" "$TMP/easytier/easytier" "$TMP/easytier/luci-app-easytier" package/extra/easytier/

# 定时控制（家长控制，按 MAC + 时段断网）：ImmortalWrt feeds 里没有，用 gaobin89 的 JS 版（支持 fw4/nftables，自带中文翻译）
rm -rf "$TMP/timecontrol" package/extra/luci-app-timecontrol
git clone --depth 1 https://github.com/gaobin89/luci-app-timecontrol "$TMP/timecontrol"
cp -r "$TMP/timecontrol/luci-app-timecontrol" package/extra/

# Nikki（mihomo 内核的透明代理，仅支持 firewall4）：ImmortalWrt feeds 里没有 nikki / mihomo，不会重名。
# 只拷稳定版内核 mihomo-meta（提供虚拟包 mihomo），不拷 mihomo-alpha，免得两个互斥的包同时出现
rm -rf "$TMP/nikki" package/extra/nikki
git clone --depth 1 https://github.com/nikkinikki-org/OpenWrt-nikki "$TMP/nikki"
mkdir -p package/extra/nikki
cp -r "$TMP/nikki/nikki" "$TMP/nikki/mihomo-meta" "$TMP/nikki/luci-app-nikki" package/extra/nikki/

# 删掉了 feeds 里的 mosdns，重建索引，避免 feeds install 时出现重名包
./scripts/feeds update -i packages
