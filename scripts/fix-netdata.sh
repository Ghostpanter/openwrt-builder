#!/bin/bash
# netdata（ImmortalWrt feeds，1.38.1）：关掉 Netdata Cloud / ACLK，去掉 protobuf-compat 依赖。
# 用法：在 openwrt 源码根目录执行 bash <仓库>/scripts/fix-netdata.sh（也可以把源码根目录当第一个参数）。
# 可重复执行（已改过就跳过）。x86_64-extra-packages.sh 会自动调用它。
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
MK="$ROOT/feeds/packages/admin/netdata/Makefile"
if [ ! -f "$MK" ]; then
  echo "netdata：没有 $MK，跳过"
  exit 0
fi

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

mv "$MK.tmp" "$MK"

if grep -q 'protobuf-compat' "$MK" || ! grep -q -- '--disable-cloud' "$MK"; then
  echo "错误：netdata Makefile 没改干净，请检查 $MK" >&2
  grep -n -- 'protobuf-compat\|--disable-cloud' "$MK" >&2 || true
  exit 1
fi
echo "netdata：已 --disable-cloud 并去掉 protobuf-compat"
