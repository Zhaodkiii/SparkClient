#!/usr/bin/env python3
"""
医院首页素材包生成脚本
根据原型图生成所有需要的图片素材
"""
import os
import urllib.parse
import urllib.request
import json
from pathlib import Path

# 素材输出目录
OUTPUT_DIR = Path("/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/医院首页素材包")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# 主色调
ACCENT_COLOR = "#00B7D4"
HIGHLIGHT_GREEN = "#00B8A0"

# 素材定义列表
ASSETS = [
    # 1. 医院Logo
    {
        "name": "01_hospital_logo",
        "prompt": "Chinese traditional hospital logo, circular green badge with white medical cross in center, green leaf/wave elements below cross, small Chinese characters around the circle border, clean medical icon style, white background, flat design, professional healthcare logo",
        "size": "square_hd",
        "desc": "医院Logo - 绿色圆形徽章"
    },
    # 2. 顶部背景图
    {
        "name": "02_header_background",
        "prompt": "Modern Chinese hospital building exterior, light blue sky with soft white clouds, distant green mountains, green trees on both sides, traditional Chinese hospital architecture with red cross sign, bright clean morning light, peaceful healing atmosphere, wide banner composition, soft watercolor illustration style",
        "size": "landscape_16_9",
        "desc": "首页顶部背景 - 医院建筑远山树木"
    },
    # 3. 预约挂号图标
    {
        "name": "03_icon_registration",
        "prompt": "Medical appointment calendar icon, teal green gradient calendar page with white plus sign in center, two small rings on top, 3D cute style, soft shadow, white background, flat design with subtle depth, healthcare app icon",
        "size": "square",
        "desc": "预约挂号图标 - 绿色日历加号"
    },
    # 4. AI导诊图标
    {
        "name": "04_icon_ai_triage",
        "prompt": "Cute friendly AI medical robot doctor, white robot with blue glowing eyes, stethoscope around neck, small 'AI' badge on top right corner, teal green gradient background, soft rounded corners, 3D illustration style, healthcare chatbot mascot, white and teal color scheme",
        "size": "portrait_4_3",
        "desc": "AI导诊图标 - 白色AI机器人"
    },
    # 5. 报告解读图标
    {
        "name": "05_icon_report",
        "prompt": "Blue medical document icon with magnifying glass, blue paper document with white text lines, magnifying glass overlapping on bottom right, blue gradient color, 3D cute style, soft shadow, white background, medical report analysis icon",
        "size": "square",
        "desc": "报告解读图标 - 蓝色文档放大镜"
    },
    # 6. 线上问诊图标
    {
        "name": "06_icon_telemedicine",
        "prompt": "Friendly female doctor avatar portrait, Asian woman doctor in white coat with stethoscope, gentle smile, dark hair tied back, professional yet approachable, 3D illustration style, soft lighting, light purple background, healthcare professional",
        "size": "portrait_4_3",
        "desc": "线上问诊图标 - 女医生头像"
    },
    # 7. 心内科图标
    {
        "name": "07_icon_cardiology",
        "prompt": "Red heart with ECG heartbeat line icon, bright red heart shape, white EKG/electrocardiogram wave across the heart, soft gradient, 3D cute style, slight shadow, white background, cardiology department icon, healthcare medical symbol",
        "size": "square",
        "desc": "心内科图标 - 红色心形心电图"
    },
    # 8. 皮肤科图标
    {
        "name": "08_icon_dermatology",
        "prompt": "Skin and hair follicle cross-section icon, peach skin tone, dark brown hair strand, simple clean medical illustration style, soft gradient, 3D cute style, white background, dermatology department icon, skincare medical symbol",
        "size": "square",
        "desc": "皮肤科图标 - 皮肤毛囊"
    },
    # 9. 内分泌科图标
    {
        "name": "09_icon_endocrinology",
        "prompt": "Thyroid gland anatomy icon, pinkish red butterfly-shaped thyroid organ, soft gradient shading, clean medical illustration style, 3D cute style, white background, endocrinology department icon, healthcare medical symbol",
        "size": "square",
        "desc": "内分泌科图标 - 甲状腺"
    },
    # 10. 患者头像
    {
        "name": "10_avatar_patient",
        "prompt": "Young Asian male patient avatar, friendly cartoon style man in light blue shirt, short black hair, gentle smile, 3D illustration portrait, circular crop, soft lighting, light blue background, approachable patient character",
        "size": "square_hd",
        "desc": "患者头像 - 年轻男性卡通头像"
    },
    # 11. 医生头像（张医生）
    {
        "name": "11_avatar_doctor",
        "prompt": "Professional Asian male doctor portrait, middle-aged man wearing glasses, white doctor coat with blue tie and stethoscope, warm friendly smile, neat black hair, realistic 3D illustration style, light blue medical background, trusted physician headshot",
        "size": "portrait_4_3",
        "desc": "医生头像 - 戴眼镜男医生"
    },
    # 12. 底部中医药装饰
    {
        "name": "12_decoration_tcm",
        "prompt": "Traditional Chinese medicine herbs and mortar, green herbal leaves like mugwort, wooden bowl with dried herbs, ginseng root, beige natural background, warm traditional Chinese medicine aesthetic, watercolor illustration style, horizontal banner, TCM elements decoration",
        "size": "landscape_16_9",
        "desc": "底部装饰 - 中医药草药"
    },
    # 13. 通知铃铛（带红点）
    {
        "name": "13_icon_bell",
        "prompt": "Notification bell icon, simple outline bell shape, dark gray color, small red dot badge on top right corner, clean minimal iOS style icon, white background, flat design, system notification bell",
        "size": "square",
        "desc": "通知铃铛图标"
    },
    # 14. AI助手小徽章
    {
        "name": "14_badge_ai",
        "prompt": "Small AI badge, white rounded rectangle with 'AI' text, teal green color, cute sparkles around, clean modern design, white background, small assistant badge icon",
        "size": "square",
        "desc": "AI助手徽章"
    },
]


