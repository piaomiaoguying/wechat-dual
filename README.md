# macOS 应用双开工具

## 功能特点

✅ **自动创建双开应用** - 一键复制应用并实现双开
✅ **智能版本检测** - 自动比较原版和双开版本，选择最佳策略
✅ **保留更新内容** - 当双开版本比原版微信新时，基于双开版本重建
✅ **自动修改Bundle ID** - 绕过单例检测，实现独立运行
✅ **自动替换图标颜色** - 将原图标改为蓝色，方便区分
✅ **自动重新签名** - 修复代码签名，确保应用正常运行
✅ **数据完全隔离** - 两个应用独立登录，数据互不干扰
✅ **状态检查工具** - 提供检查脚本，监控双开版本状态

## 支持的应用

目前本工具支持以下应用的双开：

| 应用 | 双开脚本 | 启动方式 | 备注 |
|------|---------|---------|------|
| **WeChat** | `create-wechat-dual.sh` | 直接双击 | 原生应用，直接可双开 |
| **WorkBuddy** | `create-workbuddy-dual.sh` | 需要启动脚本 | Electron应用，需要特殊启动方式 |

## 使用方法

### 快速开始 - WeChat 双开

1. 确保已安装微信到 `/Applications/WeChat.app`
2. 在终端运行脚本：
   ```bash
   sudo ./create-wechat-dual.sh
   ```
3. 脚本会自动检测版本并选择最佳策略：
   - 如果双开版本不存在或版本较旧：从原版微信复制
   - 如果双开版本比原版微信新：基于双开版本重建（保留更新内容）
   - 如果版本相同：仅修复配置（Bundle ID和图标）
4. 按提示完成操作
5. 打开双开版本登录第二个账号

### 检查双开版本状态

```bash
./check-wechat-dual.sh
```

此脚本会检查：
- Bundle ID 是否正确
- 版本号是否一致
- Helper 应用配置
- 数据目录状态

如果发现问题，会提供修复建议。

### WorkBuddy 双开

由于 WorkBuddy 是 Electron 应用，有内置的单例检查机制，需要特殊处理：

1. **创建双开版本**：
   ```bash
   sudo ./create-workbuddy-dual.sh
   ```

2. **启动双开版本**（选择一种方式）：

   **方式一：使用简易启动脚本（推荐）**
   ```bash
   ./start-workbuddy-dual.sh
   ```

   **方式二：使用完整启动脚本**
   ```bash
   ./launch-workbuddy-dual.sh
   ```

3. 正常启动原版 WorkBuddy，现在可以同时运行两个 WorkBuddy 了！

## 依赖要求

**通用依赖：**
- macOS 10.14 或更高版本
- Python 3（用于图标颜色替换）

**图标处理依赖：**
```bash
pip3 install pillow
```

## 脚本说明

### create-wechat-dual.sh
WeChat 双开主脚本，包含以下功能：
- **智能版本检测**：自动比较原版微信和双开版本的版本号
- **基于双开版本重建**：当双开版本比原版微信新时，基于双开版本重建（保留更新内容）
- 复制微信应用到新位置
- 修改 Bundle Identifier（自动处理已包含`.dual`后缀的情况）
- 修改Helper应用的Bundle Identifier（防止更新时被重置）
- 替换图标颜色（绿色→蓝色）
- 重新签名应用
- 验证完整性

### create-workbuddy-dual.sh
WorkBuddy 双开主脚本，包含以下功能：
- 复制 WorkBuddy 应用到新位置
- 修改 Bundle Identifier
- 修改应用内部名称（package.json）
- 替换图标颜色（青绿色→蓝色）
- 重新签名应用
- 验证完整性

### replace_icon_color.py
WeChat 图标颜色替换脚本：
- 使用 HSL 色彩空间进行颜色转换
- 将绿色基调（约120度）调整为蓝色基调（约210度）
- 基于实际微信双开版本的精确颜色分析

