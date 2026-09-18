#!/bin/bash

# 微信双开 - 公共配置与工具函数
# 供 create-wechat-dual.sh 与 check-wechat-dual.sh 复用

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============ 配置 ============
ORIGINAL_APP="/Applications/WeChat.app"
DUAL_APP_NAME="微信双开"
TEMP_DUAL_APP_NAME="WeChat-Dual-Temp"
DUAL_APP="/Applications/${DUAL_APP_NAME}.app"
BUNDLE_ID_SUFFIX=".dual"

# 图标改色后的主色（原版绿约 5,207,102）
EXPECTED_BLUE_TONE="blue"
EXPECTED_GREEN_TONE="green"

# WeApp 子应用的相对路径（其 Bundle ID 也需改写，否则双开与原版会互相干扰）
HELPER_APP_REL="Contents/MacOS/WeChatAppEx.app/Contents/Frameworks/WeChatAppEx Framework.framework/Versions/C/Helpers/WeApp.app"
HELPER_ORIGINAL_BUNDLE_ID="com.tencent.flue.WeApp"

# 当前脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ICON_SCRIPT="$SCRIPT_DIR/replace_icon_color.py"

# 真实用户（脚本通常以 sudo 运行，需要以此身份操作 LaunchServices 与用户缓存）
real_user() {
    if [ -n "${SUDO_USER:-}" ]; then
        echo "$SUDO_USER"
    else
        id -un
    fi
}

real_home() {
    local u
    u="$(real_user)"
    if [ "$u" = "root" ]; then
        echo "$HOME"
    else
        eval echo "~$u"
    fi
}

# ============ 输出 ============
print_info() {
    printf "${BLUE}[INFO]${NC} %s\n" "$1"
}

print_success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"
}

print_warning() {
    printf "${YELLOW}[WARNING]${NC} %s\n" "$1"
}

print_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

# ============ plist 读写 ============
# defaults read 对含中文/空格的路径不友好，统一用 plutil
read_plist_value() {
    local plist="$1"
    local key="$2"
    local fallback="${3:-未知}"
    local value
    if value=$(plutil -extract "$key" raw "$plist" 2>/dev/null) && [ -n "$value" ]; then
        printf '%s' "$value"
    else
        printf '%s' "$fallback"
    fi
}

# 设置 plist 中的字符串（存在则替换，不存在则插入）
set_plist_string() {
    local plist="$1"
    local key="$2"
    local value="$3"

    if plutil -extract "$key" raw "$plist" >/dev/null 2>&1; then
        plutil -replace "$key" -string "$value" "$plist"
    else
        plutil -insert "$key" -string "$value" "$plist"
    fi
}

# 删除 plist 中的键（不存在时静默通过）
delete_plist_key() {
    local plist="$1"
    local key="$2"
    if plutil -extract "$key" raw "$plist" >/dev/null 2>&1; then
        plutil -remove "$key" "$plist" >/dev/null 2>&1
    fi
    return 0
}

# ============ 临时文件 ============
# 不能用 mktemp -t <prefix>：Homebrew 安装的 GNU coreutils 若排在 PATH 前面，
# mktemp 为 GNU 版本，它不认 -t 的隐式模板，会报 "too few X's" 并把空串
# 当路径返回，导致后续操作落到当前目录或根目录。这里显式指定带 XXXXXX
# 的模板，兼容 BSD 与 GNU 两种实现。
make_temp_file() {
    local prefix="$1"
    local suffix="${2:-}"
    local template="${TMPDIR:-/tmp}/"
    template="${template%/}/wechat_dual_${prefix}.XXXXXXXX"

    local path
    if ! path="$(mktemp "$template" 2>/dev/null)" || [ -z "$path" ]; then
        return 1
    fi

    if [ -n "$suffix" ]; then
        mv "$path" "${path}${suffix}" 2>/dev/null || true
        path="${path}${suffix}"
    fi

    printf '%s' "$path"
}

make_temp_dir() {
    local prefix="$1"
    local template="${TMPDIR:-/tmp}/"
    template="${template%/}/wechat_dual_${prefix}.XXXXXXXX"

    mktemp -d "$template" 2>/dev/null
}

