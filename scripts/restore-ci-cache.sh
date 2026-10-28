#!/usr/bin/env bash
# CI 用：从本仓库的 GitHub Release（ci-cache-<机型>-<上游短SHA>，由 upload-ci-cache.sh 上传）恢复编译缓存。
# 用法：bash scripts/restore-ci-cache.sh <机型> <上游短SHA> <openwrt 目录>
# 环境变量：GH_TOKEN、GITHUB_REPOSITORY；可选 GITHUB_OUTPUT、GITHUB_STEP_SUMMARY、RUNNER_TEMP。
# 任何问题都只打警告并以 0 退出（软失败），CI 回到 Actions 缓存 / 从头编译。
# 输出（GITHUB_OUTPUT）：tag、exact（上游 SHA 完全一致）、toolchain、ccache、dl（true/false）。
set -uo pipefail

DEVICE="${1:?机型}"
SHA="${2:?上游短SHA}"
OW="${3:?openwrt 目录}"
REPO="${GITHUB_REPOSITORY:?}"
OUT="${GITHUB_OUTPUT:-/dev/null}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
TMP="${RUNNER_TEMP:-/tmp}/ci-cache"

note() { echo "::notice::$*"; }
warn() { echo "::warning::$*"; }
# 输出在退出时统一写一次（每个键只写一次）
declare -A O=([tag]="" [exact]=false [toolchain]=false [ccache]=false [dl]=false)
setout() { O[$1]="$2"; }
flush() { local k; for k in tag exact toolchain ccache dl; do echo "$k=${O[$k]}" >> "$OUT"; done; }
trap flush EXIT

OW=$(cd "$OW" && pwd -P) || { warn "找不到 $3"; exit 0; }
rm -rf "$TMP"
mkdir -p "$TMP"

# 1. 找 Release：优先上游 SHA 完全一致的；没有就用该机型最新的一个（增量：只重编有变化的工具）
mapfile -t TAGS < <(gh release list --repo "$REPO" --limit 200 --json tagName,createdAt \
	--jq 'sort_by(.createdAt) | reverse | .[].tagName' 2>/dev/null | grep -E "^ci-cache-$DEVICE-[0-9a-f]+$" || true)
TAG=""
for t in "${TAGS[@]}"; do [ "$t" = "ci-cache-$DEVICE-$SHA" ] && TAG="$t"; done
EXACT=false
if [ -n "$TAG" ]; then
	EXACT=true
elif [ "${#TAGS[@]}" -gt 0 ]; then
	TAG="${TAGS[0]}"
	note "没有 ci-cache-$DEVICE-$SHA，改用最新的 $TAG（上游有更新，变动的工具会增量重编）"
else
	echo "没有 ci-cache-$DEVICE-* Release，跳过（本地编译后可用 pack-ci-cache.sh / upload-ci-cache.sh 上传）"
	exit 0
fi
setout tag "$TAG"
setout exact "$EXACT"

# 2. 元数据
if ! gh release download "$TAG" --repo "$REPO" -D "$TMP" -p ci-cache.env -p SHA256SUMS; then
	warn "$TAG 缺 ci-cache.env / SHA256SUMS（可能还在上传），跳过"
	exit 0
fi
env_get() { sed -n "s/^$1=//p" "$TMP/ci-cache.env" | head -n 1; }
[ "$(env_get DEVICE)" = "$DEVICE" ] || { warn "$TAG 的 DEVICE 不是 $DEVICE，跳过"; exit 0; }
SRC_TOPDIR=$(env_get TOPDIR)
CACHE_SHA=$(env_get UPSTREAM_SHA)
echo "缓存来源：$(env_get OS_ID) $(env_get OS_VERSION) glibc $(env_get GLIBC)，源码路径 $SRC_TOPDIR，上游 $(env_get UPSTREAM_SHA)，打包于 $(env_get CREATED)"

# 编译机工具链接了打包机的系统库：打包机 glibc 不能比 runner 新（旧的可以），解压后再用 ldd 检查一遍；ccache 不受影响
# shellcheck disable=SC1091
. /etc/os-release
USE_TC=1
RUN_GLIBC=$(getconf GNU_LIBC_VERSION | awk '{print $2}')
SRC_GLIBC=$(env_get GLIBC)
if [ -z "$SRC_GLIBC" ] || [ "$(printf '%s\n%s\n' "$SRC_GLIBC" "$RUN_GLIBC" | sort -V | tail -n 1)" != "$RUN_GLIBC" ]; then
	warn "缓存在 $(env_get OS_ID) $(env_get OS_VERSION)（glibc ${SRC_GLIBC:-未知}）上打包，比 runner 的 $ID $VERSION_ID（glibc $RUN_GLIBC）新，编译机工具在这里跑不了，不用其中的工具链（请用 Ubuntu 24.04 或 Debian 12 打包）"
	USE_TC=0
elif [ "$(env_get OS_ID) $(env_get OS_VERSION)" != "$ID $VERSION_ID" ]; then
	echo "缓存来自 $(env_get OS_ID) $(env_get OS_VERSION)，runner 是 $ID $VERSION_ID；glibc 兼容，解压后检查动态库"
fi
if [ -e "$OW/staging_dir/host" ]; then
	echo "openwrt/staging_dir/host 已存在，不覆盖工具链"
	USE_TC=0
fi

assets() { gh release view "$TAG" --repo "$REPO" --json assets --jq '.assets[].name' | grep -E "^$1\.tar\.zst\.part[0-9]+$" | sort; }

