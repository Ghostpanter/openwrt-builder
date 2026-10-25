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
# shellcheck source=lib/proxy.sh
. "$REPO_ROOT/scripts/lib/proxy.sh"
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
  --proxy URL         走 Clash / HTTP 代理（也可写 --proxy=URL，或事先 export PROXY=URL），例如
                        http://192.168.31.246:7890            Clash 不带认证
                        http://用户名:密码@192.168.31.246:7893  Clash 带认证（密码特殊字符要 % 编码）
                      本次运行的所有联网步骤都走它：git 克隆/更新、feeds update、额外插件的 git clone、
                      make download（wget/curl）、编译阶段 Go 包下载模块、Python 包 pip 下载、cargo、apt（--deps）。
                      做法：export http_proxy / https_proxy / all_proxy（大小写都设）+ no_proxy=localhost，
                      并在 make 命令行上再显式传一遍，嵌套的子 make 和 go 也一定拿得到；apt 用临时配置文件（用完删除）。
                      给了 --proxy 时 GOPROXY 默认用官方 proxy.golang.org（经代理），失败再试 goproxy.cn；不设 pip 镜像。
                      不改 git config --global，也不在 /etc/apt 留永久配置。
                      shell 里已经 export 了 https_proxy / http_proxy 时，等同于给了 --proxy
  不给 --proxy 时     直连，不需要 Clash；自动用国内公开加速地址：
                        GOPROXY=https://goproxy.cn,https://proxy.golang.org,direct（Go 包编译时下载依赖）
                        PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple（编译时 pip 装宿主机 Python 包，带哈希校验）
                      源码（GitHub）和 make download 仍按上游原地址 / OpenWrt 自带镜像下载
  --goproxy URL       自定义 GOPROXY；shell 里已 export GOPROXY 时沿用它；--goproxy off 表示不设、用 Go 默认值
  --pip-index URL     自定义 pip 镜像；shell 里已 export PIP_INDEX_URL 时沿用它；--pip-index off 不设
  --no-mirror         不用任何公开加速地址（等于 --goproxy off --pip-index off）
  -h, --help          显示本帮助

目录（都在仓库的 build/ 下，已加入 .gitignore）：
  build/<机型>/openwrt          源码树；再次运行会 git fetch 到上游最新再编（增量编译）
  build/<机型>/logs             日志：feeds-update.log、feeds-install.log、download.log、
                                build.log、build-verbose.log（失败重试时）、packages/<包>/compile.txt
  固件在 build/<机型>/openwrt/bin/targets/ 下，编译成功后会打印具体路径

示例：
  ./scripts/local-build.sh --deps            # 第一次：安装依赖
  ./scripts/local-build.sh x86               # 编 x86_64（不走代理，自动用 goproxy.cn / 清华 pypi 等公开加速）
  ./scripts/local-build.sh ys                # 编亚瑟
  ./scripts/local-build.sh -j 8 ydn          # 8 线程编雅典娜
  ./scripts/local-build.sh --config-only --menuconfig x86   # 只看/调配置
  ./scripts/local-build.sh --proxy http://192.168.31.246:7890 --deps          # 走代理装依赖
  ./scripts/local-build.sh --proxy http://user:pass@192.168.31.246:7893 x86   # 走带认证的代理编译

注意：不要用 root 运行（OpenWrt 拒绝 root 编译）；磁盘建议至少 100 GB 空闲。
USAGE
}

die() { echo "错误：$*" >&2; exit 1; }
warn() { echo "警告：$*" >&2; }
STEP="准备"
step() { STEP="$1"; echo; echo "==> $1"; }
trap 'rc=$?; proxy_cleanup; [ "$rc" -eq 0 ] || [ "$STEP" = "准备" ] || echo "失败于步骤：$STEP（退出码 $rc）" >&2' EXIT

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
GOPROXY_OPT=""
PIP_INDEX_OPT=""
# 不走代理时用国内公开加速；走代理时以官方源为主（| 表示任何错误都换下一个，, 只在 404/410 时换）
GOPROXY_DEFAULT="https://goproxy.cn,https://proxy.golang.org,direct"
GOPROXY_DEFAULT_PROXIED="https://proxy.golang.org|https://goproxy.cn,direct"
PIP_INDEX_DEFAULT="https://pypi.tuna.tsinghua.edu.cn/simple"

