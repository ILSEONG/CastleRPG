#!/usr/bin/env python3
"""게임 문구 → data/texts.csv(다국어 표) 옮기기 도구. 사용법은 docs/TEXTS.md.

GDScript 파일 안의 한글 문자열 리터럴 "골드가 부족합니다"를 Lang.t("파일.위치") 호출로 바꾸고,
그 문장을 data/texts.csv에 ko 값으로 덧붙인다(키가 이미 있으면 그대로 둔다). 이미 Lang.t("…")인 곳은 건드리지 않는다.

  python3 dev/texts_extract.py scripts/foo_panel.gd ...   # 지정한 파일만
  python3 dev/texts_extract.py --all                       # scripts/·scenes/ 전부
  python3 dev/texts_extract.py --check                     # 옮기지 않은 한글 문자열이 남았는지만 본다(있으면 종료 코드 1)

건드리지 않는 것: 주석, print·push_error·push_warning·assert 같은 개발용 출력, &"…"·^"…", match 패턴, SKIP_FILES.
const 문장 안의 문자열을 바꾸면 그 const는 static var(함수 안이면 var)가 된다 — 함수 호출은 상수식이 아니라서.
"""
import csv
import io
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
CSV_PATH = os.path.join(ROOT, 'data', 'texts.csv')
COLUMNS = ['key', 'ko', 'en', 'ja', 'zh', 'note']
LANG_PATH = 'res://scripts/lang.gd'
LANG_LINE = 'const Lang := preload("%s")' % LANG_PATH
SCAN_DIRS = ['scripts', 'scenes']
# 운영자 전용 화면(관리자 이메일만 연다) — 플레이어가 보지 않는다
SKIP_FILES = {'scripts/admin_panel.gd', 'scripts/lang.gd'}
SKIP_CALLS = {'print', 'prints', 'printt', 'printraw', 'print_debug', 'print_rich', 'printerr',
              'push_error', 'push_warning', 'assert', '_err'}
HANGUL = re.compile('[\uac00-\ud7a3\u3131-\u318e]')
IDENT = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
KEY_PART = re.compile(r'[^a-z0-9_]+')


# --- texts.csv (값의 줄바꿈은 \n, 역슬래시는 \\ 로 적는다 — 한 줄에 한 문구) ---

def escape_value(s):
    return s.replace('\\', '\\\\').replace('\n', '\\n').replace('\t', '\\t').replace('\r', '\\r')


def unescape_value(s):
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == '\\' and i + 1 < len(s):
            n = s[i + 1]
            out.append({'n': '\n', 't': '\t', 'r': '\r', '\\': '\\'}.get(n, '\\' + n))
            i += 2
        else:
            out.append(c)
            i += 1
    return ''.join(out)


def read_csv():
    rows = []
    if not os.path.exists(CSV_PATH):
        return rows
    with open(CSV_PATH, encoding='utf-8', newline='') as f:
        for r in csv.DictReader(f):
            rows.append({c: r.get(c) or '' for c in COLUMNS})
    return rows


def write_csv(rows):
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=COLUMNS, lineterminator='\n')
    w.writeheader()
    for r in rows:
        w.writerow(r)
    with open(CSV_PATH, 'w', encoding='utf-8', newline='') as f:
        f.write(buf.getvalue())


# --- GDScript 토큰 ---

def decode_gd(body, raw):
    if raw:
        return body
    out = []
    i = 0
    simple = {'n': '\n', 't': '\t', 'r': '\r', 'a': '\a', 'b': '\b', 'f': '\f', 'v': '\v',
              '"': '"', "'": "'", '\\': '\\'}
    while i < len(body):
        c = body[i]
        if c == '\\' and i + 1 < len(body):
            n = body[i + 1]
            if n in simple:
                out.append(simple[n])
                i += 2
                continue
            if n == 'u' and re.match(r'[0-9a-fA-F]{4}', body[i + 2:i + 6]):
                out.append(chr(int(body[i + 2:i + 6], 16)))
                i += 6
                continue
            if n == 'U' and re.match(r'[0-9a-fA-F]{6}', body[i + 2:i + 8]):
                out.append(chr(int(body[i + 2:i + 8], 16)))
                i += 8
                continue
            if n == '\n':  # 줄 이음
                i += 2
                continue
            raise ValueError('unknown escape \\%s' % n)
        out.append(c)
        i += 1
    return ''.join(out)