def generate_image_url(prompt: str, size: str) -> str:
    """生成图片URL"""
    encoded_prompt = urllib.parse.quote(prompt)
    return f"https://console.enterprise.trae.cn/api/ide/v1/text_to_image?prompt={encoded_prompt}&image_size={size}"


def download_image(url: str, output_path: Path) -> bool:
    """下载图片到指定路径"""
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=60) as response:
            data = response.read()
            with open(output_path, 'wb') as f:
                f.write(data)
            return True
    except Exception as e:
        print(f"下载失败 {output_path.name}: {e}")
        return False


def create_contents_json(imageset_path: Path, filename: str = "image.png"):
    """创建Xcode imageset的Contents.json"""
    contents = {
        "images": [
            {
                "filename": filename,
                "idiom": "universal",
                "scale": "1x"
            },
            {
                "filename": filename,
                "idiom": "universal",
                "scale": "2x"
            },
            {
                "filename": filename,
                "idiom": "universal",
                "scale": "3x"
            }
        ],
        "info": {
            "author": "xcode",
            "version": 1
        }
    }
    with open(imageset_path / "Contents.json", 'w', encoding='utf-8') as f:
        json.dump(contents, f, indent=2, ensure_ascii=False)


def main():
    print("=" * 60)
    print("开始生成医院首页素材包")
    print("=" * 60)
    
    success_count = 0
    total = len(ASSETS)
    
    # 保存URL清单
    url_list = []
    
    for i, asset in enumerate(ASSETS, 1):
        print(f"\n[{i}/{total}] 生成: {asset['desc']}")
        print(f"  文件名: {asset['name']}.png")
        
        url = generate_image_url(asset['prompt'], asset['size'])
        output_path = OUTPUT_DIR / f"{asset['name']}.png"
        
        url_list.append({
            "name": asset['name'],
            "desc": asset['desc'],
            "url": url,
            "file": f"{asset['name']}.png"
        })
        
        print(f"  URL: {url[:80]}...")
        
        if download_image(url, output_path):
            print(f"  ✓ 已保存: {output_path}")
            success_count += 1
        else:
            print(f"  ✗ 下载失败，URL已记录在清单中")
    
    # 保存URL清单
    manifest_path = OUTPUT_DIR / "素材清单.json"
    with open(manifest_path, 'w', encoding='utf-8') as f:
        json.dump({
            "generated_at": os.popen('date +"%Y-%m-%d %H:%M:%S"').read().strip(),
            "total": total,
            "success": success_count,
            "assets": url_list
        }, f, indent=2, ensure_ascii=False)
    
    # 保存Markdown说明
    readme_path = OUTPUT_DIR / "素材说明.md"
    with open(readme_path, 'w', encoding='utf-8') as f:
        f.write("# 医院首页素材包\n\n")
        f.write(f"生成时间: {os.popen('date +\"%Y-%m-%d %H:%M:%S\"').read().strip()}\n\n")
        f.write("## 素材清单\n\n")
        f.write("| 序号 | 文件名 | 说明 | 尺寸 |\n")
        f.write("|------|--------|------|------|\n")
        for i, asset in enumerate(ASSETS, 1):
            size_map = {
                "square_hd": "1024×1024",
                "square": "1024×1024",
                "portrait_4_3": "768×1024",
                "landscape_16_9": "1792×1024"
            }
            f.write(f"| {i} | {asset['name']}.png | {asset['desc']} | {size_map.get(asset['size'], asset['size'])} |\n")
        
        f.write("\n## 使用说明\n\n")
        f.write("1. 所有图片均为PNG格式\n")
        f.write("2. 如需导入Xcode Assets.xcassets，请参考对应imageset结构\n")
        f.write("3. 主色调：青蓝色 #00B7D4\n")
        f.write("4. AI导诊高亮色：青绿色 #00B8A0\n")
    
    print("\n" + "=" * 60)
    print(f"素材生成完成！成功: {success_count}/{total}")
    print(f"素材目录: {OUTPUT_DIR}")
    print(f"清单文件: {manifest_path}")
    print(f"说明文档: {readme_path}")
    print("=" * 60)


if __name__ == "__main__":
    main()
