#!/bin/bash

# macOS 微信双开制作脚本
# 功能：复制微信、改写 Bundle ID、替换图标颜色、重新签名
#
# 注意: 本脚本不使用 set -e。原因见 bash-return-exit-issue.md——
# 函数返回非零值会直接终止脚本，导致检查流程被跳过。
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wechat-dual-common.sh"

# 版本比较的判定结果（由 decide_action 设置）
NEED_COPY_ACTION=""

# 检查原版微信是否存在
check_original_app() {
    if [ ! -d "$ORIGINAL_APP" ]; then
        print_error "找不到原版微信应用: $ORIGINAL_APP"
        print_info "请先安装微信到 /Applications/WeChat.app"
        exit 1
    fi
    print_success "找到原版微信应用"
}

# 读取原版版本信息
load_version_info() {
    ORIGINAL_VERSION="$(read_plist_value "$ORIGINAL_APP/Contents/Info.plist" CFBundleShortVersionString)"
    ORIGINAL_BUNDLE_VERSION="$(read_plist_value "$ORIGINAL_APP/Contents/Info.plist" WeChatBundleVersion)"
    print_info "原版微信版本: $ORIGINAL_VERSION (内部版本: $ORIGINAL_BUNDLE_VERSION)"
}

# 比较两个版本号，前者大于后者返回 0
version_gt() {
    local a="$1" b="$2"
    [ "$a" = "$b" ] && return 1
    local IFS=.
    local -a av=($a) bv=($b)
    local i
    for i in 0 1 2; do
        local x="${av[$i]:-0}" y="${bv[$i]:-0}"
        [ "$x" -gt "$y" ] 2>/dev/null && return 0
        [ "$x" -lt "$y" ] 2>/dev/null && return 1
    done
    return 1
}

# 决定采用哪种处理方式，结果写入 NEED_COPY_ACTION
#   rebuild_from_original - 原版更新了，从原版重新复制
#   rebuild_from_dual     - 双开版本更新了，基于双开重新复制
#   fix_config            - 版本无变化，仅修复配置
decide_action() {
    NEED_COPY_ACTION="fix_config"

    if [ ! -d "$DUAL_APP" ]; then
        print_info "未检测到双开版本，将从原版微信创建"
        NEED_COPY_ACTION="rebuild_from_original"
        return 0
    fi

    local dual_version
    dual_version="$(read_plist_value "$DUAL_APP/Contents/Info.plist" CFBundleShortVersionString)"

    echo ""
    echo "=== 版本号比较 ==="
    echo ""
    echo "原版微信:"
    echo "  显示版本: $ORIGINAL_VERSION"
    echo "  内部版本: $ORIGINAL_BUNDLE_VERSION"
    echo ""
    echo "微信双开:"
    echo "  显示版本: $dual_version"
    echo ""

    if version_gt "$dual_version" "$ORIGINAL_VERSION"; then
        print_info "双开版本高于原版微信 ($dual_version > $ORIGINAL_VERSION)"
        print_info "基于双开版本重建，保留已更新的内容"
        NEED_COPY_ACTION="rebuild_from_dual"
    elif version_gt "$ORIGINAL_VERSION" "$dual_version"; then
        print_info "原版微信已更新 ($ORIGINAL_VERSION > $dual_version)"
        print_info "从原版微信重新复制"
        NEED_COPY_ACTION="rebuild_from_original"
    else
        print_info "版本一致 ($dual_version)，仅修复配置"
        NEED_COPY_ACTION="fix_config"
    fi

    return 0
}

# 复制应用
copy_app() {
    local source_app="${1:-$ORIGINAL_APP}"
    local dest_app="/Applications/${TEMP_DUAL_APP_NAME}.app"

    print_info "正在复制微信应用..."
    print_info "源路径: $source_app"
    print_info "目标路径: $dest_app"

    if [ ! -d "$source_app" ]; then
        print_error "源应用不存在: $source_app"
        exit 1
    fi

    print_warning "这可能需要几分钟时间，请耐心等待..."
    if ! sudo cp -R "$source_app" "$dest_app"; then
        print_error "复制失败，请检查权限"
        exit 1
    fi

    if [ ! -d "$dest_app" ]; then
        print_error "复制结果验证失败"
        exit 1
    fi
    print_success "应用复制完成"
}

# 删除旧的双开版本（复制完成后调用，避免复制中途失败丢掉现有版本）
remove_old_dual() {
    if [ -d "$DUAL_APP" ]; then
        print_info "删除旧的双开版本..."
        if ! sudo rm -rf "$DUAL_APP"; then
            print_error "旧版本删除失败"
            exit 1
        fi
        print_success "旧版本已删除"
    fi
}