def tokenize(src):
    """(kind, start, end, extra) 목록. kind: str ident op nl. 주석은 버린다."""
    toks = []
    i = 0
    n = len(src)
    while i < n:
        c = src[i]
        if c == '#':
            j = src.find('\n', i)
            i = n if j < 0 else j
            continue
        if c == '\\' and i + 1 < n and src[i + 1] == '\n':
            i += 2  # 줄 이음
            continue
        if c == '\n':
            toks.append(('nl', i, i + 1, None))
            i += 1
            continue
        if c in ' \t\r':
            i += 1
            continue
        prefix = ''
        q = i
        if c in 'r&^' and i + 1 < n and src[i + 1] in '"\'' and (i == 0 or not (src[i - 1].isalnum() or src[i - 1] == '_')):
            prefix = c
            q = i + 1
        if src[q] in '"\'':
            quote = src[q]
            triple = src[q:q + 3] == quote * 3
            qlen = 3 if triple else 1
            j = q + qlen
            raw = prefix == 'r'
            while j < n:
                if not raw and src[j] == '\\':
                    j += 2
                    continue
                if src.startswith(quote * qlen, j):
                    break
                if not triple and src[j] == '\n':
                    raise ValueError('unterminated string at %d' % i)
                j += 1
            end = j + qlen
            toks.append(('str', i, end, {'prefix': prefix, 'body': src[q + qlen:j], 'raw': raw}))
            i = end
            continue
        m = IDENT.match(src, i)
        if m:
            toks.append(('ident', i, m.end(), m.group(0)))
            i = m.end()
            continue
        m = re.match(r'\d[\d_]*(\.\d*)?([eE][+-]?\d+)?|0x[0-9a-fA-F_]+|0b[01_]+', src[i:])
        if m and c.isdigit():
            toks.append(('num', i, i + m.end(), None))
            i += m.end()
            continue
        toks.append(('op', i, i + 1, c))
        i += 1
    return toks


def key_part(s):
    s = KEY_PART.sub('_', s.lower()).strip('_')
    return s


