#!/bin/bash
# netdata（ImmortalWrt feeds，1.38.1）：关掉 Netdata Cloud / ACLK，去掉 protobuf-compat 依赖。
# 用法：在 openwrt 源码根目录执行 bash <仓库>/scripts/fix-netdata.sh（也可以把源码根目录当第一个参数）。
# 可重复执行（已改过就跳过）。x86_64-extra-packages.sh 会自动调用它，local-build.sh 编译前还会再调用一次。
# 另外会检查 build_dir 里已有的 netdata 源码树：如果它当初不是用 --disable-cloud 配置的（旧的 .configured / .built 还在），
# 就整个删掉，强制下次重新解包、configure。否则 make 认为已经配置过，继续编 aclk/schema-wrappers，照样报 port_def.inc。
#
# 原因：ImmortalWrt 的 netdata 没加 --disable-cloud，会编 aclk/schema-wrappers/*.cc，要 protobuf 头文件；
# 它改用 protobuf-compat（commit 9ba2f68）后，pkg-config 给出的是不带 STAGING_DIR 的 -I/usr/protobuf-compat/include，
# 交叉编译找不到头文件：
#   connection.pb.h: fatal error: google/protobuf/port_def.inc: No such file or directory
# 修法和 OpenWrt 官方 netdata 包一致：--disable-cloud（旁路由用不到 Netdata Cloud，本地网页 / LuCI 监控照常），
# 去掉 protobuf-compat 的运行 / 编译依赖和那段 protobuf 专用 CPPFLAGS/CXXFLAGS/LDFLAGS。
# libstdcpp / libatomic 保留：netdata 1.38 的可执行文件固定用 C++ 链接器链接。
set -euo pipefail

ROOT=${1:-.}
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
find_mk() {
  local mk="$1/feeds/packages/admin/netdata/Makefile" alt="$1/package/feeds/packages/netdata/Makefile"
  if [ -f "$mk" ]; then echo "$mk"; return 0; fi
  # package/feeds/packages/netdata 通常是指向 feeds 的符号链接，解析成真实文件再改
  if [ -e "$alt" ]; then readlink -f "$alt"; return 0; fi
  return 1
}
if MK=$(find_mk "$ROOT"); then
  TOP=$ROOT
else
  # 没传参数且不在源码根：在仓库根目录执行时，自动试 build/x86_64/openwrt
  if [ -z "${1:-}" ] && MK=$(find_mk "$SCRIPT_DIR/../build/x86_64/openwrt"); then
    TOP="$SCRIPT_DIR/../build/x86_64/openwrt"
    echo "netdata：当前目录不是 openwrt 源码根，改用 $TOP"
  else
    echo "错误：在 $(cd "$ROOT" 2>/dev/null && pwd || echo "$ROOT") 下找不到 netdata 的 Makefile" >&2
    echo "  （查了 feeds/packages/admin/netdata/Makefile 和 package/feeds/packages/netdata/Makefile）" >&2
    echo "  请在 openwrt 源码根目录（例如 build/x86_64/openwrt）执行，或把源码根路径作为第一个参数：" >&2
    echo "    bash scripts/fix-netdata.sh ~/openwrt-builder/build/x86_64/openwrt" >&2
    echo "  若源码根下也没有，先执行 ./scripts/feeds update -a && ./scripts/feeds install -a" >&2
    exit 1
  fi
fi
echo "netdata：修改 $MK"

HAS_CLOUD=0
grep -q -- '--disable-cloud' "$MK" && HAS_CLOUD=1
awk -v added="$HAS_CLOUD" '
  # 去掉 PKG_BUILD_DEPENDS:=protobuf-compat/host
  /^PKG_BUILD_DEPENDS:=[[:space:]]*protobuf-compat\/host[[:space:]]*$/ { next }
  # 去掉 protobuf-compat 专用的 CONFIGURE_VARS 整段（多行续行）
  /^CONFIGURE_VARS[[:space:]]*\+=/ { inblk=1; blk=$0 "\n"; if ($0 !~ /\\$/) { inblk=0; if (blk !~ /protobuf-compat/) printf "%s", blk; blk="" } ; next }
  inblk { blk=blk $0 "\n"; if ($0 !~ /\\$/) { inblk=0; if (blk !~ /protobuf-compat/) printf "%s", blk; blk="" } ; next }
  # 在 Build/Configure 前补 --disable-cloud（已经有了就不加：重复执行 / 上游以后自己加了）
  /^define Build\/Configure/ && !added { print "CONFIGURE_ARGS += --disable-cloud"; print ""; added=1 }
  { gsub(/[[:space:]]\+protobuf-compat/, ""); print }
' "$MK" > "$MK.tmp"

# 内容没变就不覆盖，免得每次都刷新 Makefile 时间戳、导致 netdata 每次整包重编
if cmp -s "$MK.tmp" "$MK"; then
  rm -f "$MK.tmp"
else
  mv "$MK.tmp" "$MK"
fi

if grep -q 'protobuf-compat' "$MK" || ! grep -q -- '--disable-cloud' "$MK"; then
  echo "错误：netdata Makefile 没改干净，请检查 $MK" >&2
  grep -n -- 'protobuf-compat\|--disable-cloud' "$MK" >&2 || true
  exit 1
fi
echo "netdata：已 --disable-cloud 并去掉 protobuf-compat"

# 已有的 netdata 编译目录：config.status 里没有 --disable-cloud（旧 Makefile 配置的），或者没配置完的残留，整个删掉，
# 强制重新 prepare + configure。用 --disable-cloud 配置过的保留，不影响增量编译。
shopt -s nullglob
for d in "$TOP"/build_dir/target-*/netdata-v*/; do
  d=${d%/}
  if [ -f "$d/config.status" ]; then
    grep -q -- '--disable-cloud' "$d/config.status" && continue
  else
    # 开了 CONFIG_AUTOREMOVE 时，编完只剩 .built 等标记、源码被删，没法检查也不需要检查；
    # 没有 config.status 又没有 .built 的，是只解包了一半 / 配置失败的残留，删掉
    [ -f "$d/.built" ] && continue
  fi
  echo "netdata：$d 不是用 --disable-cloud 配置的（旧的编译目录），删掉强制重新 configure"
  rm -rf "$d"
done
