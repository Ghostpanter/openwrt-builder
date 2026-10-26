#!/usr/bin/env bash
# 把 pack-ci-cache.sh 打好的缓存上传到本仓库的 GitHub Release（预发布，tag：ci-cache-<机型>-<上游短SHA>）。
# 重复运行是安全的：Release 不存在就创建；已经完整传上去的切片（同名同大小）自动跳过，没传完的删掉重传；
# 每个切片失败自动重试；最后删掉多余的旧切片。只会上传缓存文件，不会上传固件。
# 用法见 ./scripts/upload-ci-cache.sh --help
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib/proxy.sh
. "$REPO_ROOT/scripts/lib/proxy.sh"

usage() {
	cat <<'USAGE'
用法：./scripts/upload-ci-cache.sh [选项] <机型 | 打包目录>

机型：x86 | x86_64、ys | arthur、ydn | athena（自动找 build/ci-cache/ 下该机型最新的打包目录）
也可以直接给 pack-ci-cache.sh 的输出目录。

选项：
  --repo OWNER/NAME   上传到哪个仓库，默认取本仓库 git remote origin
  --proxy URL         走代理（也可 --proxy=URL 或 export PROXY=URL），例如 http://192.168.31.246:7890，
                      带认证：http://用户名:密码@192.168.31.246:7893（密码特殊字符要 % 编码）。
                      本次运行的所有 gh 请求（查询、创建 Release、上传、删除旧资产）都走它：
                      export http_proxy / https_proxy / all_proxy（大小写都设），不改 gh / git 的全局配置；
                      不给时 shell 里已有的 https_proxy 照样生效（同样补齐大小写）；都没有就直连 GitHub
  --prune             上传成功后删掉该机型其他（旧上游 SHA 的）ci-cache Release，节省空间
  --part-size SIZE    上传前把大于 SIZE 的切片在本地重新切小（默认 500M；0 = 不切）。
                      走代理传 1 GB 以上的单个文件容易中途断（EOF），切小后断了也只重传一小块
  --retries N         每个切片失败后重试几次（默认 5，间隔递增）
  --gh                用 gh release upload 上传切片（默认用 curl：强制 HTTP/1.1、显示进度、
                      卡住 2 分钟自动断开重试；token 取自 gh auth token）
  -h, --help          显示本帮助

需要 GitHub CLI 并已登录：sudo apt install gh && gh auth login
（gh auth login 本身也要联网，可先 export https_proxy=http://代理IP:端口 再登录）

示例：
  ./scripts/upload-ci-cache.sh x86
  ./scripts/upload-ci-cache.sh --proxy http://192.168.31.246:7890 x86
USAGE
}

die() { echo "错误：$*" >&2; exit 1; }

TARGET=""
REPO=""
PRUNE=0
PART_SIZE=500M
RETRIES=5
UPLOADER=curl
while [ $# -gt 0 ]; do
	case "$1" in
		-h | --help) usage; exit 0 ;;
		--repo) [ $# -ge 2 ] || die "--repo 后面要跟 OWNER/NAME"; REPO="$2"; shift ;;
		--prune) PRUNE=1 ;;
		--part-size) [ $# -ge 2 ] || die "--part-size 后面要跟大小，例如 500M"; PART_SIZE="$2"; shift ;;
		--part-size=*) PART_SIZE="${1#--part-size=}" ;;
		--retries) [ $# -ge 2 ] || die "--retries 后面要跟次数"; RETRIES="$2"; shift ;;
		--retries=*) RETRIES="${1#--retries=}" ;;
		--gh) UPLOADER=gh ;;
		--proxy) [ $# -ge 2 ] || die "--proxy 后面要跟代理地址，例如 http://192.168.31.246:7890"; PROXY_URL="$2"; shift ;;
		--proxy=*) PROXY_URL="${1#--proxy=}"; [ -n "$PROXY_URL" ] || die "--proxy= 后面要跟代理地址" ;;
		-*) die "未知选项 $1（看 --help）" ;;
		*) [ -z "$TARGET" ] || die "只能指定一个机型或目录"; TARGET="$1" ;;
	esac
	shift