# 修改 Bundle Identifier
modify_bundle_id() {
    local app="${1:-/Applications/${TEMP_DUAL_APP_NAME}.app}"
    local plist="$app/Contents/Info.plist"

    if [ ! -f "$plist" ]; then
        print_error "Info.plist 不存在: $plist"
        exit 1
    fi

    local original_bundle_id
    original_bundle_id="$(read_plist_value "$plist" CFBundleIdentifier "")"

    if [ -z "$original_bundle_id" ]; then
        print_error "无法读取 Bundle Identifier"
        exit 1
    fi

    # 已经带过 .dual 后缀时先去掉，避免重复叠加
    if [[ "$original_bundle_id" == *"$BUNDLE_ID_SUFFIX" ]]; then
        original_bundle_id="${original_bundle_id%$BUNDLE_ID_SUFFIX}"
        print_info "检测到已有 ${BUNDLE_ID_SUFFIX} 后缀，已去除"
    fi

    local new_bundle_id="${original_bundle_id}${BUNDLE_ID_SUFFIX}"

    print_info "正在修改 Bundle Identifier..."
    print_info "原始: $original_bundle_id"
    print_info "修改为: $new_bundle_id"

    if ! sudo /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $new_bundle_id" "$plist"; then
        print_error "Bundle Identifier 修改失败"
        exit 1
    fi
    print_success "Bundle Identifier 修改成功"
}

# 修改 WeApp 子应用的 Bundle Identifier
# 该子应用与上下文菜单/小程序相关，不改写会与原版共用同一标识
modify_helper_bundle_id() {
    local app="${1:-/Applications/${TEMP_DUAL_APP_NAME}.app}"
    local helper_app="$app/$HELPER_APP_REL"
    local new_helper_id="${HELPER_ORIGINAL_BUNDLE_ID}${BUNDLE_ID_SUFFIX}"

    if [ ! -f "$helper_app/Contents/Info.plist" ]; then
        print_warning "找不到 WeApp 子应用，跳过修改"
        return 0
    fi

    print_info "正在修改 WeApp 子应用的 Bundle Identifier..."

    if sudo /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $new_helper_id" \
        "$helper_app/Contents/Info.plist"; then
        print_success "WeApp Bundle Identifier 修改成功: $new_helper_id"
    else
        print_warning "WeApp Bundle Identifier 修改失败（可能不影响使用）"
    fi
}

