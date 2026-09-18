#!/bin/bash

# 微信双开版本检查脚本
# 检查双开版本的 Bundle ID、图标、名称是否被微信更新重置

# 注意: 本脚本不使用 set -e。检查函数需要返回非零状态表示"发现问题"，
# 若启用 set -e，首个问题就会终止整个检查流程，修复建议也不会打印。
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wechat-dual-common.sh"

EXPECTED_BUNDLE_ID="com.tencent.xinWeChat${BUNDLE_ID_SUFFIX}"
EXPECTED_HELPER_BUNDLE_ID="${HELPER_ORIGINAL_BUNDLE_ID}${BUNDLE_ID_SUFFIX}"

ISSUE_COUNT=0

report_issue() {
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
}

# 检查应用是否存在
check_apps() {
    if [ ! -d "$ORIGINAL_APP" ]; then
        print_error "找不到原版微信: $ORIGINAL_APP"
        exit 1
    fi

    if [ ! -d "$DUAL_APP" ]; then
        print_warning "找不到微信双开: $DUAL_APP"
        print_info "请先运行 create-wechat-dual.sh 创建双开版本"
        exit 0
    fi

    print_success "找到原版微信和双开版本"
}

# 检查 Bundle ID
check_bundle_id() {
    local original_bundle
    original_bundle="$(read_plist_value "$ORIGINAL_APP/Contents/Info.plist" CFBundleIdentifier "")"
    local dual_bundle
    dual_bundle="$(read_plist_value "$DUAL_APP/Contents/Info.plist" CFBundleIdentifier "")"

    echo ""
    echo "=== Bundle ID 检查 ==="
    echo ""
    echo "原版微信: $original_bundle"
    echo "微信双开: $dual_bundle"
    echo "预期值:   $EXPECTED_BUNDLE_ID"
    echo ""

    if [ "$dual_bundle" = "$original_bundle" ]; then
        print_error "Bundle ID 已被重置，与原版微信相同"
        print_info "微信更新时重置了配置，两个微信会互相冲突"
        report_issue
    elif [ "$dual_bundle" = "$EXPECTED_BUNDLE_ID" ]; then
        print_success "Bundle ID 正常"
    else
        print_warning "Bundle ID 与预期不符"
        print_info "当前: $dual_bundle"
        print_info "预期: $EXPECTED_BUNDLE_ID"
        report_issue
    fi
}

# 检查 WeApp 子应用的 Bundle ID
check_helper_bundle_id() {
    local helper_plist="$DUAL_APP/$HELPER_APP_REL/Contents/Info.plist"

    if [ ! -f "$helper_plist" ]; then
        print_warning "找不到 WeApp 子应用，跳过检查"
        return 0
    fi

    local helper_bundle
    helper_bundle="$(read_plist_value "$helper_plist" CFBundleIdentifier "")"

    echo ""
    echo "=== WeApp 子应用 Bundle ID 检查 ==="
    echo ""
    echo "当前值: $helper_bundle"
    echo "预期值: $EXPECTED_HELPER_BUNDLE_ID"
    echo ""

    if [ "$helper_bundle" != "$EXPECTED_HELPER_BUNDLE_ID" ]; then
        print_warning "WeApp Bundle ID 与预期不符"
        report_issue
    else
        print_success "WeApp Bundle ID 正常"
    fi
}

