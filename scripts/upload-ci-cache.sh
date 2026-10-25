#!/usr/bin/env bash
# 把 pack-ci-cache.sh 打好的缓存上传到本仓库的 GitHub Release（预发布，tag：ci-cache-<机型>-<上游短SHA>）。
# 重复运行是安全的：Release 不存在就创建，存在就覆盖同名文件、删掉多余的旧切片。只会上传缓存文件，不会上传固件。
# 用法见 ./scripts/upload-ci-cache.sh --help
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

usage() {
	cat <<'USAGE'
用法：./scripts/upload-ci-cache.sh [选项] <机型 | 打包目录>

机型：x86 | x86_64、ys | arthur、ydn | athena（自动找 build/ci-cache/ 下该机型最新的打包目录）
也可以直接给 pack-ci-cache.sh 的输出目录。

选项：
  --repo OWNER/NAME   上传到哪个仓库，默认取本仓库 git remote origin
  --prune             上传成功后删掉该机型其他（旧上游 SHA 的）ci-cache Release，节省空间
  -h, --help          显示本帮助

需要 GitHub CLI 并已登录：sudo apt install gh && gh auth login
USAGE
}

die() { echo "错误：$*" >&2; exit 1; }

TARGET=""
REPO=""
PRUNE=0
while [ $# -gt 0 ]; do
	case "$1" in
		-h | --help) usage; exit 0 ;;
		--repo) [ $# -ge 2 ] || die "--repo 后面要跟 OWNER/NAME"; REPO="$2"; shift ;;
		--prune) PRUNE=1 ;;
		-*) die "未知选项 $1（看 --help）" ;;
		*) [ -z "$TARGET" ] || die "只能指定一个机型或目录"; TARGET="$1" ;;
	esac
	shift
done
[ -n "$TARGET" ] || { usage; exit 1; }
command -v gh >/dev/null || die "没有 gh 命令：sudo apt install gh，然后 gh auth login"
gh auth status >/dev/null 2>&1 || die "gh 还没登录：先运行 gh auth login"

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
FILES=()
OTHER=0
for p in "$DIR"/*; do
	f=$(basename "$p")
	if [[ "$f" =~ ^((toolchain|ccache|dl)\.tar\.zst\.part[0-9]+|ci-cache\.env|SHA256SUMS)$ ]]; then
		FILES+=("$f")
	else
		OTHER=1
	fi
done
[ "${#FILES[@]}" -gt 2 ] || die "$DIR 里没有 *.tar.zst.partNN"
[ "$OTHER" -eq 0 ] || echo "注意：$DIR 里有其他文件，不会上传"
for f in "${FILES[@]}"; do
	sz=$(stat -c %s "$DIR/$f")
	[ "$sz" -lt 2147483648 ] || die "$f 超过 2 GB（GitHub Release 单文件上限），请重新运行 pack-ci-cache.sh"
done

echo "==> 校验 SHA256SUMS"
(cd "$DIR" && sha256sum -c --quiet SHA256SUMS) || die "校验失败，请重新打包"

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

# 先传数据切片，最后传 ci-cache.env / SHA256SUMS
DATA=()
for f in "${FILES[@]}"; do
	case "$f" in ci-cache.env | SHA256SUMS) ;; *) DATA+=("$DIR/$f") ;; esac
done
echo "==> 上传 ${#DATA[@]} 个切片（大文件需要一段时间）"
for f in "${DATA[@]}"; do
	echo "  $(basename "$f")（$(du -h "$f" | cut -f1)）"
	gh release upload "$TAG" "$f" --repo "$REPO" --clobber
done
gh release upload "$TAG" "$DIR/ci-cache.env" "$DIR/SHA256SUMS" --repo "$REPO" --clobber

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
