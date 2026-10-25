#!/usr/bin/env bash
# 把本地编好的「耗时部分」打包，上传到 GitHub Release 后给 CI 复用（CI 会自动下载，跳过工具/工具链，ccache 大量命中）。
# 用法见 ./scripts/pack-ci-cache.sh --help
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib/proxy.sh
. "$REPO_ROOT/scripts/lib/proxy.sh"

usage() {
	cat <<'USAGE'
用法：./scripts/pack-ci-cache.sh [选项] <机型 | openwrt 源码目录>

机型（和 local-build.sh 一样，打包的是 build/<机型>/openwrt）：
  x86 | x86_64        ys | arthur        ydn | athena
也可以直接给源码目录，例如 build/x86_64/openwrt，或在源码目录里运行时给 .

默认打包：
  toolchain.tar.zst   staging_dir/host、staging_dir/toolchain-*、build_dir/host、build_dir/toolchain-*
                      （编译机工具 + 交叉工具链；build_dir 里有「已编完」标记，四个目录缺一不可）
  ccache.tar.zst      .ccache（C/C++ 编译缓存，node、内核等第二次编译能大量命中）

选项：
  --no-ccache         不打包 ccache
  --with-dl           另外打包 dl/（源码包，3–4 GB，通常从镜像下载也不慢，按需）
  -l, --level N       zstd 压缩级别 1–19，默认 10（19 更小但慢很多）
  -o DIR              输出目录，默认 build/ci-cache/<机型>-<上游短SHA>
  --proxy URL         接受但用不到：打包完全在本地，不联网（方便和其他脚本写同一串参数）
  --force             系统 glibc 比 CI（Ubuntu 24.04，glibc 2.39）新时也打包（CI 用不上，一般不需要）
  -h, --help          显示本帮助

输出：每个压缩包按 1900 MB 切成 *.tar.zst.partNN（GitHub Release 单个文件上限 2 GB），
另有 ci-cache.env（机型、上游 SHA、源码绝对路径、系统/glibc 版本）和 SHA256SUMS。
大小参考（x86_64）：toolchain 约 1.5 GB，ccache 约 2–3 GB，dl 约 3–4 GB。

之后上传：./scripts/upload-ci-cache.sh <机型>
USAGE
}

die() { echo "错误：$*" >&2; exit 1; }
warn() { echo "警告：$*" >&2; }

TARGET=""
WITH_CCACHE=1
WITH_DL=0
LEVEL=10
OUT=""
FORCE=0
# CI runner（ubuntu-24.04）的 glibc 版本：打包机的 glibc 不能比它新，否则编译机工具在 CI 上跑不了
CI_GLIBC=2.39
while [ $# -gt 0 ]; do
	case "$1" in
		-h | --help) usage; exit 0 ;;
		--no-ccache) WITH_CCACHE=0 ;;
		--with-dl) WITH_DL=1 ;;
		-l | --level) [ $# -ge 2 ] || die "$1 后面要跟级别"; LEVEL="$2"; shift ;;
		--force) FORCE=1 ;;
		-o) [ $# -ge 2 ] || die "-o 后面要跟目录"; OUT="$2"; shift ;;
		--proxy) [ $# -ge 2 ] || die "--proxy 后面要跟代理地址"; PROXY_URL="$2"; shift ;;
		--proxy=*) PROXY_URL="${1#--proxy=}" ;;
		-*) die "未知选项 $1（看 --help）" ;;
		*) [ -z "$TARGET" ] || die "只能指定一个机型或目录"; TARGET="$1" ;;
	esac
	shift
done
[ -n "$TARGET" ] || { usage; exit 1; }
[ -z "$PROXY_URL" ] || echo "提示：打包不联网，--proxy 不起作用（上传时给 upload-ci-cache.sh 加 --proxy）"
case "$LEVEL" in '' | *[!0-9]*) die "压缩级别要是 1–19 的数字" ;; esac
[ "$LEVEL" -ge 1 ] && [ "$LEVEL" -le 19 ] || die "压缩级别要在 1–19 之间"
for c in tar zstd split sha256sum git; do
	command -v "$c" >/dev/null || die "缺少命令 $c（sudo apt install zstd coreutils git tar）"
