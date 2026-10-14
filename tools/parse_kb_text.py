"""正方课表页文本解析器（针对柳州工学院实采样本验证）

输入：从正方「个人课表查询」页面复制的文本
输出：结构化 JSON（课程列表）+ 直接可用的 Timetable JSON

课程块结构（实采）：
    【调】课程名○
     (1-2节)3-4周,7-9周
     南校区 1教408
     陈稳中
     (2026-2027-1)-DJ0100701-12
     工设251;工设252
     考试
     理论:24,上机:8
     4
     24
     2
"""

import json
import re
import sys
from pathlib import Path


def parse_weeks(expr: str) -> list[int]:
    """'1-5周,7-11周(单),12-13周' / '第16周' / '2-6周(双),7-15周' -> [1,2,...]"""
    weeks: set[int] = set()
    if not expr:
        return []
    s = (expr.replace('（', '(').replace('）', ')')
         .replace('—', '-').replace('～', '-').replace('~', '-').replace(' ', ''))
    for part in re.split(r'[,，;；]', s):
        if not part:
            continue
        is_odd = '单' in part
        is_even = '双' in part
        cleaned = re.sub(r'\([^)]*\)', '', part).replace('周', '').replace('第', '')
        if not cleaned:
            continue
        m = re.fullmatch(r'(\d+)(?:-(\d+))?', cleaned)
        if m:
            a = int(m.group(1))
            b = int(m.group(2)) if m.group(2) else a
        else:
            nums = [int(x) for x in re.findall(r'\d+', cleaned)]
            if not nums:
                continue
            a = nums[0]
            b = nums[1] if len(nums) > 1 else nums[0]
        for w in range(a, b + 1):
            if is_odd and w % 2 == 0:
                continue
            if is_even and w % 2 == 1:
                continue
            weeks.add(w)
    return sorted(weeks)


KIND_MARKS = {'●': '实践', '★': '实验上机', '○': '理论', '▲': '上机', '■': '实验'}


def parse_schedule_block(raw: str) -> dict | None:
    """解析一段课程文本（多行），返回课程字典"""
    text = raw.strip()
    if not text:
        return None

    is_adjusted = text.startswith('【调】')
    text = text.replace('【调】', '')

    lines = [ln.strip() for ln in text.split('\n') if ln.strip()]
    if not lines:
        return None

    # 1) 节次 + 周次 行
    sec_line_idx = None
    sec_start = sec_end = None
    weeks: list[int] = []
    for i, ln in enumerate(lines):
        m = re.search(r'\((\d+)(?:-(\d+))?\s*节\)\s*(.*)', ln)
        if m:
            sec_line_idx = i
            sec_start = int(m.group(1))
            sec_end = int(m.group(2)) if m.group(2) else sec_start
            weeks = parse_weeks(m.group(3))
            break
    if sec_line_idx is None:
        return None

    # 2) 课程名 = 节次行之前的全部内容（去掉末尾类型符号）
    name_lines = lines[:sec_line_idx]
    if not name_lines:
        return None
    name = ' '.join(name_lines).strip()
    kind = ''
    for mark, kind_name in KIND_MARKS.items():
        if name.endswith(mark):
            kind = kind_name
            name = name[:-len(mark)].strip()
            break

    # 3) 节次行之后：校区/教室、教师、教学班、组成、考核、学时、周学时、总学时、学分
    tail = lines[sec_line_idx + 1:]

    campus = room = teacher = class_no = composition = assess = hours = ''
    credits = None

    for ln in tail:
        if re.match(r'^\(20\d{2}-20\d{2}-\d\)', ln):          # 教学班
            class_no = ln
        elif re.search(r'[;；]', ln) and not hours:              # 教学班组成
            composition = ln
        elif ln in ('考试', '考查', '未安排'):                    # 考核方式
            assess = ln
        elif re.match(r'^[\u4e00-\u9fa5]+[:：]', ln):            # 理论:24,上机:8
            hours = ln
        elif re.match(r'^(南校区|北校区|东校区|西校区)', ln):     # 校区 + 教室
            parts = ln.split(None, 1)
            campus = parts[0] if parts else ''
            room = parts[1].strip() if len(parts) > 1 else ''
        elif re.fullmatch(r'\d+(\.\d+)?', ln):                   # 纯数字：周学时/总学时/学分
            continue
        elif not teacher and re.fullmatch(r'[\u4e00-\u9fa5,，]+', ln):
            teacher = ln

    # 4) 学分 = 末尾的纯数字里最后一个（形如 ... 4 / 24 / 2 -> 学分 2）
    nums = [ln for ln in tail if re.fullmatch(r'\d+(\.\d+)?', ln)]
    if nums:
        credits = float(nums[-1])

    return {
        'name': name,
        'kind': kind,
        'adjusted': is_adjusted,
        'startSection': sec_start,
        'endSection': sec_end,
        'weeks': weeks,
        'campus': campus,
        'room': room,
        'teacher': teacher,
        'classNo': class_no,
        'composition': composition,
        'assess': assess,
        'hours': hours,
        'credits': credits,
    }


def parse_timetable_text(text: str) -> list[dict]:
    """把整页文本切成课程块并解析"""
    # 去掉表头与页脚
    body = text
    for marker in ['时间段', '上午', '下午', '晚上']:
        pass  # 保留，块内靠节次行定位

    # 课程块的起点：形如 【调】课程名 或 课程名（且下一行含 "(n-m节)"）
    blocks: list[str] = []
    current: list[str] = []
    lines = text.split('\n')

    def is_block_start(idx: int) -> bool:
        ln = lines[idx].strip()
        if not ln:
            return False
        if ln.startswith('【调】'):
            return True
        # 无【调】的块：本行是中文课程名且有类型符号，且下一行是节次行
        if re.search(r'[○▲■★●]$', ln) and idx + 1 < len(lines) and re.search(r'\(\d+.*节\)', lines[idx + 1]):
            return True
        # 也可能是 "课程名" 单独一行 + 下一行节次
        if re.search(r'\(\d+.*节\)', lines[idx]) and idx > 0 and re.search(r'[○▲■★●]$', lines[idx - 1].strip()):
            return False
        return False

    i = 0
    while i < len(lines):
        if is_block_start(i):
            if current:
                blocks.append('\n'.join(current))
            current = [lines[i]]
        elif current:
            # 属于当前块：直到遇到下一个块起点或空行分隔后的新课程
            current.append(lines[i])
        i += 1
    if current:
        blocks.append('\n'.join(current))

    courses = []
    for b in blocks:
        c = parse_schedule_block(b)
        if c:
            courses.append(c)
    return courses


def main():
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else \
        Path(__file__).parent / 'sample_kb_2026_2027_1.txt'
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else \
        Path(__file__).parent / 'parsed_courses.json'

    text = src.read_text(encoding='utf-8')
    courses = parse_timetable_text(text)

    out.write_text(json.dumps(courses, ensure_ascii=False, indent=1), encoding='utf-8')
    print(f'parsed {len(courses)} course blocks -> {out}')
    for c in courses:
        wk = f"{len(c['weeks'])}周" if c['weeks'] else '?'
        print(f"  [{'调' if c['adjusted'] else ' '}] {c['name'][:28]:<30} "
              f"{c['startSection']}-{c['endSection']}节 {wk} {c['room']} {c['teacher']}")


if __name__ == '__main__':
    main()
