#!/usr/bin/env python3
"""Takes the translations of the Tryton clients for our UI texts.

Development tool, not part of the app. Our English ARB texts (template
lib/l10n/app_en.arb) are matched with the msgids of the Tryton desktop
client 8.0 (primary) and of SAO (supplementary, only texts the client
lacks); their translations replace ours, except the keys and terms we
keep on purpose (KEEP, KEEP_WORDS). The Tryton translations are GPL-3
like this project.

    python3 tool/l10n_from_tryton.py            # report only
    python3 tool/l10n_from_tryton.py --apply    # write the ARB files
    flutter gen-l10n                            # after --apply

Paths: TRYTON_CLIENT_DIR (the `tryton` package), SAO_DIR.
"""
import json
import os
import re
import sys
from collections import OrderedDict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ARB = os.path.join(ROOT, 'lib', 'l10n')
TRYTON = os.environ.get(
    'TRYTON_CLIENT_DIR',
    '/Users/jank/python/tryton/.venv/lib/python3.13/site-packages/tryton')
SAO = os.environ.get('SAO_DIR', '/Users/jank/python/sao')

# Keys that keep our translation in every language: the same English text
# means something else here (rangeTo: "To" of a date range, not the
# recipient; keyDelete: the key name "Del"), or the Tryton text is weaker.
KEEP = {
    'rangeTo',
    'keyDelete',
    'username',
    'fuzzy',
    'emailBody',
}
# Terms of this client (user decision 2026-11-13): "Tab" and "Revision"
# stay, Tryton says e.g. "Registerkarte" / "Bearbeitung".
KEEP_WORDS = re.compile(r'\b(tabs?|revisions?)\b', re.IGNORECASE)

# Errors of single Tryton translations (reviewed 2026-11-13): wrong
# meaning, typos, untranslated text; these keep our translation.
KEEP_LANG = {
    'de': {'csvOverrideExport', 'ctxPasteRows', 'csvFieldString'},
    'es': {'clearField', 'shortcutToggleMenu', 'logModule',
           'csvFieldsSelected', 'csvOverrideExport'},
    'fr': {'createdBy', 'createdAt', 'logCreatedBy', 'logCreatedAt',
           'newProfile', 'recordModified', 'aboutMenu'},
    'nl': {'concurrencyException', 'csvFieldsSelected',
           'csvFieldRecordName', 'x2mUndelete'},
    'pl': {'csvFieldString', 'csvFieldModelName', 'shortcutListOpen',
           'bookmarkName'},
    'pt': {'compare', 'clearField', 'duplicate', 'menuDuplicate',
           'shortcutToggleMenu', 'scanCode'},
    'ru': {'x2mDelete', 'x2mRemove', 'x2mUndelete', 'csvParameters',
           'attachmentsOf', 'fieldId', 'concurrencyException',
           'reallyDelete', 'reallyDeleteRecords'},
}

# Our text has the meaning of another Tryton msgid (our English stays).
ALIASES = {
    'recordModified': 'This record has been modified\ndo you want to save it?',
    'relatedRecords': 'Open related records',
    'openRecord': 'Open the record <F2>',
    'clearField': 'Clear the field <Del>',
    'searchRecord': 'Search a record <F2>',
    'newProfile': 'Add new profile',
    'launchActions': 'Launch action',
}


def parse_po(path, template=False):
    """msgid → msgstr of the translated, not fuzzy entries (a
    [template] .pot: all msgids)."""
    result = {}
    if not os.path.exists(path):
        return result
    entry, current, fuzzy = {}, None, False

    def flush():
        msgid = entry.get('msgid')
        msgstr = entry.get('msgstr', entry.get('msgstr[0]'))
        if msgid and (template or msgstr and not fuzzy) \
                and 'msgctxt' not in entry:
            result[msgid] = msgstr

    with open(path, encoding='utf-8') as f:
        for line in f:
            line = line.rstrip('\n')
            if not line.strip():
                flush()
                entry, current, fuzzy = {}, None, False
                continue
            if line.startswith('#,') and 'fuzzy' in line:
                fuzzy = True
                continue
            if line.startswith('#'):
                continue
            m = re.match(
                r'^(msgctxt|msgid_plural|msgid|msgstr(?:\[\d\])?) (".*")$', line)
            if m:
                current = m.group(1)
                entry[current] = json.loads(m.group(2))
            elif line.startswith('"') and current:
                entry[current] += json.loads(line)
    flush()
    return result


SHORTCUT = re.compile(r'\s*<[^<>]+>\s*$')  # " <Del>", " <F2>"
SHORTCUT_ANY = re.compile(r'\s*<[\w+]{1,8}>')  # <Del>, <Supr>, <F2>, <Ins>
QUOTES = '„“”"\'«»‚‘’'
PLACEHOLDER_PO = re.compile(r'%\((\w+)\)s|%[sd]')
PLACEHOLDER_ARB = re.compile(r'\{(\w+)\}')


