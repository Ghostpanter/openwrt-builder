# shellcheck shell=bash
# 代理设置：给 local-build.sh / pack-ci-cache.sh / upload-ci-cache.sh 共用（被 source，不单独运行）。
#
# 用法（在脚本里）：
#   . "$REPO_ROOT/scripts/lib/proxy.sh"
#   参数解析里：--proxy) PROXY_URL="$2"; shift ;;  --proxy=*) PROXY_URL="${1#--proxy=}" ;;
#   解析完后：proxy_apply
#   apt 前：proxy_apt_conf（有代理时生成临时 apt 配置，用 sudo apt-get -c "$PROXY_APT_CONF"），退出时 proxy_cleanup
#
# 优先级：--proxy > 环境变量 PROXY > 已有的 https_proxy / HTTPS_PROXY / http_proxy / HTTP_PROXY / all_proxy / ALL_PROXY。
# 只设置本进程及子进程的环境变量（git、curl、wget、gh、go、OpenWrt 的 feeds / make download 都认），
# 不改 git config --global，不往 /etc/apt 写永久配置。

PROXY_URL="${PROXY_URL:-}"
PROXY_APT_CONF=""

# 显示用：把密码换成 ***
proxy_mask() {
	printf '%s' "$1" | sed -E 's#^([A-Za-z0-9+.-]+://)([^:@/]+):[^@/]*@#\1\2:***@#'
}

proxy_apply() {
	local src="--proxy"
	if [ -z "$PROXY_URL" ] && [ -n "${PROXY:-}" ]; then
		PROXY_URL="$PROXY"
		src="环境变量 PROXY"
	fi
	if [ -z "$PROXY_URL" ]; then
		# 没给 --proxy：沿用 shell 里已经设好的代理（同样补齐大小写、传给 make 和 apt）
		local v
		for v in "${https_proxy:-}" "${HTTPS_PROXY:-}" "${http_proxy:-}" "${HTTP_PROXY:-}" "${all_proxy:-}" "${ALL_PROXY:-}"; do
			if [ -n "$v" ]; then
				PROXY_URL="$v"
				src="shell 里已有的代理环境变量"
				break
			fi
		done
		if [ -z "$PROXY_URL" ]; then
			echo "代理：未设置（直连；国内可用的公开加速地址见后面的 GOPROXY 等）"
			return 0
		fi
	fi
	if [ "$src" = "--proxy" ] || [ "$src" = "环境变量 PROXY" ]; then
		# 没写协议当成 http://
		case "$PROXY_URL" in
			*://*) ;;
			*) PROXY_URL="http://$PROXY_URL" ;;
		esac
		case "$PROXY_URL" in
			http://* | https://* | socks5://* | socks5h://*) ;;
			*) echo "错误：--proxy 只支持 http:// https:// socks5:// socks5h://，收到：$(proxy_mask "$PROXY_URL")" >&2; exit 1 ;;
		esac
		case "$PROXY_URL" in
			*://*[!/]:[0-9]* | *://*[!/]:[0-9]*/) ;;
			*) echo "错误：代理地址要带端口，例如 http://192.168.31.246:7890，收到：$(proxy_mask "$PROXY_URL")" >&2; exit 1 ;;
		esac
	fi
	# 大小写都设（curl 只认小写 http_proxy，Go / gh 认大写），本进程和所有子进程（git、feeds、make、go、wget、curl、gh）都继承
	export http_proxy="$PROXY_URL" https_proxy="$PROXY_URL" HTTP_PROXY="$PROXY_URL" HTTPS_PROXY="$PROXY_URL"
	export all_proxy="$PROXY_URL" ALL_PROXY="$PROXY_URL"
	echo "代理：$(proxy_mask "$PROXY_URL")（来自 $src；git / feeds / make download / Go 模块 / apt / gh 都走它）"
	# 本机地址不走代理
	local np="${no_proxy:-${NO_PROXY:-}}"
	case ",$np," in
		*,localhost,*) ;;
		*) np="${np:+$np,}localhost,127.0.0.1,::1" ;;
	esac
	export no_proxy="$np" NO_PROXY="$np"

	case "$PROXY_URL" in
		socks5://* | socks5h://*)
			echo "警告：wget 不支持 socks5，OpenWrt 的 make download 可能直连；建议用 Clash 的 HTTP / mixed 端口（http://...）" >&2 ;;
	esac
	# WSL2 默认 NAT 网络里 127.0.0.1 是 WSL 自己，不是 Windows（除非 .wslconfig 开了 networkingMode=mirrored）
	if { [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; }; then
		case "$PROXY_URL" in
			*://127.0.0.1:* | *://localhost:* | *@127.0.0.1:* | *@localhost:*)
				echo "警告：WSL2 默认（NAT 网络）里 127.0.0.1 指的是 WSL 自己，不是 Windows 上的 Clash；请用 Windows / 路由器的局域网 IP（Clash 开「允许局域网」），或在 .wslconfig 里设 networkingMode=mirrored" >&2 ;;
		esac
	fi
	case "$PROXY_URL" in
		*://*:*@*) echo "提示：代理带了密码。密码里有 @ : / # $ 等特殊字符时要写成 %40 %3A %2F %23 %24；别把带密码的命令写进仓库或发给别人" ;;
	esac
}

# 给 make 命令行用的代理变量（除了 export，再显式写到 make 命令行上：命令行变量会进 MAKEFLAGS，
# 嵌套的子 make、golang-build.sh 里的 go、download.pl 里的 wget/curl 都一定拿得到）。用法：
#   proxy_make_args; make ... "${PROXY_MAKE_ARGS[@]}"
PROXY_MAKE_ARGS=()
proxy_make_args() {
	PROXY_MAKE_ARGS=()
	[ -n "$PROXY_URL" ] || return 0
	local v
	for v in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY; do
		PROXY_MAKE_ARGS+=("$v=${!v:-}")
	done
}

# apt 不读环境变量（sudo 也会清掉），有代理时生成一个临时配置文件（权限 600，退出时删除），用法：sudo apt-get -c "$PROXY_APT_CONF" ...
proxy_apt_conf() {
	PROXY_APT_CONF=""
	[ -n "$PROXY_URL" ] || return 0
	PROXY_APT_CONF=$(mktemp "${TMPDIR:-/tmp}/openwrt-builder-apt-proxy.XXXXXX")
	chmod 600 "$PROXY_APT_CONF"
	local u="${PROXY_URL//\"/}"
	printf 'Acquire::http::Proxy "%s";\nAcquire::https::Proxy "%s";\n' "$u" "$u" > "$PROXY_APT_CONF"
}

proxy_cleanup() {
	if [ -n "$PROXY_APT_CONF" ] && [ -f "$PROXY_APT_CONF" ]; then
		rm -f "$PROXY_APT_CONF"
	fi
	PROXY_APT_CONF=""
}