done
[ -n "$TARGET" ] || { usage; exit 1; }
case "$RETRIES" in '' | *[!0-9]*) die "--retries 要是数字" ;; esac
PART_BYTES=0
if [ "$PART_SIZE" != "0" ]; then
	PART_BYTES=$(numfmt --from=iec "$PART_SIZE" 2>/dev/null) || die "--part-size 看不懂：$PART_SIZE（例如 500M、1G）"
	[ "$PART_BYTES" -ge $((50 * 1024 * 1024)) ] || die "--part-size 至少 50M"
	[ "$PART_BYTES" -lt 2147483648 ] || die "--part-size 要小于 2G（GitHub Release 单文件上限）"
fi
proxy_apply
if [ "$UPLOADER" = curl ] && ! command -v curl >/dev/null; then
	echo "没有 curl，改用 gh 上传"
	UPLOADER=gh
fi
command -v gh >/dev/null || die "没有 gh 命令：sudo apt install gh，然后 gh auth login"
gh auth status >/dev/null 2>&1 || die "gh 还没登录（或连不上 GitHub）：先运行 gh auth login；网络不通时加 --proxy http://代理IP:端口"

DEVICE=""
case "$TARGET" in
	x86 | x86_64 | x64) DEVICE=x86_64 ;;
	ys | arthur | 亚瑟) DEVICE=arthur ;;
	ydn | athena | 雅典娜) DEVICE=athena ;;
esac
if [ -n "$DEVICE" ]; then
	# 该机型最新的打包目录
	DIR=$(ls -1dt "$REPO_ROOT/build/ci-cache/$DEVICE"-*/ 2>/dev/null | head -n 1 || true)
	[ -n "$DIR" ] || die "build/ci-cache/ 下没有 $DEVICE 的打包，先运行 ./scripts/pack-ci-cache.sh $TARGET"
else
	DIR="$TARGET"
fi
DIR=$(cd "$DIR" && pwd -P) || die "找不到目录 $TARGET"
[ -f "$DIR/ci-cache.env" ] && [ -f "$DIR/SHA256SUMS" ] || die "$DIR 里没有 ci-cache.env / SHA256SUMS，不是 pack-ci-cache.sh 的输出"

env_get() { sed -n "s/^$1=//p" "$DIR/ci-cache.env" | head -n 1; }
P_DEVICE=$(env_get DEVICE)
SHA=$(env_get UPSTREAM_SHA)
[ -n "$P_DEVICE" ] && [ -n "$SHA" ] || die "ci-cache.env 缺 DEVICE / UPSTREAM_SHA"
[ -z "$DEVICE" ] || [ "$DEVICE" = "$P_DEVICE" ] || die "打包目录是 $P_DEVICE 的，不是 $DEVICE"
DEVICE="$P_DEVICE"
TAG="ci-cache-$DEVICE-$SHA"