while [ $# -gt 0 ]; do
	case "$1" in
		-h | --help) usage; exit 0 ;;
		-j) [ $# -ge 2 ] || die "-j 后面要跟线程数"; JOBS="$2"; shift ;;
		-j*) JOBS="${1#-j}" ;;
		--clean) CLEAN=1 ;;
		--config-only) CONFIG_ONLY=1 ;;
		--menuconfig) MENUCONFIG=1 ;;
		--deps) DEPS=1 ;;
		--proxy) [ $# -ge 2 ] || die "--proxy 后面要跟代理地址，例如 http://192.168.31.246:7890"; PROXY_URL="$2"; shift ;;
		--proxy=*) PROXY_URL="${1#--proxy=}"; [ -n "$PROXY_URL" ] || die "--proxy= 后面要跟代理地址" ;;
		--goproxy) [ $# -ge 2 ] || die "--goproxy 后面要跟地址，例如 https://goproxy.cn,direct，或 off"; GOPROXY_OPT="$2"; shift ;;
		--goproxy=*) GOPROXY_OPT="${1#--goproxy=}"; [ -n "$GOPROXY_OPT" ] || die "--goproxy= 后面要跟地址或 off" ;;
		--pip-index) [ $# -ge 2 ] || die "--pip-index 后面要跟地址或 off"; PIP_INDEX_OPT="$2"; shift ;;
		--pip-index=*) PIP_INDEX_OPT="${1#--pip-index=}"; [ -n "$PIP_INDEX_OPT" ] || die "--pip-index= 后面要跟地址或 off" ;;
		--no-mirror) GOPROXY_OPT=off; PIP_INDEX_OPT=off ;;
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
case "$(uname -s)" in
	MINGW* | MSYS* | CYGWIN*)
		die "这是 Windows 的 Git Bash / MSYS，不能编译 OpenWrt。请在 WSL 里运行：先在 PowerShell 执行 wsl -d Debian 进入 Linux，再 cd ~/openwrt-builder 运行本脚本" ;;
esac

# ---- 本机 Linux 还是 WSL ----
IS_WSL=0
if [ -n "${WSL_DISTRO_NAME:-}" ] || [ -e /proc/sys/fs/binfmt_misc/WSLInterop ] ||
	grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null || uname -r | grep -qiE 'microsoft|wsl'; then
	IS_WSL=1
fi

OS_ID=unknown
OS_VER=""
OS_NAME="未知系统"
if [ -r /etc/os-release ]; then
	# shellcheck disable=SC1091
	. /etc/os-release
	OS_ID="${ID:-unknown}"
	OS_VER="${VERSION_ID:-}"
	OS_NAME="${PRETTY_NAME:-$OS_ID $OS_VER}"
fi