def norm(text):
    """Matching key: without mnemonics, shortcut suffix, trailing colon,
    case, with one style of ellipsis and placeholders."""
    text = text.replace('…', '...').replace(' ', ' ')
    text = re.sub(r'_(?=\w)', '', text)
    text = SHORTCUT.sub('', text)
    text = PLACEHOLDER_ARB.sub('%s', PLACEHOLDER_PO.sub('%s', text))
    text = re.sub(r'\s*\.\.\.', ' ...', text)
    text = re.sub(r'\s+', ' ', text).strip()
    return text.lower().rstrip(':').strip()


def convert(translation, english, ours):
    """The Tryton translation in the form of our text."""
    text = re.sub(r'_(?=\w)', '', translation)  # GTK mnemonics
    if not SHORTCUT.search(english):
        text = SHORTCUT_ANY.sub('', text)
    text = text.strip()
    # the first letter like the English text („filters“ → „Filters“)
    if text and english[:1].isupper() and text[0].islower():
        text = text[0].upper() + text[1:]
    if not english.rstrip().endswith(':'):
        text = re.sub(r'\s*:$', '', text)
    # placeholders by position: %s / %(name)s → {name} of our English
    names = PLACEHOLDER_ARB.findall(english)
    found = list(PLACEHOLDER_PO.finditer(text))
    if found:
        if len(found) != len(names):
            return None
        parts, last = [], 0
        for m, name in zip(found, names):
            if m.group(1) and m.group(1) in names:
                name = m.group(1)
            parts.append(text[last:m.start()] + '{' + name + '}')
            last = m.end()
        text = ''.join(parts) + text[last:]
    elif names:
        return None  # our text has a value the translation lacks
    # quotes around a value as in our translation („{field}“)
    for name in names:
        m = ours and re.search(
            '([' + QUOTES + '])\\{' + name + '\\}([' + QUOTES + '])', ours)
        if m:
            text = re.sub('["\']\\{' + name + '\\}["\']',
                          m.group(1) + '{' + name + '}' + m.group(2), text)
    if re.search(r'(\.\.\.|…)$', english) and not re.search(
            r'(\.\.\.|…)$', text):
        text += '...'
    # the ellipsis as in our translation („ …“ / „…“)
    if re.search(r'\.\.\.$', text):
        stem = re.sub(r'\s*\.\.\.$', '', text)
        if ours and re.search(r'\s…$', ours):
            text = stem + ' …'
        else:
            text = stem + '…'
    return text


def main(apply):
    template = json.load(open(os.path.join(ARB, 'app_en.arb')),
                         object_pairs_hook=OrderedDict)
    keys = [k for k, v in template.items()
            if not k.startswith('@') and isinstance(v, str)]
    pot = parse_po(os.path.join(TRYTON, 'data', 'locale', 'tryton.pot'),
                   template=True)
    pot_all = list(pot) + list(
        parse_po(os.path.join(SAO, 'locale', 'messages.pot'), template=True))
    # the msgids keep their original text (lookup in the .po files)
    index = {}
    for msgid in pot_all:
        index.setdefault(norm(msgid), msgid)
    langs = sorted(f[4:-4] for f in os.listdir(ARB)
                   if f.startswith('app_') and f.endswith('.arb')
                   and f != 'app_en.arb')
    total = 0
    for lang in langs:
        path = os.path.join(ARB, f'app_{lang}.arb')
        arb = json.load(open(path), object_pairs_hook=OrderedDict)
        sources = [
            parse_po(os.path.join(TRYTON, 'data', 'locale', lang,
                                  'LC_MESSAGES', 'tryton.po')),
            parse_po(os.path.join(SAO, 'locale', f'{lang}.po')),
        ]
        changes = []
        for key in keys:
            english = template[key]
            if (key in KEEP or key in KEEP_LANG.get(lang, ())
                    or KEEP_WORDS.search(english)):
                continue
            msgid = ALIASES.get(key) or index.get(norm(english))
            if not msgid:
                continue
            translation = next(
                (s[msgid] for s in sources if msgid in s), None)
            if not translation:
                continue
            ours = arb.get(key)
            text = convert(translation, english, ours)
            if text is None or text == ours:
                continue
            changes.append((key, ours, text))
            arb[key] = text
        total += len(changes)
        print(f'## {lang}: {len(changes)} changes')
        for key, ours, text in changes:
            print(f'  {key}: {ours!r} → {text!r}')
        if apply and changes:
            with open(path, 'w', encoding='utf-8') as f:
                f.write(json.dumps(arb, ensure_ascii=False, indent=2) + '\n')
    print(f'{total} changes' + ('' if apply else ' (report only, --apply writes)'))


if __name__ == '__main__':
    main('--apply' in sys.argv[1:])