### replace_workbuddy_icon_color.py
WorkBuddy 图标颜色替换脚本：
- 使用 HSL 色彩空间进行颜色转换
- 将青绿色基调调整为蓝色基调
- 基于实际 WorkBuddy 图标分析和微信双开的蓝色配色

### start-workbuddy-dual.sh
WorkBuddy 双开简易启动脚本：
- 检查双开版本是否存在
- 创建独立的用户数据目录
- 直接启动双开版本

### check-wechat-dual.sh
微信双开版本检查脚本（v1.2新增）：
- 检查双开版本的 Bundle ID 是否被重置
- 检查版本号是否与原版微信一致
- 检查 Helper 应用的 Bundle ID
- 检查数据目录是否正常
- 提供修复建议
- 支持自动修复功能

### launch-workbuddy-dual.sh
WorkBuddy 双开完整启动脚本：
- 检查双开版本是否存在
- 创建独立的用户数据目录
- 使用命令行参数启动双开版本
- 传递 `--user-data-dir` 参数绕过单例检查

## 工作原理

### Bundle Identifier 机制

macOS 通过 Bundle Identifier（包标识符）来识别应用：

| 场景 | 说明 |
|------|------|
| **进程唯一性** | 系统通过 Bundle Identifier 判断"这个应用是否已经在运行" |
| **沙盒隔离** | 应用数据（缓存、偏好设置、数据库）按 Bundle ID 分目录存储 |
| **登录态管理** | 客户端通过 Bundle ID 关联本地的登录会话 |
| **通知路由** | 系统推送通知根据 Bundle ID 分发到对应应用 |

### 图标颜色替换

通过以下步骤实现图标颜色替换：
1. 使用 `iconutil` 将 ICNS 解压为 iconset（包含多个分辨率的 PNG）
2. 对所有 PNG 文件进行颜色转换（HSL 色相旋转）
3. 使用 `iconutil` 将 iconset 重新打包为 ICNS

### Electron 应用单例检查

WorkBuddy 作为 Electron 应用，使用了 `app.requestSingleInstanceLock()` 来实现单例检查：

**工作原理：**
- 尝试获取实例锁
- 如果获取失败（已有实例运行），当前实例退出
- 如果获取成功，成为主实例，监听 `second-instance` 事件

**多开解决方案：**
1. 修改应用内部名称（package.json 中的 `name` 字段）
2. 使用独立的用户数据目录
3. 通过启动脚本传递 `--user-data-dir` 参数

### 数据隔离

两个应用使用不同的数据目录：

**WeChat：**
- 原版：`~/Library/Containers/com.tencent.xinWeChat`
- 双开：`~/Library/Containers/com.tencent.xinWeChat.dual`

**WorkBuddy：**
- 原版：`~/Library/Application Support/WorkBuddy`
- 双开：`~/Library/Application Support/WorkBuddyDual`（通过启动脚本设置）

## 🔍 微信双开自动更新现象分析

### ⚠️ 发现的异常现象

在使用微信双开时，可能会发现以下情况：

```
正常微信：      4.1.8.107 (37342)
微信双开：      4.1.9.29  (268573)  ← 版本号更高！
```

### 🎯 现象详解

1. **双开版本能自动更新**
   - 从 4.1.8 更新到了 4.1.9
   - 更新时间可能比原版微信更新

2. **Bundle ID 在更新时被重置**
   - 原始设置：`com.tencent.xinWeChat.dual`
   - 更新后：`com.tencent.xinWeChat` ← 丢失了 `.dual` 后缀

3. **仍然使用独立的数据目录**
   - 正常微信：`~/Library/Containers/com.tencent.xinWeChat`
   - 双开微信：`~/Library/Containers/com.tencent.xinWeChat.dual`
   - 说明微信有额外的数据目录选择机制

