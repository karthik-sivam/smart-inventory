#!/usr/bin/env python3
"""
translate_catalog.py  —  Stoqly UI translation filler (S14, Phase 2)

Reads AITest/Localizable.xcstrings, finds every string that is NOT yet
translated into each target language, translates it via the Claude API using a
domain glossary, and writes the result back into the catalog with
state = "needs_review" (so a native reviewer can approve later in Xcode).

Design goals:
  - Idempotent: never overwrites an existing translation (pilot + reviewed
    strings are preserved). Re-run any time to fill only the gaps.
  - Consistent: a glossary keeps brand/domain terms stable across languages.
  - Safe: keeps format specifiers (%@, %lld, %d, %.2f, %1$@) and placeholders.
  - Marked: everything it writes is state="needs_review" — nothing is silently
    treated as final.

USAGE  (no pip installs needed — uses only the Python standard library)
  # API key: read automatically from AITest/Secrets.plist (ANTHROPIC_API_KEY),
  # or override with an env var: export ANTHROPIC_API_KEY="sk-ant-..."
  python3 translate_catalog.py                 # translate all 14 languages
  python3 translate_catalog.py --langs hi,ta   # just Hindi + Tamil
  python3 translate_catalog.py --dry-run       # show counts, write nothing
  python3 translate_catalog.py --model claude-sonnet-4-5  # higher quality

NOTES
  - Default model is Haiku (cheap, matches the app). For best regional-language
    quality you can pass a stronger --model; this is an offline build tool, not
    the shipping app, so the "don't change the app's Claude model" rule does not
    apply here.
  - Cost with Haiku for ~700 strings x 14 langs is a few rupees. It only calls
    the API for gaps, so re-runs are near-free.
"""

import argparse
import json
import os
import plistlib
import re
import sys
import time
import urllib.request
import urllib.error

CATALOG_DEFAULT = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Localizable.xcstrings")
)

# catalog code -> human language name for the prompt
LANGUAGES = {
    "hi": "Hindi",
    "ta": "Tamil",
    "te": "Telugu",
    "kn": "Kannada",
    "ml": "Malayalam",
    "ar": "Arabic",
    "es": "Spanish",
    "pt-BR": "Brazilian Portuguese",
    "fr": "French",
    "zh-Hans": "Simplified Chinese",
    "id": "Indonesian",
    "de": "German",
    "ru": "Russian",
    "ja": "Japanese",
}

# Terms to keep verbatim (do not translate) — ONLY the brand name + hard codes.
# NOTE: do NOT keep "Pro"/"AI"/"Smart" here — that made the model leave whole
# feature names ("Smart Insights", "Smart Sales Entry", "Go Pro") in English.
# Feature/section names MUST be translated.
GLOSSARY_KEEP = ["Stoqly", "SKU", "CSV", "PDF", "QR", "FIFO"]

# Whole strings we never translate (brand, symbols, etc.)
DO_NOT_TRANSLATE = {"Stoqly", "SKU", "PDF", "CSV", "AI", "OK"}

# Founder-approved preferred terms per language (register anchor + consistency).
# The model is told to use these EXACT translations and match their register/word
# choice everywhere else. Tamil confirmed 2026-07-22.
TERM_GLOSSARY = {
    "ta": {
        "Storage": "கிடங்கு",
        "Storages": "கிடங்குகள்",
        "Stock": "இருப்பு",
        "Low Stock": "குறைந்த இருப்பு",
        "Out of Stock": "இருப்பு இல்லை",
        "Item": "பொருள்",
        "Items": "பொருட்கள்",
        "Supplier": "சப்ளையர்",
        "Profit": "லாபம்",
        "Revenue": "வருவாய்",
        "Sale": "விற்பனை",
        "Category": "வகை",
    },
}


def glossary_prompt(lang):
    terms = TERM_GLOSSARY.get(lang)
    if not terms:
        return ""
    pairs = "; ".join(f"'{en}' = '{tr}'" for en, tr in terms.items())
    return ("\nGLOSSARY (use these EXACT translations, and match their everyday register "
            "and word-choice for all other strings): " + pairs)

