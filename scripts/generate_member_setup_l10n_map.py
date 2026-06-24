#!/usr/bin/env python3
"""Generate member_setup_l10n_map.json from MemberSetup Swift sources."""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SETUP_ROOT = ROOT / "SparkClient/Projects/Features/Home/Presentation/Members/MemberSetup"
OUT = ROOT / "scripts/member_setup_l10n_map.json"
EXTRACTED = Path("/tmp/member_setup_strings.json")

SWIFT_INTERP = re.compile(r"\\\([^)]*\)")


def normalize_swift_interp(text: str) -> str:
    return SWIFT_INTERP.sub("%@", text)


def is_artifact(zh: str) -> bool:
    if zh.startswith(", ") or zh.startswith(" ("):
        return True
    if "String(format:" in zh:
        return True
    if re.match(r"^[,\\(]", zh):
        return True
    return False


KEY_MAP = {
    "未填写": "member.setup.common.not_filled",
    "待补充": "member.setup.common.pending",
    "已完成": "member.setup.common.completed",
    "未完成": "member.setup.common.incomplete",
    "未开始": "member.setup.common.not_started",
    "未开启": "member.module.status.not_opened",
    "重试": "common.retry",
    "下一步": "common.next",
    "跳过": "common.skip",
    "完成": "common.done",
    "保存": "common.save",
    "开始": "member.setup.common.start",
    "创建": "home.members.add.save",
    "上一步": "common.back",
    "基本信息": "home.members.field.basic_info",
    "成员信息缺失": "member.setup.flow.member_missing",
    "暂无长期用药": "member.setup.medical.medication.none_long_term",
    "已完成 %d / %d": "member.setup.common.progress_count",
}

EN: dict[str, str] = {
    "未填写": "Not filled",
    "待补充": "Pending",
    "已完成": "Completed",
    "未完成": "Incomplete",
    "未开始": "Not started",
    "未开启": "Not enabled",
    "重试": "Retry",
    "下一步": "Next",
    "跳过": "Skip",
    "完成": "Done",
    "保存": "Save",
    "开始": "Start",
    "创建": "Create",
    "上一步": "Back",
    "基本信息": "Basic information",
    "成员信息缺失": "Member information is missing",
    "暂无长期用药": "No long-term medications",
    "男": "Male",
    "女": "Female",
    "不确定 / 暂不填": "Unsure / Prefer not to say",
    "未选择": "Not selected",
    "无": "None",
    "有": "Yes",
    "不清楚": "Not sure",
    "低": "Low",
    "中": "Medium",
    "高": "High",
    "轻度": "Mild",
    "中度": "Moderate",
    "重度": "Severe",
    "从不": "Never",
    "已戒烟": "Quit smoking",
    "偶尔": "Occasionally",
    "经常": "Often",
    "不饮酒": "No alcohol",
    "已戒酒": "Quit drinking",
    "不运动": "No exercise",
    "1-2 次": "1–2 times",
    "3-5 次": "3–5 times",
    "5次以上": "More than 5 times",
    "低强度": "Low intensity",
    "中强度": "Moderate intensity",
    "高强度": "High intensity",
    "低强度 (轻微出汗)": "Low intensity (light sweat)",
    "中强度 (呼吸加快)": "Moderate intensity (breathing quickens)",
    "适量/小酌": "Light / social drinking",
    "中度/尽兴": "Moderate / hearty drinking",
    "过量/宿醉": "Heavy / hangover",
    "入睡快、睡得香": "Fall asleep quickly, sleep well",
    "多梦/易惊醒": "Many dreams / easy to wake",
    "经常失眠": "Often insomnia",
    "少于4小时": "Less than 4 hours",
    "4-8小时": "4–8 hours",
    "超过8小时": "More than 8 hours",
    "无既往病史": "No past medical history",
    "有既往病史": "Has past medical history",
    "无长期用药": "No long-term medications",
    "有用药记录": "Has medication records",
    "无手术史": "No surgical history",
    "无过敏经历": "No allergy history",
    "无家族病史": "No family history",
    "无任何不适": "No discomfort",
    "过敏备注已填": "Allergy notes provided",
    "有体检史": "Has exam history",
    "报告已填": "Report details provided",
    "已自动带入": "Auto-filled",
    "身高未填": "Height not filled",
    "体重未填": "Weight not filled",
    "职业未填": "Occupation not filled",
    "久坐未填": "Sedentary time not filled",
    "已设置用药提醒": "Medication reminders set",
    "医疗资料加载失败": "Failed to load medical profile",
    "正在加载医疗资料": "Loading medical profile",
    "还没有填写医疗资料。可以从任意一组开始，也可以直接使用「开始全部流程」一次性完成。": (
        "No medical profile yet. Start with any section, or use \"Start full flow\" to complete everything at once."
    ),
    "开始全部流程": "Start full flow",
    "基础档案 -> 病史 -> 生活习惯 -> 体检档案": "Basic profile → Medical history → Lifestyle → Exam archive",
    "暂不填写": "Skip for now",
    "选择维护模块": "Choose modules to maintain",
    "至少开启一个模块，后续可以分步完善": "Enable at least one module; you can complete details later",
    "正在读取已开通模块": "Loading enabled modules",
    "暂不完善": "Complete later",
    "模块配置加载失败，请稍后重试": "Failed to load module settings. Please try again later.",
    "医疗资料加载失败，请稍后重试": "Failed to load medical profile. Please try again later.",
    "记录慢性病史、用药计划与体检报告，持续追踪症状变化，辅助健康随访与病情管理。": (
        "Track chronic conditions, medications, and exam reports; monitor symptoms for follow-up and care management."
    ),
    "制定个性化饮食计划，追踪每日营养摄入与热量，科学管理体重与体脂变化。": (
        "Build a personalized diet plan, track daily nutrition and calories, and manage weight and body fat."
    ),
    "记录运动、睡眠、饮水和照护提醒，帮助形成稳定的日常健康习惯。": (
        "Log exercise, sleep, hydration, and care reminders to build steady daily health habits."
    ),
    "日常健康模块预留": "Daily health module (placeholder)",
    "先填写成员的基础信息": "Enter the member's basic information first",
    "年龄会影响健康建议与模块推荐": "Age affects health recommendations and module suggestions",
    "确认与当前账号的关系与性别": "Confirm relationship to this account and gender",
    "成员关系": "Member relationship",
    "医疗模块": "Medical module",
    "饮食健康": "Nutrition",
    "日常健康": "Daily health",
    "慢病、用药、体检、症状随访": "Chronic conditions, medications, exams, symptom follow-up",
    "饮食目标、营养、体重管理": "Diet goals, nutrition, weight management",
    "运动、睡眠、饮水、照护提醒（预留）": "Exercise, sleep, hydration, care reminders (placeholder)",
    "已完成 %d / %d": "Completed %d / %d",
    "预留": "Placeholder",
    "正在保存": "Saving…",
    "去完善": "Complete profile",
}

