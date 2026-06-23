#!/usr/bin/env python3
"""Prepend a new release entry to appcast.xml.

Usage: update_appcast.py VERSION ED_SIGNATURE LENGTH

Called automatically by `make release`. Release notes are embedded *inline* as
HTML, rendered from the matching `### <version>` section of CHANGES.md, so
Sparkle's updater shows clean formatted notes — NOT a rendered GitHub web page
(which is what a `sparkle:releaseNotesLink` to a GitHub URL produces).
"""
import sys
import os
import re
import html
from datetime import datetime, timezone


def _inline(text):
    """Escape HTML, then turn `code` spans into <code>…</code>."""
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", html.escape(text))


def _extract_section(version, changes_path):
    """Return the body lines of the `### <version>` section of CHANGES.md, or None."""
    try:
        with open(changes_path) as f:
            lines = f.read().splitlines()
    except OSError:
        return None
    body, in_section = [], False
    for line in lines:
        if line.startswith("### "):
            if in_section:
                break  # reached the next version
            tokens = line[4:].split()
            if tokens and tokens[0] == version:
                in_section = True
            continue
        if in_section:
            if line.startswith("---"):
                break  # section separator
            body.append(line)
    return body if in_section else None


def render_notes_html(version, changes_path):
    """Build the inline release-notes HTML embedded in the appcast <description>.

    Renders the version's CHANGES.md section: `#### X` -> <h3>, `- y` (with
    wrapped continuation lines) -> <li>, `` `code` `` -> <code>.
    """
    body = _extract_section(version, changes_path)
    parts, in_list, bullet = [], False, None

    def flush():
        nonlocal bullet
        if bullet is not None:
            parts.append(f"      <li>{_inline(bullet.strip())}</li>")
            bullet = None

    for line in (body or []):
        s = line.strip()
        if s.startswith("#### "):
            flush()
            if in_list:
                parts.append("    </ul>")
                in_list = False
            parts.append(f"    <h3>{_inline(s[5:].strip())}</h3>")
        elif s.startswith("- "):
            flush()
            if not in_list:
                parts.append("    <ul>")
                in_list = True
            bullet = s[2:]
        elif s == "":
            flush()
        elif bullet is not None:
            bullet += " " + s  # continuation of the current bullet
    flush()
    if in_list:
        parts.append("    </ul>")

    body_html = "\n".join(parts) if parts else "    <p>See the changelog for details.</p>"

    return (
        "\n"
        "    <style>\n"
        "      body { background:#fff; color:#1d1d1f; margin:0; padding:14px 16px;\n"
        "             font:13px/1.5 -apple-system, system-ui, sans-serif; }\n"
        "      h2 { font-size:1.6em; font-weight:700; color:#0a84ff; margin:0 0 .4em; }\n"
        "      h3 { font-size:.8em; font-weight:700; text-transform:uppercase;\n"
        "           letter-spacing:.05em; color:#86868b; margin:1.1em 0 .35em; }\n"
        "      ul { margin:.2em 0 .9em; padding-left:1.25em; }\n"
        "      li { margin:.35em 0; }\n"
        "      code { font-family:ui-monospace, SFMono-Regular, monospace; font-size:.88em;\n"
        "             background:#f0f0f2; padding:.08em .35em; border-radius:4px; }\n"
        "    </style>\n"
        f"    <h2>{html.escape(version)}</h2>\n"
        f"{body_html}\n"
    )


def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} VERSION ED_SIGNATURE LENGTH", file=sys.stderr)
        sys.exit(1)

    version, ed_sig, length = sys.argv[1], sys.argv[2], sys.argv[3]
    pub_date = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")

    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    download_url = (
        f"https://github.com/vmlrodrigues/Siloquy/releases/download/v{version}/Siloquy.dmg"
    )

    notes_html = render_notes_html(version, os.path.join(repo_root, "CHANGES.md"))
    # Guard against the (very unlikely) CDATA terminator appearing in the notes.
    notes_html = notes_html.replace("]]>", "]]]]><![CDATA[>")

    item = (
        f"        <item>\n"
        f"            <title>Siloquy {version}</title>\n"
        f"            <pubDate>{pub_date}</pubDate>\n"
        f"            <sparkle:version>{version}</sparkle:version>\n"
        f"            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>\n"
        f"            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>\n"
        f"            <description><![CDATA[{notes_html}            ]]></description>\n"
        f"            <enclosure\n"
        f'                url="{download_url}"\n'
        f'                sparkle:edSignature="{ed_sig}"\n'
        f'                length="{length}"\n'
        f'                type="application/octet-stream"/>\n'
        f"        </item>"
    )

    appcast_path = os.path.join(repo_root, "appcast.xml")
    with open(appcast_path) as f:
        content = f.read()

    # Prepend before the first <item>, or before </channel> if the feed is empty.
    if "<item>" in content:
        content = content.replace("<item>", item + "\n        <item>", 1)
    else:
        content = content.replace("    </channel>", item + "\n    </channel>")

    with open(appcast_path, "w") as f:
        f.write(content)

    print(f"  ✓ appcast.xml updated with v{version} (inline release notes)")


if __name__ == "__main__":
    main()
