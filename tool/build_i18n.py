"""Builds lib/core/i18n_table.dart from the translation files in tool/i18n/*.json.
Each file maps English -> [Luganda, Kiswahili]. A translation that loses or adds a {0} placeholder is dropped
(the English shows instead), so a bad translation can never break a sentence or hide a number."""
import json, glob, re, sys

table, dropped = {}, []
for f in sorted(glob.glob('tool/i18n/*.json')):
    for en, tr in json.load(open(f)).items():
        if not isinstance(tr, list) or len(tr) != 2: dropped.append((en, 'shape')); continue
        want = sorted(re.findall(r'\{\d\}', en.replace('#}', '}')))
        ok = [t if isinstance(t, str) and t.strip() and sorted(re.findall(r'\{\d\}', t)) == want else None for t in tr]
        if None in ok:
            dropped.append((en, 'placeholders'))
            ok = [t if t is not None else en for t in ok]
        if ok == [en, en]: continue
        table[en] = ok

def dart(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$').replace('\n', '\\n') + "'"

out = ['// Made by tool/build_i18n.py from tool/i18n/*.json. Edit those files, not this one.',
       '// English -> [Luganda, Kiswahili].', 'const i18nTable = <String, List<String>>{']
for en in sorted(table):
    lg, sw = table[en]
    out.append(f'  {dart(en)}: [{dart(lg)}, {dart(sw)}],')
out.append('};\n')
open('lib/core/i18n_table.dart', 'w').write('\n'.join(out))
print(f'{len(table)} entries; {len(dropped)} fixed back to English:')
for d in dropped[:30]: print('  ', d)
