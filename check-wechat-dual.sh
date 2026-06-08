#!/bin/bash

# 微信双开版本检查脚本
# 检查双开版本的Bundle ID是否被重置

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
ORIGINAL_APP="/Applications/WeChat.app"
DUAL_APP="/Applications/微信双开.app"
EXPECTED_BUNDLE_ID="com.tencent.xinWeChat.dual"
HELPER_EXPECTED_BUNDLE_ID="com.tencent.flue.WeApp.dual"

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

# 检查Bundle ID
check_bundle_id() {
    local original_bundle=$(defaults read "$ORIGINAL_APP/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || echo "未知")
    local dual_bundle=$(defaults read "$DUAL_APP/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || echo "未知")

    echo ""
    echo "=== Bundle ID 检查 ==="
    echo ""
    echo "原版微信:  $original_bundle"
    echo "微信双开:  $dual_bundle"
    echo "预期双开:  $EXPECTED_BUNDLE_ID"
    echo ""

    if [ "$dual_bundle" = "$original_bundle" ]; then
        print_error "❌ Bundle ID 已被重置！双开版本与原版微信相同"
        print_info "这意味着微信更新时重置了配置"
        print_warning "需要重新创建双开版本"
        return 1
    elif [ "$dual_bundle" = "$EXPECTED_BUNDLE_ID" ]; then
        print_success "✓ Bundle ID 正常"
        return 0
    else
        print_warning "⚠️ Bundle ID 与预期不符"
        print_info "当前: $dual_bundle"
        print_info "预期: $EXPECTED_BUNDLE_ID"
        return 0
    fi
}

# 检查版本信息
check_version_info() {
    local original_version=$(defaults read "$ORIGINAL_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "未知")
    local dual_version=$(defaults read "$DUAL_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "未知")

    local original_bundle_version=$(defaults read "$ORIGINAL_APP/Contents/Info.plist" WeChatBundleVersion 2>/dev/null || echo "未知")
    local dual_bundle_version=$(defaults read "$DUAL_APP/Contents/Info.plist" WeChatBundleVersion 2>/dev/null || echo "未知")

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

    # 比较版本号
    if [ "$dual_version" != "$original_version" ]; then
        print_warning "⚠️ 版本号不一致"
        print_info "双开版本可能已自动更新"

        # 简单的版本号比较
        local orig_major=$(echo "$original_version" | cut -d'.' -f1)
        local orig_minor=$(echo "$original_version" | cut -d'.' -f2)
        local orig_patch=$(echo "$original_version" | cut -d'.' -f3)

        local dual_major=$(echo "$dual_version" | cut -d'.' -f1)
        local dual_minor=$(echo "$dual_version" | cut -d'.' -f2)
        local dual_patch=$(echo "$dual_version" | cut -d'.' -f3)

        if [ "$dual_major" -gt "$orig_major" ] || \
           [ "$dual_major" -eq "$orig_major" ] && [ "$dual_minor" -gt "$orig_minor" ] || \
           [ "$dual_major" -eq "$orig_major" ] && [ "$dual_minor" -eq "$orig_minor" ] && [ "$dual_patch" -gt "$orig_patch" ]; then
            print_warning "⚠️ 双开版本号比原版微信高"
        fi
    else
        print_success "✓ 版本号一致"
    fi
}

# 检查Helper应用Bundle ID
check_helper_bundle_id() {
    local helper_app="$DUAL_APP/Contents/MacOS/WeChatAppEx.app/Contents/Frameworks/WeChatAppEx Framework.framework/Versions/C/Helpers/WeApp.app"

    if [ ! -f "$helper_app/Contents/Info.plist" ]; then
        print_warning "找不到Helper应用，跳过检查"
        return 0
    fi

    local helper_bundle=$(defaults read "$helper_app/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || echo "未知")

    echo ""
    echo "=== Helper应用Bundle ID 检查 ==="
    echo ""
    echo "微信双开Helper: $helper_bundle"
    echo "预期Helper: $HELPER_EXPECTED_BUNDLE_ID"
    echo ""

    if [ "$helper_bundle" != "$HELPER_EXPECTED_BUNDLE_ID" ]; then
        print_warning "⚠️ Helper Bundle ID 与预期不符"
        print_info "当前: $helper_bundle"
        print_info "预期: $HELPER_EXPECTED_BUNDLE_ID"
    else
        print_success "✓ Helper Bundle ID 正常"
    fi
}

# 检查数据目录
check_data_directories() {
    echo ""
    echo "=== 数据目录检查 ==="
    echo ""

    local original_data="$HOME/Library/Containers/com.tencent.xinWeChat"
    local dual_data="$HOME/Library/Containers/com.tencent.xinWeChat.dual"

    if [ -d "$original_data" ]; then
        local original_size=$(du -sh "$original_data" | cut -f1)
        echo "原版微信数据: $original_data ($original_size)"
    fi

    if [ -d "$dual_data" ]; then
        local dual_size=$(du -sh "$dual_data" | cut -f1)
        echo "微信双开数据: $dual_data ($dual_size)"
    else
        print_error "❌ 找不到双开数据目录"
    fi
}

# 提供修复建议
provide_fix_suggestion() {
    local bundle_status=$1

    echo ""
    echo "=========================================="
    echo "               修复建议"
    echo "=========================================="
    echo ""

    if [ "$bundle_status" -eq 1 ]; then
        echo "发现 Bundle ID 已被重置，建议执行以下操作："
        echo ""
        echo "1. 重新创建双开版本："
        echo "   sudo ./create-wechat-dual.sh"
        echo ""
        echo "2. 重新登录双开版本"
        echo ""
        echo "这将确保："
        echo "  - Bundle ID 正确设置为 $EXPECTED_BUNDLE_ID"
        echo "  - Helper Bundle ID 正确设置"
        echo "  - 图标颜色正确替换"
        echo "  - 代码签名正确"
    else
        echo "配置检查通过，双开版本运行正常！"
    fi
    echo ""
}

# 主函数
main() {
    echo "=========================================="
    echo "     微信双开版本检查工具"
    echo "=========================================="
    echo ""

    check_apps

    # 执行检查并收集状态
    check_bundle_id
    local bundle_issue=$?  # 捕获上一个命令的退出状态

    check_version_info
    check_helper_bundle_id
    check_data_directories

    # 根据检查结果提供建议
    if [ "$bundle_issue" -ne 0 ]; then
        provide_fix_suggestion 1
    else
        provide_fix_suggestion 0
    fi
}

# 运行主函数
main "$@"
