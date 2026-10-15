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
    ts_rels = [r for r in rels if r.endswith('.ts') and r not in TS_SKIP_FILES]
    if not files:
        ts_rels = sorted('server/src/' + f for f in os.listdir(os.path.join(ROOT, 'server', 'src'))
                         if f.endswith('.ts') and 'server/src/' + f not in TS_SKIP_FILES)
    rels = [r for r in rels if r.endswith('.gd')]
    rows = read_csv()
    by_key = {r['key']: r for r in rows}
    if ts_rels:
        if check:
            left = ts_main(ts_rels, rows, by_key, True)
            for r, ln, v in left:
                print('%s:%d: %s' % (r, ln, v.replace('\n', '\\n')))
            if left:
                print('%d Korean literals in server code not in data/texts.csv' % len(left))
            ts_left = len(left)
        else:
            ts_added = ts_main(ts_rels, rows, by_key, False)
            print('server: %d texts added' % ts_added)
            write_csv(rows)
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
        used = set()
        for d in SCAN_DIRS + ['server/src']:
            for base, _, fs in os.walk(os.path.join(ROOT, d)):
                for f in fs:
                    if f.endswith('.gd') or f.endswith('.ts'):
                        with open(os.path.join(base, f), encoding='utf-8') as fh:
                            used.update(re.findall(r'(?:Lang\.t|txt)\(["\']([a-z0-9_.]+)["\']', fh.read()))
        unused = [r['key'] for r in rows if r['key'] not in used and not r['key'].startswith('data.')]
        if unused:
            print('%d keys in data/texts.csv not used by code (remove them if the text is gone): %s' % (len(unused), ' '.join(unused[:20])))
        return 1 if left or (ts_rels and ts_left) else 0
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


# --- 서버 TypeScript(server/src/*.ts) ---
# '…'·"…"·`…${식}…` 안의 한글 → txt('키') / txt('키', { 이름: 식 }). 값의 ${식} 자리는 {이름}.
TS_SKIP_FILES = {'server/src/legal.ts', 'server/src/profanity.ts', 'server/src/seed.ts', 'server/src/main.ts',
                 'server/src/texts.ts', 'server/src/cli.ts', 'server/src/env.ts'}
TS_SKIP_CALLS = {'log', 'warn', 'error', 'info', 'debug', 'Error', 'TypeError', 'RangeError'}
TS_IMPORT = "import { txt } from './texts.ts'"
ROUTE_CALLS = {'get', 'post', 'put', 'delete', 'patch'}


def ts_scan_string(src, i):
    """i = 따옴표 위치. (끝 위치, 조각) — 템플릿이면 조각 = [('s', 글), ('e', 식 시작, 식 끝)...]."""
    q = src[i]
    j = i + 1
    if q != '`':
        while src[j] != q:
            if src[j] == '\\':
                j += 1
            elif src[j] == '\n':
                raise ValueError('unterminated string')
            j += 1
        return j + 1, [('s', src[i + 1:j])]
    parts = []
    buf_start = j
    while True:
        c = src[j]
        if c == '\\':
            j += 2
            continue
        if c == '`':
            parts.append(('s', src[buf_start:j]))
            return j + 1, parts
        if c == '$' and src[j + 1] == '{':
            parts.append(('s', src[buf_start:j]))
            k = j + 2
            depth = 1
            while depth:
                ch = src[k]
                if ch in '\'"`':
                    k, _ = ts_scan_string(src, k)
                    continue
                if ch == '{':
                    depth += 1
                elif ch == '}':
                    depth -= 1
                k += 1
            parts.append(('e', j + 2, k - 1))
            j = k
            buf_start = j
            continue
        j += 1


def ts_decode(body):
    return decode_gd(body.replace('\\`', '`').replace('\\$', '$'), False)