# ============ 本地化字符串表 ============
# .lproj/InfoPlist.strings 优先级高于 Info.plist，Dock 与启动台取的就是这里的名字。
# 该文件是 UTF-16 编码的二进制 plist，直接替换中文会失败，因此走 json 中转。
set_localized_name() {
    local strings_file="$1"
    local new_name="$2"

    if [ ! -f "$strings_file" ]; then
        return 1
    fi

    local tmp_json tmp_out
    tmp_json="$(make_temp_file lproj .json)" || return 1
    tmp_out="$(make_temp_file lproj .strings)" || { rm -f "$tmp_json"; return 1; }

    # 分步写入临时文件，全部成功后才替换原文件，
    # 避免中途失败把原本可用的本地化资源写坏
    if ! plutil -convert json -o "$tmp_json" "$strings_file" 2>/dev/null; then
        rm -f "$tmp_json" "$tmp_out"
        return 1
    fi

    if ! plutil -replace CFBundleDisplayName -string "$new_name" "$tmp_json" 2>/dev/null; then
        rm -f "$tmp_json" "$tmp_out"
        return 1
    fi
    plutil -replace CFBundleName -string "$new_name" "$tmp_json" 2>/dev/null

    if ! plutil -convert binary1 -o "$tmp_out" "$tmp_json" 2>/dev/null; then
        rm -f "$tmp_json" "$tmp_out"
        return 1
    fi

    # 保留原文件权限（cp 会沿用目标文件的 inode 权限，mv 会带入临时文件权限）
    if ! cat "$tmp_out" > "$strings_file" 2>/dev/null; then
        rm -f "$tmp_json" "$tmp_out"
        return 1
    fi

    rm -f "$tmp_json" "$tmp_out"
    return 0
}

# ============ 图标处理 ============
# 判断改色能力是否就绪（需要 Pillow）
icon_tooling_ready() {
    [ -f "$ICON_SCRIPT" ] || return 1
    if python3 -c "from PIL import Image" 2>/dev/null; then
        return 0
    fi
    # sudo 环境下依赖装在原用户下
    if [ -n "${SUDO_USER:-}" ] && sudo -u "$SUDO_USER" python3 -c "from PIL import Image" 2>/dev/null; then
        return 0
    fi
    return 1
}

# 以原用户身份运行命令，避免 sudo 下 PATH、依赖、文件属主与登录用户不一致
run_as_user() {
    if [ -n "${SUDO_USER:-}" ]; then
        sudo -u "$SUDO_USER" "$@"
    else
        "$@"
    fi
}

# 以原用户身份运行图标脚本，避免 sudo 下找不到 Pillow
run_icon_script() {
    run_as_user python3 "$ICON_SCRIPT" "$@"
}

# 安装 Pillow
ensure_pillow() {
    if icon_tooling_ready; then
        return 0
    fi

    print_info "检测到 Pillow 未安装，正在自动安装..."

    local ok=1
    if [ -n "${SUDO_USER:-}" ]; then
        sudo -u "$SUDO_USER" pip3 install Pillow -q >/dev/null 2>&1 && ok=0
    else
        pip3 install Pillow -q >/dev/null 2>&1 && ok=0
    fi

    if [ "$ok" -eq 0 ] && icon_tooling_ready; then
        print_success "Pillow 安装成功"
        return 0
    fi

    print_warning "Pillow 安装失败"
    print_info "可手动执行: pip3 install Pillow"
    return 1
}

# 从 ICNS 解出 iconset 目录
extract_iconset() {
    local src_icns="$1"
    local out_dir="$2"

    rm -rf "$out_dir"
    if ! iconutil --convert iconset "$src_icns" --output "$out_dir" 2>/dev/null; then
        return 1
    fi
    [ -n "$(ls -A "$out_dir" 2>/dev/null)" ] || return 1
    return 0
}

# 从 iconset 打包回 ICNS
pack_iconset() {
    local iconset_dir="$1"
    local out_icns="$2"
    iconutil --convert icns "$iconset_dir" --output "$out_icns" 2>/dev/null
}