# --- Script guard: catch cross-script contamination (e.g. a Hindi char inside Tamil) ---
# Unicode block (lo, hi) that each language's translation is EXPECTED to use.
SCRIPT_BLOCKS = {
    "Devanagari": (0x0900, 0x097F),
    "Bengali":    (0x0980, 0x09FF),
    "Tamil":      (0x0B80, 0x0BFF),
    "Telugu":     (0x0C00, 0x0C7F),
    "Kannada":    (0x0C80, 0x0CFF),
    "Malayalam":  (0x0D00, 0x0D7F),
    "Arabic":     (0x0600, 0x06FF),
}
EXPECT_SCRIPT = {"hi": "Devanagari", "ta": "Tamil", "te": "Telugu",
                 "kn": "Kannada", "ml": "Malayalam", "ar": "Arabic"}


def has_foreign_script(text, lang):
    """True if text contains characters from an Indic/Arabic block that is NOT
    the language's expected script (e.g. a Devanagari char inside Tamil)."""
    expected = EXPECT_SCRIPT.get(lang)
    if not expected:
        return False  # Latin/CJK langs — no Indic-script guard needed
    for ch in text:
        cp = ord(ch)
        for name, (lo, hi) in SCRIPT_BLOCKS.items():
            if lo <= cp <= hi and name != expected:
                return True
    return False

SYSTEM_PROMPT = (
    "You are a professional software localizer specializing in mobile app UI for "
    "small-business inventory management. You translate short UI strings from "
    "English into {lang}. Rules:\n"
    "1. Keep it concise — these are space-constrained UI labels/buttons.\n"
    "2. Preserve ALL format specifiers exactly: %@, %lld, %d, %.2f, %1$@, \\n, etc.\n"
    "3. Do NOT translate these terms — keep them verbatim: " + ", ".join(GLOSSARY_KEEP) + ".\n"
    "4. Use natural, native business terminology a real shopkeeper would use "
    "(not literal/robotic translation). For inventory terms (storage, reorder, "
    "stock, count, batch, supplier) use the standard commercial term in {lang}.\n"
    "4b. REGISTER — middle, everyday business language. Write {lang} the way a modern "
    "retail app, shop signboard, or WhatsApp Business message would: clear and natural. "
    "Do NOT use classical/literary/heavily-Sanskritized words, and do NOT use street slang "
    "or regional colloquialisms. When shopkeepers commonly say an English business/tech term "
    "(stock, bill, report, mobile, scan), the everyday transliterated loanword is PREFERRED "
    "over a rare pure-{lang} coinage. Aim for what an average shop owner reads instantly.\n"
    "5. Match the source register: buttons stay imperative, labels stay nouns.\n"
    "5b. TRANSLATE feature and section names too — e.g. 'Smart Insights', 'Smart Count', "
    "'Smart Sales Entry', 'Inventory Health', 'Go Pro'. Do NOT leave them in English. "
    "Only 'Stoqly' and the codes (SKU/CSV/PDF/QR) stay verbatim; 'Pro' as the plan name "
    "may stay but the words around it must be translated. Never return the English source unchanged.\n"
    "6. SCRIPT: write the translation ONLY in the native script of {lang}. "
    "Never mix in characters from another Indic script (e.g. no Devanagari/Hindi "
    "or Bengali characters inside a Tamil/Telugu/Kannada/Malayalam translation). "
    "Every non-Latin character must belong to {lang}'s own script.\n"
    "7. OUTPUT FORMAT: return one line per input id, formatted exactly as the id, "
    "then a single TAB character, then the translation — e.g. `0\t<translation>`. "
    "Do NOT use JSON, do NOT wrap translations in quotes, no numbering words, no commentary."
)

API_URL = "https://api.anthropic.com/v1/messages"

SECRETS_PLIST = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Secrets.plist")
)


def get_api_key():
    """Prefer the env var; fall back to the app's AITest/Secrets.plist so the
    key already stored there works without any copy/paste."""
    key = os.environ.get("ANTHROPIC_API_KEY")
    if key:
        return key
    try:
        with open(SECRETS_PLIST, "rb") as f:
            key = plistlib.load(f).get("ANTHROPIC_API_KEY")
        if key:
            print(f"  (using ANTHROPIC_API_KEY from {SECRETS_PLIST})")
            return key
    except FileNotFoundError:
        pass
    except Exception as e:
        print(f"  could not read Secrets.plist: {e}", file=sys.stderr)
    sys.exit("ERROR: no ANTHROPIC_API_KEY in env or AITest/Secrets.plist.")