# 检查图标颜色
# 微信 4.x 同时提供 AppIcon.icns 与 Assets.car，Info.plist 声明了
# CFBundleIconName，系统优先使用 Assets.car 中的图标。只改 icns 不会生效。
check_icon_color() {
    local resources="$DUAL_APP/Contents/Resources"
    local icns="$resources/AppIcon.icns"
    local car="$resources/Assets.car"

    echo ""
    echo "=== 图标颜色检查 ==="
    echo ""

    local icns_tone="unknown"
    if [ -f "$icns" ]; then
        icns_tone="$(icon_tone "$icns")"
        case "$icns_tone" in
            blue)  print_success "AppIcon.icns 已是蓝色" ;;
            green) print_error "AppIcon.icns 仍为绿色（未替换）"; report_issue ;;
            *)     print_warning "无法识别 AppIcon.icns 颜色" ;;
        esac
    else
        print_warning "找不到 AppIcon.icns"
    fi

    if [ -f "$car" ]; then
        local orig_car="$ORIGINAL_APP/Contents/Resources/Assets.car"
        if [ -f "$orig_car" ] && cmp -s "$car" "$orig_car"; then
            print_error "Assets.car 与原版微信完全相同（图标未替换）"
            print_info "系统优先读取 Assets.car，这会导致 Dock 显示绿色图标"
            report_issue
        else
            print_success "Assets.car 已重建"
        fi
    elif [ -f "$ORIGINAL_APP/Contents/Resources/Assets.car" ]; then
        # 原版带资源目录，双开却没有，说明重建失败走了回退分支。
        # 当前靠 ICNS 也能显示正确颜色，但微信一旦自行补回该文件就会变绿。
        print_warning "原版微信含 Assets.car，双开缺失（上次重建失败已回退到 ICNS）"
        print_info "重新运行 create-wechat-dual.sh 会重建该文件"
        report_issue
    else
        print_info "应用不含 Assets.car，系统将使用 AppIcon.icns"
    fi

    # 以系统实际渲染结果为准（Dock / 启动台看到的就是这张）
    local rendered_tone
    rendered_tone="$(app_icon_tone "$DUAL_APP")"
    case "$rendered_tone" in
        blue)  print_success "系统实际渲染的图标为蓝色" ;;
        green) print_error "系统实际渲染的图标仍为绿色"; report_issue ;;
        *)     print_warning "无法读取系统渲染的图标" ;;
    esac
}

