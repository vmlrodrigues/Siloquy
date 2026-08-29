#!/usr/bin/env python3
"""Export raw Siloquy dictation history to a single portable JSON file.

Run this on any Mac that has Siloquy history:

    python3 export-dictation-history.py

It writes ~/Desktop/siloquy-history-<hostname>-<date>.json, which you then copy
back to the machine where the analysis runs.

Deliberately dependency-free: uses only the Python standard library, which ships
with macOS. Nothing to install, nothing to configure.

Safe by construction:
  • Reads a *copy* of the database (with its -wal), never the live file, so a
    running Siloquy is untouched and never needs to be quit.
  • Read-only. Never writes to, modifies, or deletes app data.
  • Exports transcript text only — no audio, no API keys, no settings.

The export contains your raw dictation. Treat it like any other private
document: move it between machines with AirDrop, a USB stick, or iCloud Drive —
not email or a chat app.
"""

import hashlib
import json
import os
import shutil
import sqlite3
import socket
import sys
import tempfile
from datetime import datetime, timezone

# Core Data stores its timestamps as seconds since 2001-01-01 (Apple epoch).
APPLE_EPOCH_OFFSET = 978307200

CANDIDATE_DIRS = [
    "~/Library/Application Support/com.victorrodrigues.siloquy",
    "~/Library/Application Support/com.victorrodrigues.siloquy.dev",
    "~/Library/Application Support/com.prakashjoshipax.VoiceInk",  # pre-fork installs
]


def find_stores():
    """Every Siloquy/VoiceInk store on this machine, newest data first."""
    found = []
    for d in CANDIDATE_DIRS:
        path = os.path.join(os.path.expanduser(d), "default.store")
        if os.path.exists(path):
            found.append(path)
    return found


def copy_store(path, workdir):
    """Copy the store and its sidecars so we never read the live database.

    The -wal file holds recent writes that haven't been checkpointed yet; without
    it the copy silently misses the newest dictations.
    """
    dest = os.path.join(workdir, "copy.store")
    shutil.copy2(path, dest)
    for suffix in ("-wal", "-shm"):
        side = path + suffix
        if os.path.exists(side):
            shutil.copy2(side, dest + suffix)
    return dest


def make_id(raw, timestamp):
    """Stable 8-char id derived from the dictation itself.

    Content-derived rather than sequential so it survives re-exporting, is
    identical on every machine that holds the same dictation, and lets the
    edited files be matched back without keeping a separate ledger.
    """
    basis = f"{(raw or '').strip()}|{timestamp or ''}"
    return hashlib.sha256(basis.encode("utf-8")).hexdigest()[:8]


def read_entries(store_path, source_label):
    conn = sqlite3.connect(f"file:{store_path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    try:
        cols = {r["name"] for r in conn.execute("PRAGMA table_info(ZTRANSCRIPTION)")}
    except sqlite3.DatabaseError as exc:
        print(f"    ! unreadable ({exc}) — skipping", file=sys.stderr)
        return []
    if not cols:
        return []

    def col(name, default="NULL"):
        return name if name in cols else default

    query = f"""
        SELECT {col('ZTEXT')}                    AS raw,
               {col('ZENHANCEDTEXT')}            AS enhanced,
               {col('ZTIMESTAMP')}               AS ts,
               {col('ZAIENHANCEMENTMODELNAME')}  AS model,
               {col('ZPROMPTNAME')}              AS prompt,
               {col('ZTRANSCRIPTIONMODELNAME')}  AS asr,
               {col('ZDURATION')}                AS duration
        FROM ZTRANSCRIPTION
        WHERE {col('ZTEXT')} IS NOT NULL AND length({col('ZTEXT')}) > 0
        ORDER BY {col('ZTIMESTAMP')}
    """
    out = []
    for row in conn.execute(query):
        ts = row["ts"]
        iso = None
        if ts:
            iso = datetime.fromtimestamp(
                ts + APPLE_EPOCH_OFFSET, tz=timezone.utc
            ).isoformat()
        out.append(
            {
                "id": make_id(row["raw"], iso),
                "raw": row["raw"],
                "enhanced": row["enhanced"],
                "timestamp": iso,
                "enhancement_model": row["model"],
                "prompt_name": row["prompt"],
                "asr_model": row["asr"],
                "duration": row["duration"],
                "source": source_label,
            }
        )
    conn.close()
    return out


def main():
    stores = find_stores()
    if not stores:
        print("No Siloquy history found on this machine.", file=sys.stderr)
        print("Looked in:", file=sys.stderr)
        for d in CANDIDATE_DIRS:
            print(f"  {os.path.expanduser(d)}", file=sys.stderr)
        sys.exit(1)

    host = socket.gethostname().split(".")[0]
    entries = []

    workdir = tempfile.mkdtemp(prefix="siloquy-export-")
    try:
        for path in stores:
            label = os.path.basename(os.path.dirname(path))
            print(f"  reading {label}…")
            try:
                entries.extend(read_entries(copy_store(path, workdir), label))
            except Exception as exc:  # keep going; one bad store shouldn't lose the rest
                print(f"    ! failed ({exc}) — skipping", file=sys.stderr)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

    # Same dictation can appear in both the dev and release stores; the id is
    # content-derived, so it doubles as the dedupe key here and across machines.
    seen, unique = set(), []
    for e in entries:
        if e["id"] not in seen:
            seen.add(e["id"])
            unique.append(e)

    payload = {
        "schema": 1,
        "hostname": host,
        "exported_at": datetime.now(timezone.utc).isoformat(),
        "count": len(unique),
        "entries": unique,
    }

    stamp = datetime.now().strftime("%Y-%m-%d")
    out_path = os.path.expanduser(f"~/Desktop/siloquy-history-{host}-{stamp}.json")
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=1)

    words = sum(len((e["raw"] or "").split()) for e in unique)
    dates = sorted(e["timestamp"][:10] for e in unique if e["timestamp"])
    enhanced = sum(1 for e in unique if e["enhanced"])

    print()
    print(f"  ✓ {len(unique)} dictations ({words:,} words)")
    if dates:
        print(f"    {dates[0]} → {dates[-1]}")
    print(f"    {enhanced} already have enhanced text")
    print(f"    duplicates skipped: {len(entries) - len(unique)}")
    print()
    print(f"  Written to: {out_path}")
    print("  Copy that file to the analysis Mac (AirDrop / USB / iCloud Drive).")


if __name__ == "__main__":
    main()