done

case "$TARGET" in
	x86 | x86_64 | x64) OW="$REPO_ROOT/build/x86_64/openwrt" ;;
	ys | arthur | 亚瑟) OW="$REPO_ROOT/build/arthur/openwrt" ;;
	ydn | athena | 雅典娜) OW="$REPO_ROOT/build/athena/openwrt" ;;
	*) OW="$TARGET" ;;
esac
[ -d "$OW" ] || die "找不到源码目录 $OW（先运行 ./scripts/local-build.sh <机型>）"
OW=$(cd "$OW" && pwd -P)
[ -f "$OW/rules.mk" ] && [ -f "$OW/.config" ] || die "$OW 不像编过的 OpenWrt 源码树（缺 rules.mk 或 .config）"

# 机型从 .config 判断，和目录名无关
if grep -q '^CONFIG_TARGET_x86_64=y' "$OW/.config"; then
	DEVICE=x86_64
elif grep -q '^CONFIG_TARGET_.*_DEVICE_jdcloud_re-cs-02=y' "$OW/.config"; then
	DEVICE=athena
elif grep -q '^CONFIG_TARGET_.*_DEVICE_jdcloud_re-ss-01=y' "$OW/.config"; then
	DEVICE=arthur
else
	die "从 $OW/.config 认不出机型（x86_64 / 雅典娜 / 亚瑟）"
fi
SHA=$(git -C "$OW" rev-parse --short=12 HEAD) || die "$OW 不是 git 仓库"
URL=$(git -C "$OW" remote get-url origin 2>/dev/null || echo "")
echo "机型：$DEVICE   上游：$URL @ $SHA"
echo "源码：$OW"

# ---------- 检查工具链是否完整 ----------
cd "$OW"
shopt -s nullglob
TC_STAGING=(staging_dir/toolchain-*)
TC_BUILD=(build_dir/toolchain-*)
shopt -u nullglob
[ -d staging_dir/host ] || die "缺 staging_dir/host：工具还没编（先 ./scripts/local-build.sh，至少编过 tools）"
[ -d build_dir/host ] || die "缺 build_dir/host：只有 staging_dir 的话 CI 还是会整套重编工具"
[ "${#TC_STAGING[@]}" -ge 1 ] || die "缺 staging_dir/toolchain-*：交叉工具链还没编"
[ "${#TC_BUILD[@]}" -ge 1 ] || die "缺 build_dir/toolchain-*：工具链的编译目录被删了（例如 make clean / dirclean），CI 会重编工具链"
ls staging_dir/host/stamp/.tools_compile_* >/dev/null 2>&1 || die "staging_dir/host/stamp 里没有 .tools_compile_*：工具没编完"
for t in "${TC_STAGING[@]}"; do
	[ -e "$t/stamp/.gcc_final_installed" ] || die "$t/stamp 里没有 .gcc_final_installed：工具链没编完"
done
if [ "${#TC_STAGING[@]}" -gt 1 ] || [ "${#TC_BUILD[@]}" -gt 1 ]; then
	warn "有多个工具链目录（${TC_STAGING[*]} ${TC_BUILD[*]}），可能是旧版本 gcc 留下的，会一起打包、变大；可以手动删掉旧的再打包"
fi
if pgrep -f "make.*$OW" >/dev/null 2>&1; then
	warn "好像还有 make 在这个源码树里运行，打包结果可能不完整"
fi
if [ -r /etc/os-release ]; then
	# shellcheck disable=SC1091
	. /etc/os-release
fi
OS_ID="${ID:-unknown}"
OS_VER="${VERSION_ID:-unknown}"
GLIBC=$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}')
echo "系统：${PRETTY_NAME:-未知}，glibc $GLIBC"
if [ "$(printf '%s\n%s\n' "$GLIBC" "$CI_GLIBC" | sort -V | tail -n 1)" != "$CI_GLIBC" ]; then
	msg="本机 glibc $GLIBC 比 CI（Ubuntu 24.04）的 $CI_GLIBC 新：本地编出的编译机工具在 CI 上运行不了，CI 不会用这份工具链，ccache 也命中不了（编译器不同），上传了也基本没用。