L10N_EN = {
    "common.preview": "Placeholder",
    "common.skip": "Skip",
    "home.members.add.failed": "Failed to add member",
    "home.members.add.subtitle": "Enter the member's basic information first",
    "home.members.birth_date.subtitle": "Age affects health recommendations and module suggestions",
    "home.members.field.basic_info": "Basic information",
    "home.members.finish": "Complete profile",
    "home.members.relationship.subtitle": "Confirm relationship to this account and gender",
    "home.members.relationship.title": "Member relationship",
    "home.members.save.loading": "Saving…",
    "home.members.save.success": "Completed",
    "member.module.daily_health.subtitle": "Exercise, sleep, hydration, care reminders (placeholder)",
    "member.module.daily_health.title": "Daily health",
    "member.module.medical.load_failed": "Failed to load medical profile. Please try again later.",
    "member.module.medical.subtitle": "Chronic conditions, medications, exams, symptom follow-up",
    "member.module.medical.title": "Medical module",
    "member.module.nutrition.subtitle": "Diet goals, nutrition, weight management",
    "member.module.nutrition.title": "Nutrition",
    "member.module.selection.load_failed": "Failed to load module settings. Please try again later.",
    "member.module.selection.loading": "Loading enabled modules",
    "member.module.selection.skip": "Complete later",
    "member.module.selection.subtitle": "Enable at least one module; you can complete details later",
    "member.module.selection.title": "Choose modules to maintain",
}

# Load extended translations from companion file if present
EXT = Path(__file__).with_name("member_setup_l10n_en_overrides.json")
if EXT.exists():
    EN.update(json.loads(EXT.read_text(encoding="utf-8")))