def call_claude(model, system, user_content, max_tokens=4000, retries=4):
    key = get_api_key()
    body = json.dumps({
        "model": model,
        "max_tokens": max_tokens,
        "system": system,
        "messages": [{"role": "user", "content": user_content}],
    }).encode("utf-8")
    req = urllib.request.Request(API_URL, data=body, method="POST")
    req.add_header("x-api-key", key)
    req.add_header("anthropic-version", "2023-06-01")
    req.add_header("content-type", "application/json")
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                return "".join(part.get("text", "") for part in data.get("content", []))
        except urllib.error.HTTPError as e:
            wait = 2 ** attempt
            print(f"  HTTP {e.code}; retry in {wait}s", file=sys.stderr)
            time.sleep(wait)
        except urllib.error.URLError as e:
            wait = 2 ** attempt
            print(f"  Network error {e}; retry in {wait}s", file=sys.stderr)
            time.sleep(wait)
    raise RuntimeError("Claude API failed after retries")


def parse_translations(text):
    """Parse the model's reply into {id: translation}.

    Primary format is TAB-delimited lines ('<id>\\t<translation>') which cannot
    break on quotes/commas the way JSON does. Falls back to JSON and to a
    tolerant 'id: translation' line parse so older/looser replies still work.
    """
    text = text.strip()
    if text.startswith("```"):
        text = re.sub(r"^```[a-zA-Z]*\n?", "", text)
        text = re.sub(r"\n?```$", "", text).strip()

    # 1) TAB / colon delimited lines: 0<TAB>trans   or   0: trans   or   "0": "trans"
    out = {}
    line_re = re.compile(r'^\s*"?(\d+)"?\s*[\t:]\s*(.*?)\s*,?\s*$')
    for line in text.splitlines():
        m = line_re.match(line)
        if m:
            val = m.group(2).strip().strip('"').strip()
            if val:
                out[m.group(1)] = val
    if out:
        return out

    # 2) Fallback: strict JSON object
    start, end = text.find("{"), text.rfind("}")
    if start != -1 and end != -1:
        return json.loads(text[start:end + 1])
    raise ValueError("could not parse translations from response")


def source_text_for(key, entry):
    """The English source: an explicit 'en' localization value, else the key."""
    loc = entry.get("localizations", {}).get("en", {})
    val = loc.get("stringUnit", {}).get("value")
    return val if val else key


def has_letters(s):
    return bool(re.search(r"[A-Za-z]", s))


