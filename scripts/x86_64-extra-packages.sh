#!/bin/bash
# x86_64 专用：在 ./scripts/feeds update -a 之后、feeds install -a 之前执行（工作目录为 openwrt 源码根目录）
# ImmortalWrt 自带的 luci/packages 已经有 OpenClash、PassWall、AdGuard Home、ZeroTier、DiskMan、Docker 等，
# 这里只补上游没有的两个 LuCI 插件：MosDNS（sbwml）和 Tailscale（asvow）。
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

# 删掉了 feeds 里的 mosdns，重建索引，避免 feeds install 时出现重名包
./scripts/feeds update -i packages