def ts_quote(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n') + "'"


def ts_param_name(expr, used):
    e = expr.strip()
    wrappers = {'toLocaleString', 'join', 'toString', 'String', 'Number', 'slice', 'trim', 'Math', 'round', 'floor', 'en', 'US', 'ko', 'KR'}
    e2 = re.sub(r"'[^']*'", '', e)
    m = re.fullmatch(r'(?:[A-Za-z_][A-Za-z0-9_]*\.)*([A-Za-z_][A-Za-z0-9_]*)\s*(\([^()]*\))?', e2)
    if m and m.group(1) not in wrappers:
        name = m.group(1)
    else:
        words = [w for w in re.findall(r'[A-Za-z_][A-Za-z0-9_]*', e2) if w not in wrappers]
        name = words[-1] if words else 'v'
    base = name
    n = 2
    while name in used:
        name = '%s%d' % (base, n)
        n += 1
    used.add(name)
    return name


class TsJob:
    def __init__(self, rel, src):
        self.rel = rel
        self.src = src
        self.stem = key_part(os.path.basename(rel)[:-3])
        self.found = []  # (parts, value, start, end, params[(name, expr)])
        self.skipped = []

    def analyze(self, src=None, base=0, ctx=None):
        src = self.src if src is None else src
        n = len(src)
        i = 0
        stack = ctx or []  # 프레임 {'ch','call','route','id','key'}
        top = None
        prev = None  # 마지막 의미 있는 토큰(kind, text)
        while i < n:
            c = src[i]
            if src.startswith('//', i):
                j = src.find('\n', i)
                i = n if j < 0 else j
                continue
            if src.startswith('/*', i):
                j = src.find('*/', i + 2)
                i = n if j < 0 else j + 2
                continue
            if c == '/' and (prev is None or (prev[0] == 'op' and prev[1] in '(,=:[!&|?{};+-*%<>~^') or (prev[0] == 'id' and prev[1] in ('return', 'typeof', 'case'))):
                j = i + 1
                in_cls = False
                while j < n and src[j] != '\n':
                    if src[j] == '\\':
                        j += 2
                        continue
                    if src[j] == '[':
                        in_cls = True
                    elif src[j] == ']':
                        in_cls = False
                    elif src[j] == '/' and not in_cls:
                        break
                    j += 1
                i = j + 1
                prev = ('re', '')
                continue
            if c in '\'"`':
                end, parts = ts_scan_string(src, i)
                statics = ''.join(p[1] for p in parts if p[0] == 's')
                # 프레임 정보: 라우트 경로, 객체 id·키
                if stack and stack[-1]['ch'] == '(' and stack[-1]['call'] in ROUTE_CALLS and stack[-1].get('route') is None and c != '`':
                    stack[-1]['route'] = parts[0][1]
                if stack and stack[-1]['ch'] == '{' and prev and prev[0] == 'op' and prev[1] == ':' and stack[-1].get('key') == 'id' and c != '`':
                    stack[-1]['id'] = parts[0][1]
                if HANGUL.search(statics):
                    calls = [f['call'] for f in stack if f['call']]
                    if any(cn in TS_SKIP_CALLS for cn in calls):
                        pass
                    else:
                        self._found(src, base, i, end, parts, stack, top)
                elif c == '`':
                    for p in parts:
                        if p[0] == 'e':
                            self.analyze(src[p[1]:p[2]], base + p[1], [dict(f) for f in stack])
                prev = ('str', '')
                i = end
                continue
            m = IDENT.match(src, i)
            if m:
                w = m.group(0)
                line_start = src.rfind('\n', 0, i) + 1
                if not stack and line_start == src.rfind('\n', 0, i) + 1 and src[line_start:i].strip() in ('', 'export', 'export async', 'async', 'export default'):
                    pass
                if not stack and w in ('const', 'let', 'function', 'class', 'interface', 'type'):
                    m2 = IDENT.match(src, m.end() + 1) if m.end() < n else None
                    j = m.end()
                    while j < n and src[j] in ' \t*':
                        j += 1
                    m2 = IDENT.match(src, j)
                    if m2:
                        top = m2.group(0)
                if stack and stack[-1]['ch'] == '{':
                    k = m.end()
                    while k < n and src[k] in ' \t':
                        k += 1
                    if k < n and src[k] == ':' and not src.startswith('::', k):
                        stack[-1]['key'] = w
                prev = ('id', w)
                i = m.end()
                continue
            if c in '([{':
                call = prev[1] if (c == '(' and prev and prev[0] == 'id') else None
                stack.append({'ch': c, 'call': call, 'route': None, 'id': None, 'key': None})
            elif c in ')]}':
                if stack:
                    stack.pop()
            elif c == ',' and stack and stack[-1]['ch'] == '{':
                stack[-1]['key'] = None
            if c not in ' \t\r\n':
                prev = ('op', c)
            i += 1
        return self

    def _found(self, src, base, i, end, parts, stack, top):
        params = []
        used = set()
        value = ''
        for p in parts:
            if p[0] == 's':
                value += ts_decode(p[1]) if src[i] == '`' else decode_gd(p[1], False)
            else:
                expr = src[p[1]:p[2]]
                name = ts_param_name(expr, used)
                # 식 안의 한글 문자열도 옮긴다(따로 키)
                sub = TsJob(self.rel, expr)
                sub.stem = self.stem
                sub.analyze(expr, 0, [dict(f) for f in stack])
                if sub.found:
                    self.nested = getattr(self, 'nested', [])
                    expr = ('__NESTED__', expr, sub.found)
                params.append((name, expr))
                value += '{%s}' % name
        if '{' in ''.join(p[1] for p in parts if p[0] == 's'):
            self.skipped.append((base + i, 'literal { in text'))
            return
        key_parts = []
        route = next((f['route'] for f in reversed(stack) if f.get('route')), None)
        if route:
            key_parts.append(key_part(route.replace('/v1/', '').replace('/', '_').replace(':', '')))
        elif top:
            key_parts.append(key_part(top))
        oid = next((f['id'] for f in reversed(stack) if f['ch'] == '{' and f.get('id')), None)
        if oid:
            key_parts.append(key_part(oid))
        if stack and stack[-1]['ch'] == '{' and stack[-1].get('key'):
            key_parts.append(key_part(stack[-1]['key']))
        self.found.append(([p for p in key_parts if p], value, base + i, base + end, params))


def ts_render_expr(expr, assign):
    if isinstance(expr, tuple):
        _, text, found = expr
        out = text
        calls = [(s, e, ts_call(assign(parts, value), params, assign)) for parts, value, s, e, params in sorted(found, key=lambda f: f[2])]
        for s, e, t in reversed(calls):
            out = out[:s] + t + out[e:]
        return out
    return expr


def ts_call(key, params, assign):
    if not params:
        return "txt('%s')" % key
    items = []
    for name, expr in params:
        ex = ts_render_expr(expr, assign).strip()
        items.append(name if ex == name else '%s: %s' % (name, ex))
    return "txt('%s', { %s })" % (key, ', '.join(items))


def ts_main(rels, rows, by_key, check):
    jobs = {}
    for r in rels:
        with open(os.path.join(ROOT, r), encoding='utf-8') as f:
            jobs[r] = TsJob(r, f.read()).analyze()
    if check:
        return [(r, j.src.count('\n', 0, f[2]) + 1, f[1]) for r, j in jobs.items() for f in j.found]
    added = 0
    for r, j in jobs.items():
        if not j.found:
            continue
        counters = {}

        def assign(parts, value, j=j, r=r, counters=counters):
            nonlocal added
            base = '.'.join(['server', j.stem] + parts)
            if not parts:
                counters[base] = counters.get(base, 0) + 1
                base = '%s.%03d' % (base, counters[base])
            key = base
            n = 2
            while key in by_key and unescape_value(by_key[key]['ko']) != value:
                key = '%s_%d' % (base, n)
                n += 1
            if key not in by_key:
                row = {c: '' for c in COLUMNS}
                row.update({'key': key, 'ko': escape_value(value), 'note': r})
                rows.append(row)
                by_key[key] = row
                added += 1
            return key
        out = j.src
        calls = [(s, e, ts_call(assign(parts, value), params, assign)) for parts, value, s, e, params in sorted(j.found, key=lambda f: f[2])]
        for s, e, text in reversed(calls):
            out = out[:s] + text + out[e:]
        if TS_IMPORT not in out:
            lines = out.split('\n')
            last = max(i for i, l in enumerate(lines) if l.startswith('import ') or (l.startswith('  ') and i > 0 and lines[i - 1].startswith('import ') and not lines[i - 1].rstrip().endswith("'")) or l.startswith('} from ')) if any(l.startswith('import ') for l in lines) else -1
            # 여러 줄 import가 끝나는 줄까지
            while last >= 0 and last + 1 < len(lines) and not (lines[last].rstrip().endswith("'") or lines[last].rstrip().endswith("';")):
                last += 1
            if last < 0:  # import가 없으면 맨 위 주석 덩어리 뒤
                while last + 1 < len(lines) and lines[last + 1].startswith('//'):
                    last += 1
            lines.insert(last + 1, TS_IMPORT)
            out = '\n'.join(lines)
        with open(os.path.join(ROOT, r), 'w', encoding='utf-8') as f:
            f.write(out)
        for s, why in j.skipped:
            print('skip %s:%d (%s)' % (r, j.src.count('\n', 0, s) + 1, why))
        print('%s: %d texts' % (r, len(j.found)))
    return added


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