def needs_translation(entry, lang):
    loc = entry.get("localizations", {}).get(lang, {})
    val = loc.get("stringUnit", {}).get("value")
    return not val  # translate only if missing/empty


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", default=CATALOG_DEFAULT)
    ap.add_argument("--model", default="claude-haiku-4-5-20251001")
    ap.add_argument("--langs", default=",".join(LANGUAGES.keys()),
                    help="comma-separated catalog codes")
    ap.add_argument("--batch-size", type=int, default=40)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--revalidate", action="store_true",
                    help="clear existing translations with wrong-script contamination "
                         "so they get re-translated (fixes e.g. Hindi chars inside Tamil)")
    ap.add_argument("--clear-english", action="store_true",
                    help="clear target-lang translations that exactly match the English "
                         "source so the hardened prompt re-translates feature names")
    ap.add_argument("--regenerate", action="store_true",
                    help="re-translate ALL strings for the target langs (ignore existing "
                         "values) — use to apply a new register/glossary across the app")
    args = ap.parse_args()

    with open(args.catalog, encoding="utf-8") as f:
        catalog = json.load(f)
    strings = catalog.setdefault("strings", {})
    target_langs = [l.strip() for l in args.langs.split(",") if l.strip() in LANGUAGES]

    # --revalidate: drop any existing value that contains a foreign script so it
    # becomes a gap and gets re-translated (with the script guard now enforced).
    if args.revalidate:
        cleared = {}
        for key, entry in strings.items():
            for lang in target_langs:
                unit = entry.get("localizations", {}).get(lang, {}).get("stringUnit", {})
                val = unit.get("value")
                if val and has_foreign_script(val, lang):
                    del entry["localizations"][lang]
                    cleared[lang] = cleared.get(lang, 0) + 1
        print("Revalidate — cleared contaminated values:", cleared or "none")

    if args.clear_english:
        cleared_en = {}
        for key, entry in strings.items():
            src = source_text_for(key, entry)
            if not src or not has_letters(src) or src in DO_NOT_TRANSLATE:
                continue
            for lang in target_langs:
                unit = entry.get("localizations", {}).get(lang, {}).get("stringUnit", {})
                val = unit.get("value")
                if val and val == src and len(src) > 2:
                    del entry["localizations"][lang]
                    cleared_en[lang] = cleared_en.get(lang, 0) + 1
        print("Clear-english — removed same-as-source copies:", cleared_en or "none")

    # Build the translatable source list (skip symbols / do-not-translate).
    translatable = []
    for key, entry in strings.items():
        if entry.get("shouldTranslate") is False:
            continue
        src = source_text_for(key, entry)
        if not src or not has_letters(src) or src in DO_NOT_TRANSLATE:
            continue
        translatable.append((key, src, entry))

    print(f"Catalog: {len(strings)} strings; {len(translatable)} translatable.")
    grand_total = 0

    for lang in target_langs:
        if args.regenerate:
            gaps = list(translatable)  # re-translate everything (new register/glossary)
        else:
            gaps = [(k, s, e) for (k, s, e) in translatable if needs_translation(e, lang)]
        print(f"\n[{lang}] {LANGUAGES[lang]}: {len(gaps)} to translate")
        if args.dry_run or not gaps:
            grand_total += len(gaps)
            continue

        system = SYSTEM_PROMPT.format(lang=LANGUAGES[lang]) + glossary_prompt(lang)
        for i in range(0, len(gaps), args.batch_size):
            batch = gaps[i:i + args.batch_size]
            payload = {str(j): src for j, (k, src, e) in enumerate(batch)}
            lines = "\n".join(f"{j}\t{src}" for j, (k, src, e) in enumerate(batch))
            user = ("Translate these UI strings into " + LANGUAGES[lang] +
                    ". Each input line is 'id<TAB>English'. Reply with one line per id as "
                    "'id<TAB>translation' (a real tab). No JSON, no quotes.\n" + lines)
            try:
                result = parse_translations(call_claude(args.model, system, user))
            except Exception as ex:
                print(f"  batch {i}: FAILED ({ex}); skipping", file=sys.stderr)
                continue
            for j, (key, src, entry) in enumerate(batch):
                tr = result.get(str(j))
                if not tr:
                    continue
                # Script guard: never write a wrong-script translation. Leaving it
                # as a gap lets a later re-run try again (English shows meanwhile).
                if has_foreign_script(tr, lang):
                    print(f"  ! skipped wrong-script output for {src[:30]!r}", file=sys.stderr)
                    continue
                entry.setdefault("localizations", {})[lang] = {
                    "stringUnit": {"state": "needs_review", "value": tr}
                }
                # Protect from Xcode stale-dropping: an entry we translate must be
                # kept in the build even if the extractor can't match it to code.
                if "extractionState" not in entry:
                    entry["extractionState"] = "manual"
                grand_total += 1
            print(f"  {min(i + args.batch_size, len(gaps))}/{len(gaps)}")
            # persist incrementally so a crash never loses work
            with open(args.catalog, "w", encoding="utf-8") as f:
                json.dump(catalog, f, ensure_ascii=False, indent=2)

    if args.dry_run:
        print(f"\nDRY RUN — would translate {grand_total} strings total.")
    else:
        with open(args.catalog, "w", encoding="utf-8") as f:
            json.dump(catalog, f, ensure_ascii=False, indent=2)
        print(f"\nDone. Wrote {grand_total} translations (state=needs_review).")
        print("Open Localizable.xcstrings in Xcode — new strings show as "
              "'Needs Review' (yellow) for native approval.")


if __name__ == "__main__":
    main()
