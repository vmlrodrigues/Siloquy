# Troubleshooting

How to diagnose a Siloquy crash, an unexpected quit, or a dictation that
"just disappeared" — and what to collect so it can be debugged.

---

## 1. First: did it actually crash?

Siloquy is a **menu-bar app**, so the recorder window (or a single dictation) can
vanish while the app keeps running. Before assuming a crash:

- **Look for the Siloquy icon in the menu bar.**
  - **Still there** → the app didn't die. A dictation that produced no output is a
    *paste or pipeline* problem, not a crash — skip to
    [§4 Capture the unified log](#4-capture-the-unified-log-the-main-tool).
  - **Gone** → the app terminated. Continue below.

---

## 2. Grab the crash report (if there is one)

A genuine fault — segfault, Swift `fatalError`/precondition, or an uncaught
exception — writes a report to `~/Library/Logs/DiagnosticReports/`.

**Terminal:**
```bash
ls -t ~/Library/Logs/DiagnosticReports/Siloquy* /Library/Logs/DiagnosticReports/Siloquy* 2>/dev/null | head -3
cat "$(ls -t ~/Library/Logs/DiagnosticReports/Siloquy*.ips 2>/dev/null | head -1)"
```

**Or Console.app:** open **Console** → sidebar **Crash Reports** → newest
**Siloquy** entry → ⌘A, ⌘C.

The stack trace of the crashed thread (near the top) is what pinpoints the cause.

---

## 3. No crash report? That's a clue, not a dead end

An app can terminate **without** a standard crash report when it:

- **Exits cleanly** — some error path calls `exit()` / `NSApp.terminate`. Looks like
  a normal quit; no `.ips` is written.
- **Is hard-killed** — SIGKILL / force-quit / a watchdog. Can't be caught; often no
  report.
- **Is jetsammed** — killed under memory pressure. Writes a different kind of report,
  or none you'll notice.

So a **missing** report actually suggests it wasn't a hard crash — which is exactly
where the unified log earns its keep.

---

## 4. Capture the unified log (the main tool)

macOS keeps a rolling unified log of everything the process did up to the moment it
stopped. It **ages out**, so capture it around the event.

### A. Reactive — right after it happens (within the hour)
```bash
/usr/bin/log show --last 30m --predicate 'process == "Siloquy"' --info --debug > ~/Desktop/siloquy-log.txt 2>&1
open -R ~/Desktop/siloquy-log.txt
```

### B. Live — record while you reproduce it
Leave this running in a Terminal window and use the app normally:
```bash
/usr/bin/log stream --predicate 'process == "Siloquy"' --info --debug > ~/Desktop/siloquy-live.log 2>&1
```
When it misbehaves, note the time, press **Ctrl-C**, and keep the file. This captures
the app's last words before it vanished — a self-exit, a caught error mid-dictation,
or an external kill.

> Always use the full path `/usr/bin/log`. Under zsh, `log` alone is a shell builtin
> that shadows it.

---

## 5. One-shot collection

Grabs the version, macOS, the latest crash report, and recent filtered logs into a
single file on the Desktop:

```bash
OUT=~/Desktop/siloquy-crash.txt
{
  echo "### version + macOS"
  defaults read /Applications/Siloquy.app/Contents/Info CFBundleShortVersionString 2>/dev/null
  sw_vers
  echo; echo "### latest crash report"
  CRASH=$(ls -t ~/Library/Logs/DiagnosticReports/Siloquy* /Library/Logs/DiagnosticReports/Siloquy* 2>/dev/null | head -1)
  echo "file: $CRASH"; cat "$CRASH" 2>/dev/null
  echo; echo "### Siloquy logs, last 20 min (filtered)"
  /usr/bin/log show --last 20m --predicate 'process == "Siloquy"' --info --debug 2>/dev/null \
    | grep -iE "siloquy|coredata|cloudkit|backfill|migrat|fatal|precondition|exception|abort|error" | tail -200
} > "$OUT" 2>&1
open -R "$OUT"
```

---

## 6. What to include when reporting

- Siloquy **version** and **macOS version** (`sw_vers`)
- Whether it **crashed** (menu-bar icon gone) or **disappeared** (icon still there)
- The **crash report** (if any) and the **captured log**
- What you were doing when it happened — mid-dictation, right after updating, on launch
