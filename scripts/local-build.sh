#!/usr/bin/env bash
# 在自己的 Ubuntu（推荐 24.04）上按 GitHub Actions 同样的步骤编译固件。
# 用法见 ./scripts/local-build.sh --help
#
# 上游仓库地址 / 分支、apt 依赖列表都直接从 .github/workflows/build.yml 里读，
# 和 CI 保持同一份；改上游或依赖只改 workflow 即可。
# 编译步骤（复制 files、feeds、额外插件、defconfig 检查、download、编译、失败重试）与 build.yml 的 build job 一一对应，
# 改了 workflow 的步骤记得同步改这里。
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORKFLOW="$REPO_ROOT/.github/workflows/build.yml"

usage() {
	cat <<'USAGE'
用法：./scripts/local-build.sh [选项] <机型>

机型：
  x86 | x86_64        x86_64 旁路由（ImmortalWrt master）
  ys  | arthur        亚瑟 AX1800 Pro（LibWrt 25.12-nss）
  ydn | athena        雅典娜 AX6600（LibWrt 25.12-nss）

选项：
  -j N                编译线程数（默认 nproc）
  --clean             删掉已有源码重新克隆（会保留 dl/ 下载缓存）
  --config-only       只做到 make defconfig（含 --menuconfig），不下载、不编译
  --menuconfig        make defconfig 之后打开 make menuconfig 手动调整
  --deps              先用 sudo apt 安装编译依赖（列表同 workflow），只给这个参数不给机型就只装依赖
  -h, --help          显示本帮助

目录（都在仓库的 build/ 下，已加入 .gitignore）：
  build/<机型>/openwrt          源码树；再次运行会 git fetch 到上游最新再编（增量编译）
  build/<机型>/logs             日志：feeds-update.log、feeds-install.log、download.log、
                                build.log、build-verbose.log（失败重试时）、packages/<包>/compile.txt
  固件在 build/<机型>/openwrt/bin/targets/ 下，编译成功后会打印具体路径

示例：
  ./scripts/local-build.sh --deps            # 第一次：安装依赖
  ./scripts/local-build.sh x86               # 编 x86_64
  ./scripts/local-build.sh ys                # 编亚瑟
  ./scripts/local-build.sh -j 8 ydn          # 8 线程编雅典娜
  ./scripts/local-build.sh --config-only --menuconfig x86   # 只看/调配置

注意：不要用 root 运行（OpenWrt 拒绝 root 编译）；磁盘建议至少 100 GB 空闲。
USAGE
}

die() { echo "错误：$*" >&2; exit 1; }
warn() { echo "警告：$*" >&2; }
STEP="准备"
step() { STEP="$1"; echo; echo "==> $1"; }
trap 'rc=$?; [ "$rc" -eq 0 ] || [ "$STEP" = "准备" ] || echo "失败于步骤：$STEP（退出码 $rc）" >&2' EXIT

# 从 workflow 读 KEY="value"（check job 里的 IMMORTAL_URL 等）
wf_var() {
	local v
	v=$(sed -n "s/^[[:space:]]*$1=\"\([^\"]*\)\".*/\1/p" "$WORKFLOW" | head -n 1)
	[ -n "$v" ] || die "没能从 $WORKFLOW 读到 $1"
	echo "$v"
}

# 从 workflow 读 apt 依赖列表（"sudo apt-get install -y" 开始，到不以 \ 结尾的行为止）
wf_deps() {
	awk '/sudo apt-get install -y/{f=1} f{print; if ($0 !~ /\\$/) exit}' "$WORKFLOW" |
		sed 's/.*apt-get install -y//; s/\\$//' | tr -s ' \n' ' '
}

DEVICE=""
JOBS=$(nproc)
CLEAN=0
CONFIG_ONLY=0
MENUCONFIG=0
DEPS=0

while [ $# -gt 0 ]; do
	case "$1" in
		-h | --help) usage; exit 0 ;;
		-j) [ $# -ge 2 ] || die "-j 后面要跟线程数"; JOBS="$2"; shift ;;
		-j*) JOBS="${1#-j}" ;;
		--clean) CLEAN=1 ;;
		--config-only) CONFIG_ONLY=1 ;;
		--menuconfig) MENUCONFIG=1 ;;
		--deps) DEPS=1 ;;
		-*) die "未知选项 $1（看 --help）" ;;
		*)
			[ -z "$DEVICE" ] || die "只能指定一个机型"
			case "$1" in
				x86 | x86_64 | x64) DEVICE=x86_64 ;;
				ys | arthur | 亚瑟) DEVICE=arthur ;;
				ydn | athena | 雅典娜) DEVICE=athena ;;
				*) die "未知机型 $1（可选 x86 / ys / ydn）" ;;
			esac
			;;
	esac
	shift