if [ "$IS_WSL" -eq 1 ]; then
	echo "环境：WSL（$OS_NAME，发行版 ${WSL_DISTRO_NAME:-未知}，内核 $(uname -r)）"
	# WSL2 的内核版本号里带 microsoft-standard / WSL2；WSL1 是 4.4.0-xxxxx-Microsoft 这种
	if ! uname -r | grep -qiE 'microsoft-standard|wsl2'; then
		die "看起来是 WSL1（内核 $(uname -r)）。WSL1 文件系统太慢且有兼容问题，OpenWrt 基本编不过。请在 PowerShell 执行：wsl --set-version ${WSL_DISTRO_NAME:-Debian} 2"
	fi
	# 绝不能在 /mnt/c、/mnt/e 这类 Windows 盘（NTFS）上编译：大小写不敏感、权限/软链接不对、慢几十倍
	for d in "$REPO_ROOT" "$REPO_ROOT/build"; do
		case "$d/" in
			/mnt/*)
				die "仓库在 Windows 盘上（$REPO_ROOT）。请放到 WSL 自己的 Linux 文件系统里，例如：
    cd ~ && git clone https://github.com/Ghostpanter/openwrt-builder.git && cd openwrt-builder
（Debian 装在 E: 盘只是虚拟磁盘文件 ext4.vhdx 放在 E:，WSL 里的 ~ 和 /home 仍然是 Linux ext4，可以编译；/mnt/e 才是 NTFS，不行）" ;;
		esac
	done
	FS_TYPE=$(stat -f -c %T "$REPO_ROOT" 2>/dev/null || echo unknown)
	case "$FS_TYPE" in
		v9fs | 9p | drvfs | fuseblk | ntfs* | msdos | vfat | exfat)
			die "仓库所在文件系统是 $FS_TYPE（Windows 盘），不能编译；请把仓库克隆到 ~ 下" ;;
	esac
	# Windows 的 PATH（/mnt/c/Program Files/... 带空格、括号）会把 OpenWrt 的编译搞坏，编译时去掉
	if printf '%s' "$PATH" | tr ':' '\n' | grep -q '^/mnt/'; then
		PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v '^/mnt/' | paste -sd: -)
		export PATH
		echo "已从 PATH 去掉 Windows 路径（/mnt/...），避免空格/括号导致编译出错；想永久关掉可在 /etc/wsl.conf 写 [interop] appendWindowsPath=false"
	fi
	# 内存：WSL2 默认只用 Windows 内存的一半
	MEM_GB=$(awk '/^MemTotal:/{printf "%d", $2/1024/1024 + 0.5}' /proc/meminfo)
	SWAP_GB=$(awk '/^SwapTotal:/{printf "%d", $2/1024/1024 + 0.5}' /proc/meminfo)
	echo "WSL 可用内存 ${MEM_GB} GB，swap ${SWAP_GB} GB，CPU $(nproc) 线程"
	if [ "${MEM_GB:-0}" -lt 16 ]; then
		warn "WSL 内存不足 16 GB，x86_64（node、rust、内核）多线程编译可能被 OOM 杀掉。可在 Windows 的 %UserProfile%\\.wslconfig 里写：
    [wsl2]
    memory=16GB
    swap=16GB
然后 PowerShell 执行 wsl --shutdown 再进来；或者用 -j 4 少开线程"
	fi
	echo "提醒：WSL 的虚拟磁盘（ext4.vhdx）放在安装发行版的那个 Windows 盘（例如 E:），编译会让它涨到 100 GB 以上，请确认该盘空间足够"
	for m in /mnt/[c-z]; do
		[ -d "$m" ] && mountpoint -q "$m" 2>/dev/null || continue
		echo "  Windows 盘 ${m#/mnt/}: 剩余 $(df -h --output=avail "$m" 2>/dev/null | tail -n 1 | tr -d ' ')"
	done
else
	echo "环境：本机 Linux（$OS_NAME，内核 $(uname -r)）"
fi

# 代理（--proxy / PROXY / 已有环境变量）：之后的 git / feeds / wget / curl / go / pip / apt 都走它
proxy_apply

# Go 模块代理：OpenWrt 的 golang-package.mk 会透传环境里的 GOPROXY / GOSUMDB（GOSUMDB 不动，校验照常）。
# Go 包在编译时才 go mod download，国内直连 proxy.golang.org 经常超时，包就 "failed to build"。
if [ -n "$PROXY_URL" ]; then GOPROXY_AUTO="$GOPROXY_DEFAULT_PROXIED"; else GOPROXY_AUTO="$GOPROXY_DEFAULT"; fi
case "$GOPROXY_OPT" in
	off | default | none) unset GOPROXY; echo "GOPROXY：不设置（Go 默认 proxy.golang.org${PROXY_URL:+，经代理}）" ;;
	"")
		if [ -n "${GOPROXY:-}" ]; then
			echo "GOPROXY：沿用环境变量 $GOPROXY"
		else
			export GOPROXY="$GOPROXY_AUTO"
			if [ -n "$PROXY_URL" ]; then
				echo "GOPROXY：$GOPROXY（经代理访问；--goproxy 可改）"
			else
				echo "GOPROXY：$GOPROXY（公开加速，直连可用；--goproxy 可改，off 关掉）"
			fi
		fi
		;;
	*) export GOPROXY="$GOPROXY_OPT"; echo "GOPROXY：$GOPROXY（来自 --goproxy）" ;;
esac

# pip 镜像：python 宿主机构建依赖在编译时用 pip 下载（requirements 带 --require-hashes，换镜像不影响校验）
case "$PIP_INDEX_OPT" in
	off | default | none) unset PIP_INDEX_URL; echo "pip：不设镜像（pypi.org${PROXY_URL:+，经代理}）" ;;
	"")
		if [ -n "${PIP_INDEX_URL:-}" ]; then
			echo "pip：沿用环境变量 PIP_INDEX_URL=$PIP_INDEX_URL"
		elif [ -z "$PROXY_URL" ]; then
			export PIP_INDEX_URL="$PIP_INDEX_DEFAULT"
			echo "pip：PIP_INDEX_URL=$PIP_INDEX_URL（公开加速；--pip-index 可改，off 关掉）"
		else
			echo "pip：pypi.org（经代理）"
		fi
		;;
	*) export PIP_INDEX_URL="$PIP_INDEX_OPT"; echo "pip：PIP_INDEX_URL=$PIP_INDEX_URL（来自 --pip-index）" ;;
esac

# 除了 export，再在 make 命令行上显式传一次（命令行变量会进 MAKEFLAGS，所有子 make、go、pip、wget 都能拿到）
proxy_make_args
MAKE_NET_ARGS=("${PROXY_MAKE_ARGS[@]}")
[ -z "${GOPROXY:-}" ] || MAKE_NET_ARGS+=("GOPROXY=$GOPROXY")
[ -z "${PIP_INDEX_URL:-}" ] || MAKE_NET_ARGS+=("PIP_INDEX_URL=$PIP_INDEX_URL")

case "$OS_ID:$OS_VER" in
	ubuntu:24.04) echo "系统：$OS_NAME（和 CI 相同）" ;;
	debian:12 | debian:13) echo "系统：$OS_NAME（支持；依赖包名会自动换成 Debian 的）" ;;
	*) warn "当前系统是 $OS_NAME，推荐 Ubuntu 24.04 或 Debian 12/13，其他版本可能缺包或工具太旧" ;;
esac

if [ "$DEPS" -eq 1 ]; then
	step "安装编译依赖（sudo apt）"
	DEP_LIST=$(wf_deps)
	[ -n "$DEP_LIST" ] || die "没能从 workflow 读到依赖列表"
	if [ "$OS_ID" = debian ]; then
		# Debian 里这几个是虚包名，换成实际的包；Debian 12 默认 clang 14 太旧，另装 clang/lld/llvm 16
		DEP_LIST=$(printf ' %s ' "$DEP_LIST" | sed 's/ gnutls-dev / libgnutls28-dev /; s/ libz-dev / zlib1g-dev /; s/ mkisofs / genisoimage /')
		[ "$OS_VER" != 12 ] || DEP_LIST="$DEP_LIST clang-16 lld-16 llvm-16"
	fi
	# apt 不读 http_proxy（sudo 也会清掉环境变量）：有代理时用临时配置文件传给 apt（-c），退出时删除
	APT=(sudo apt-get)
	proxy_apt_conf
	if [ -n "$PROXY_APT_CONF" ]; then
		APT+=(-c "$PROXY_APT_CONF")
		echo "apt 走代理 $(proxy_mask "$PROXY_URL")（临时配置，用完删除）"
	fi
	"${APT[@]}" update -y
	# shellcheck disable=SC2086
	if ! "${APT[@]}" install -y $DEP_LIST; then
		# 某个包名在这个系统上不存在时，逐个安装，最后列出装不上的
		warn "一次性安装失败，改为逐个安装"
		FAILED=""
		for pkg in $DEP_LIST; do
			"${APT[@]}" install -y "$pkg" > /dev/null 2>&1 || FAILED="$FAILED $pkg"
		done
		[ -z "$FAILED" ] || warn "以下包没装上（大多数不影响编译，编译报缺什么再手动装）：$FAILED"
	fi
	proxy_cleanup
fi

# Debian 12 等默认 clang 太旧时，用 /usr/lib/llvm-N/bin 里更新的版本
if ! command -v clang >/dev/null 2>&1 || [ "$(clang -dumpversion | cut -d. -f1)" -lt 15 ]; then
	for d in $(ls -1d /usr/lib/llvm-*/bin 2>/dev/null | sort -t- -k2 -n -r); do
		v=${d#/usr/lib/llvm-}; v=${v%/bin}
		if [ "$v" -ge 15 ] 2>/dev/null && [ -x "$d/clang" ]; then
			PATH="$d:$PATH"
			export PATH
			echo "使用 $d 里的 clang $v"
			break
		fi
	done
fi

# 内核 6.18（x86_64）的 bpf-headers 要求宿主机 clang >= 15
if command -v clang >/dev/null 2>&1; then
	CLANG_MAJOR=$(clang -dumpversion | cut -d. -f1)
	if [ "$CLANG_MAJOR" -lt 15 ]; then
		if [ "$DEVICE" = "x86_64" ]; then
			die "clang $CLANG_MAJOR 太旧，x86_64（内核 6.18）的 bpf-headers 至少要 clang 15；Ubuntu 24.04 / Debian 13 自带的就够，Debian 12 运行 --deps 会装 clang-16"
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
if ! make download -j8 "${MAKE_NET_ARGS[@]}" > "$LOG_DIR/download.log" 2>&1; then
	echo "并行下载有失败，单线程重试："
	grep -E 'ERROR:' "$LOG_DIR/download.log" || true
	if ! make download -j1 V=s "${MAKE_NET_ARGS[@]}" > "$LOG_DIR/download-verbose.log" 2>&1; then
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
make -j"$JOBS" "${MAKE_NET_ARGS[@]}" BUILD_LOG=1 BUILD_LOG_DIR="$PKG_LOG_DIR" 2>&1 | tee "$LOG_DIR/build.log" | grep --line-buffered -E "$FILTER"
rc=${PIPESTATUS[0]}
set -e

if [ "$rc" -ne 0 ]; then
	step "并行编译失败（退出码 $rc），用 make -j1 V=s 重试（日志 logs/build-verbose.log）"
	set +e
	make -j1 V=s "${MAKE_NET_ARGS[@]}" BUILD_LOG=1 BUILD_LOG_DIR="$PKG_LOG_DIR" > "$LOG_DIR/build-verbose.log" 2>&1
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
	# 失败包自己的 compile.txt 末尾才有真正的编译器 / go 报错
	while IFS= read -r e; do
		c="$(dirname "$e")/compile.txt"
		[ -f "$c" ] || continue
		echo "===== ${c#"$LOG_DIR"/} 最后 60 行 ====="
		tail -n 60 "$c"
		if grep -qE 'proxy\.golang\.org|sum\.golang\.org|goproxy|dial tcp|i/o timeout|TLS handshake timeout|connection reset|go: .*: (Get|reading) ' "$c"; then
			echo "提示：看起来是 Go 下载依赖时网络不通。当前 GOPROXY=${GOPROXY:-未设置}，代理=$( [ -n "$PROXY_URL" ] && proxy_mask "$PROXY_URL" || echo 未设置)；换 --goproxy 或加/去掉 --proxy 后重跑（不用 --clean）" >&2
			echo "      自己在源码树里手动 make 时不经过脚本，要先 export GOPROXY=$GOPROXY_AUTO（走代理再 export https_proxy=... http_proxy=...）" >&2
		fi
		if grep -qE 'signal: killed|Killed|cannot allocate memory|out of memory' "$c"; then
			echo "提示：像是内存不够被杀（WSL 默认只给一半内存）。用 -j 4 之类少点线程，或在 .wslconfig 里调大 memory / swap" >&2
		fi
	done < <(find "$PKG_LOG_DIR" -name error.txt 2>/dev/null)
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
