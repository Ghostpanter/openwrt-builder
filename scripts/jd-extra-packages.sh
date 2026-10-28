#!/usr/bin/env bash
# 雅典娜 / 亚瑟专用：在 ./scripts/feeds update -a 之后、feeds install -a 之前执行
# （工作目录为 openwrt 源码根目录）。只拉 Tailscale 的 LuCI（与 x86 同一来源）。
set -euo pipefail

# Tailscale：按 asvow/luci-app-tailscale 的说明，去掉 tailscale 包自带的启动脚本和配置，改用 LuCI 插件提供的
sed -i '/\/etc\/init\.d\/tailscale/d;/\/etc\/config\/tailscale/d;' feeds/packages/net/tailscale/Makefile
rm -rf package/extra/luci-app-tailscale
git clone --depth 1 https://github.com/asvow/luci-app-tailscale package/extra/luci-app-tailscale
rm -rf package/extra/luci-app-tailscale/.git