def infer_prefix(files: list[str]) -> str:
    f = files[0] if files else ""
    if "Nutrition/" in f:
        return "member.setup.nutrition"
    if "Lifestyle/" in f:
        return "member.setup.lifestyle"
    if "ExamArchive/" in f:
        return "member.setup.medical.exam_archive"
    if "Allergy" in f:
        return "member.setup.medical.allergy"
    if "Chronic" in f:
        return "member.setup.medical.chronic"
    if "FamilyHistory" in f:
        return "member.setup.medical.family"
    if "Medical/" in f:
        return "member.setup.medical"
    if any(x in f for x in ("MemberModule", "MemberSetup", "MemberBirth", "MemberName", "MemberRelationship")):
        if any(x in f for x in ("ModuleSetup", "ModuleToggle", "ModuleSummary", "ModuleSection")):
            return "member.module"
        return "member.setup.flow"
    if "Components/" in f:
        return "member.setup.common"
    return "member.setup"


def assign_key(zh: str, files: list[str]) -> str:
    if zh in KEY_MAP:
        return KEY_MAP[zh]
    nz = normalize_swift_interp(zh)
    if nz in KEY_MAP:
        return KEY_MAP[nz]
    prefix = infer_prefix(files)
    if "过敏" in zh or "Allergy" in str(files):
        sub = "allergy"
    elif "慢病" in zh or "Chronic" in str(files) or "疾病" in zh:
        sub = "chronic"
    elif "家族" in zh or "Family" in str(files):
        sub = "family"
    elif "症状" in zh or "Symptom" in str(files):
        sub = "symptom"
    elif "用药" in zh or "Medication" in str(files):
        sub = "medication"
    elif "手术" in zh or "Surgery" in str(files):
        sub = "surgery"
    elif any(x in zh for x in ("吸烟", "饮酒", "运动", "睡眠")):
        sub = "lifestyle"
    elif any(x in zh for x in ("说明", "概览", "介绍")):
        sub = "guide"
    elif any(x in zh for x in ("营养", "饮食", "千卡", "碳水")) or "Nutrition" in str(files):
        sub = "nutrition"
    else:
        sub = "general"
    short = hashlib.md5(zh.encode()).hexdigest()[:6]
    if prefix == "member.module":
        return f"member.module.{sub}.{short}"
    if prefix == "member.setup.medical":
        return f"member.setup.medical.{sub}.{short}"
    return f"{prefix}.{sub}.{short}"


def translate(zh: str) -> str | None:
    if zh in EN:
        return EN[zh]
    nz = normalize_swift_interp(zh)
    if nz in EN:
        return EN[nz]
    rules: list[tuple[str, str]] = [
        (r"^%@年%@月$", "%@ %@"),
        (r"^%@年$", "%@"),
        (r"^%@千卡$", "%@ kcal"),
        (r"^%@ 千卡$", "%@ kcal"),
        (r"^%.1f小时$", "%.1f hours"),
        (r"^%.1f 小时$", "%.1f hours"),
        (r"^%@运动$", "%@ exercise"),
        (r"^目标 %@ 千卡 · 建议 %@ 千卡$", "Target %@ kcal · Suggested %@ kcal"),
        (r"^目标 %@ 千卡$", "Target %@ kcal"),
        (r"^碳水 %@%% · 蛋白质 %@%% · 脂肪 %@%%$", "Carbs %@%% · Protein %@%% · Fat %@%%"),
        (r"^%@ · %@ · 每周 %@ kg$", "%@ · %@ · %@ kg per week"),
        (r"^%@ · %@千卡$", "%@ · %@ kcal"),
        (r"^年龄：%@ 岁$", "Age: %@ years"),
        (r"^已完成 %d / %d$", "Completed %d / %d"),
        (r"^已填写 %@ 项关键指标$", "%@ key indicators filled"),
        (r"^%@份报告$", "%@ reports"),
        (r"^%@年确诊$", "Diagnosed in %@"),
        (r"^必做 %@ 项$", "%@ required items"),
        (r"^建议增加 %@ 项$", "%@ recommended items"),
        (r"^已生成 %@ 项随访$", "%@ follow-up tasks created"),
        (r"^每日 %@ 小时$", "%@ hours per day"),
        (r"^睡眠：%@小时$", "Sleep: %@ hours"),
        (r"^参考：%@$", "Reference: %@"),
        (r"^约%@/日$", "About %@/day"),
        (r"^历史吸烟 %@$", "Smoked for %@"),
        (r"^已成功戒烟 %@$", "Quit smoking %@ ago"),
        (r"^历史吸烟%@$", "Smoked for %@"),
        (r"^已戒烟%@$", "Quit smoking %@ ago"),
        (r"^吸烟%@$", "Smoking %@"),
        (r"^偶尔吸烟$", "Occasional smoking"),
        (r"^经常吸烟$", "Frequent smoking"),
        (r"^从不吸烟$", "Never smoked"),
        (r"^已戒酒$", "Quit drinking"),
        (r"^偶尔饮酒$", "Occasional drinking"),
        (r"^经常饮酒$", "Frequent drinking"),
        (r"^缺乏运动$", "Insufficient exercise"),
        (r"^轻度运动$", "Light exercise"),
        (r"^规律运动$", "Regular exercise"),
        (r"^积极运动$", "Active exercise"),
        (r"^当前不运动$", "Currently no exercise"),
        (r"^每周%@$", "%@ per week"),
        (r"^每次%@$", "%@ per session"),
        (r"^职业：%@$", "Occupation: %@"),
        (r"^久坐：%@$", "Sedentary: %@"),
        (r"^手术史：%@$", "Surgery history: %@"),
        (r"^过敏史：%@$", "Allergy history: %@"),
        (r"^症状持续：%@$", "Symptom duration: %@"),
        (r"^症状严重度：%@$", "Symptom severity: %@"),
        (r"^持续%@$", "Duration: %@"),
        (r"^为%@完善医疗健康档案$", "Complete medical profile for %@"),
        (r"^为%@完善饮食目标与身体指标$", "Complete nutrition goals and body metrics for %@"),
        (r"^ \(确诊年龄：%@\)$", " (diagnosed at age %@)"),
    ]
    for pat, repl in rules:
        if re.match(pat, nz):
            return repl
    return None


