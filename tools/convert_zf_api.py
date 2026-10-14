"""正方教务系统课表接口 JSON  ->  App 课表 JSON

输入：kbList（课表网格数据，含 xqj/jcs/zcd/cdmc/xm 等）+ xsxx（学生信息）
输出：Timetable JSON（App 直接消费）

分组规则：kcmc(课程名) + jxbmc(教学班) + xslxbj(修读性质符号) 相同 -> 合并为一门课，
         每个分组里的每条记录变成一个 CourseSlot。
"""

import json
import re
import sys
from pathlib import Path

WEEKDAY_NAMES = ['', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日']

# 柳州工学院-南校区作息（来自 WakeUp 截图）
SECTION_TIMES = [
    (1, '08:30', '09:15'), (2, '09:20', '10:05'),
    (3, '10:25', '11:10'), (4, '11:15', '12:00'),
    (5, '14:00', '14:45'), (6, '14:50', '15:35'),
    (7, '15:55', '16:40'), (8, '16:45', '17:30'),
    (9, '19:30', '20:15'), (10, '20:20', '21:05'),
]

KIND_BY_SYMBOL = {
    '●': '实践', '★': '实验上机', '■': '实验', '▲': '上机', '○': '理论',
}


def parse_weeks(expr: str) -> list[int]:
    """'3-4周,7-9周' / '2-6周(双),7-15周' / '第7周' -> [3,4,7,8,9]"""
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
        if not m:
            nums = [int(x) for x in re.findall(r'\d+', cleaned)]
            if not nums:
                continue
            a, b = nums[0], (nums[1] if len(nums) > 1 else nums[0])
        else:
            a = int(m.group(1))
            b = int(m.group(2)) if m.group(2) else a
        for w in range(a, b + 1):
            if is_odd and w % 2 == 0:
                continue
            if is_even and w % 2 == 1:
                continue
            weeks.add(w)
    return sorted(weeks)


def parse_sections(jcs: str) -> tuple[int, int]:
    m = re.fullmatch(r'(\d+)(?:-(\d+))?', (jcs or '').strip())
    if not m:
        return 1, 1
    a = int(m.group(1))
    b = int(m.group(2)) if m.group(2) else a
    return a, b


def convert_unscheduled(api: dict) -> list[dict]:
    """把 sjkList（实践课程 / 其它课程）转成无固定时段的课程条目。

    这些课只有周次范围（qsjsz），没有星期和节次，塞不进周视图网格，
    但必须展示 —— 否则用户会以为毕业实习、认识实习这些课"不存在"。
    """
    out = []
    for r in api.get('sjkList', []):
        name = (r.get('kcmc') or '').strip()
        if not name:
            continue
        # kindMark 优先从课程名字尾的符号取（如 "毕业实习●"），否则从 sjkcgs 里找
        kind = ''
        for sym, kind_name in KIND_BY_SYMBOL.items():
            if name.endswith(sym):
                kind = kind_name
                name = name[:-len(sym)].strip()
                break
        if not kind:
            for sym, kind_name in KIND_BY_SYMBOL.items():
                if sym in (r.get('sjkcgs') or ''):
                    kind = kind_name
                    break
        out.append({
            'name': name,
            'weeks': (r.get('qsjsz') or '').strip(),
            'teacher': (r.get('jsxm') or '').strip(),
            'credits': str(r.get('xf') or '').strip(),
            'kindMark': kind,
            'retake': (r.get('cxbj') == '1') or bool(r.get('cxbjmc')),
        })
    return out


def convert(api: dict, *, start_date: str = '2026-08-24', total_weeks: int = 20,
            name: str = '大四上') -> dict:
    xsxx = api.get('xsxx', {})
    kb = api.get('kbList', [])

    groups: dict[tuple, dict] = {}
    for r in kb:
        key = (r.get('kcmc', ''), r.get('jxbmc', ''), r.get('xslxbj', ''))
        g = groups.setdefault(key, {
            'name': r.get('kcmc', ''),
            'classNo': r.get('jxbmc', ''),
            'composition': r.get('jxbzc', ''),
            'assess': r.get('khfsmc', ''),
            'credits': float(r.get('xf') or 0),
            'hours': r.get('kcxszc', ''),
            'kind': KIND_BY_SYMBOL.get(r.get('xslxbj', ''), ''),
            'retake': r.get('cxbjmc', '') or '',
            'slots': [],
        })
        s, e = parse_sections(r.get('jcs', ''))
        g['slots'].append({
            'weekday': int(r.get('xqj') or 1),
            'startSection': s,
            'endSection': e,
            'weeks': parse_weeks(r.get('zcd', '')),
            'room': r.get('cdmc', ''),
            'campus': r.get('xqmc', ''),
            'teacher': r.get('xm', ''),
        })

    courses = []
    for i, g in enumerate(groups.values()):
        g['id'] = f"{g['name']}|{g['classNo']}|{g['kind']}"
        courses.append(g)

    # 合并同一课程同名不同符号（理论/上机/实验）的显示效果：保留分开，但排序稳定
    courses.sort(key=lambda c: (c['name'], c['classNo']))

    return {
        'id': 'jwglxt-2026-2027-1',
        'name': name,
        'semesterName': f"{xsxx.get('XNMC', '')}-{xsxx.get('XQMMC', '')}",
        'xnm': xsxx.get('XNM', ''),
        'xqm': xsxx.get('XQM', ''),
        'student': {
            'xh': xsxx.get('XH', ''),
            'xm': xsxx.get('XM', ''),
            'className': xsxx.get('BJMC', ''),
            'major': xsxx.get('ZYMC', ''),
            'grade': xsxx.get('NJDM_ID', ''),
        },
        'startDate': start_date,
        'totalWeeks': total_weeks,
        'sectionsPerDay': 10,
        'weekdayStart': 1,
        'sectionTimes': [
            {'section': n, 'start': st, 'end': en} for n, st, en in SECTION_TIMES
        ],
        'courses': courses,
        'unscheduled': convert_unscheduled(api),
        'holidays': {},
    }


def main():
    tools = Path(__file__).parent
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else tools / 'sample_kb_api.json'
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else tools / 'timetable_2026_2027_1.json'

    api = json.loads(src.read_text(encoding='utf-8'))
    tt = convert(api)
    out.write_text(json.dumps(tt, ensure_ascii=False, indent=1), encoding='utf-8')

    xs = tt['student']
    print(f"student: {xs['xm']} {xs['xh']} {xs['className']} {xs['major']} ({xs['grade']}级)")
    print(f"semester: {tt['semesterName']}  xnm={tt['xnm']} xqm={tt['xqm']}")
    print(f"courses: {len(tt['courses'])}  slots: {sum(len(c['slots']) for c in tt['courses'])}")
    print('-' * 100)
    for c in tt['courses']:
        for s in c['slots']:
            wk = s['weeks']
            wk_s = f"{wk[0]}-{wk[-1]}({len(wk)}周)" if wk else '?'
            print(f"  周{s['weekday']} {s['startSection']:>2}-{s['endSection']:<2}节 {wk_s:<12} "
                  f"{c['name'][:20]:<22} {s['room'][:16]:<18} {s['teacher'][:10]:<12} {c['kind']} {c['retake']}")
    print(f"\n-> {out}")


if __name__ == '__main__':
    main()