if [ -z "$REPO" ]; then
	url=$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)
	REPO=$(printf '%s\n' "$url" | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')
	[ -n "$REPO" ] && [ "$REPO" != "$url" ] || die "认不出仓库，用 --repo OWNER/NAME 指定"
fi

# 只允许上传缓存文件（白名单），防止误传固件
collect_files() {
	FILES=()
	OTHER=0
	local p f
	for p in "$DIR"/*; do
		f=$(basename "$p")
		if [[ "$f" =~ ^((toolchain|ccache|dl)\.tar\.zst\.part[0-9]+|ci-cache\.env|SHA256SUMS)$ ]]; then
			FILES+=("$f")
		else
			OTHER=1
		fi
	done
	[ "${#FILES[@]}" -gt 2 ] || die "$DIR 里没有 *.tar.zst.partNN"
}
collect_files
[ "$OTHER" -eq 0 ] || echo "注意：$DIR 里有其他文件，不会上传"
for f in "${FILES[@]}"; do
	sz=$(stat -c %s "$DIR/$f")
	[ "$sz" -lt 2147483648 ] || die "$f 超过 2 GB（GitHub Release 单文件上限），请重新运行 pack-ci-cache.sh"
done

echo "==> 校验 SHA256SUMS"
(cd "$DIR" && sha256sum -c --quiet SHA256SUMS) || die "校验失败，请重新打包"

# 切片太大时在本地重新切小（内容不变，只是切法不同；CI 的 restore-ci-cache.sh 按序号拼回去，切几片都行）
resplit() {
	[ "$PART_BYTES" -gt 0 ] || return 0
	local need=0 f name tmp total
	for f in "${FILES[@]}"; do
		case "$f" in ci-cache.env | SHA256SUMS) continue ;; esac
		[ "$(stat -c %s "$DIR/$f")" -le "$PART_BYTES" ] || need=1
	done
	[ "$need" -eq 1 ] || return 0
	echo "==> 有切片大于 $PART_SIZE，本地重新切成 $PART_SIZE 一片（需要和缓存差不多大的临时空间）"
	tmp="$DIR/.resplit"
	rm -rf "$tmp"
	mkdir -p "$tmp"
	for name in toolchain ccache dl; do
		compgen -G "$DIR/$name.tar.zst.part[0-9]*" >/dev/null || continue
		total=$(cat "$DIR/$name".tar.zst.part* | wc -c)
		[ $(( (total + PART_BYTES - 1) / PART_BYTES )) -le 100 ] || die "$name 切成 $PART_SIZE 会超过 100 片，--part-size 调大一点"
		cat "$DIR/$name".tar.zst.part* | split -b "$PART_BYTES" -d -a 2 - "$tmp/$name.tar.zst.part"
		cmp -s <(cat "$DIR/$name".tar.zst.part*) <(cat "$tmp/$name".tar.zst.part*) || die "$name 重新切片后内容不一致（磁盘满了？），原文件没动"
	done
	rm -f "$DIR"/*.tar.zst.part*
	mv "$tmp"/*.tar.zst.part* "$DIR"/
	rmdir "$tmp"
	(cd "$DIR" && sha256sum ./*.tar.zst.part* ci-cache.env | sed 's| \./| |' > SHA256SUMS)
	collect_files
	echo "    完成：$(cd "$DIR" && ls -1 ./*.tar.zst.part* | wc -l) 个切片"
}
resplit

echo "==> 仓库 $REPO，Release $TAG，目录 $DIR（$(du -sh "$DIR" | cut -f1)）"
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
	echo "Release 已存在，覆盖文件"
else
	echo "创建预发布 Release"
	gh release create "$TAG" --repo "$REPO" --prerelease \
		--title "CI 编译缓存 $DEVICE @ $SHA（不是固件，请勿下载刷机）" \
		--notes "$(printf '%s\n' \
			"**这不是固件。** 这是本地编译后上传的编译缓存，GitHub Actions 编译 $DEVICE 时会自动下载，用来跳过编译机工具 / 交叉工具链，并让 ccache 命中。" \
			"" \
			"- 机型：$DEVICE" \
			"- 上游源码：$(env_get UPSTREAM_URL) @ $SHA" \
			"- 打包系统：$(env_get OS_ID) $(env_get OS_VERSION)，glibc $(env_get GLIBC)" \
			"- 生成方式：./scripts/local-build.sh → ./scripts/pack-ci-cache.sh → ./scripts/upload-ci-cache.sh" \
			"" \
			"可以随时删除，删除后 CI 只是回到没有缓存时的速度。")" \
		--target main
fi

RELEASE_ID=$(gh api "repos/$REPO/releases/tags/$TAG" --jq .id) || die "查不到 Release $TAG 的 id"

# Release 上的文件：名字<TAB>大小<TAB>状态<TAB>id
remote_assets() {
	gh api "repos/$REPO/releases/$RELEASE_ID/assets" --paginate \
		--jq '.[] | [.name, (.size|tostring), .state, (.id|tostring)] | @tsv'
}
delete_asset_id() { gh api -X DELETE "repos/$REPO/releases/assets/$1" >/dev/null; }

# 用 curl 上传：强制 HTTP/1.1（代理对长时间 HTTP/2 流不友好）、流式读文件不占内存、显示进度、
# 2 分钟平均低于 10 KB/s 视为卡死并断开
curl_upload() {
	local f="$1" name resp code
	name=$(basename "$f")
	resp=$(mktemp)
	code=$(curl --http1.1 -# -o "$resp" -w '%{http_code}' \
		-K <(printf 'header = "Authorization: Bearer %s"\n' "$(gh auth token)") \
		-H "Accept: application/vnd.github+json" \
		-H "Content-Type: application/octet-stream" \
		-H "Expect:" \
		--connect-timeout 30 --speed-limit 10240 --speed-time 120 \
		-X POST -T "$f" \
		"https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=$name") || code="${code:-000}"
	if [ "$code" = 201 ]; then
		rm -f "$resp"
		return 0
	fi
	echo "    HTTP $code：$(head -c 300 "$resp" 2>/dev/null)" >&2
	rm -f "$resp"
	return 1
}

# 上传一个文件：已完整存在就跳过；有同名残缺/大小不对的先删；失败重试
upload_one() {
	local f="$1" force="${2:-0}" name size line rsize rstate rid try=0 wait
	name=$(basename "$f")
	size=$(stat -c %s "$f")
	while :; do
		line=$(remote_assets | awk -F'\t' -v n="$name" '$1 == n' | head -n 1 || true)
		if [ -n "$line" ]; then
			IFS=$'\t' read -r _ rsize rstate rid <<<"$line"
			if [ "$force" -eq 0 ] && [ "$rstate" = uploaded ] && [ "$rsize" = "$size" ]; then
				echo "  $name 已经传过（大小一致），跳过"
				return 0
			fi
			delete_asset_id "$rid" || true
		fi
		echo "  $name（$(du -h "$f" | cut -f1)）"
		if [ "$UPLOADER" = curl ]; then
			curl_upload "$f" && return 0
		else
			gh release upload "$TAG" "$f" --repo "$REPO" --clobber && return 0
		fi
		try=$((try + 1))
		[ "$try" -le "$RETRIES" ] || die "$name 重试 $RETRIES 次仍失败；直接再运行一次本脚本会从这里接着传（已完成的切片会跳过）"
		wait=$((try * 15))
		echo "    上传失败，${wait} 秒后第 $try/$RETRIES 次重试" >&2
		sleep "$wait"
	done
}

# 先传数据切片，最后传 ci-cache.env / SHA256SUMS（这两个每次都重传，保证和本地一致）
DATA=()
for f in "${FILES[@]}"; do
	case "$f" in ci-cache.env | SHA256SUMS) ;; *) DATA+=("$DIR/$f") ;; esac
done
echo "==> 上传 ${#DATA[@]} 个切片（用 $UPLOADER；大文件需要一段时间，断了会自动重试）"
for f in "${DATA[@]}"; do
	upload_one "$f"
done
upload_one "$DIR/ci-cache.env" 1
upload_one "$DIR/SHA256SUMS" 1

# 删掉 Release 上多余的旧文件（例如上次切片更多）
mapfile -t REMOTE < <(gh release view "$TAG" --repo "$REPO" --json assets --jq '.assets[].name')
for a in "${REMOTE[@]}"; do
	keep=0
	for f in "${FILES[@]}"; do [ "$a" = "$f" ] && keep=1; done
	if [ "$keep" -eq 0 ]; then
		echo "删除旧文件 $a"
		gh release delete-asset "$TAG" "$a" --repo "$REPO" -y
	fi
done

if [ "$PRUNE" -eq 1 ]; then
	mapfile -t OLD < <(gh api "repos/$REPO/releases" --paginate --jq '.[].tag_name' |
		grep -E "^ci-cache-$DEVICE-[0-9a-f]+$" | grep -vxF "$TAG" || true)
	for t in "${OLD[@]}"; do
		echo "删除旧缓存 Release $t"
		gh release delete "$t" --repo "$REPO" --cleanup-tag -y
	done
fi

echo
echo "上传完成：https://github.com/$REPO/releases/tag/$TAG"
echo "现在去 Actions 手动运行编译（机型选 $DEVICE，勾选强制编译），CI 会自动下载这个缓存。"
