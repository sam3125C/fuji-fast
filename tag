#!/usr/bin/env bash
#
# tag - 同步照片配套文件的 Finder 标签
#
# 用法:
#   tag <动作> <目录>
#
# 动作:
#   jpg2raf   将目录下同名 RAF 文件的标签标记为与 JPG 一致
#             （只处理该目录，不递归子目录）
#
# 示例:
#   tag jpg2raf ./
#   tag jpg2raf ~/Pictures/101_FUJI
#
# 说明:
#   - 仅支持 macOS，依赖系统自带的 xattr 命令
#   - 标签属性存在但内容为空数组，视为“无标签”
#   - JPG 无标签时，会清除同名 RAF 的实际标签，使两者保持一致

set -uo pipefail

TAG_ATTR="com.apple.metadata:_kMDItemUserTags"

usage() {
    cat >&2 <<'EOF'
用法: tag <动作> <目录>

动作:
  jpg2raf   将目录下同名 RAF 文件的标签标记为与 JPG 一致

示例:
  tag jpg2raf ./
EOF
}

to_lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# has_real_tags <file>
# 文件带有“非空”的标签数组时返回 0，否则返回 1。
# bplist 前 8 字节为 "bplist00"，第 9 字节是数组 marker：
#   A0 = 空数组（无标签），A1..AF = 非空数组。
has_real_tags() {
    local f="$1" hex marker
    xattr "$f" 2>/dev/null | grep -qx "$TAG_ATTR" || return 1
    hex=$(xattr -px "$TAG_ATTR" "$f" 2>/dev/null | tr -d ' \n' | tr 'A-F' 'a-f')
    [ "${#hex}" -ge 18 ] || return 1
    marker="${hex:16:2}"          # 第 9 字节（前 8 字节 = 16 个 hex 字符）
    [ "${marker:0:1}" = "a" ] || return 1
    [ "$marker" = "a0" ] && return 1
    return 0
}

# 仅支持 macOS
if [ "$(uname -s)" != "Darwin" ]; then
    echo "错误: tag 仅支持 macOS" >&2
    exit 1
fi

if ! command -v xattr >/dev/null 2>&1; then
    echo "错误: 未找到 xattr 命令" >&2
    exit 1
fi

if [ $# -ne 2 ]; then
    echo "错误: 需要 2 个参数" >&2
    usage
    exit 1
fi

ACTION="$1"
DIR="$2"

case "$ACTION" in
    jpg2raf) ;;
    *)
        echo "错误: 不支持的动作 '$ACTION'，目前仅支持 jpg2raf" >&2
        usage
        exit 1
        ;;
esac

if [ ! -d "$DIR" ]; then
    echo "错误: 目录不存在: $DIR" >&2
    exit 1
fi

# 先把 JPG / RAF 列表读入数组，避免在循环中嵌套进程替换导致输出交错
jpgs=()
while IFS= read -r -d '' f; do jpgs+=("$f"); done \
    < <(find "$DIR" -maxdepth 1 -type f -iname '*.jpg' -print0 2>/dev/null)

rafs=()
while IFS= read -r -d '' f; do rafs+=("$f"); done \
    < <(find "$DIR" -maxdepth 1 -type f -iname '*.raf' -print0 2>/dev/null)

# 统计
ok=0        # JPG 有标签，已同步到 RAF
cleared=0   # JPG 无标签，RAF 有实际标签，已清除
untagged=0  # JPG、RAF 均无标签，无需动作
no_raf=0    # 找不到同名 RAF
failed=0    # 处理失败

for jpg in "${jpgs[@]}"; do
    jpg_name=$(basename "$jpg")
    stem="${jpg_name%.*}"
    stem_lower=$(to_lower "$stem")

    # 在数组中查找同名 RAF
    raf=""
    for cand in "${rafs[@]}"; do
        cand_stem="$(basename "$cand")"
        cand_stem="${cand_stem%.*}"
        if [ "$(to_lower "$cand_stem")" = "$stem_lower" ]; then
            raf="$cand"
            break
        fi
    done

    if [ -z "$raf" ]; then
        echo "跳过(无RAF): $jpg_name"
        no_raf=$((no_raf + 1))
        continue
    fi

    raf_name=$(basename "$raf")

    if has_real_tags "$jpg"; then
        # JPG 有实际标签：复制到 RAF
        hex=$(xattr -px "$TAG_ATTR" "$jpg" 2>/dev/null | tr '\n' ' ')
        if [ -n "$(printf '%s' "$hex" | tr -d '[:space:]')" ] \
            && xattr -wx "$TAG_ATTR" "$hex" "$raf" 2>/dev/null; then
            echo "已标记: $raf_name"
            ok=$((ok + 1))
        else
            echo "失败: $raf_name"
            failed=$((failed + 1))
        fi
    else
        # JPG 无实际标签
        if has_real_tags "$raf"; then
            # RAF 有实际标签，清除
            if xattr -d "$TAG_ATTR" "$raf" 2>/dev/null; then
                echo "已清除标签: $raf_name"
                cleared=$((cleared + 1))
            else
                echo "失败(无法清除): $raf_name"
                failed=$((failed + 1))
            fi
        else
            # RAF 也无实际标签；若残留空数组属性则清理（静默，不计动作）
            if xattr "$raf" 2>/dev/null | grep -qx "$TAG_ATTR"; then
                xattr -d "$TAG_ATTR" "$raf" 2>/dev/null
            fi
            echo "无标签(未处理): $jpg_name"
            untagged=$((untagged + 1))
        fi
    fi
done

echo "----"
echo "完成: 已标记 $ok, 已清除 $cleared, 无标签 $untagged, 无RAF $no_raf, 失败 $failed"

if [ "$failed" -gt 0 ]; then
    exit 1
fi
exit 0
