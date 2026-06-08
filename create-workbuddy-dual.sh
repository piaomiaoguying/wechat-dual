#!/bin/bash

# macOS WorkBuddy 双开制作脚本
# 功能：复制 WorkBuddy 并修改Bundle ID实现双开

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
ORIGINAL_APP="/Applications/WorkBuddy.app"
DUAL_APP_NAME="WorkBuddy双开"
TEMP_DUAL_APP_NAME="WorkBuddy-Dual-Temp"
BUNDLE_ID_SUFFIX=".dual"

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查原版 WorkBuddy 是否存在
check_original_app() {
    if [ ! -d "$ORIGINAL_APP" ]; then
        print_error "找不到原版 WorkBuddy 应用: $ORIGINAL_APP"
        print_info "请先安装 WorkBuddy 到 /Applications/WorkBuddy.app"
        exit 1
    fi
    print_success "找到原版 WorkBuddy 应用"
}

# 获取原版版本信息
get_version_info() {
    local version=$(defaults read "$ORIGINAL_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "未知")
    local bundle_version=$(defaults read "$ORIGINAL_APP/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo "未知")
    print_info "原版 WorkBuddy 版本: $version (内部版本: $bundle_version)"
}

# 检查并删除旧的双开版本
check_existing_dual() {
    local dual_path="/Applications/${DUAL_APP_NAME}.app"

    if [ -d "$dual_path" ]; then
        print_info "检测到旧版本双开应用: $dual_path"
        print_info "正在删除旧版本..."
        sudo rm -rf "$dual_path"
        print_success "旧版本已删除"
    fi
}

# 复制应用
copy_app() {
    print_info "正在复制 WorkBuddy 应用..."
    print_warning "这可能需要几分钟时间，请耐心等待..."

    # 先复制到临时名称
    if sudo cp -R "$ORIGINAL_APP" "/Applications/${TEMP_DUAL_APP_NAME}.app"; then
        print_success "应用复制完成"
    else
        print_error "复制失败，请检查权限"
        exit 1
    fi
}

# 修改Bundle Identifier
modify_bundle_id() {
    local dual_app="/Applications/${TEMP_DUAL_APP_NAME}.app"
    local original_bundle_id=$(defaults read "$ORIGINAL_APP/Contents/Info.plist" CFBundleIdentifier)
    local new_bundle_id="${original_bundle_id}${BUNDLE_ID_SUFFIX}"

    print_info "正在修改Bundle Identifier..."
    print_info "原始: $original_bundle_id"
    print_info "修改为: $new_bundle_id"

    if sudo /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $new_bundle_id" \
        "$dual_app/Contents/Info.plist" 2>/dev/null; then
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
}

# 替换图标颜色
replace_icon_color() {
    local dual_app="/Applications/${TEMP_DUAL_APP_NAME}.app"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local color_script="$script_dir/replace_workbuddy_icon_color.py"
    local original_icon="$dual_app/Contents/Resources/WorkBuddy.icns"
    local temp_dir="/tmp/workbuddy_icon_$$"
    local iconset_dir="$temp_dir/WorkBuddy.iconset"

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
    local processed_count=0
    for png_file in "$iconset_dir"/*.png; do
        if [ -f "$png_file" ]; then
            if python3 "$color_script" "$png_file" "$png_file" 2>/dev/null; then
                processed_count=$((processed_count + 1))
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

    print_success "图标颜色替换成功（青绿色→蓝色）"
}

# 修改应用名称
modify_app_name() {
    local dual_app="/Applications/${TEMP_DUAL_APP_NAME}.app"
    local package_json="$dual_app/Contents/Resources/app/package.json"

    print_info "正在修改应用内部名称..."

    if [ ! -f "$package_json" ]; then
        print_warning "找不到 package.json 文件，跳过应用名称修改"
        return 0
    fi

    # 使用Python脚本修改package.json中的应用名称
    python3 << EOF
import json
import sys

try:
    with open("$package_json", 'r', encoding='utf-8') as f:
        data = json.load(f)

    # 修改应用名称
    data['name'] = 'WorkBuddyDual'
    data['productName'] = 'WorkBuddyDual'

    # 保存修改
    with open("$package_json", 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    print("应用名称修改成功")
except Exception as e:
    print(f"应用名称修改失败: {e}")
    sys.exit(1)
EOF

    if [ $? -eq 0 ]; then
        print_success "应用内部名称修改成功"
    else
        print_warning "应用名称修改失败，但可以继续"
    fi
}

# 重新签名
resign_app() {
    local dual_app="/Applications/${TEMP_DUAL_APP_NAME}.app"

    print_info "正在重新签名应用..."
    print_warning "这可能需要几分钟时间..."

    if sudo codesign --force --deep --sign - "$dual_app" 2>/dev/null; then
        print_success "应用签名成功"

        # 验证签名
        if codesign -v "$dual_app" 2>/dev/null; then
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

    echo ""
    echo "=========================================="
    echo "           🎉 双开版本创建成功！"
    echo "=========================================="
    echo ""
    echo "📦 应用名称: ${DUAL_APP_NAME}.app"
    echo "📍 位置: /Applications/${DUAL_APP_NAME}.app"
    echo "🔖 Bundle ID: $bundle_id"
    echo "📝 版本: $version"
    echo ""
    echo "=========================================="
    echo "               使用说明"
    echo "=========================================="
    echo ""
    echo "重要提醒："
    echo "WorkBuddy 是 Electron 应用，需要使用特殊方式启动双开版本"
    echo ""
    echo "1. 使用启动脚本启动双开版本："
    echo "   ./launch-workbuddy-dual.sh"
    echo ""
    echo "2. 或者直接运行双开版本（会使用默认用户数据目录）："
    echo "   open /Applications/${DUAL_APP_NAME}.app"
    echo ""
    echo "推荐使用启动脚本，这样可以确保使用独立的用户数据目录"
    echo ""
    echo "⚠️  重要提醒:"
    echo "- 双开版本不会自动更新"
    echo "- WorkBuddy 升级后需要重新运行此脚本"
    echo "- 两个 WorkBuddy 独立运行，数据完全隔离"
    echo ""
    print_success "完成！"
}

# 主函数
main() {
    echo "=========================================="
    echo "     macOS WorkBuddy 双开制作工具"
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
    check_existing_dual
    copy_app
    modify_bundle_id
    modify_app_name
    replace_icon_color
    resign_app
    rename_to_final
    show_summary
}

# 运行主函数
main "$@"
