"""Build app/assets/intel/catalog.json from churn_plan/*.md.

The md encyclopedias are the source of truth; re-run this after editing them:
    python scripts/gen_intel_catalog.py
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'app/assets/intel/catalog.json'


def cells(line):
    return [c.strip() for c in line.strip().strip('|').split('|')]


def clean(s):
    return re.sub(r'[*`]', '', s).strip()


def indicators():
    rows, matrix, group = [], '', ''
    for line in (ROOT / 'churn_plan/indicators_encyclopedia_4272.md').read_text(encoding='utf-8').splitlines():
        if line.startswith('## '):
            matrix = clean(line[3:])
        elif line.startswith('### '):
            group = clean(line[4:])
        elif line.startswith('| **IND_'):
            c = cells(line) + [''] * 6
            rows.append({'id': clean(c[0]), 'n': clean(c[1]), 'm': matrix, 'g': group,
                         'what': c[2], 'tells': c[3], 'ret': c[4], 'pay': c[5]})
    return rows


def rules(names):
    rows, book = [], ''
    for line in (ROOT / 'churn_plan/action_reaction_encyclopedia_3370.md').read_text(encoding='utf-8').splitlines():
        if line.startswith('## '):
            book = clean(line[3:])
        elif line.startswith('| **AR_'):
            c = cells(line) + [''] * 6
            scen = clean(c[1])
            target, _, persona = scen.partition(' × ')
            refs = sorted({r for r in re.findall(r'`([a-z0-9_]+)', ' '.join(c[2:])) if r in names})
            sym = next((m.group(1) for r in refs for m in [re.match(r'sym_(.+?)_(chart|trades|consecutive|net|unrealized|margin|revenge|avg|held|whatif|autopsy|premature|bag|user|community)', r)] if m), None)
            num = int(re.search(r'Rulebook (\d+)', book).group(1)) if 'Rulebook' in book else 0
            rows.append({'id': clean(c[0]), 'b': num, 'bt': book, 'target': target.strip(),
                         'persona': persona.strip() or None, 'sym': sym, 'refs': refs,
                         'action': c[2], 'reaction': c[3], 'pursuit': c[4], 'goal': c[5]})
    return rows


def main():
    inds = indicators()
    rs = rules({i['n'] for i in inds})
    assert len({i['id'] for i in inds}) == len(inds), 'duplicate indicator ids'
    assert len({r['id'] for r in rs}) == len(rs), 'duplicate rule ids'
    assert len(inds) > 4000 and len(rs) > 3000, f'parse missed rows: {len(inds)} / {len(rs)}'
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({'indicators': inds, 'rules': rs}, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
    print(f'{len(inds)} indicators, {len(rs)} rules -> {OUT} ({OUT.stat().st_size // 1024} KB)')


if __name__ == '__main__':
    main()
