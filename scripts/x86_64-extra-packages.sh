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

# clash-exporter：OpenClash / Mihomo 的 Prometheus exporter。
# 源码在 Ghostpanter/clash-exporter，OpenWrt 包装在 openwrt/Makefile。
# 编译时把 Go 源码放进包目录的 src/，Makefile 从 ./src 取。
rm -rf "$TMP/clash-exporter" package/extra/clash-exporter
# 固定到审查、测试过的提交，避免仓库后续改动直接进固件；升级时改这里的 SHA
CLASH_EXPORTER_COMMIT=03ac45885000a7d0d4cefd704afc34321fba8c94
git init -q "$TMP/clash-exporter"
git -C "$TMP/clash-exporter" fetch -q --depth 1 https://github.com/Ghostpanter/clash-exporter.git "$CLASH_EXPORTER_COMMIT"
git -C "$TMP/clash-exporter" checkout -q FETCH_HEAD
mkdir -p package/extra/clash-exporter/src
cp "$TMP/clash-exporter/openwrt/Makefile" package/extra/clash-exporter/Makefile
cp -a "$TMP/clash-exporter/openwrt/files" package/extra/clash-exporter/files
cp "$TMP/clash-exporter/main.go" "$TMP/clash-exporter/go.mod" "$TMP/clash-exporter/go.sum" package/extra/clash-exporter/src/
cp -a "$TMP/clash-exporter/collector" package/extra/clash-exporter/src/collector

# sing-box：完整版的 NaiveProxy 出站开关是 def_bool y（菜单里关不掉），一开就要编 libcronet（Chromium 网络栈），
# libcronet 又要先编 gn，gn 现在要求 C++23，GitHub ubuntu-22.04 上默认的 clang 14 不认 -std=c++23，直接编译失败；
# 而且即使只装 sing-box-tiny，只要这个开关是 y，编 sing-box 时也会先去编 libcronet。
# 这里把它改成默认关：sing-box 其他功能（HomeProxy / PassWall 用到的 QUIC、uTLS、WireGuard、gVisor 等）不受影响，
# 只是少了 naive 出站（客户端连 NaiveProxy 服务器）。
SB_MK=feeds/packages/net/sing-box/Makefile
if [ -f "$SB_MK" ]; then
  sed -i '/config SING_BOX_BUILD_NAIVE_OUTBOUND/{n;s/def_bool y/def_bool n/}' "$SB_MK"
  if grep -A1 'config SING_BOX_BUILD_NAIVE_OUTBOUND' "$SB_MK" | grep -q 'def_bool y'; then
    echo "警告：没能关掉 sing-box 的 NaiveProxy 出站，libcronet / gn 可能仍会被编译" >&2
  fi
fi

# perf：上游 Makefile 写死了 NO_LIBZSTD=1，但内核 6.18 的 perf 会检测「libelf 是否需要 zstd」，
# 检测方法只是试着链接 -lelf -lz -lzstd。整机编译时 libzstd 已经先编好放进 staging（别的包要用），
# 检测就会通过，再碰上 NO_LIBZSTD=1 直接报错：
#   Makefile.config:581: *** Error: libzstd is required by libelf, please do not set NO_LIBZSTD.
# （单独编 perf 时 staging 里还没有 libzstd，检测不通过，所以不报错，看起来像偶发问题。）
# 修法：去掉 NO_LIBZSTD=1，并让 perf 依赖 libzstd（保证先编 zstd、结果稳定）；
# libzstd 固件里本来就有，不增加体积，perf 顺带支持 zstd 压缩的 perf.data。
PERF_MK=package/devel/perf/Makefile
if [ -f "$PERF_MK" ] && grep -q 'NO_LIBZSTD=1' "$PERF_MK"; then
  sed -i '/^[[:space:]]*NO_LIBZSTD=1[[:space:]]*\\$/d' "$PERF_MK"
  grep -q '+libzstd' "$PERF_MK" || sed -i 's/^\([[:space:]]*DEPENDS:=[[:space:]]*+libelf\)/\1 +libzstd/' "$PERF_MK"
  if grep -q 'NO_LIBZSTD=1' "$PERF_MK" || ! grep -q '+libzstd' "$PERF_MK"; then
    echo "错误：没能给 perf 去掉 NO_LIBZSTD / 加上 libzstd 依赖，请检查 $PERF_MK" >&2
    exit 1
  fi
  echo "perf：已去掉 NO_LIBZSTD，依赖 libzstd"
fi

# 删掉了 feeds 里的 mosdns，重建索引，避免 feeds install 时出现重名包
./scripts/feeds update -i packages

# 内核配置补丁：给 DETECT_HUNG_TASK 等选项带出来的新子选项定值，避免编译内核时卡在 "(NEW)" 交互提问
bash "$(dirname "$0")/x86_64-kernel-fixups.sh"