# 检查应用显示名称
# Dock 与启动台读取的是 .lproj/InfoPlist.strings，优先级高于 Info.plist
check_display_name() {
    echo ""
    echo "=== 显示名称检查 ==="
    echo ""

    local plist_name
    plist_name="$(read_plist_value "$DUAL_APP/Contents/Info.plist" CFBundleDisplayName "")"
    echo "Info.plist:  $plist_name"

    local found=0
    local mismatch=0
    local lproj
    for lproj in "$DUAL_APP"/Contents/Resources/*.lproj; do
        local strings_file="$lproj/InfoPlist.strings"
        [ -f "$strings_file" ] || continue
        local name
        name="$(read_plist_value "$strings_file" CFBundleDisplayName "")"
        [ -n "$name" ] || continue
        found=$((found + 1))
        echo "$(basename "$lproj"): $name"
        # 本地化名称是系统实际显示的名称
        if [ "$name" = "微信" ] || [ "$name" = "WeChat" ]; then
            mismatch=1
        fi
    done

    echo ""

    if [ "$found" -eq 0 ]; then
        print_warning "没有找到本地化名称资源"
        return 0
    fi

    if [ "$mismatch" -eq 1 ]; then
        print_error "本地化显示名称仍为微信官方名称，Dock 与启动台会显示原名"
        report_issue
    else
        print_success "显示名称正常"
    fi
}

# 检查版本信息
check_version_info() {
    local original_version
    original_version="$(read_plist_value "$ORIGINAL_APP/Contents/Info.plist" CFBundleShortVersionString)"
    local dual_version
    dual_version="$(read_plist_value "$DUAL_APP/Contents/Info.plist" CFBundleShortVersionString)"
    local original_bundle_version
    original_bundle_version="$(read_plist_value "$ORIGINAL_APP/Contents/Info.plist" WeChatBundleVersion)"
    local dual_bundle_version
    dual_bundle_version="$(read_plist_value "$DUAL_APP/Contents/Info.plist" WeChatBundleVersion)"

    echo ""
    echo "=== 版本信息检查 ==="
    echo ""
    echo "原版微信:"
    echo "  显示版本: $original_version"
    echo "  内部版本: $original_bundle_version"
    echo ""
    echo "微信双开:"
    echo "  显示版本: $dual_version"
    echo "  内部版本: $dual_bundle_version"
    echo ""

    if [ "$dual_version" != "$original_version" ]; then
        print_warning "版本号不一致，双开版本可能已自动更新"
        print_info "重新运行 create-wechat-dual.sh 会保留较新的版本内容"
    else
        print_success "版本号一致"
    fi
}

# 检查代码签名
check_signature() {
    echo ""
    echo "=== 代码签名检查 ==="
    echo ""

    if codesign --verify --deep "$DUAL_APP" >/dev/null 2>&1; then
        print_success "签名有效"
    else
        print_warning "签名验证未通过"
        print_info "应用可能无法启动，运行 create-wechat-dual.sh 可重新签名"
        report_issue
    fi
}

# 检查启动台记录
check_launchpad_entries() {
    echo ""
    echo "=== 启动台记录检查 ==="
    echo ""

    local u
    u="$(real_user)"
    local user_dir
    user_dir="$(getconf DARWIN_USER_DIR 2>/dev/null)"
    [ -n "$user_dir" ] || user_dir="$(sudo -u "$u" getconf DARWIN_USER_DIR 2>/dev/null)"
    local db="${user_dir}com.apple.dock.launchpad/db/db"

    if [ ! -f "$db" ]; then
        print_info "找不到启动台数据库，跳过检查"
        return 0
    fi

    local dup_count
    dup_count="$(sqlite3 "file:$db?mode=ro" \
        "SELECT count(*) FROM apps WHERE bundleid='$EXPECTED_BUNDLE_ID';" 2>/dev/null || echo 0)"

    echo "双开应用记录数: ${dup_count:-0}"
    echo ""

    if [ "${dup_count:-0}" -gt 1 ]; then
        print_warning "启动台中存在多条双开记录，会出现名称或图标不一致的重复图标"
        print_info "运行 create-wechat-dual.sh 可自动清理"
        report_issue
    elif [ "${dup_count:-0}" -eq 1 ]; then
        print_success "启动台记录正常"
    else
        print_info "启动台中暂无双开记录，首次启动后生成"
    fi
}

# 检查数据目录
check_data_directories() {
    echo ""
    echo "=== 数据目录检查 ==="
    echo ""

    local original_data="$HOME/Library/Containers/com.tencent.xinWeChat"
    local dual_data="$HOME/Library/Containers/${EXPECTED_BUNDLE_ID}"

    if [ -d "$original_data" ]; then
        echo "原版微信数据: $original_data ($(du -sh "$original_data" 2>/dev/null | cut -f1))"
    fi

    if [ -d "$dual_data" ]; then
        echo "微信双开数据: $dual_data ($(du -sh "$dual_data" 2>/dev/null | cut -f1))"
    else
        print_warning "找不到双开数据目录，可能导致需要重新登录"
    fi
}

# 输出修复建议
provide_fix_suggestion() {
    echo ""
    echo "=========================================="
    echo "               检查结论"
    echo "=========================================="
    echo ""

    if [ "$ISSUE_COUNT" -eq 0 ]; then
        print_success "双开版本配置正常"
        echo ""
        return 0
    fi

    print_error "发现 $ISSUE_COUNT 项配置异常"
    echo ""
    echo "执行以下命令修复："
    echo ""
    echo "  sudo ./create-wechat-dual.sh"
    echo ""
    echo "修复内容包括："
    echo "  - Bundle ID 与 WeApp 子应用标识"
    echo "  - 应用显示名称（含本地化资源）"
    echo "  - 图标颜色（ICNS 与 Assets.car）"
    echo "  - 代码签名与系统图标缓存"
    echo "  - 启动台重复记录"
    echo ""
    echo "登录状态保存在数据目录中，修复后无需重新扫码。"
    echo ""
}

# 主函数
main() {
    echo "=========================================="
    echo "     微信双开版本检查工具"
    echo "=========================================="
    echo ""

    check_apps
    check_bundle_id
    check_helper_bundle_id
    check_icon_color
    check_display_name
    check_version_info
    check_signature
    check_launchpad_entries
    check_data_directories
    provide_fix_suggestion

    if [ "$ISSUE_COUNT" -eq 0 ]; then
        exit 0
    fi
    exit 1
}

main "$@"