class FileJob:
    def __init__(self, rel, src):
        self.rel = rel
        self.src = src
        stem = rel[:-3]
        for d in SCAN_DIRS:
            if stem.startswith(d + '/'):
                stem = stem[len(d) + 1:]
        self.stem = '.'.join(key_part(p) for p in stem.split('/'))
        self.edits = []  # (start, end, text)
        self.found = []  # (key_hint, value, start, end)
        self.const_spans = {}  # 줄 시작 위치 → (start, end, replacement)
        self.skipped = []

    def analyze(self):
        toks = tokenize(self.src)
        src = self.src
        line_start_of = lambda pos: src.rfind('\n', 0, pos) + 1
        blocks = []  # (indent, kind, name)
        stack = []  # 괄호 프레임 {'ch','call','id','dict'}
        stmt = None
        prev_sig = None
        at_line_start = True
        for idx, (kind, s, e, x) in enumerate(toks):
            if kind == 'nl':
                if not stack:
                    at_line_start = True
                continue
            if at_line_start and not stack:
                ls = line_start_of(s)
                indent = len(src[ls:s].expandtabs(4))
                while blocks and blocks[-1][0] >= indent:
                    blocks.pop()
                words = []
                k = idx
                while k < len(toks) and toks[k][0] == 'ident' and len(words) < 3:
                    words.append(toks[k][3])
                    k += 1
                first = words[0] if words else ''
                name = None
                decl = None
                if first in ('const', 'var') and len(words) > 1:
                    decl, name = first, words[1]
                elif first == 'static' and len(words) > 2 and words[1] in ('var', 'func'):
                    decl, name = words[1], words[2]
                elif first == '@export' or (kind == 'op' and x == '@'):
                    # @export var NAME / @onready var NAME
                    j = idx
                    while j < len(toks) and toks[j][0] != 'nl':
                        if toks[j][0] == 'ident' and toks[j][3] == 'var' and j + 1 < len(toks) and toks[j + 1][0] == 'ident':
                            decl, name = 'var', toks[j + 1][3]
                            break
                        j += 1
                in_func = next((b for b in reversed(blocks) if b[1] == 'func'), None)
                in_match = bool(blocks) and blocks[-1][1] == 'match'
                stmt = {'indent': indent, 'decl': decl, 'name': name, 'func': in_func[2] if in_func else None,
                        'const_tok': (s, toks[idx][2]) if first == 'const' else None, 'pattern': in_match and kind == 'str',
                        'start': ls}
                # 블록 여는 줄
                fn = None
                if first == 'func' and len(words) > 1:
                    fn = ('func', words[1])
                elif first == 'static' and len(words) > 2 and words[1] == 'func':
                    fn = ('func', words[2])
                elif first == 'class' and len(words) > 1:
                    fn = ('class', words[1])
                elif first == 'match':
                    fn = ('match', None)
                if fn:
                    blocks.append((indent, fn[0], fn[1]))
                elif in_match and not stmt['pattern']:
                    pass
                at_line_start = False
                if blocks and blocks[-1][1] == 'match' and blocks[-1][0] < indent and fn is None:
                    # match 바로 아래 줄 = 패턴 줄(그 아래 본문은 더 깊다)
                    blocks.append((indent, 'pattern', None))
                    stmt['pattern'] = True
            if kind == 'op' and x in '([{':
                call = prev_sig[3] if (x == '(' and prev_sig and prev_sig[0] == 'ident') else None
                stack.append({'ch': x, 'call': call, 'id': None, 'last_key': None})
            elif kind == 'op' and x in ')]}':
                if stack:
                    stack.pop()
            elif kind == 'str':
                body = x['body']
                # 딕셔너리 키("id": "lumber"의 "id")·값 추적
                nxt = toks[idx + 1] if idx + 1 < len(toks) else None
                is_key = stack and stack[-1]['ch'] == '{' and nxt and nxt[0] == 'op' and nxt[3] == ':'
                if is_key:
                    stack[-1]['last_key'] = body if not HANGUL.search(body) else None
                elif stack and stack[-1]['ch'] == '{' and prev_sig and prev_sig[0] == 'op' and prev_sig[3] == ':' and stack[-1].get('last_key') == 'id':
                    stack[-1]['id'] = body
                if HANGUL.search(body) and x['prefix'] not in ('&', '^'):
                    calls = [f['call'] for f in stack if f['call']]
                    if any(cn in SKIP_CALLS for cn in calls):
                        pass
                    elif stmt and stmt.get('pattern'):
                        self.skipped.append((s, 'match pattern'))
                    else:
                        dict_key = None
                        dict_id = None
                        if stack and stack[-1]['ch'] == '{':
                            if not is_key and prev_sig and prev_sig[0] == 'op' and prev_sig[3] in ':=':
                                if prev_sig[3] == ':':
                                    dict_key = stack[-1].get('last_key')
                                else:  # lua 꼴 {name = "…"}
                                    p2 = toks[idx - 2] if idx >= 2 else None
                                    dict_key = p2[3] if p2 and p2[0] == 'ident' else None
                            dict_id = next((f['id'] for f in reversed(stack) if f['ch'] == '{' and f['id']), None)
                        try:
                            value = decode_gd(body, x['raw'])
                        except ValueError as ex:
                            self.skipped.append((s, str(ex)))
                            prev_sig = toks[idx]
                            continue
                        parts = []
                        if stmt and stmt['func']:
                            parts.append(key_part(stmt['func']))
                            if stmt['decl'] == 'var' and stmt['name'] and not stack:
                                parts.append(key_part(stmt['name']))
                        elif stmt and stmt['name']:
                            parts.append(key_part(stmt['name']))
                        if dict_id and not HANGUL.search(dict_id):
                            parts.append(key_part(dict_id))
                        if dict_key:
                            parts.append(key_part(dict_key))
                        parts = [p for p in parts if p]
                        self.found.append((parts, value, s, e))
                        if stmt and stmt['const_tok']:
                            cs, ce = stmt['const_tok']
                            self.const_spans[cs] = (cs, ce, 'var' if stmt['func'] else 'static var')
            if kind != 'nl':
                prev_sig = toks[idx]
        return self


def lang_ancestors(rel, src_by_rel):
    """extends "res://…" 사슬의 조상 상대 경로들."""
    out = []
    cur = src_by_rel.get(rel)
    seen = set()
    while cur:
        m = re.search(r'^extends\s+"res://([^"]+)"', cur, re.M)
        if not m:
            break
        p = m.group(1)
        if p in seen:
            break
        seen.add(p)
        out.append(p)
        cur = src_by_rel.get(p)
        if cur is None and os.path.exists(os.path.join(ROOT, p)):
            with open(os.path.join(ROOT, p), encoding='utf-8') as f:
                cur = f.read()
            src_by_rel[p] = cur
    return out


