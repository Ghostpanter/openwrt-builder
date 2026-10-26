#!/usr/bin/env bash
# 检查并清掉 OpenWrt cargo 缓存（dl/cargo）里下载不完整 / 损坏的 crate。
#
# 症状（Rust 包，如 shadowsocks-rust）：
#   failed to download `tokio v1.48.0` ... failed to unpack ... unexpected end of file
# 原因：dl/cargo/registry/cache/<源>/<crate>-<版本>.crate 被截断（中途断网 / 被杀 / 磁盘满），
#       cargo 每次都用这个坏包解压，不会自己重新下载。
# 做法：对每个 .crate 做 gzip -t 完整性检查，坏的连同 registry/src 下对应的解压目录一起删掉，
#       下次编译 cargo 会重新下载。只删坏包，好包不动；不联网。
#
# 用法：
#   bash scripts/fix-cargo-cache.sh [openwrt 源码目录 | CARGO_HOME 目录]
#   不给参数时用当前目录（应在 openwrt 源码根运行）。local-build.sh 编译前会自动调用。
set -euo pipefail

arg="${1:-.}"
if [ -d "$arg/registry" ]; then
	CARGO_DIR="$arg"
elif [ -d "$arg/dl/cargo" ]; then
	CARGO_DIR="$arg/dl/cargo"
elif [ -d "$arg/dl" ] || [ -f "$arg/rules.mk" ]; then
	echo "cargo 缓存：$arg/dl/cargo 还不存在，跳过（还没编过 Rust 包）"
	exit 0
else
	echo "错误：$arg 不像 openwrt 源码根（没有 dl/ 或 rules.mk），也不是 CARGO_HOME（没有 registry/）" >&2
	echo "      用法：bash $0 ~/openwrt-builder/build/x86_64/openwrt" >&2
	exit 1
fi

CACHE="$CARGO_DIR/registry/cache"
SRCD="$CARGO_DIR/registry/src"
if [ ! -d "$CACHE" ]; then
	echo "cargo 缓存：$CACHE 不存在，跳过"
	exit 0
fi
command -v gzip >/dev/null 2>&1 || { echo "警告：没有 gzip，跳过 cargo 缓存检查" >&2; exit 0; }

total=0
bad=0
while IFS= read -r -d '' f; do
	total=$((total + 1))
	if ! gzip -t "$f" 2>/dev/null; then
		bad=$((bad + 1))
		idx=$(basename "$(dirname "$f")")
		name=$(basename "$f" .crate)
		echo "损坏：$idx/$name.crate，删除（连同解压目录）"
		rm -f "$f"
		rm -rf "${SRCD:?}/$idx/$name"
	fi
done < <(find "$CACHE" -mindepth 2 -maxdepth 2 -type f -name '*.crate' -print0)

# 坏包是解压到一半失败时，解压目录里没有 .cargo-ok；cargo 下次会自己重解压，这里顺手删掉更干净
partial=0
if [ -d "$SRCD" ]; then
	while IFS= read -r -d '' d; do
		if [ ! -e "$d/.cargo-ok" ]; then
			partial=$((partial + 1))
			echo "未解压完整：${d#"$SRCD"/}，删除"
			rm -rf "$d"
		fi
	done < <(find "$SRCD" -mindepth 2 -maxdepth 2 -type d -print0)
fi

echo "cargo 缓存检查：$total 个 crate，删除损坏 $bad 个、未解压完整目录 $partial 个（$CARGO_DIR）"