4. **版本号可能更高**
   - 双开版本可能更新到比原版微信更新的版本
   - 可能是微信的"内测版"或"测试版"更新通道

### ⚡ 原因分析

微信的双开版本能够自动更新，可能是因为：

1. **更新机制不依赖Bundle ID**
   - 微信可能使用其他机制来识别应用
   - 如：应用路径、文件签名、内部标识等

2. **内测/测试版通道**
   - 双开版本可能被识别为测试版用户
   - 能够接收到更早的版本更新

3. **更新时覆盖配置**
   - 微信更新程序可能覆盖了 `Info.plist` 中的配置
   - 导致 Bundle ID 重置为原始值

4. **数据目录锁定机制**
   - 微信内部可能检测到已有实例运行
   - 自动使用带有后缀的数据目录

### 🔧 解决方案

#### 方案一：修改Helper应用Bundle ID（推荐）

更新后的脚本已经包含了此功能：
- 同时修改主应用和Helper应用的Bundle ID
- 使用统一的 `.dual` 后缀
- 降低更新时被重置的风险

#### 方案二：手动检查Bundle ID

定期检查双开版本的Bundle ID：

```bash
# 查看双开版本的Bundle ID
defaults read "/Applications/微信双开.app/Contents/Info.plist" CFBundleIdentifier

# 如果不是com.tencent.xinWeChat.dual，重新创建双开版本
sudo ./create-wechat-dual.sh
```

#### 方案三：禁用自动更新（不推荐）

可以通过修改网络设置或权限来阻止更新，但：
- ❌ 可能错过重要的安全更新
- ❌ 可能影响正常功能使用
- ❌ 操作复杂，不推荐

### ⚠️ 风险提醒

1. **更新冲突风险**
   - 两个应用现在有相同的 Bundle ID
   - 可能影响系统对应用的识别

2. **数据混乱风险**
   - 如果两个应用开始使用同一个数据目录
   - 可能导致数据丢失或覆盖

3. **功能异常风险**
   - Bundle ID 冲突可能导致系统通知、文件关联等功能异常

### 📊 推荐做法

1. **定期检查Bundle ID**
   ```bash
   # 创建一个简单的检查脚本
   if [ "$(defaults read "/Applications/微信双开.app/Contents/Info.plist" CFBundleIdentifier)" != "com.tencent.xinWeChat.dual" ]; then
       echo "Bundle ID 已被重置，需要重新创建双开版本"
       sudo ./create-wechat-dual.sh
   fi
   ```

2. **更新后重新创建双开**
   - 当原版微信更新后，重新创建双开版本
   - 确保使用最新版本的正确配置

3. **监控数据目录**
   - 定期检查两个应用是否使用了正确的数据目录
   - 确保数据隔离正常

## 重要提醒

⚠️ **版本更新**
- **WeChat**：双开版本**可能**自动更新，但更新时Bundle ID可能被重置
  - 更新后可能获得比原版微信更新的版本
  - 更新时Bundle ID 可能从 `.dual` 重置为原始ID
  - **v1.2 新增**：脚本会智能检测版本，当双开版本比原版微信新时，会基于双开版本重建（保留更新内容）
  - 建议定期运行 `./check-wechat-dual.sh` 检查Bundle ID状态
- **WorkBuddy**：双开版本不会自动更新
- 建议定期检查主版本是否有更新

⚠️ **安全性**
- 脚本使用 ad-hoc 签名，可能在某些系统上被标记
- 不会影响原版应用的正常使用
- 建议不要在重要设备上使用，或者定期备份

⚠️ **磁盘空间**
- 每次创建双开会占用约 500MB（微信）或 1GB+（WorkBuddy）空间
- 建议定期清理旧版本

## 技术细节

### 颜色转换算法

**WeChat（精确匹配老双开版本）：**
```python
# 使用 HSL 色彩空间
h, l, s = rgb_to_hls(r, g, b)

# 色相旋转 +50度 (0.1389)
h = (h + 0.1389) % 1.0

# 饱和度和亮度保持不变
l = l  # 保持不变
s = s  # 保持不变
```