def has_lang(src):
    return re.search(r'^const Lang\s*:?=', src, re.M) is not None


def insert_lang(src):
    lines = src.split('\n')
    at = 0
    for i, ln in enumerate(lines[:30]):
        if ln.startswith('extends') or ln.startswith('class_name') or ln.startswith('@tool'):
            at = i + 1
    # extends 다음의 ## 문서 주석 덩어리 뒤에 둔다
    while at < len(lines) and lines[at].startswith('##'):
        at += 1
    lines.insert(at, LANG_LINE)
    if at > 0 and lines[at - 1].startswith('##'):
        lines.insert(at, '')  # 문서 주석(##)이 Lang 설명으로 붙지 않게
    return '\n'.join(lines)


def list_files(args):
    if args:
        return [os.path.relpath(os.path.abspath(a), ROOT).replace(os.sep, '/') for a in args]
    out = []
    for d in SCAN_DIRS:
        for base, _, files in os.walk(os.path.join(ROOT, d)):
            for f in files:
                if f.endswith('.gd'):
                    out.append(os.path.relpath(os.path.join(base, f), ROOT).replace(os.sep, '/'))
    return sorted(out)


def main(argv):
    check = '--check' in argv
    files = [a for a in argv if not a.startswith('--')]
    if not files and '--all' not in argv and not check:
        print(__doc__)
        return 2
    rels = [r for r in list_files(files) if r not in SKIP_FILES]
    rows = read_csv()
    by_key = {r['key']: r for r in rows}
    srcs = {}
    for r in rels:
        with open(os.path.join(ROOT, r), encoding='utf-8') as f:
            srcs[r] = f.read()
    jobs = {r: FileJob(r, srcs[r]).analyze() for r in rels}
    if check:
        left = [(r, j.src.count('\n', 0, s) + 1, v) for r, j in jobs.items() for (_, v, s, _) in j.found]
        for r, ln, v in left:
            print('%s:%d: %s' % (r, ln, v.replace('\n', '\\n')))
        print('%d Korean literals not in data/texts.csv' % len(left))
        return 1 if left else 0
    added = 0
    uses_lang = set()
    for r in rels:
        j = jobs[r]
        if not j.found:
            continue
        counters = {}
        local = {}  # 이 파일에서 값 → 키(같은 위치 이름이면 다시 쓴다)
        for parts, value, s, e in j.found:
            base = '.'.join([j.stem] + parts)
            if not parts:
                counters[base] = counters.get(base, 0) + 1
                base = '%s.%03d' % (base, counters[base])
            key = base
            n = 1
            while key in by_key and unescape_value(by_key[key]['ko']) != value:
                n += 1
                key = '%s_%d' % (base, n)
            if (base, value) in local:
                key = local[(base, value)]
            if key not in by_key:
                row = {c: '' for c in COLUMNS}
                row.update({'key': key, 'ko': escape_value(value), 'note': r})
                rows.append(row)
                by_key[key] = row
                added += 1
            local[(base, value)] = key
            j.edits.append((s, e, 'Lang.t("%s")' % key))
        for cs, ce, rep in j.const_spans.values():
            j.edits.append((cs, ce, rep))
        out = j.src
        for s, e, t in sorted(j.edits, key=lambda x: -x[0]):
            out = out[:s] + t + out[e:]
        srcs[r] = out
        uses_lang.add(r)
    # Lang 상수: 부모 스크립트(extends "res://…")가 이미 가졌거나 이번에 얻으면 넣지 않는다(이름 겹침 오류)
    for r in sorted(uses_lang):
        anc = lang_ancestors(r, srcs)
        if has_lang(srcs[r]) or any(a in uses_lang or has_lang(srcs.get(a, '')) for a in anc):
            continue
        srcs[r] = insert_lang(srcs[r])
    # 조상이 이번에 Lang을 얻었는데 자식이 원래 가지고 있던 경우는 없다(이 도구만 넣는다)
    for r in uses_lang:
        with open(os.path.join(ROOT, r), 'w', encoding='utf-8') as f:
            f.write(srcs[r])
    write_csv(rows)
    for r, j in jobs.items():
        for s, why in j.skipped:
            print('skip %s:%d (%s)' % (r, j.src.count('\n', 0, s) + 1, why))
    print('%d files changed, %d texts added (data/texts.csv now %d rows)' % (len(uses_lang), added, len(rows)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
