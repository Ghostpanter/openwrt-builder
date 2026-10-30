#!/usr/bin/env bash
# 雅典娜 / 亚瑟专用：在 ./scripts/feeds update -a 之后、feeds install -a 之前执行
# （工作目录为 openwrt 源码根目录）。
# 拉取 MosDNS（sbwml，与 x86 同源）和雅典娜 LED（unraveloop；仅 athena.config 勾选）。
# Tailscale 用上游官方 luci-app-tailscale-community，不再拉 asvow。
set -euo pipefail

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# MosDNS：ImmortalWrt luci 没有 luci-app-mosdns，且它需要 sbwml 打过补丁的 mosdns（两边都带 /etc/init.d/mosdns），
# 所以删掉 feeds 里的 mosdns，换成 sbwml 的 mosdns + geo2txt + luci-app-mosdns（与 x86 相同）；
# v2ray-geoip / v2ray-geosite 继续用 feeds 自带的。
rm -rf feeds/packages/net/mosdns package/feeds/packages/mosdns
git clone --depth 1 -b v5 https://github.com/sbwml/luci-app-mosdns "$TMP/mosdns"
rm -rf package/extra/mosdns package/extra/geo2txt package/extra/luci-app-mosdns
mkdir -p package/extra
cp -r "$TMP/mosdns/mosdns" "$TMP/mosdns/geo2txt" "$TMP/mosdns/luci-app-mosdns" package/extra/

# Athena LED：京东云雅典娜 AX6600 点阵屏（Rust 预编译二进制 + LuCI JS 界面）
# 源：unraveloop/JDC-AX6600-Athena-LED-Controller；仅 configs/athena.config 勾选。
rm -rf "$TMP/athena-led-src" package/extra/athena-led package/extra/luci-app-athena-led
git clone --depth 1 https://github.com/unraveloop/JDC-AX6600-Athena-LED-Controller "$TMP/athena-led-src"
cp -r "$TMP/athena-led-src/athena-led" "$TMP/athena-led-src/luci-app-athena-led" package/extra/
rm -rf package/extra/athena-led/.git package/extra/luci-app-athena-led/.git 2>/dev/null || true

# 删掉了 feeds 里的 mosdns，重建索引，避免 feeds install 时出现重名包
./scripts/feeds update -i packages
