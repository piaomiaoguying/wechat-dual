#!/usr/bin/env python3
"""
微信图标颜色替换脚本
将绿色基调的微信图标替换为蓝色基调

纯 Python + Pillow 实现，无 numpy 依赖。

用法:
    replace_icon_color.py <输入> <输出>              单文件改色
    replace_icon_color.py --iconset <iconset目录>    批量改色目录下所有 PNG
    replace_icon_color.py --xcassets <iconset目录> <xcassets目录>
                                                    生成 Xcode 资源目录结构
    replace_icon_color.py --probe <icns文件>         读取图标主色（用于校验）
"""

from PIL import Image
from colorsys import rgb_to_hls, hls_to_rgb
from collections import Counter
import json
import os
import shutil
import sys

# 色相旋转参数：+0.1389 (50度)，绿 -> 蓝
# 原图主色 (5, 207, 102) -> 目标主色 (5, 143, 207)
HUE_SHIFT = 0.1389

# iconset 中的文件名 -> (尺寸, 倍率)，用于生成 Xcode 资源目录
ICONSET_ENTRIES = [
    ("icon_16x16.png", "16x16", "1x"),
    ("icon_16x16@2x.png", "16x16", "2x"),
    ("icon_32x32.png", "32x32", "1x"),
    ("icon_32x32@2x.png", "32x32", "2x"),
    ("icon_128x128.png", "128x128", "1x"),
    ("icon_128x128@2x.png", "128x128", "2x"),
    ("icon_256x256.png", "256x256", "1x"),
    ("icon_256x256@2x.png", "256x256", "2x"),
    ("icon_512x512.png", "512x512", "1x"),
    ("icon_512x512@2x.png", "512x512", "2x"),
]


def _shift_pixel(r, g, b):
    """将单个像素的色相旋转 +50度，保持饱和度与亮度不变"""
    h, l, s = rgb_to_hls(r / 255.0, g / 255.0, b / 255.0)
    nr, ng, nb = hls_to_rgb((h + HUE_SHIFT) % 1.0, l, s)
    return int(nr * 255), int(ng * 255), int(nb * 255)


def replace_icon_color(input_path, output_path):
    """
    替换图标颜色：从绿色基调改为蓝色基调

    微信图标本身是扁平色块，同色像素极多，因此对颜色做记忆化缓存
    （实测 1024x1024 图标约 1900 种颜色），避免逐像素重复计算 HLS。
    """
    try:
        img = Image.open(input_path).convert("RGBA")
        data = list(img.getdata())

        cache = {}
        out = []
        for r, g, b, a in data:
            if a == 0:
                out.append((r, g, b, a))
                continue
            key = (r, g, b)
            shifted = cache.get(key)
            if shifted is None:
                shifted = _shift_pixel(r, g, b)
                cache[key] = shifted
            out.append((shifted[0], shifted[1], shifted[2], a))

        img.putdata(out)

        # 统一按 PNG 保存，后续由 iconutil / actool 打包
        target = output_path
        if not target.lower().endswith(".png"):
            target = target.rsplit(".", 1)[0] + ".png"
        img.save(target, "PNG")

        return True

    except Exception as e:
        print(f"错误: 处理图标时出错 - {e}", file=sys.stderr)
        return False


def replace_iconset(iconset_dir):
    """批量处理 iconset 目录下的所有 PNG"""
    if not os.path.isdir(iconset_dir):
        print(f"错误: 目录不存在: {iconset_dir}", file=sys.stderr)
        return False

    png_files = sorted(f for f in os.listdir(iconset_dir) if f.endswith(".png"))
    if not png_files:
        print(f"错误: 目录中没有 PNG 文件: {iconset_dir}", file=sys.stderr)
        return False

    processed = 0
    for name in png_files:
        path = os.path.join(iconset_dir, name)
        if replace_icon_color(path, path):
            processed += 1
        else:
            return False

    print(f"已改色 {processed} 个分辨率")
    return True


def make_xcassets(iconset_dir, xcassets_dir):
    """从 iconset 目录生成 Xcode 资源目录（供 actool 编译出 Assets.car）"""
    if not os.path.isdir(iconset_dir):
        print(f"错误: 目录不存在: {iconset_dir}", file=sys.stderr)
        return False

    appiconset = os.path.join(xcassets_dir, "AppIcon.appiconset")
    if os.path.isdir(xcassets_dir):
        shutil.rmtree(xcassets_dir)
    os.makedirs(appiconset)

    images = []
    for filename, size, scale in ICONSET_ENTRIES:
        src = os.path.join(iconset_dir, filename)
        if not os.path.isfile(src):
            continue
        shutil.copy2(src, os.path.join(appiconset, filename))
        images.append({
            "filename": filename,
            "idiom": "mac",
            "scale": scale,
            "size": size,
        })

    if not images:
        print("错误: iconset 中没有可用的图标文件", file=sys.stderr)
        return False

    with open(os.path.join(appiconset, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}},
                  f, indent=2)

    with open(os.path.join(xcassets_dir, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)

    print(f"已生成资源目录，包含 {len(images)} 个图标")
    return True


def probe_icon(icon_path):
    """读取图标主色并输出 RGB，用于校验改色是否生效"""
    try:
        img = Image.open(icon_path).convert("RGBA")
    except Exception as e:
        print(f"错误: 无法读取图标 - {e}", file=sys.stderr)
        return 1

    counter = Counter()
    for r, g, b, a in img.getdata():
        if a > 200 and not (r > 240 and g > 240 and b > 240):
            counter[(r, g, b)] += 1

    if not counter:
        print("错误: 图标中没有可见像素", file=sys.stderr)
        return 1

    r, g, b = counter.most_common(1)[0][0]
    # 绿色系：G 通道最高；蓝色系：B 通道最高
    tone = "blue" if b > g else "green"
    print(f"{r},{g},{b},{tone}")
    return 0


def main():
    args = sys.argv[1:]

    if len(args) >= 2 and args[0] == "--iconset":
        sys.exit(0 if replace_iconset(args[1]) else 1)

    if len(args) >= 3 and args[0] == "--xcassets":
        sys.exit(0 if make_xcassets(args[1], args[2]) else 1)

    if len(args) >= 2 and args[0] == "--probe":
        sys.exit(probe_icon(args[1]))

    if len(args) != 2:
        print("使用方法:")
        print("  replace_icon_color.py <输入图标路径> <输出图标路径>")
        print("  replace_icon_color.py --iconset <iconset目录>")
        print("  replace_icon_color.py --xcassets <iconset目录> <xcassets目录>")
        print("  replace_icon_color.py --probe <图标文件>")
        sys.exit(1)

    input_path, output_path = args
    if not os.path.exists(input_path):
        print(f"错误: 输入文件不存在: {input_path}", file=sys.stderr)
        sys.exit(1)

    if replace_icon_color(input_path, output_path):
        sys.exit(0)
    else:
        print("✗ 图标颜色替换失败！", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
