#!/bin/bash

# WorkBuddy 双开启动脚本
# 使用不同的用户数据目录绕过单例检查

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
WORKBUDDY_APP="/Applications/WorkBuddy.app"
WORKBUDDY_DUAL="/Applications/WorkBuddy双开.app"
USER_DATA_DIR="$HOME/Library/Application Support/WorkBuddyDual"

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 WorkBuddy 是否存在
check_app() {
    if [ ! -d "$WORKBUDDY_DUAL" ]; then
        print_error "找不到 WorkBuddy 双开版本: $WORKBUDDY_DUAL"
        print_info "请先运行 create-workbuddy-dual.sh 创建双开版本"
        exit 1
    fi
    print_success "找到 WorkBuddy 双开版本"
}

# 创建用户数据目录
create_user_data_dir() {
    if [ ! -d "$USER_DATA_DIR" ]; then
        print_info "创建独立的用户数据目录..."
        mkdir -p "$USER_DATA_DIR"
        print_success "用户数据目录创建成功: $USER_DATA_DIR"
    else
        print_info "使用现有的用户数据目录: $USER_DATA_DIR"
    fi
}

# 启动 WorkBuddy 双开版本
launch_workbuddy_dual() {
    print_info "正在启动 WorkBuddy 双开版本..."
    print_info "用户数据目录: $USER_DATA_DIR"

    # 使用 --user-data-dir 参数启动，绕过单例检查
    # 同时设置不同的应用名称
    exec "$WORKBUDDY_DUAL/Contents/MacOS/Electron" \
        --user-data-dir="$USER_DATA_DIR" \
        --name="WorkBuddyDual" \
        --log-file="$USER_DATA_DIR/logs/main.log" \
        "$WORKBUDDY_DUAL/Contents/Resources/app/out/main.js"
}

# 主函数
main() {
    echo "=========================================="
    echo "     WorkBuddy 双开启动工具"
    echo "=========================================="
    echo ""

    check_app
    create_user_data_dir
    launch_workbuddy_dual
}

# 运行主函数
main "$@"