要给 CI 用的缓存，请在 Ubuntu 24.04 或 Debian 12（WSL 里可以另装一个发行版）上编译后再打包。Debian 13 / 更新的系统本地编固件没问题。"
	[ "$FORCE" -eq 1 ] || die "$msg
（确实要打包加 --force）"
	warn "$msg"
elif [ "$OS_ID" != ubuntu ] || [ "$OS_VER" != 24.04 ]; then
	echo "不是 Ubuntu 24.04，但 glibc 不比 CI 新，CI 会在解压后检查动态库，能用就用"
fi
case "$OW/" in
	/mnt/*) warn "源码在 /mnt 下（WSL 的 Windows 盘），这样编出来的东西本身就不可靠" ;;
esac

[ -n "$OUT" ] || OUT="$REPO_ROOT/build/ci-cache/$DEVICE-$SHA"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd -P)
case "$OUT/" in "$OW"/*) die "输出目录不能放在源码树里面" ;; esac
rm -f "$OUT"/*.tar.zst.part* "$OUT/ci-cache.env" "$OUT/SHA256SUMS"

FREE_KB=$(df -Pk "$OUT" | awk 'NR==2{print $4}')
[ "$FREE_KB" -gt $((8 * 1024 * 1024)) ] || warn "输出目录所在磁盘只剩 $((FREE_KB / 1024 / 1024)) GB，可能不够"

# 打包：tar → zstd（多线程）→ 按 1900 MB 切片
pack() {
	local name="$1"; shift
	local s
	s=$(date +%s)
	echo
	echo "==> 打包 $name：$*（原始大小 $(du -sch "$@" | tail -n 1 | cut -f1)）"
	tar -cf - --sort=name "$@" |
		zstd -q -T0 -"$LEVEL" --long=27 |
		split -b 1900M -d -a 2 - "$OUT/$name.tar.zst.part"
	echo "    完成，用时 $(( $(date +%s) - s )) 秒，压缩后 $(du -ch "$OUT/$name".tar.zst.part* | tail -n 1 | cut -f1)"
}

pack toolchain staging_dir/host "${TC_STAGING[@]}" build_dir/host "${TC_BUILD[@]}"
if [ "$WITH_CCACHE" -eq 1 ]; then
	if [ -d .ccache ] && [ -n "$(ls -A .ccache)" ]; then
		pack ccache .ccache
	else
		warn "没有 .ccache（配置里要有 CONFIG_CCACHE=y），跳过 ccache"
	fi
fi
if [ "$WITH_DL" -eq 1 ]; then
	if [ -d dl ]; then pack dl dl; else warn "没有 dl/，跳过"; fi
fi

CONFIG_SHA=""
[ -f "$REPO_ROOT/configs/$DEVICE.config" ] && CONFIG_SHA=$(sha256sum "$REPO_ROOT/configs/$DEVICE.config" | cut -d' ' -f1)
{
	echo "DEVICE=$DEVICE"
	echo "UPSTREAM_SHA=$SHA"
	echo "UPSTREAM_URL=$URL"
	echo "TOPDIR=$OW"
	echo "OS_ID=$OS_ID"
	echo "OS_VERSION=$OS_VER"
	echo "GLIBC=$GLIBC"
	echo "CONFIG_SHA256=$CONFIG_SHA"
	echo "BUILDER_COMMIT=$(git -C "$REPO_ROOT" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
	echo "CREATED=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
} > "$OUT/ci-cache.env"
(cd "$OUT" && sha256sum ./*.tar.zst.part* ci-cache.env | sed 's| \./| |' > SHA256SUMS)

echo
echo "打包完成：$OUT"
ls -lh "$OUT"
echo
echo "总大小：$(du -sh "$OUT" | cut -f1)。下一步上传到 GitHub Release（tag：ci-cache-$DEVICE-$SHA）："
echo "  ./scripts/upload-ci-cache.sh $DEVICE"
echo "  （要走代理：./scripts/upload-ci-cache.sh --proxy http://代理IP:端口 $DEVICE）"