# 下载 → 校验 → 解压 一个组件；失败返回 1
restore() {
	local name="$1" s parts p
	s=$(date +%s)
	mapfile -t parts < <(assets "$name")
	[ "${#parts[@]}" -gt 0 ] || return 2
	echo "==> 下载 $name（${#parts[@]} 个切片）"
	for p in "${parts[@]}"; do
		gh release download "$TAG" --repo "$REPO" -D "$TMP" -p "$p" --clobber || return 1
	done
	(cd "$TMP" && grep -E " $name\.tar\.zst\.part[0-9]+$" SHA256SUMS | sha256sum -c --quiet -) || { warn "$name 校验失败"; return 1; }
	echo "    下载 $(du -ch "$TMP/$name".tar.zst.part* | tail -n 1 | cut -f1)，解压到 openwrt/"
	cat "${parts[@]/#/$TMP/}" | zstd -d -q -T0 --long=27 | tar -x -C "$OW" || return 1
	rm -f "$TMP/$name".tar.zst.part*
	echo "    完成，用时 $(( $(date +%s) - s )) 秒"
}

RESTORED=()
if [ "$USE_TC" -eq 1 ]; then
	restore toolchain; rc=$?
	if [ "$rc" -eq 0 ]; then
		# 检查：所有编译机工具 / 工具链可执行文件在 runner 上都能找到依赖的动态库，并且 mkhash 能运行
		bad=$(find "$OW/staging_dir/host/bin" "$OW"/staging_dir/toolchain-*/bin "$OW"/staging_dir/toolchain-*/libexec \
			-type f -perm -u+x -size +1k 2>/dev/null | while read -r f; do
				[ "$(head -c 4 "$f" | od -An -c | tr -d ' ')" = '177ELF' ] || continue
				ldd "$f" 2>&1 | grep -qE 'not found' && echo "${f#"$OW"/}: $(ldd "$f" 2>&1 | grep -E 'not found' | head -n 1 | xargs)"
			done | head -n 10)
		if [ -n "$bad" ]; then
			# 上游 SHA 不一致时旧缓存缺库很常见，用 notice；完全一致仍失败才 warning
			msg="恢复的编译机工具缺动态库，丢弃工具链缓存：$(echo "$bad" | head -n 3 | paste -sd';' -)"
			if [ "$EXACT" = true ]; then warn "$msg"; else note "$msg"; fi
			echo "$bad"
			rc=1
		elif "$OW/staging_dir/host/bin/mkhash" md5 </dev/null >/dev/null 2>&1; then
			setout toolchain true
			RESTORED+=("工具和工具链：$(du -sh "$OW/staging_dir/host" "$OW"/staging_dir/toolchain-* "$OW/build_dir/host" "$OW"/build_dir/toolchain-* 2>/dev/null | awk -v p="$OW/" '{sub(p, "", $2); printf "%s%s %s", (NR > 1 ? "，" : ""), $2, $1}')")
		else
			msg="恢复的 staging_dir/host/bin/mkhash 无法运行，丢弃工具链缓存"
			if [ "$EXACT" = true ]; then warn "$msg"; else note "$msg"; fi
			rc=1
		fi
	fi
	if [ "$rc" -eq 1 ]; then
		msg="工具链缓存恢复失败，删掉解压了一半的目录，改用 Actions 缓存 / 从头编译"
		if [ "$EXACT" = true ]; then warn "$msg"; else note "$msg"; fi
		rm -rf "$OW/staging_dir/host" "$OW"/staging_dir/toolchain-* "$OW/build_dir/host" "$OW"/build_dir/toolchain-*
	elif [ "$rc" -eq 2 ]; then
		echo "$TAG 里没有 toolchain，跳过"
	fi
fi
# ccache 的结果按「编译器文件的修改时间」匹配：工具链没从这里恢复时，交叉编译器是 CI 现编的，本地 ccache 基本不命中，不下载
if [ "${O[toolchain]}" != true ]; then
	echo "工具链没有从 Release 恢复，跳过其中的 ccache（编译器不同，命中不了）"
elif restore ccache; then
	setout ccache true
	RESTORED+=("ccache：$(du -sh "$OW/.ccache" | cut -f1)")
fi
if [ ! -e "$OW/dl" ] || [ -z "$(ls -A "$OW/dl" 2>/dev/null)" ]; then
	if restore dl; then
		setout dl true
		RESTORED+=("dl：$(du -sh "$OW/dl" | cut -f1)")
	fi
fi
rm -rf "$TMP"

# 3. 打包机的源码绝对路径会写进编译机工具（pkg-config、libtool、autom4te 等）：
#    在 runner 上把那个路径软链接到这里的 openwrt，路径不同也能直接用
if [ "${O[toolchain]}" = true ] && [ -n "$SRC_TOPDIR" ] && [ "$SRC_TOPDIR" != "$OW" ]; then
	if [ -L "$SRC_TOPDIR" ] || [ ! -e "$SRC_TOPDIR" ]; then
		sudo mkdir -p "$(dirname "$SRC_TOPDIR")" && sudo ln -sfn "$OW" "$SRC_TOPDIR" &&
			echo "已建软链接 $SRC_TOPDIR -> $OW（兼容缓存里的绝对路径）"
	else
		warn "$SRC_TOPDIR 在 runner 上已存在且不是软链接，没法兼容缓存里的绝对路径"
	fi
fi

if [ "${#RESTORED[@]}" -eq 0 ]; then
	echo "没有从 $TAG 恢复任何内容"
	exit 0
fi
{
	echo "### 从 Release 恢复的编译缓存：$TAG"
	[ "$EXACT" = true ] || echo "（上游 SHA 不一致：缓存是 $CACHE_SHA，本次是 $SHA，变动部分会增量重编）"
	for r in "${RESTORED[@]}"; do echo "- $r"; done
} | tee -a "$SUMMARY"