**WorkBuddy（基于精确的颜色分析）：**
```python
# 基于实际 WorkBuddy 图标分析
# 原色: RGB(93, 217, 181) -> H=0.4508, L=0.6108, S=0.6255
# 目标色: RGB(0, 128, 192) -> H=0.5556, L=0.3765, S=1.0000

# 色相旋转 +37.8度 (0.1048)
h = (h + 0.1048) % 1.0

# 亮度调整到目标值
if abs(h - 0.55) < 0.1:  # 蓝色区域
    l = 0.3765
else:
    l = l * 0.55  # 其他颜色按比例调整

# 饱和度调整到目标值
if abs(h - 0.55) < 0.1:  # 蓝色区域
    s = 1.0  # 最大饱和度
else:
    s = min(s * 1.8, 1.0)  # 提高其他颜色的饱和度
```

### 效果对比

**WeChat：**
| 项目 | 原版微信 | 双开版本 |
|------|---------|---------|
| **Bundle ID** | `com.tencent.xinWeChat` | `com.tencent.xinWeChat.dual` |
| **图标颜色** | 绿色 | 蓝色 |
| **数据目录** | `~/Library/Containers/com.tencent.xinWeChat` | `~/Library/Containers/com.tencent.xinWeChat.dual` |
| **自动更新** | 支持 | 可能支持（但Bundle ID可能被重置） |

**WorkBuddy：**
| 项目 | 原版 WorkBuddy | 双开版本 |
|------|---------------|----------|
| **Bundle ID** | `com.workbuddy.workbuddy` | `com.workbuddy.workbuddy.dual` |
| **应用名称** | `WorkBuddy` | `WorkBuddyDual` |
| **图标颜色** | 青绿色 | 蓝色 |
| **数据目录** | `~/Library/Application Support/WorkBuddy` | `~/Library/Application Support/WorkBuddyDual` |
| **自动更新** | 支持 | 不支持 |

## 故障排除

### "应用已损坏" 错误
- 确保有管理员权限
- 重新运行对应脚本
- 检查 macOS 版本兼容性

### WorkBuddy 双开无法启动
- 确保使用启动脚本（`start-workbuddy-dual.sh` 或 `launch-workbuddy-dual.sh`）
- 检查应用内部名称是否已修改
- 确认用户数据目录是否正确创建

### 图标颜色未替换
- 检查 Python 3 是否已安装
- 确认对应的图标替换脚本与主脚本在同一目录
- 检查依赖库是否安装完整

### 双开版本无法运行
- 确认代码签名是否成功
- 检查系统安全设置
- 尝试右键→打开→确认运行

## 免责声明

本工具仅供学习和个人使用，请勿用于商业用途。使用本工具产生的任何后果，作者不承担责任。请在遵守相关法律法规的前提下使用。

## 更新日志

### v1.2
- **智能版本检测**：自动比较原版微信和双开版本的版本号
- **基于双开版本重建**：当双开版本比原版微信更新时，基于双开版本重建（保留更新内容）
- **修复Bundle ID重复后缀问题**：正确处理已包含`.dual`后缀的Bundle ID
- **添加检查脚本**：`check-wechat-dual.sh` 用于检查双开版本状态
- **改进错误处理**：使用 `printf` 替代 `echo -e`，提高兼容性
- **修复bash return退出问题**：使用 `echo` 输出返回值，避免 `set -e` 导致脚本意外退出

### v1.1
- 添加 WorkBuddy 双开支持
- 为 Electron 应用实现特殊的多开方案
- 添加应用名称修改功能
- 添加 WorkBuddy 专用启动脚本

### v1.0
- 初始版本
- 支持基本的微信双开功能
- 添加自动图标颜色替换
- 添加完整的错误处理和验证