# 用 actool 把 iconset 编译为 Assets.car（微信 4.x 起系统优先读取该文件）
# 成功时输出生成的 Assets.car 路径，失败输出空
#
# 产物在同一用户身份下生成：整个中间目录先交给原用户，再由原用户创建
# xcassets 与输出目录。若由 root 创建目录、再由原用户写入，会因目录属主
# 是 root 而写入失败（脚本以 sudo 运行，这一步是实际踩过的坑）。
compile_assets_car() {
    local iconset_dir="$1"
    local out_dir="$2"
    local owner
    owner="$(real_user)"

    [ -d "$iconset_dir" ] || return 0

    if ! xcrun --find actool >/dev/null 2>&1; then
        return 0
    fi

    # 交给原用户后，中间产物全部以该身份创建
    local work_dir="$out_dir/work"
    rm -rf "$work_dir"
    mkdir -p "$work_dir"
    chown -R "$owner" "$out_dir" 2>/dev/null || true

    local xcassets="$work_dir/AppIcon.xcassets"
    if ! run_icon_script --xcassets "$iconset_dir" "$xcassets" >/dev/null 2>&1; then
        return 0
    fi

    local car_out="$work_dir/car"
    mkdir -p "$car_out"
    chown -R "$owner" "$work_dir" 2>/dev/null || true

    if ! run_as_user xcrun actool \
        --output-format human-readable-text \
        --app-icon AppIcon \
        --output-partial-info-plist "$car_out/partial.plist" \
        --target-device mac \
        --minimum-deployment-target 12.0 \
        --platform macosx \
        --compile "$car_out" \
        "$xcassets" >/dev/null 2>&1; then
        return 0
    fi

    if [ -f "$car_out/Assets.car" ]; then
        printf '%s' "$car_out/Assets.car"
    fi
}

# 调用系统 API 渲染应用的真实图标（Dock / 启动台看到的就是这张）
# 输出 PNG 路径，失败输出空
render_app_icon() {
    local app_path="$1"
    local out_png="$2"

    rm -f "$out_png"

    local js_file
    js_file="$(make_temp_file render .js)" || return 0
    cat > "$js_file" <<JSEOF
ObjC.import('Cocoa');
var icon = \$.NSWorkspace.sharedWorkspace.iconForFile('$app_path');
var rep = \$.NSBitmapImageRep.imageRepWithData(icon.TIFFRepresentation);
rep.representationUsingTypeProperties(\$.NSBitmapImageFileTypePNG, \$()).writeToFileAtomically('$out_png', true);
JSEOF

    osascript -l JavaScript "$js_file" >/dev/null 2>&1
    rm -f "$js_file"

    if [ -f "$out_png" ]; then
        printf '%s' "$out_png"
    fi
}

# 判断图标色调，输出 green / blue / unknown
icon_tone() {
    local target="$1"
    local tone

    [ -f "$ICON_SCRIPT" ] || { echo "unknown"; return 0; }
    icon_tooling_ready || { echo "unknown"; return 0; }

    tone="$(run_icon_script --probe "$target" 2>/dev/null | tail -1 | awk -F',' '{print $NF}')"
    case "$tone" in
        green|blue) echo "$tone" ;;
        *) echo "unknown" ;;
    esac
}

# 判断给定应用当前被系统渲染出的图标色调（最接近用户观感的判定）
app_icon_tone() {
    local app_path="$1"
    local tmp_png
    tmp_png="$(make_temp_file icon .png)" || { echo "unknown"; return 0; }

    if [ -z "$(render_app_icon "$app_path" "$tmp_png")" ]; then
        rm -f "$tmp_png"
        echo "unknown"
        return 0
    fi

    local tone
    tone="$(icon_tone "$tmp_png")"
    rm -f "$tmp_png"
    echo "$tone"
}

