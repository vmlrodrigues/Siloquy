#!/usr/bin/env python3
"""Turn exported Siloquy history into individual files you can edit by hand.

    python3 make-review-files.py ~/Desktop/siloquy-history-*.json

Produces, next to the exports (override with --out):

    dictation-review/
      README.md
      EDIT-THESE/          0001-a1b2c3d4-enhanced.md  ← correct these
      original-spoken/     0001-a1b2c3d4-original.md  ← what you actually said
      index.tsv                                        ← id → date, machine, model

Each file in EDIT-THESE/ holds nothing but the text, with the id in the filename.
That is deliberate: you can paste it into Apple Notes, mangle the formatting,
paste it back, and it still round-trips — there are no markers to preserve and
nothing to parse. Edit them until each one reads the way you would have written
it, and that becomes the gold standard the models get scored against.

Dependency-free: standard library only.

Selection: by default every entry that has enhanced text. `--sample N` takes a
stratified sample instead — half long, half short — because long dictations are
where cleanup matters and models disagree, while short ones catch over-editing.
"""

import argparse
import glob
import json
import os
import sys


def load(paths):
    entries, seen = [], set()
    for pattern in paths:
        for path in sorted(glob.glob(os.path.expanduser(pattern))):
            with open(path, encoding="utf-8") as fh:
                data = json.load(fh)
            host = data.get("hostname", "?")
            for e in data.get("entries", []):
                eid = e.get("id")
                if not eid or eid in seen:
                    continue
                seen.add(eid)
                e.setdefault("hostname", host)
                entries.append(e)
            print(f"  {os.path.basename(path)}: {len(data.get('entries', []))} entries")
    return entries


