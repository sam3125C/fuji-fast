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
#   - JPG 无标签时，会清除同名 RAF 的标签，使两者保持一致

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

# 统计
ok=0        # 成功复制标签
cleared=0   # JPG 无标签，已清除 RAF 标签
no_raf=0    # 找不到同名 RAF
failed=0    # 处理失败

# 遍历目录下所有 JPG（大小写不敏感、不递归）
while IFS= read -r -d '' jpg; do
    jpg_name=$(basename "$jpg")
    stem="${jpg_name%.*}"
    stem_lower=$(to_lower "$stem")

    # 查找同名 RAF（大小写不敏感），通过逐一比对避免通配符问题
    raf=""
    while IFS= read -r -d '' cand; do
        cand_stem="$(basename "$cand")"
        cand_stem="${cand_stem%.*}"
        if [ "$(to_lower "$cand_stem")" = "$stem_lower" ]; then
            raf="$cand"
            break
        fi
    done < <(find "$DIR" -maxdepth 1 -type f -iname '*.raf' -print0 2>/dev/null)

    if [ -z "$raf" ]; then
        echo "跳过(无RAF): $jpg_name"
        no_raf=$((no_raf + 1))
        continue
    fi

    # JPG 是否带有标签
    if ! xattr "$jpg" 2>/dev/null | grep -qx "$TAG_ATTR"; then
        # JPG 无标签，清除 RAF 标签（若有）
        if xattr "$raf" 2>/dev/null | grep -qx "$TAG_ATTR"; then
            if xattr -d "$TAG_ATTR" "$raf" 2>/dev/null; then
                echo "已清除标签: $(basename "$raf")"
                cleared=$((cleared + 1))
            else
                echo "失败(无法清除): $(basename "$raf")"
                failed=$((failed + 1))
            fi
        fi
        continue
    fi

    # 读取 JPG 标签（十六进制）并写入 RAF
    hex=$(xattr -px "$TAG_ATTR" "$jpg" 2>/dev/null | tr '\n' ' ')
    if [ -z "$(printf '%s' "$hex" | tr -d '[:space:]')" ]; then
        echo "失败(无法读取标签): $jpg_name"
        failed=$((failed + 1))
        continue
    fi

    if xattr -wx "$TAG_ATTR" "$hex" "$raf" 2>/dev/null; then
        echo "已标记: $(basename "$raf")"
        ok=$((ok + 1))
    else
        echo "失败: $(basename "$raf")"
        failed=$((failed + 1))
    fi
done < <(find "$DIR" -maxdepth 1 -type f -iname '*.jpg' -print0 2>/dev/null)

echo "----"
echo "完成: 已标记 $ok, 已清除 $cleared, 无RAF $no_raf, 失败 $failed"

if [ "$failed" -gt 0 ]; then
    exit 1
fi
exit 0