done

case "$JOBS" in
	'' | *[!0-9]* | 0) die "-j 需要正整数，收到：$JOBS" ;;
esac
if [ -z "$DEVICE" ] && [ "$DEPS" -eq 0 ]; then
	usage
	exit 1
fi
[ -f "$WORKFLOW" ] || die "找不到 $WORKFLOW，请在仓库里运行本脚本"
[ "$(id -u)" -ne 0 ] || die "不要用 root 运行：OpenWrt 拒绝以 root 编译，请换普通用户（需要装依赖时脚本会自己调用 sudo）"

# ---------- 环境检查 ----------
step "检查系统环境"
if [ -r /etc/os-release ]; then
	# shellcheck disable=SC1091
	. /etc/os-release
	if [ "${ID:-}" != "ubuntu" ] || [ "${VERSION_ID:-}" != "24.04" ]; then
		warn "当前系统是 ${PRETTY_NAME:-未知}，CI 用的是 Ubuntu 24.04，其他版本可能缺包或工具链太旧"
	else
		echo "系统：$PRETTY_NAME"
	fi
fi

if [ "$DEPS" -eq 1 ]; then
	step "安装编译依赖（sudo apt）"
	DEP_LIST=$(wf_deps)
	[ -n "$DEP_LIST" ] || die "没能从 workflow 读到依赖列表"
	sudo apt-get update -y
	# shellcheck disable=SC2086
	sudo apt-get install -y $DEP_LIST
fi

# 内核 6.18（x86_64）的 bpf-headers 要求宿主机 clang >= 15
if command -v clang >/dev/null 2>&1; then
	CLANG_MAJOR=$(clang -dumpversion | cut -d. -f1)
	if [ "$CLANG_MAJOR" -lt 15 ]; then
		if [ "$DEVICE" = "x86_64" ]; then
			die "clang $CLANG_MAJOR 太旧，x86_64（内核 6.18）的 bpf-headers 至少要 clang 15；请用 Ubuntu 24.04"
		fi
		warn "clang $CLANG_MAJOR 低于 15，x86_64 会编不过"
	else
		echo "clang $CLANG_MAJOR（>= 15）"
	fi
else
	[ "$DEVICE" != "x86_64" ] || die "没有 clang；先运行 ./scripts/local-build.sh --deps"
	warn "没有 clang；建议先运行 ./scripts/local-build.sh --deps"
fi

if [ -z "$DEVICE" ]; then
	echo "依赖安装完成"
	exit 0
fi

# 上游：和 build.yml 的 check job 是同一份
IMMORTAL_URL=$(wf_var IMMORTAL_URL)
IMMORTAL_BRANCH=$(wf_var IMMORTAL_BRANCH)
LIBWRT_URL=$(wf_var LIBWRT_URL)
LIBWRT_BRANCH=$(wf_var LIBWRT_BRANCH)
if [ "$DEVICE" = "x86_64" ]; then
	REPO_URL=$IMMORTAL_URL
	REPO_BRANCH=$IMMORTAL_BRANCH
else
	REPO_URL=$LIBWRT_URL
	REPO_BRANCH=$LIBWRT_BRANCH
fi
CONFIG_FILE="$REPO_ROOT/configs/$DEVICE.config"
[ -f "$CONFIG_FILE" ] || die "找不到配置 $CONFIG_FILE"

DEV_DIR="$REPO_ROOT/build/$DEVICE"
SRC="$DEV_DIR/openwrt"
LOG_DIR="$DEV_DIR/logs"
mkdir -p "$DEV_DIR"

AVAIL_GB=$(df -BG --output=avail "$DEV_DIR" | tail -n 1 | tr -dc '0-9')
if [ "${AVAIL_GB:-0}" -lt 100 ]; then
	warn "$DEV_DIR 所在分区只剩 ${AVAIL_GB} GB，建议至少 100 GB"
else
	echo "磁盘空闲 ${AVAIL_GB} GB"
