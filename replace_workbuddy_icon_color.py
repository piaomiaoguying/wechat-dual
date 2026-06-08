#!/usr/bin/env python3
"""
WorkBuddy 图标颜色替换脚本
将 WorkBuddy 图标的主色调替换为蓝色基调

基于精确的颜色分析：
- WorkBuddy 原色: RGB(93, 217, 181) -> H=0.4508, L=0.6108, S=0.6255
- 目标蓝色: RGB(0, 128, 192) -> H=0.5556, L=0.3765, S=1.0000
- 转换规则: 色相旋转 +0.1048 (37.8°)，饱和度调整，亮度调整
"""

from PIL import Image
import numpy as np
import sys
import os

def replace_workbuddy_icon_color(input_path, output_path):
    """
    替换 WorkBuddy 图标颜色：从青绿色基调改为蓝色基调

    基于实际 WorkBuddy 图标的分析和微信双开的蓝色配色方案

    Args:
        input_path: 输入图标路径
        output_path: 输出图标路径
    """
    try:
        # 读取图标并转换为RGBA
        img = Image.open(input_path).convert("RGBA")
        pixels = np.array(img)

        # 创建新的像素数组
        new_pixels = pixels.copy()

        # 使用HSL色彩空间进行颜色调整
        # 精确调整以接近目标蓝色 RGB(0, 128, 192)
        # 色相旋转参数：+0.1048 (37.8度)
        # 亮度调整：降低到目标亮度
        # 饱和度调整：提高到目标饱和度
        hue_shift = 0.1048
        target_brightness = 0.3765
        target_saturation = 1.0000

        # 获取所有非透明像素
        mask = pixels[:,:,3] > 0

        if np.any(mask):
            from colorsys import rgb_to_hls, hls_to_rgb

            # 对每个像素进行颜色转换
            for i in range(pixels.shape[0]):
                for j in range(pixels.shape[1]):
                    if mask[i, j]:
                        r, g, b = pixels[i, j, 0]/255.0, pixels[i, j, 1]/255.0, pixels[i, j, 2]/255.0
                        h, l, s = rgb_to_hls(r, g, b)

                        # 色相旋转 +37.8度 (0.1048)
                        h = (h + hue_shift) % 1.0

                        # 亮度调整到目标值（保持颜色的整体亮度特征）
                        # 对于主色调，直接使用目标亮度
                        if abs(h - 0.55) < 0.05:  # 接近蓝色区域
                            l = target_brightness
                        else:
                            # 其他颜色按比例调整
                            l = l * 0.55  # 进一步降低到目标亮度水平

                        # 饱和度调整到目标值，提高蓝色区域的饱和度
                        if abs(h - 0.55) < 0.1:  # 蓝色区域及附近
                            s = 1.0  # 最大饱和度
                        else:
                            s = min(s * 1.8, 1.0)  # 提高其他颜色的饱和度

                        # 转换回RGB
                        new_r, new_g, new_b = hls_to_rgb(h, l, s)

                        new_pixels[i, j, 0] = int(new_r * 255)
                        new_pixels[i, j, 1] = int(new_g * 255)
                        new_pixels[i, j, 2] = int(new_b * 255)

        # 转换回PIL图像
        new_img = Image.fromarray(new_pixels.astype(np.uint8), 'RGBA')

        # 保存为PNG（如果输出路径以.png结尾）
        if output_path.lower().endswith('.png'):
            new_img.save(output_path, 'PNG')
        else:
            # 保存为ICNS格式需要特殊处理
            # 这里先保存为PNG，后续可以转换为ICNS
            temp_png = output_path.rsplit('.', 1)[0] + '.png'
            new_img.save(temp_png, 'PNG')

            # 尝试使用sips转换为ICNS
            import subprocess
            try:
                subprocess.run(['sips', '-s', 'format', 'icns', temp_png, '--out', output_path],
                             check=True, capture_output=True)
                print(f"已创建ICNS格式图标: {output_path}")
            except subprocess.CalledProcessError:
                print(f"警告: 无法转换为ICNS，使用PNG格式: {temp_png}")

        return True

    except Exception as e:
        print(f"错误: 处理图标时出错 - {e}", file=sys.stderr)
        return False

def main():
    if len(sys.argv) != 3:
        print("使用方法: python3 replace_workbuddy_icon_color.py <输入图标路径> <输出图标路径>")
        print("示例: python3 replace_workbuddy_icon_color.py WorkBuddy.icns workbuddy_blue.png")
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2]

    if not os.path.exists(input_path):
        print(f"错误: 输入文件不存在: {input_path}", file=sys.stderr)
        sys.exit(1)

    print(f"正在处理 WorkBuddy 图标: {input_path}")
    print(f"输出路径: {output_path}")

    if replace_workbuddy_icon_color(input_path, output_path):
        print("✓ WorkBuddy 图标颜色替换成功（青绿色→蓝色）！")
        sys.exit(0)
    else:
        print("✗ WorkBuddy 图标颜色替换失败！")
        sys.exit(1)

if __name__ == "__main__":
    main()
