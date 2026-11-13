"""Lists every English sentence the app shows, so each one can be given a translation.
Run: python3 tool/extract_strings.py  -> writes tool/strings.txt (one per line)."""
import re, glob, json, sys

FILES = [f for f in glob.glob('lib/**/*.dart', recursive=True)
         if not f.endswith(('i18n_table.dart', 'i18n.dart', 'config.dart', 'api.dart', 'json.dart', 'countries.dart', 'names.dart'))]

lit = re.compile(r"""(?<![A-Za-z0-9_])(r?)('(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*")""")

def literals(src):
    # Joins 'a' 'b' written next to each other, as Dart does.
    out = []
    pos = 0
    toks = [(m.start(), m.end(), m.group(2)[1:-1], m.group(1)) for m in lit.finditer(src)]
    i = 0
    while i < len(toks):
        s, e, body, raw = toks[i]
        j = i
        while j + 1 < len(toks) and src[toks[j][1]:toks[j + 1][0]].strip() == '':
            j += 1
            body += toks[j][2]
        out.append((src[max(0, s - 40):s], body))
        i = j + 1
    return out

def template(body):
    n = [0]
    def rep(m):
        k = n[0]; n[0] += 1
        return '{%d}' % k
    # ${...} with nested braces
    res = ''
    i = 0
    while i < len(body):
        if body.startswith('${', i):
            d = 1; j = i + 2
            while j < len(body) and d:
                if body[j] == '{': d += 1
                elif body[j] == '}': d -= 1
                j += 1
            res += '{%d}' % n[0]; n[0] += 1; i = j
        elif body[i] == '$' and i + 1 < len(body) and (body[i + 1].isalpha() or body[i + 1] == '_'):
            j = i + 1
            while j < len(body) and (body[j].isalnum() or body[j] == '_'): j += 1
            res += '{%d}' % n[0]; n[0] += 1; i = j
        elif body[i] == '\\' and i + 1 < len(body):
            c = body[i + 1]
            res += {'n': '\n', "'": "'", '"': '"', '$': '$', '\\': '\\'}.get(c, c); i += 2
        else:
            res += body[i]; i += 1
    return res

SKIP_CTX = re.compile(r"(import |export |part |_rpc\(|\.s\(|\.i\(|\.b\(|\.n\(|\[|ValueKey\(|debugLabel|getString|setString|'p_|RegExp\(|Uri\.|key:|case |==\s*$|!=\s*$|\.code\s*==|name ==)\s*$")
seen = {}
for f in FILES:
    src = open(f).read()
    for ctx, body in literals(src):
        t = template(body)
        words = re.sub(r'\{\d\}', '', t)
        if not re.search(r'[A-Za-z]{2,}', words): continue
        if SKIP_CTX.search(ctx): continue
        if re.fullmatch(r'[a-z0-9_.\-/:]+', t): continue          # keys, codes, paths
        if re.fullmatch(r'[A-Z0-9_]+', t): continue                # AUDIT_ACTIONS
        if t.startswith(('http', 'package:', 'assets/', 'com.', 'tel:', 'mailto:')): continue
        if re.search(r'[a-z]+_[a-z]+', t) and ' ' not in t: continue
        if t.strip() in ('{0}',): continue
        if ' ' not in t.strip() and not t[0].isupper(): continue
        seen.setdefault(t, f)
open('tool/strings.txt', 'w').write('\n'.join(json.dumps(k) for k in sorted(seen)))
print(len(seen))
