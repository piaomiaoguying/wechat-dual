#!/bin/bash

# macOS 微信双开制作脚本
# 功能：复制微信并修改Bundle ID实现双开

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
ORIGINAL_APP="/Applications/WeChat.app"
DUAL_APP_NAME="微信双开"
TEMP_DUAL_APP_NAME="WeChat-Dual-Temp"
BUNDLE_ID_SUFFIX=".dual"

# 打印带颜色的消息
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

# 检查原版微信是否存在
check_original_app() {
    if [ ! -d "$ORIGINAL_APP" ]; then
        print_error "找不到原版微信应用: $ORIGINAL_APP"
        print_info "请先安装微信到 /Applications/WeChat.app"
        exit 1
    fi
    print_success "找到原版微信应用"
}

# 检查双开版本是否需要更新
check_dual_version_need_update() {
    # 检查双开版本是否存在
    check_dual_app_exists
    local dual_exists=$?

    if [ "$dual_exists" -eq 1 ]; then
        # 双开版本不存在，需要创建
        print_info "双开版本不存在，需要从原版微信复制"
        echo "0"
        return 0  # 需要复制
    fi

    # 双开版本存在，获取版本号信息
    local dual_app="/Applications/${DUAL_APP_NAME}.app"
    local dual_version=$(defaults read "$dual_app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "0.0.0")
    local dual_bundle_version=$(defaults read "$dual_app/Contents/Info.plist" WeChatBundleVersion 2>/dev/null || echo "0.0.0")

    echo ""
    echo "=== 版本号比较 ==="
    echo ""
    echo "原版微信:"
    echo "  显示版本: $ORIGINAL_VERSION"
    echo "  内部版本: $ORIGINAL_BUNDLE_VERSION"
    echo ""
    echo "微信双开:"
    echo "  显示版本: $dual_version"
    echo "  内部版本: $dual_bundle_version"
    echo ""

    # 比较版本号
    local original_major=$(echo "$ORIGINAL_VERSION" | cut -d'.' -f1)
    local original_minor=$(echo "$ORIGINAL_VERSION" | cut -d'.' -f2)
    local original_patch=$(echo "$ORIGINAL_VERSION" | cut -d'.' -f3)

    local dual_major=$(echo "$dual_version" | cut -d'.' -f1)
    local dual_minor=$(echo "$dual_version" | cut -d'.' -f2)
    local dual_patch=$(echo "$dual_version" | cut -d'.' -f3)

    # 版本号比较逻辑
    if [ "$dual_major" -gt "$original_major" ] 2>/dev/null; then
        print_info "✓ 双开版本号高于原版微信 ($dual_version > $ORIGINAL_VERSION)"
        print_info "基于双开版本重新创建（保留更新内容）"
        echo "2"
        return 0  # 基于双开版本复制
    elif [ "$dual_major" -eq "$original_major" ] 2>/dev/null; then
        if [ "$dual_minor" -gt "$original_minor" ] 2>/dev/null; then
            print_info "✓ 双开版本号高于原版微信 ($dual_version > $ORIGINAL_VERSION)"
            print_info "基于双开版本重新创建（保留更新内容）"
            echo "2"
            return 0  # 基于双开版本复制
        elif [ "$dual_minor" -eq "$original_minor" ] 2>/dev/null; then
            if [ "$dual_patch" -ge "$original_patch" ] 2>/dev/null; then
                print_info "✓ 双开版本号不低于原版微信 ($dual_version >= $ORIGINAL_VERSION)"
                print_info "基于双开版本重新创建（保留更新内容）"
                echo "2"
                return 0  # 基于双开版本复制
            fi
        fi
    fi

    print_info "✓ 原版微信版本号更新 ($ORIGINAL_VERSION > $dual_version)"
    print_info "需要删除旧版本并从新复制"
    echo "0"
    return 0  # 需要复制
}

# 获取原版版本信息（设置全局变量）
get_version_info() {
    ORIGINAL_VERSION=$(defaults read "$ORIGINAL_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "未知")
    ORIGINAL_BUNDLE_VERSION=$(defaults read "$ORIGINAL_APP/Contents/Info.plist" WeChatBundleVersion 2>/dev/null || echo "未知")
    print_info "原版微信版本: $ORIGINAL_VERSION (内部版本: $ORIGINAL_BUNDLE_VERSION)"
}

# 检查并删除旧的双开版本
# 检查双开版本是否存在
check_dual_app_exists() {
    local dual_path="/Applications/${DUAL_APP_NAME}.app"

    if [ -d "$dual_path" ]; then
        print_info "检测到双开版本: $dual_path"
        return 0  # 存在
    else
        print_info "未检测到双开版本，需要创建"
        return 1  # 不存在
    fi
}

# 复制应用
copy_app() {
    local source_app="${1:-$ORIGINAL_APP}"
    print_info "正在复制微信应用..."
    print_info "源路径: $source_app"
    print_info "目标路径: /Applications/${TEMP_DUAL_APP_NAME}.app"
    print_warning "这可能需要几分钟时间，请耐心等待..."

    # 检查源应用是否存在
    if [ ! -d "$source_app" ]; then
        print_error "源应用不存在: $source_app"
        exit 1
    fi

    # 先复制到临时名称
    print_info "开始复制..."
    if sudo cp -R "$source_app" "/Applications/${TEMP_DUAL_APP_NAME}.app"; then
        print_success "应用复制完成"

        # 验证复制是否成功
        if [ -d "/Applications/${TEMP_DUAL_APP_NAME}.app" ]; then
            print_success "临时应用验证成功"
        else
            print_error "临时应用验证失败"
            exit 1
        fi
    else
        print_error "复制失败，请检查权限"
        exit 1
    fi
}

# 修改Bundle Identifier
modify_bundle_id() {
    local dual_app="/Applications/${TEMP_DUAL_APP_NAME}.app"

    print_info "正在准备修改Bundle Identifier..."
    print_info "临时应用路径: $dual_app"

    # 检查临时应用是否存在
    if [ ! -d "$dual_app" ]; then
        print_error "临时应用不存在: $dual_app"
        exit 1
    fi

    # 检查Info.plist是否存在
    if [ ! -f "$dual_app/Contents/Info.plist" ]; then
        print_error "Info.plist不存在: $dual_app/Contents/Info.plist"
        exit 1
    fi

    local original_bundle_id=$(defaults read "$dual_app/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || echo "")

    if [ -z "$original_bundle_id" ]; then
        print_error "无法读取Bundle Identifier"
        exit 1
    fi

    # 如果原始Bundle ID已经包含.dual后缀，先去掉
    if [[ "$original_bundle_id" == *".dual" ]]; then
        original_bundle_id="${original_bundle_id%.dual}"
        print_info "检测到已有.dual后缀，已去除"
    fi

    local new_bundle_id="${original_bundle_id}${BUNDLE_ID_SUFFIX}"

    print_info "正在修改Bundle Identifier..."
    print_info "原始: $original_bundle_id"
    print_info "修改为: $new_bundle_id"

    if sudo /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $new_bundle_id" \
        "$dual_app/Contents/Info.plist" 2>&1; then
        print_success "Bundle Identifier 修改成功"

        # 验证修改
        local verify=$(defaults read "$dual_app/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || echo "")
        if [ "$verify" = "$new_bundle_id" ]; then
            print_success "Bundle Identifier 验证通过: $verify"
        else
            print_error "Bundle Identifier 验证失败"
            print_error "期望: $new_bundle_id"
            print_error "实际: $verify"
            exit 1
        fi
    else
        print_error "Bundle Identifier 修改失败"
        exit 1
    fi
}

# 修改Helper应用的Bundle Identifier（防止更新时被重置）
modify_helper_bundle_id() {
    local dual_app="${1:-/Applications/${TEMP_DUAL_APP_NAME}.app}"
    local helper_app="$dual_app/Contents/MacOS/WeChatAppEx.app/Contents/Frameworks/WeChatAppEx Framework.framework/Versions/C/Helpers/WeApp.app"
    local original_helper_id="com.tencent.flue.WeApp"
    local new_helper_id="${original_helper_id}${BUNDLE_ID_SUFFIX}"

    print_info "正在修改Helper应用的Bundle Identifier..."

    if [ ! -f "$helper_app/Contents/Info.plist" ]; then
        print_warning "找不到Helper应用，跳过修改"
        return 0
    fi

    if sudo /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $new_helper_id" \
        "$helper_app/Contents/Info.plist"; then
        print_success "Helper Bundle Identifier 修改成功: $new_helper_id"
    else
        print_warning "Helper Bundle Identifier 修改失败（可能不影响使用）"
    fi
}

# 替换图标颜色
replace_icon_color() {
    local dual_app="${1:-/Applications/${TEMP_DUAL_APP_NAME}.app}"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local color_script="$script_dir/replace_icon_color.py"
    local original_icon="$dual_app/Contents/Resources/AppIcon.icns"
    local temp_dir="/tmp/wechat_icon_$$"
    local iconset_dir="$temp_dir/AppIcon.iconset"

    print_info "正在替换图标颜色..."

    # 检查颜色替换脚本是否存在
    if [ ! -f "$color_script" ]; then
        print_warning "颜色替换脚本不存在，跳过图标颜色替换"
        return 0
    fi

    # 检查图标文件是否存在
    if [ ! -f "$original_icon" ]; then
        print_warning "找不到图标文件，跳过图标颜色替换"
        return 0
    fi

    # 使用iconutil将ICNS解压为iconset
    if ! iconutil --convert iconset "$original_icon" --output "$iconset_dir" 2>/dev/null; then
        print_warning "图标解压失败，跳过图标颜色替换"
        rm -rf "$temp_dir"
        return 0
    fi

    # 对iconset中的所有PNG文件进行颜色替换
    print_info "处理图标分辨率..."

    # 确保图标文件对原用户可写（sudo 下 iconutil 解压的文件属于 root）
    chmod -R u+w "$iconset_dir" 2>/dev/null
    if [ -n "$SUDO_USER" ]; then
        chown -R "$SUDO_USER" "$iconset_dir" 2>/dev/null
    fi

    local processed_count=0
    for png_file in "$iconset_dir"/*.png; do
        if [ -f "$png_file" ]; then
            # 使用原始用户身份运行 Python 脚本，避免 sudo 下找不到 Pillow 等依赖
            if [ -n "$SUDO_USER" ]; then
                if sudo -u "$SUDO_USER" python3 "$color_script" "$png_file" "$png_file"; then
                    processed_count=$((processed_count + 1))
                fi
            else
                if python3 "$color_script" "$png_file" "$png_file"; then
                    processed_count=$((processed_count + 1))
                fi
            fi
        fi
    done

    if [ $processed_count -eq 0 ]; then
        print_warning "没有处理任何图标文件，使用原图标"
        rm -rf "$temp_dir"
        return 0
    fi

    print_info "已处理 $processed_count 个图标分辨率"

    # 使用iconutil将iconset重新打包为ICNS
    if ! iconutil --convert icns "$iconset_dir" --output "$original_icon" 2>/dev/null; then
        print_warning "图标打包失败，使用原图标"
        rm -rf "$temp_dir"
        return 0
    fi

    # 清理临时文件
    rm -rf "$temp_dir"

    print_success "图标颜色替换成功（绿色→蓝色）"
}

# 修复双开版本的配置（不复制应用）
fix_dual_config() {
    local dual_app="/Applications/${DUAL_APP_NAME}.app"
    local original_bundle_id=$(defaults read "$ORIGINAL_APP/Contents/Info.plist" CFBundleIdentifier)
    local new_bundle_id="${original_bundle_id}${BUNDLE_ID_SUFFIX}"

    echo ""
    echo "=========================================="
    echo "     仅修复双开版本配置"
    echo "=========================================="
    echo ""

    print_info "正在修复 Bundle ID..."
    print_info "原始: $original_bundle_id"
    print_info "修改为: $new_bundle_id"

    if sudo /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $new_bundle_id" \
        "$dual_app/Contents/Info.plist"; then
        print_success "Bundle Identifier 修改成功"

        # 验证修改
        local verify=$(defaults read "$dual_app/Contents/Info.plist" CFBundleIdentifier)
        if [ "$verify" = "$new_bundle_id" ]; then
            print_success "Bundle Identifier 验证通过: $verify"
        else
            print_error "Bundle Identifier 验证失败"
            exit 1
        fi
    else
        print_error "Bundle Identifier 修改失败"
        exit 1
    fi

    # 修复Helper应用的Bundle ID
    modify_helper_bundle_id "$dual_app"

    # 替换图标颜色
    replace_icon_color "$dual_app"

    # 重新签名
    print_info "正在重新签名应用..."
    print_warning "这可能需要几分钟时间..."

    if sudo codesign --force --deep --sign - "$dual_app"; then
        print_success "应用签名成功"

        # 验证签名
        if codesign -v "$dual_app"; then
            print_success "签名验证通过"
        else
            print_warning "签名验证失败，但应用可能仍可运行"
        fi
    else
        print_error "应用签名失败"
        exit 1
    fi

    print_success "配置修复完成！"
}

# 重新签名
resign_app() {
    local dual_app="/Applications/${TEMP_DUAL_APP_NAME}.app"

    print_info "正在重新签名应用..."
    print_warning "这可能需要几分钟时间..."

    if sudo codesign --force --deep --sign - "$dual_app"; then
        print_success "应用签名成功"

        # 验证签名
        if codesign -v "$dual_app"; then
            print_success "签名验证通过"
        else
            print_warning "签名验证失败，但应用可能仍可运行"
        fi
    else
        print_error "应用签名失败"
        exit 1
    fi
}

# 重命名为最终名称
rename_to_final() {
    local temp_app="/Applications/${TEMP_DUAL_APP_NAME}.app"
    local final_app="/Applications/${DUAL_APP_NAME}.app"

    print_info "正在重命名为最终名称..."
    print_info "临时名称: $TEMP_DUAL_APP_NAME.app"
    print_info "最终名称: $DUAL_APP_NAME.app"

    # 如果最终应用已存在，先删除
    if [ -d "$final_app" ]; then
        print_info "检测到旧的双开版本，正在删除..."
        if sudo rm -rf "$final_app"; then
            print_success "旧版本删除成功"
        else
            print_error "旧版本删除失败"
            exit 1
        fi
    fi

    if sudo mv "$temp_app" "$final_app"; then
        print_success "重命名成功"
    else
        print_error "重命名失败"
        exit 1
    fi
}

# 显示最终信息
show_summary() {
    local dual_app="/Applications/${DUAL_APP_NAME}.app"
    local bundle_id=$(defaults read "$dual_app/Contents/Info.plist" CFBundleIdentifier)
    local version=$(defaults read "$dual_app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "未知")
    local original_version=$(defaults read "$ORIGINAL_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "未知")

    echo ""
    echo "=========================================="
    echo "           🎉 双开版本处理完成！"
    echo "=========================================="
    echo ""
    echo "📦 应用名称: ${DUAL_APP_NAME}.app"
    echo "📍 位置: /Applications/${DUAL_APP_NAME}.app"
    echo "🔖 Bundle ID: $bundle_id"
    echo "📝 版本: $version (原版微信: $original_version)"
    echo ""
    echo "=========================================="
    echo "               使用说明"
    echo "=========================================="
    echo ""
    echo "1. 打开双开版本: open /Applications/${DUAL_APP_NAME}.app"
    echo "2. 登录你的第二个微信账号"
    echo "3. 现在可以同时运行两个微信了！"
    echo ""
    echo "⚠️  重要提醒:"
    echo "- 双开版本可能自动更新，但更新后需要重新运行此脚本"
    echo "- 更新后运行此脚本会智能修复Bundle ID和图标"
    echo "- 推荐定期运行 ./check-wechat-dual.sh 检查配置"
    echo "- 两个微信独立运行，数据完全隔离"
    echo ""
    print_success "完成！"
}

# 主函数
main() {
    echo "=========================================="
    echo "     macOS 微信双开制作工具"
    echo "=========================================="
    echo ""

    # 检查sudo权限
    if [ "$EUID" -ne 0 ]; then
        print_info "需要管理员权限执行此脚本"
        exec sudo "$0" "$@"
    fi

    # 执行各步骤
    check_original_app
    get_version_info

    # 检查双开版本是否需要更新
    printf "DEBUG: Before calling check_dual_version_need_update\n"
    local need_copy=$(check_dual_version_need_update | tail -1)
    printf "DEBUG: After calling check_dual_version_need_update, need_copy=%s\n" "$need_copy"

    print_info "检查完成，返回值: $need_copy"

    if [ "$need_copy" = "0" ]; then
        # 需要复制应用（原版微信版本更新）
        check_dual_app_exists
        copy_app
        modify_bundle_id
        modify_helper_bundle_id
        replace_icon_color
        resign_app
    elif [ "$need_copy" = "2" ]; then
        # 基于双开版本复制（双开版本比原版微信新）
        print_info "基于双开版本重新创建..."
        local dual_app="/Applications/${DUAL_APP_NAME}.app"

        print_info "双开版本路径: $dual_app"

        # 检查双开版本是否存在
        if [ ! -d "$dual_app" ]; then
            print_error "双开版本不存在: $dual_app"
            exit 1
        fi

        copy_app "$dual_app"

        # 删除旧的双开版本
        print_info "删除旧的双开版本..."
        if sudo rm -rf "$dual_app"; then
            print_success "旧的双开版本删除成功"
        else
            print_error "旧的双开版本删除失败"
            exit 1
        fi

        print_info "开始修改配置..."
        modify_bundle_id
        modify_helper_bundle_id
        replace_icon_color
        resign_app
    else
        # 双开版本已更新或版本相同，仅修复配置
        print_info "双开版本已存在且版本号满足要求，仅修复配置"
        fix_dual_config
    fi

    rename_to_final
    show_summary
}

# 运行主函数
main "$@"