def prioritise(entries):
    """Order so that *any* prefix is a balanced sample.

    Files are numbered in this order, alternating long and short. Stopping after
    40 or 70 or 120 therefore still leaves a set with both halves represented:
    long dictations, where cleanup matters and models disagree, and short ones,
    which are the regression control that catches a model over-editing text that
    was already fine. No need to decide the sample size up front.
    """
    ranked = sorted(entries, key=lambda e: len((e.get("raw") or "").split()))
    mid = len(ranked) // 2
    short, long_ = ranked[:mid], ranked[mid:][::-1]  # longest first
    out = []
    for i in range(max(len(short), len(long_))):
        if i < len(long_):
            out.append(long_[i])
        if i < len(short):
            out.append(short[i])
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("exports", nargs="+", help="siloquy-history-*.json files")
    ap.add_argument("--out", default="~/Desktop/dictation-review")
    ap.add_argument("--sample", type=int, default=0,
                    help="stratified sample of N instead of everything")
    ap.add_argument("--min-words", type=int, default=15,
                    help="skip very short dictations (default 15 words)")
    ap.add_argument("--combined", action="store_true",
                    help="also write one all-in-one file for editing in a single pass")
    args = ap.parse_args()

    entries = load(args.exports)
    if not entries:
        print("No entries found.", file=sys.stderr)
        sys.exit(1)
    print(f"\n  {len(entries)} unique dictations across all exports")

    usable = [
        e for e in entries
        if (e.get("enhanced") or "").strip()
        and len((e.get("raw") or "").split()) >= args.min_words
    ]
    print(f"  {len(usable)} have enhanced text and >= {args.min_words} words")

    usable = prioritise(usable)
    if args.sample:
        usable = usable[: args.sample]
    print(f"  {len(usable)} written, ordered so any prefix stays balanced")

    out = os.path.expanduser(args.out)
    # Names chosen so the job is obvious from Finder alone, without opening
    # anything: one folder is an instruction, the other says what it holds.
    review = os.path.join(out, "EDIT-THESE")
    reference = os.path.join(out, "original-spoken")
    os.makedirs(review, exist_ok=True)
    os.makedirs(reference, exist_ok=True)

    index = ["seq\tid\tdate\tmachine\tmodel\tprompt\traw_words\tenhanced_words"]
    for i, e in enumerate(usable, 1):
        stem = f"{i:04d}-{e['id']}"
        # The suffix repeats in the filename so it stays clear once the file is
        # open somewhere else — Grammarly, Apple Notes, a browser tab.
        with open(os.path.join(review, f"{stem}-enhanced.md"), "w", encoding="utf-8") as fh:
            fh.write((e.get("enhanced") or "").strip() + "\n")
        with open(os.path.join(reference, f"{stem}-original.md"), "w", encoding="utf-8") as fh:
            fh.write((e.get("raw") or "").strip() + "\n")
        index.append(
            "\t".join([
                f"{i:04d}", e["id"],
                (e.get("timestamp") or "")[:10],
                e.get("hostname", "?"),
                e.get("enhancement_model") or "-",
                e.get("prompt_name") or "-",
                str(len((e.get("raw") or "").split())),
                str(len((e.get("enhanced") or "").split())),
            ])
        )

    with open(os.path.join(out, "index.tsv"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(index) + "\n")

    words = sum(len((e.get("enhanced") or "").split()) for e in usable)
    machines = len({e.get("hostname", "?") for e in usable})

    with open(os.path.join(out, "README.md"), "w", encoding="utf-8") as fh:
        fh.write(f"""# Dictation gold standard

Correcting these builds the benchmark that every enhancement model gets scored
against. Right now there is no ground truth, so "is model X better than Y" can
only be answered by eye.

## What to do

Work through **`EDIT-THESE/`**. Each file is Siloquy's AI cleanup of one
dictation. Correct it until it reads the way you would have written it, and save.
Grammarly, Apple Notes, any editor — all fine.

**`original-spoken/`** is the raw transcript of what you actually said. Read-only.
Check it whenever a sentence looks odd, so you correct toward what you *meant*
rather than just smoothing whatever the model produced.

Matching numbers are the same dictation:
`0001-a1b2c3d4-enhanced.md` ↔ `0001-a1b2c3d4-original.md`

## How many

**Around 70 is the target.** That is enough to prove a real difference between
two models at the rate they actually disagree on your dictation; below about 30
the run-to-run noise swamps the signal.

The files are ordered so **any prefix stays balanced** — alternating long and
short. Stop at 40, 70 or 120 and the set is still valid. No need to commit up
front.

Roughly 2 minutes each, so ~70 is a couple of hours. It does not have to be one
sitting.

## Rules

1. **Don't rename files.** The id in the filename is how edits are matched back.
2. **No headings, notes or markers** — just the corrected text.
3. **Leave a file alone if the cleanup is already right.** That is a result too,
   and a useful one. Don't feel obliged to change something in every file.
4. Long files matter most. If you are short on time, do those and skip the
   trivial ones.

## What to look for

The differences that matter are not only grammar:

- **Meaning changed.** The worst failure. One sample turned "so pink slip for
  that car" into "Please put a pink slip on that car".
- **Swearing softened or dropped.** "as hot as balls" lost its "as balls".
  Your prompt says keep it verbatim.
- **Voice flattened.** Hedges, "gonna", "mate", interjections quietly removed,
  or an informal message made formal.
- **Self-corrections left in.** "Tuesday, sorry, Wednesday" should just become
  "Wednesday".
- **Mis-transcriptions.** Words the recogniser got wrong that a human would fix
  from context.

A note on Grammarly: it is good on grammar but tends to formalise, which is the
opposite of what this prompt wants. Keep your voice.

## Contents

- **{len(usable)}** dictations, from {machines} machines
- **{words:,}** words to review
- `index.tsv` — id, date, machine, model, prompt and word counts
""")

    if args.combined:
        # One file, one heading per sample. The id line is the only thing that
        # must survive editing, so it is on its own line and clearly marked.
        parts = []
        for i, e in enumerate(usable, 1):
            parts.append(
                f"===== {i:04d}-{e['id']} =====\n"
                f"{(e.get('enhanced') or '').strip()}\n"
            )
        with open(os.path.join(out, "all-for-editing.md"), "w", encoding="utf-8") as fh:
            fh.write("\n".join(parts))

    print()
    print(f"  ✓ {len(usable)} files written ({words:,} words to review)")
    print(f"    EDIT THESE:  {review}")
    print(f"    reference:   {reference}  (read-only)")
    if args.combined:
        print(f"    single file: {os.path.join(out, 'all-for-editing.txt')}")
    print()
    print("  Edit the files in EDIT-THESE/ until each reads how you'd have written it.")
    print("  Keep the filenames unchanged — the id is how they're matched back.")


if __name__ == "__main__":
    main()
