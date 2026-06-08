#!/usr/bin/env python3
"""
微信图标颜色替换脚本
将绿色基调的微信图标替换为蓝色基调

纯 Python + Pillow 实现，无 numpy 依赖。
"""

from PIL import Image
from colorsys import rgb_to_hls, hls_to_rgb
import sys
import os


def replace_icon_color(input_path, output_path):
    """
    替换图标颜色：从绿色基调改为蓝色基调

    基于实际微信双开版本的精确颜色分析：
    - 原图主色: (0, 192, 96) -> H=0.4167, L=0.3765, S=1.0000
    - 双开主色: (0, 128, 192) -> H=0.5556, L=0.3765, S=1.0000
    - 转换规则: 色相旋转 +0.1389 (50度)，饱和度和亮度保持不变
    """
    try:
        # 读取图标并转换为RGBA
        img = Image.open(input_path).convert("RGBA")
        width, height = img.size
        pixels = img.load()  # 像素访问对象

        # 色相旋转参数：+0.1389 (50度)
        hue_shift = 0.1389

        # 检查是否有非透明像素
        has_visible = False
        for y in range(height):
            for x in range(width):
                r, g, b, a = pixels[x, y]
                if a > 0:
                    has_visible = True
                    break
            if has_visible:
                break

        # 对每个像素进行色相旋转
        if has_visible:
            for y in range(height):
                for x in range(width):
                    r, g, b, a = pixels[x, y]
                    if a > 0:
                        # RGB -> HLS
                        h, l, s = rgb_to_hls(r / 255.0, g / 255.0, b / 255.0)
                        # 色相旋转 +50度
                        h = (h + hue_shift) % 1.0
                        # HLS -> RGB
                        nr, ng, nb = hls_to_rgb(h, l, s)
                        pixels[x, y] = (
                            int(nr * 255),
                            int(ng * 255),
                            int(nb * 255),
                            a,
                        )

        # 保存为 PNG
        if output_path.lower().endswith(".png"):
            img.save(output_path, "PNG")
        else:
            # 非 .png 后缀时，保存为 png（后面 iconutil 会处理）
            temp_png = output_path.rsplit(".", 1)[0] + ".png"
            img.save(temp_png, "PNG")

        return True

    except Exception as e:
        print(f"错误: 处理图标时出错 - {e}", file=sys.stderr)
        return False


def main():
    if len(sys.argv) != 3:
        print("使用方法: python3 replace_icon_color.py <输入图标路径> <输出图标路径>")
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2]

    if not os.path.exists(input_path):
        print(f"错误: 输入文件不存在: {input_path}", file=sys.stderr)
        sys.exit(1)

    print(f"正在处理图标: {input_path}")
    print(f"输出路径: {output_path}")

    if replace_icon_color(input_path, output_path):
        print("✓ 图标颜色替换成功！")
        sys.exit(0)
    else:
        print("✗ 图标颜色替换失败！")
        sys.exit(1)


if __name__ == "__main__":
    main()