# 修改应用显示名称
# Dock 与启动台取的是 .lproj/InfoPlist.strings，其优先级高于 Info.plist，
# 只改 Info.plist 名称不会变化。
modify_display_name() {
    local app="${1:-/Applications/${TEMP_DUAL_APP_NAME}.app}"
    local plist="$app/Contents/Info.plist"

    print_info "正在修改应用显示名称..."

    # 脚本以 root 运行，可直接改写；用 plutil 而非 PlistBuddy 是因为
    # PlistBuddy 的 Set 在键不存在时会失败，而 plutil 可兜底插入
    set_plist_string "$plist" CFBundleDisplayName "$DUAL_APP_NAME" 2>/dev/null
    set_plist_string "$plist" CFBundleName "$DUAL_APP_NAME" 2>/dev/null
    set_plist_string "$plist" CFBundleGetInfoString "$DUAL_APP_NAME" 2>/dev/null

    local updated=0
    local lproj
    for lproj in "$app"/Contents/Resources/*.lproj; do
        if [ -f "$lproj/InfoPlist.strings" ] && [ -w "$lproj/InfoPlist.strings" ]; then
            if set_localized_name "$lproj/InfoPlist.strings" "$DUAL_APP_NAME"; then
                updated=$((updated + 1))
            fi
        fi
    done

    if [ "$updated" -gt 0 ]; then
        print_success "显示名称已改为「${DUAL_APP_NAME}」（含 ${updated} 个本地化资源）"
    else
        print_warning "本地化名称修改失败，Dock 与启动台可能仍显示原名"
    fi
}

# 替换图标颜色
# 微信 4.x 同时提供 AppIcon.icns 与 Assets.car，且 Info.plist 声明了
# CFBundleIconName。只要 Assets.car 存在，系统优先使用其中的图标，
# 因此两者必须一起替换。源图一律取原版微信的图标，避免重复运行导致色相二次偏移。
replace_icon_color() {
    local app="${1:-/Applications/${TEMP_DUAL_APP_NAME}.app}"
    local resources="$app/Contents/Resources"
    local src_icns="$ORIGINAL_APP/Contents/Resources/AppIcon.icns"

    print_info "正在替换图标颜色..."

    for tool in iconutil plutil; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            print_warning "缺少 ${tool}，跳过图标颜色替换"
            return 0
        fi
    done

    if [ ! -f "$src_icns" ]; then
        print_warning "找不到源图标文件: ${src_icns}，跳过图标颜色替换"
        return 0
    fi

    if ! ensure_pillow; then
        print_warning "Pillow 不可用，跳过图标颜色替换"
        return 0
    fi

    local temp_dir
    temp_dir="$(make_temp_dir icon)"
    if [ -z "$temp_dir" ]; then
        print_warning "无法创建临时目录，跳过图标颜色替换"
        return 0
    fi
    local iconset_dir="$temp_dir/AppIcon.iconset"

    if ! extract_iconset "$src_icns" "$iconset_dir"; then
        print_warning "图标解压失败，跳过图标颜色替换"
        rm -rf "$temp_dir"
        return 0
    fi

    # 脚本以 root 运行，但改色由原用户身份执行，临时文件需交给原用户
    local owner
    owner="$(real_user)"
    chown -R "$owner" "$temp_dir" 2>/dev/null || true

    # 源图标已是蓝色时不再旋转色相，保证脚本可重复执行
    local src_tone
    src_tone="$(icon_tone "$iconset_dir/icon_256x256.png")"
    if [ "$src_tone" = "blue" ]; then
        print_info "源图标已是蓝色，跳过色相旋转"
    else
        if ! run_icon_script --iconset "$iconset_dir"; then
            print_warning "图标改色失败，保留原图标"
            rm -rf "$temp_dir"
            return 0
        fi
        print_success "图标色相旋转完成（绿色 → 蓝色）"
    fi

    local failed=0

    # 1) 写回 ICNS
    if pack_iconset "$iconset_dir" "$temp_dir/AppIcon.icns"; then
        if sudo cp "$temp_dir/AppIcon.icns" "$resources/AppIcon.icns"; then
            print_success "AppIcon.icns 已更新"
        else
            print_warning "AppIcon.icns 写入失败"
            failed=1
        fi
    else
        print_warning "图标打包失败"
        failed=1
    fi

    # 2) 写回 Assets.car（系统实际读取的图标来源）
    # 以原版微信为准判断是否需要重建：双开是原版的复制品，原版带资源目录
    # 双开就该有。若只看双开自身，一旦上次运行走了回退分支删掉了该文件，
    # 后续运行会因文件不存在而永远跳过重建。
    if [ -f "$ORIGINAL_APP/Contents/Resources/Assets.car" ]; then
        local car_dir="$temp_dir/car"
        mkdir -p "$car_dir"

        local new_car
        new_car="$(compile_assets_car "$iconset_dir" "$car_dir")"

        if [ -n "$new_car" ] && sudo cp "$new_car" "$resources/Assets.car"; then
            print_success "Assets.car 已重建"
        else
            print_warning "Assets.car 重建失败，移除该文件以回退使用 ICNS"
            if sudo rm -f "$resources/Assets.car"; then
                print_info "已移除 Assets.car，系统改用 AppIcon.icns"
            fi
        fi
    fi

    rm -rf "$temp_dir"

    if [ "$failed" -eq 1 ]; then
        print_warning "图标替换未完全成功"
    fi
    return 0
}

# 重新签名
resign_app() {
    local app="${1:-/Applications/${TEMP_DUAL_APP_NAME}.app}"

    print_info "正在重新签名应用..."
    print_warning "这可能需要几分钟时间，请耐心等待..."

    if ! sudo codesign --force --deep --sign - "$app"; then
        print_error "应用签名失败"
        exit 1
    fi
    print_success "应用签名成功"

    if codesign --verify --deep "$app" >/dev/null 2>&1; then
        print_success "签名验证通过"
    else
        print_warning "签名验证失败，但应用可能仍可运行"
    fi
}

# 对已存在的双开版本做签名修复
resign_dual_app() {
    local app="$DUAL_APP"

    print_info "正在重新签名应用..."
    print_warning "这可能需要几分钟时间，请耐心等待..."

    if ! sudo codesign --force --deep --sign - "$app"; then
        print_error "应用签名失败"
        exit 1
    fi
    print_success "应用签名成功"

    # 二进制被改动后签名会失效，此处必须真正校验
    if codesign --verify --deep "$app" >/dev/null 2>&1; then
        print_success "签名验证通过"
    else
        print_warning "签名验证未通过，应用可能无法启动"
        print_info "建议重新执行本脚本进行完整重建"
    fi
}

# 接管 Bundle ID：让系统重新解析应用信息（名称、图标、URL 关联）
register_with_launch_services() {
    local app="$1"
    local u
    u="$(real_user)"

    sudo -u "$u" /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -f "$app" >/dev/null 2>&1 || true
}

# 清理启动台中残留的失效条目
# 复制阶段会短暂生成 WeChat-Dual-Temp.app，Dock 会为它建立启动台条目；
# 应用改名后该条目指向的路径已不存在，会表现为启动台里出现名称错误的
# 重复图标。按书签还原路径、只删除磁盘上确实不存在的条目，避免误删。
clean_launchpad_entries() {
    local bundle_id="$1"

    if ! command -v sqlite3 >/dev/null 2>&1; then
        return 0
    fi

    local db
    db="$(launchpad_db)" || return 0
    [ -f "$db" ] || return 0

    local stale_ids
    stale_ids="$(stale_launchpad_items "$bundle_id")"
    [ -n "$stale_ids" ] || return 0

    local count
    count="$(printf '%s\n' "$stale_ids" | grep -c .)"

    print_warning "启动台存在 ${count} 条失效记录，正在清理"

    # Dock 持有数据库连接并用内存副本回写，改写前必须先停掉它
    killall Dock >/dev/null 2>&1 || true
    sleep 1

    local backup="${db}.bak.$(date +%Y%m%d%H%M%S)"
    if ! sudo cp "$db" "$backup" 2>/dev/null; then
        print_warning "无法备份启动台数据库，跳过清理"
        return 0
    fi

    # shellcheck disable=SC2086
    if ! remove_launchpad_items "$db" $stale_ids; then
        print_warning "启动台记录清理失败，已保留备份: $backup"
        return 0
    fi

    print_success "启动台失效记录已清理"
}

# 重命名为最终名称
rename_to_final() {
    local temp_app="/Applications/${TEMP_DUAL_APP_NAME}.app"

    print_info "正在重命名为最终名称..."
    print_info "临时名称: ${TEMP_DUAL_APP_NAME}.app"
    print_info "最终名称: ${DUAL_APP_NAME}.app"

    remove_old_dual

    if ! sudo mv "$temp_app" "$DUAL_APP"; then
        print_error "重命名失败"
        exit 1
    fi
    print_success "重命名成功"
}

# 显示最终信息
show_summary() {
    local bundle_id
    bundle_id="$(read_plist_value "$DUAL_APP/Contents/Info.plist" CFBundleIdentifier)"
    local version
    version="$(read_plist_value "$DUAL_APP/Contents/Info.plist" CFBundleShortVersionString)"

    echo ""
    echo "=========================================="
    echo "           双开版本处理完成"
    echo "=========================================="
    echo ""
    echo "应用名称: ${DUAL_APP_NAME}.app"
    echo "位置:     $DUAL_APP"
    echo "Bundle:   $bundle_id"
    echo "版本:     $version (原版微信: $ORIGINAL_VERSION)"
    echo ""
    echo "使用说明:"
    echo "1. 打开双开版本: open \"$DUAL_APP\""
    echo "2. 登录第二个微信账号"
    echo ""
    echo "注意: 双开版本自动更新后 Bundle ID 会被重置，"
    echo "      届时重新运行本脚本即可修复，登录状态不会丢失。"
    echo ""
}

# 主函数
main() {
    echo "=========================================="
    echo "     macOS 微信双开制作工具"
    echo "=========================================="
    echo ""

    if [ "$EUID" -ne 0 ]; then
        print_info "需要管理员权限执行此脚本"
        exec sudo "$0" "$@"
    fi

    check_original_app
    load_version_info
    decide_action

    case "$NEED_COPY_ACTION" in
        rebuild_from_original)
            copy_app "$ORIGINAL_APP"
            modify_bundle_id
            modify_helper_bundle_id
            modify_display_name
            replace_icon_color
            resign_app
            rename_to_final
            ;;
        rebuild_from_dual)
            copy_app "$DUAL_APP"
            modify_bundle_id
            modify_helper_bundle_id
            modify_display_name
            replace_icon_color
            resign_app
            rename_to_final
            ;;
        fix_config)
            modify_bundle_id "$DUAL_APP"
            modify_helper_bundle_id "$DUAL_APP"
            modify_display_name "$DUAL_APP"
            replace_icon_color "$DUAL_APP"
            resign_dual_app
            ;;
    esac

    local bundle_id
    bundle_id="$(read_plist_value "$DUAL_APP/Contents/Info.plist" CFBundleIdentifier)"

    register_with_launch_services "$DUAL_APP"

    print_info "正在刷新系统图标缓存..."
    refresh_icon_cache

    # 放在图标缓存刷新之后：此时 Dock 已停止，改写启动台数据库不会被它
    # 用内存副本覆盖回去
    clean_launchpad_entries "$bundle_id"

    # Dock 由 launchd 托管，退出后会自动重启以重建条目与图标
    if ! pgrep -x Dock >/dev/null 2>&1; then
        open -a Dock >/dev/null 2>&1 || true
    fi

    show_summary
    print_success "完成！"
}

main "$@"
