#!/bin/bash
# x86_64 专用：给内核配置补上「新出现、没人回答」的选项，避免编译内核时卡在交互提问。
# 工作目录为 openwrt 源码根目录，由 scripts/x86_64-extra-packages.sh 在最后调用。
#
# 原因：configs/x86_64.config 里打开的部分 CONFIG_KERNEL_* 选项（例如 DETECT_HUNG_TASK）
# 会让内核多出几个子选项，而 ImmortalWrt 的 target/linux/generic/config-<版本> 里没有给它们定值，
# 内核执行 syncconfig 时就会出现 "(NEW) ... [Y/n/?]" 的提问；CI 里没有人回答，直接报错。
# 这些子选项写不进 .config（make defconfig 会删掉不认识的 CONFIG_KERNEL_*），
# 所以追加到 x86/64 子目标的内核配置里，只影响 x86_64，雅典娜/亚瑟不受影响。
set -euo pipefail

PATCHVER=$(sed -n 's/^KERNEL_PATCHVER:=[[:space:]]*//p' target/linux/x86/Makefile | head -n1)
[ -n "$PATCHVER" ] || { echo "kernel-fixups: 读不到 KERNEL_PATCHVER" >&2; exit 1; }
CONF="target/linux/x86/64/config-$PATCHVER"
touch "$CONF"

# 每行一个选项，写法和内核 .config 一样
FIXUPS='
CONFIG_DETECT_HUNG_TASK_BLOCKER=y
'

for line in $FIXUPS; do
	sym=${line%%=*}
	# 上游已经在 generic / x86 / x86_64 任一配置里定过值，就不再追加，以上游为准
	if grep -qE "^(# )?${sym}([= ]|$)" \
		"target/linux/generic/config-$PATCHVER" "target/linux/x86/config-$PATCHVER" "$CONF" 2>/dev/null; then
		echo "kernel-fixups: ${sym} 上游已有定义，跳过"
		continue
	fi
	echo "$line" >> "$CONF"
	echo "kernel-fixups: 追加 ${line} -> ${CONF}"
done