def main() -> None:
    data = json.loads(EXTRACTED.read_text(encoding="utf-8"))
    hardcoded = data["hardcoded"]
    l10n_data = data["l10n"]

    zh_keys: dict[str, str] = {}
    en_keys: dict[str, str] = {}
    for path in (
        ROOT / "SparkClient/Projects/App/Resources/zh-Hans.lproj/Localizable.strings",
        ROOT / "SparkClient/Projects/App/Resources/en.lproj/Localizable.strings",
    ):
        target = zh_keys if "zh-Hans" in str(path) else en_keys
        for line in path.read_text(encoding="utf-8").splitlines():
            m = re.match(r'\s*"([^"]+)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;', line)
            if m:
                target[m.group(1)] = m.group(2).replace("\\n", "\n")

    entries: list[dict] = []
    used_keys: dict[str, str] = {}
    untranslated: list[str] = []

    for zh, files in sorted(hardcoded.items()):
        if is_artifact(zh):
            continue
        nz = normalize_swift_interp(zh)
        key = assign_key(zh, files)
        if key in used_keys and used_keys[key] != nz:
            key = f"{key}.{hashlib.md5(zh.encode()).hexdigest()[:4]}"
        used_keys[key] = nz
        en = translate(zh) or translate(nz)
        if en is None:
            untranslated.append(zh)
            en = f"[NEEDS TRANSLATION] {nz}"
        note_parts: list[str] = []
        if len(files) > 1:
            note_parts.append(f"shared across {len(files)} files")
        if SWIFT_INTERP.search(zh):
            note_parts.append("contains format placeholders")
        entry = {
            "key": key,
            "zh": nz if SWIFT_INTERP.search(zh) else zh,
            "en": en,
            "files": sorted(set(files)),
        }
        if note_parts:
            entry["notes"] = "; ".join(note_parts)
        entries.append(entry)

    existing = {e["key"] for e in entries}
    for key, info in l10n_data.items():
        if key.startswith("medical.exam_archive."):
            continue
        in_zh = key in zh_keys
        in_en = key in en_keys
        if in_zh and in_en:
            continue
        if key in existing:
            continue
        zh = info["zh"] or zh_keys.get(key) or ""
        en = en_keys.get(key) or L10N_EN.get(key, "")
        if key == "home.members.add.failed" and not zh:
            zh = "成员创建失败"
            en = "Failed to add member"
        if key in L10N_EN:
            en = L10N_EN[key]
        entries.append(
            {
                "key": key,
                "zh": zh,
                "en": en,
                "files": info["files"],
                "notes": "L10n key missing from Localizable.strings",
            }
        )

    entries.sort(key=lambda e: e["key"])
    OUT.write_text(json.dumps({"entries": entries}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Written {len(entries)} entries")
    print(f"Untranslated: {len(untranslated)}")


if __name__ == "__main__":
    main()
