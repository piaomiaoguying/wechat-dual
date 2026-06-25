# 🟢🔵 一行命令，Mac 微信双开

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS-blue?logo=apple" alt="platform">
  <img src="https://img.shields.io/badge/WeChat-自动适配版本-green?logo=wechat" alt="wechat">
  <img src="https://img.shields.io/badge/一行命令-搞定双开-orange" alt="one-command">
  <img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="license">
</p>

<p align="center">
  <b>复制一份微信 → 改 Bundle ID → 换蓝色图标 → 重签名 → 完工。</b><br>
  从此 Mac 上同时登录两个微信，生活号、工作号再也不打架。
</p>

---

## 🤔 为什么你需要这个

微信官方不允许同时登录两个账号——切换账号要扫码、等同步、丢消息。市面上的"微信多开"要么是付费流氓软件，要么往你电脑里塞东西。

**这个方案不一样：**

- 📁 **纯脚本，代码全公开**——不到 500 行 bash + 100 行 Python，每行你都看得见
- 🧠 **更新也不怕**——智能检测版本，微信偷偷更新后自动修复
- 🎨 **图标自动变蓝**——绿色是原版，蓝色是双开，一眼分清，告别点错
- ⚡ **一个命令一行搞定**——不需要图形界面，不需要注册，不需要付费

---

## 🚀 一行命令

```bash
sudo ./create-wechat-dual.sh
```

然后你的 `/Applications` 里就多了一个 **"微信双开.app"**——蓝色图标，独立运行，第二个账号直接登录。

### 已装好 Pillow？再来一条

```bash
./check-wechat-dual.sh   # 随时检查双开是否健康
```

> 首次使用需要 `pip3 install Pillow`（给图标换颜色用的）

---

## 🎯 为什么比别人的方案更强

| | 普通方案 | 本工具 |
|---|---|---|
| 微信更新后 | 💥 双开消失 / 冲突 | ✅ 智能检测，自动修复 |
| 图标区分 | 🤷 两个一模一样的绿图标 | 🔵 双开自动变蓝色，一眼分辨 |
| 数据隔离 | ⚠️ 偶尔串号 | ✅ Bundle ID 级隔离，永不串数据 |
| 依赖 | 📦 Electron / Node / 各种框架 | 🪶 纯 bash + Python 标准库 |
| 透明度 | 🕵️ 闭源二进制，鬼知道干了什么 | 📖 开源脚本，行行可读 |

---

## 🔍 到底做了什么

```
微信.app  →  复制一份  →  改 Info.plist (Bundle ID + .dual)  →  改 Helper App 的 Bundle ID
                                                                       ↓
  完成！  ←  codesign 重签名  ←  绿 → 蓝 (HSL 色相旋转 50°)  ←  拆包图标 ICNS
```

每一步都有详细日志输出，哪里出问题一目了然：

```
==========================================
     macOS 微信双开制作工具
==========================================

[INFO] 需要管理员权限执行此脚本
[SUCCESS] 找到原版微信应用
[INFO] 原版微信版本: 4.1.8.107 (内部版本: 37342)
[INFO] 未检测到双开版本，需要创建
[INFO] 正在复制微信应用...（等待约 1~2 分钟）
[SUCCESS] 应用复制完成
[INFO] 正在修改 Bundle Identifier...
[INFO] 原始: com.tencent.xinWeChat
[INFO] 修改为: com.tencent.xinWeChat.dual
[SUCCESS] Bundle Identifier 验证通过
[SUCCESS] 图标颜色替换成功（绿色→蓝色）
[SUCCESS] 应用签名成功

==========================================
           🎉 双开版本处理完成！
==========================================
```

---

## 🧠 微信更新也不怕（核心亮点）

微信双开最头疼的问题：**微信一自动更新，双开就废了。**

我们发现微信双开版本**竟然能自己偷偷更新**，而且有时候比原版微信更新得还快（疑似走内测通道）。更新时 Bundle ID 会被微信重置为原始值，导致两个微信冲突。

本工具内置了三层防护：

| 机制 | 作用 |
|---|---|
| **Helper App Bundle ID** | 同时修改子进程的标识，降低重置概率 |
| **智能版本检测** | 比较原版和双开的版本号，自动选择最佳重建策略 |
| **check-wechat-dual.sh** | 随时巡检 Bundle ID，发现异常一键修复 |

实际案例——微信更新把双开的 Bundle ID 重置后，运行检查脚本：

```
[ERROR] ❌ Bundle ID 已被重置！双开版本与原版微信相同
[INFO] 这意味着微信更新时重置了配置
[WARNING] 需要重新创建双开版本

==========================================
               修复建议
==========================================

1. 重新创建双开版本：
   sudo ./create-wechat-dual.sh
```

**注意：虽然 Bundle ID 被重置了，但数据目录没丢，重新创建后登录态还在，不需要重新扫码！**

---

## 🌈 颜色是怎么换的

不是简单的 RGB 叠加，而是**精确色彩空间映射**——采集了真实微信双开版本的蓝色，反推转换参数：

```
原版微信绿  RGB(0, 192, 96)   → HSL(150°, 37.6%, 100%)
    ↓  色相旋转 +50°，饱和度亮度不变
双开蓝色    RGB(0, 128, 192)  → HSL(200°, 37.6%, 100%)
```

结果就是——**和微信官方如果出双开版，图标颜色一模一样。**

---

## 📦 文件清单

| 文件 | 用途 |
|---|---|
| `create-wechat-dual.sh` | 🌟 主脚本：创建微信双开 |
| `check-wechat-dual.sh` | 🔍 巡检脚本：检查双开是否正常 |
| `replace_icon_color.py` | 🎨 图标换色：绿→蓝，纯 Pillow，无 numpy |

就三个文件，没有框架，没有配置文件，clone 下来直接跑。

---

## 🖥️ 系统要求

- macOS（用到了 `PlistBuddy`、`codesign`、`iconutil`，仅限 Mac）
- 微信装在 `/Applications/WeChat.app`
- Python 3 + Pillow：`pip3 install Pillow`
- sudo 权限（要往 `/Applications` 里写东西）

---

## ❓ 常见问题

<details>
<summary><b>会封号吗？</b></summary>
不修改微信本身的任何代码，只是利用 macOS 的 Bundle ID 机制让系统认为这是两个不同的应用。原理上完全合规。
</details>

<details>
<summary><b>双开能同步更新吗？</b></summary>
可能会自动更新（是的，微信居然会给双开版本推更新），但更新后 Bundle ID 会被重置。跑一下 <code>sudo ./create-wechat-dual.sh</code> 就修好了。
</details>

<details>
<summary><b>两个微信的数据互相影响吗？</b></summary>
完全隔离。原版用 <code>com.tencent.xinWeChat</code>，双开用 <code>com.tencent.xinWeChat.dual</code>，数据目录完全不同。
</details>

<details>
<summary><b>图标没变色？</b></summary>
<code>pip3 install Pillow</code> 先装好，确认 <code>replace_icon_color.py</code> 和主脚本在同一目录下。
</details>

<details>
<summary><b>能开三个吗？</b></summary>
理论上可以，把 <code>BUNDLE_ID_SUFFIX</code> 改成不同的值再跑一遍就行。不过两个账号通常够用了。
</details>

---

## 📜 免责声明

本工具仅供学习 macOS 应用 Bundle 机制之用。使用本工具产生的任何后果由使用者自行承担。