# ============ 启动台数据库 ============
# 启动台数据库路径（位于用户的 Darwin 缓存目录下）
launchpad_db() {
    local u
    u="$(real_user)"
    local user_dir
    user_dir="$(run_as_user getconf DARWIN_USER_DIR 2>/dev/null)"
    [ -n "$user_dir" ] || return 1
    printf '%s' "${user_dir}com.apple.dock.launchpad/db/db"
}

# 列出某个 Bundle ID 下已失效的启动台条目 ID（书签指向的应用已不在磁盘上）
# 条目书签以「长度 + UTF-8」编码保存卷内相对路径，据此还原绝对路径后判断存在性。
stale_launchpad_items() {
    local bundle_id="$1"
    local db
    db="$(launchpad_db)" || return 0
    [ -f "$db" ] || return 0

    python3 - "$db" "$bundle_id" <<'PY' 2>/dev/null
import os, re, sqlite3, sys

db_path, bundle_id = sys.argv[1], sys.argv[2]
con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)

# 书签中的路径组件：4 字节小端长度 + 4 字节标志 + UTF-8 数据
def components(blob):
    b = bytes(blob)
    out, i = [], 0
    while i + 8 <= len(b):
        n = int.from_bytes(b[i:i + 4], "little")
        if 1 <= n <= 200 and i + 8 + n <= len(b):
            try:
                s = b[i + 8:i + 8 + n].decode("utf-8")
            except UnicodeDecodeError:
                i += 1
                continue
            if re.fullmatch(r"[\w .\-+()一-鿿]+", s):
                out.append(s)
                i += 8 + n
                continue
        i += 1
    return out

def volume_relative_path(comps):
    if not any(c.endswith(".app") for c in comps):
        return None
    # 书签中 .app 之后是卷名与卷 UUID 等标识信息，不属于路径，
    # 因此以最后一个 .app 组件作为路径终点（不依赖卷名，卷重命名也不会失效）
    names = [i for i, c in enumerate(comps) if c.endswith(".app")]
    parts = [c for c in comps[:names[-1] + 1] if c != " "]
    return "/" + "/".join(parts) if parts else None

for item_id, title, blob in con.execute(
        "SELECT item_id, title, bookmark FROM apps WHERE bundleid=?", (bundle_id,)):
    if not blob:
        continue
    path = volume_relative_path(components(blob))
    # 还原出的路径不存在，且同名应用也不在常见位置，即视为失效条目
    if path and not os.path.exists(path):
        name = os.path.basename(path)
        if not os.path.exists(f"/Applications/{name}") and \
           not os.path.exists(f"/System/Applications/{name}"):
            print(item_id)
PY
}

# 删除启动台条目（连带其图标缓存与可能的子级项）
remove_launchpad_items() {
    local db="$1"
    shift
    local id_list
    id_list="$(printf '%s,' "$@" | sed 's/,$//')"
    [ -n "$id_list" ] || return 0

    run_as_user sqlite3 "$db" <<SQL >/dev/null 2>&1
PRAGMA wal_checkpoint(TRUNCATE);
BEGIN;
DELETE FROM image_cache WHERE item_id IN ($id_list);
DELETE FROM items WHERE parent_id IN ($id_list);
DELETE FROM items WHERE rowid IN ($id_list);
DELETE FROM apps WHERE item_id IN ($id_list);
COMMIT;
SQL
}

refresh_icon_cache() {
    local u
    u="$(real_user)"

    # 图标渲染结果按 Bundle ID 缓存，改动图标后必须清掉才会重新出图。
    # 缓存位于系统级 /Library/Caches 下，清理需要 root 权限。
    local user_dir
    user_dir="$(sudo -u "$u" getconf DARWIN_USER_DIR 2>/dev/null)"
    if [ -n "$user_dir" ]; then
        rm -rf "${user_dir}com.apple.iconservices.store" 2>/dev/null
        rm -f "${user_dir}com.apple.dock.iconcache" 2>/dev/null
    fi

    rm -rf "$(real_home)/Library/Caches/com.apple.iconservices.store" 2>/dev/null
    rm -rf /Library/Caches/com.apple.iconservices.store 2>/dev/null

    killall Dock >/dev/null 2>&1 || true
}