fi
echo "机型 $DEVICE：$REPO_URL 分支 $REPO_BRANCH，配置 configs/$DEVICE.config，$JOBS 线程"

# 每次运行重新开始写日志
rm -rf "$LOG_DIR"
mkdir -p "$LOG_DIR"

# ---------- 拉取 / 更新源码 ----------
if [ "$CLEAN" -eq 1 ] && [ -d "$SRC" ]; then
	step "--clean：删除旧源码（保留 dl/ 下载缓存）"
	if [ -d "$SRC/dl" ]; then
		rm -rf "$DEV_DIR/dl.keep"
		mv "$SRC/dl" "$DEV_DIR/dl.keep"
	fi
	rm -rf "$SRC"
fi

if [ -d "$SRC/.git" ]; then
	step "更新源码到 $REPO_BRANCH 最新"
	OLD_URL=$(git -C "$SRC" remote get-url origin)
	[ "$OLD_URL" = "$REPO_URL" ] || die "$SRC 的上游是 $OLD_URL，不是 $REPO_URL；加 --clean 重新克隆"
	git -C "$SRC" fetch --depth 1 origin "$REPO_BRANCH"
	git -C "$SRC" checkout -q -B "$REPO_BRANCH" FETCH_HEAD
	git -C "$SRC" reset -q --hard FETCH_HEAD
	# 上次的额外插件脚本改过 feeds 里的文件（如 tailscale Makefile），先还原，feeds update 才能正常拉取
	for f in "$SRC"/feeds/*/; do
		if [ -d "$f.git" ]; then
			git -C "$f" reset -q --hard
			git -C "$f" clean -fdq
		fi
	done
else
	step "克隆 $REPO_URL（$REPO_BRANCH）"
	rm -rf "$SRC"
	git clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$SRC"
fi
if [ -d "$DEV_DIR/dl.keep" ]; then
	rm -rf "$SRC/dl"
	mv "$DEV_DIR/dl.keep" "$SRC/dl"
fi
echo "源码：$(git -C "$SRC" log -1 --format='%h %cd %s' --date=short)"

# files/common 给所有机型，files/<机型> 只给对应机型；每次重新复制，删掉的文件不会残留
step "复制自定义文件"
rm -rf "$SRC/files"
for d in "$REPO_ROOT/files/common" "$REPO_ROOT/files/$DEVICE"; do
	if [ -d "$d" ]; then
		mkdir -p "$SRC/files"
		cp -r "$d/." "$SRC/files/"
		echo "已复制 ${d#"$REPO_ROOT"/}"
	fi
done

cd "$SRC"

# ---------- feeds 和配置 ----------
step "feeds update（日志 logs/feeds-update.log）"
if ! ./scripts/feeds update -a > "$LOG_DIR/feeds-update.log" 2>&1; then
	tail -n 60 "$LOG_DIR/feeds-update.log"
	exit 1
fi

if [ "$DEVICE" = "x86_64" ]; then
	step "x86_64 额外插件（日志 logs/extra-packages.log）"
	if ! bash "$REPO_ROOT/scripts/x86_64-extra-packages.sh" > "$LOG_DIR/extra-packages.log" 2>&1; then
		tail -n 60 "$LOG_DIR/extra-packages.log"
		exit 1
	fi
fi

step "feeds install（日志 logs/feeds-install.log）"
if ! ./scripts/feeds install -a > "$LOG_DIR/feeds-install.log" 2>&1; then
	tail -n 100 "$LOG_DIR/feeds-install.log"
	exit 1
fi

step "载入配置 configs/$DEVICE.config 并 make defconfig"
cp "$CONFIG_FILE" .config
make defconfig > "$LOG_DIR/defconfig.log" 2>&1 || { tail -n 60 "$LOG_DIR/defconfig.log"; exit 1; }
# 和 CI 一样：配置里写成 =y 的包在 defconfig 后都要还在
missing=$(grep -E '^CONFIG_[A-Za-z0-9_.+-]+=y$' "$CONFIG_FILE" | while read -r l; do grep -qxF "$l" .config || echo "$l"; done)
if [ -n "$missing" ]; then
	echo "以下选项在 make defconfig 后丢失："
	echo "$missing"
	# 和 CI 一样只对 x86_64 严格检查，其他机型只提示
	[ "$DEVICE" != "x86_64" ] || die "x86_64 配置有选项丢失"
else
	echo "配置检查通过：所有 =y 选项都在"
fi

if [ "$MENUCONFIG" -eq 1 ]; then
	step "make menuconfig"
	make menuconfig
	echo "提示：menuconfig 的改动只在 build/$DEVICE/openwrt/.config 里；"
	echo "      想写回仓库可运行 (cd build/$DEVICE/openwrt && ./scripts/diffconfig.sh) 对照修改 configs/$DEVICE.config"
fi
cp .config "$LOG_DIR/config"

if [ "$CONFIG_ONLY" -eq 1 ]; then
	echo
	echo "--config-only：配置完成，未下载、未编译。配置文件：$SRC/.config"
	exit 0
fi

# ---------- 下载 ----------
step "make download（日志 logs/download.log）"
if ! make download -j8 > "$LOG_DIR/download.log" 2>&1; then
	echo "并行下载有失败，单线程重试："
	grep -E 'ERROR:' "$LOG_DIR/download.log" || true
	if ! make download -j1 V=s > "$LOG_DIR/download-verbose.log" 2>&1; then
		grep -E 'ERROR:|No more mirrors|Download failed' "$LOG_DIR/download-verbose.log" || true
		tail -n 60 "$LOG_DIR/download-verbose.log"
		die "make download 失败，完整日志：$LOG_DIR/download-verbose.log"
	fi
fi
echo "下载完成，dl 目录 $(du -sh dl 2>/dev/null | cut -f1)"

# ---------- 编译 ----------
step "编译（$JOBS 线程，完整输出在 logs/build.log，控制台只显示进度和报错）"
# BUILD_LOG=1：每个包的输出另存到 logs/packages/<包路径>/compile.txt，失败的包写 error.txt
PKG_LOG_DIR="$LOG_DIR/packages"
FILTER='^ make\[[0-9]+\] |ERROR:|^make\[[0-9]+\]: \*\*\*|^make: \*\*\*'
START=$(date +%s)
set +e
make -j"$JOBS" BUILD_LOG=1 BUILD_LOG_DIR="$PKG_LOG_DIR" 2>&1 | tee "$LOG_DIR/build.log" | grep --line-buffered -E "$FILTER"
rc=${PIPESTATUS[0]}
set -e

if [ "$rc" -ne 0 ]; then
	step "并行编译失败（退出码 $rc），用 make -j1 V=s 重试（日志 logs/build-verbose.log）"
	set +e
	make -j1 V=s BUILD_LOG=1 BUILD_LOG_DIR="$PKG_LOG_DIR" > "$LOG_DIR/build-verbose.log" 2>&1
	rc=$?
	set -e
fi

if [ "$rc" -ne 0 ]; then
	V="$LOG_DIR/build-verbose.log"
	echo
	echo "===== 编译失败的包 ====="
	grep -hE 'ERROR: .* failed to build' "$LOG_DIR/build.log" "$V" | sort -u || true
	echo "===== logs/packages 里的 error.txt ====="
	find "$PKG_LOG_DIR" -name error.txt -exec sh -c 'echo "== $1"; cat "$1"' _ {} \; 2>/dev/null || true
	first=$(grep -nE 'ERROR: .* failed to build' "$V" | head -n 1 | cut -d: -f1)
	before=80
	if [ -z "$first" ]; then
		first=$(grep -nE 'error:|Error [0-9]+' "$V" | head -n 1 | cut -d: -f1)
		before=30
	fi
	if [ -n "$first" ]; then
		echo "===== 第一个报错前后（build-verbose.log 第 $first 行） ====="
		start=$((first > before ? first - before : 1))
		sed -n "${start},$((first + 10))p" "$V"
	fi
	echo "===== build-verbose.log 最后 200 行 ====="
	tail -n 200 "$V"
	die "编译失败，日志在 $LOG_DIR（每个包的日志在 $PKG_LOG_DIR）"
fi

STEP="完成"
echo
echo "编译成功，用时 $((($(date +%s) - START) / 60)) 分钟"
echo "固件目录："
for t in bin/targets/*/*/; do
	[ -d "$t" ] && echo "  $SRC/${t%/}"
done
echo "主要文件："
find "$SRC/bin/targets" -maxdepth 3 -type f \( -name '*.img.gz' -o -name '*.bin' -o -name '*.itb' -o -name '*.ubi' \) \
	-exec du -h {} + | sort -k2 | sed 's/^/  /'
