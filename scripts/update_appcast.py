#!/usr/bin/env python3
"""Prepend a new release entry to appcast.xml.

Usage: update_appcast.py VERSION ED_SIGNATURE LENGTH

Called automatically by `make release`. The download URL and release notes
link are derived from the version using the standard GitHub Releases pattern.
"""
import sys
import os
from datetime import datetime, timezone


def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} VERSION ED_SIGNATURE LENGTH", file=sys.stderr)
        sys.exit(1)

    version, ed_sig, length = sys.argv[1], sys.argv[2], sys.argv[3]

    pub_date = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")

    download_url = (
        f"https://github.com/vmlrodrigues/Siloquy/releases/download/"
        f"v{version}/Siloquy.dmg"
    )
    release_notes_url = f"https://github.com/vmlrodrigues/Siloquy/releases/tag/v{version}"

    item = (
        f"        <item>\n"
        f"            <title>Siloquy {version}</title>\n"
        f"            <pubDate>{pub_date}</pubDate>\n"
        f"            <sparkle:version>{version}</sparkle:version>\n"
        f"            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>\n"
        f"            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>\n"
        f"            <sparkle:releaseNotesLink>{release_notes_url}</sparkle:releaseNotesLink>\n"
        f"            <enclosure\n"
        f"                url=\"{download_url}\"\n"
        f"                sparkle:edSignature=\"{ed_sig}\"\n"
        f"                length=\"{length}\"\n"
        f"                type=\"application/octet-stream\"/>\n"
        f"        </item>"
    )

    appcast_path = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "appcast.xml",
    )

    with open(appcast_path) as f:
        content = f.read()

    # Prepend before any existing <item>, or before </channel> if feed is empty.
    if "<item>" in content:
        content = content.replace("<item>", item + "\n        <item>", 1)
    else:
        content = content.replace("    </channel>", item + "\n    </channel>")

    with open(appcast_path, "w") as f:
        f.write(content)

    print(f"  ✓ appcast.xml updated with v{version}")


if __name__ == "__main__":
    main()
