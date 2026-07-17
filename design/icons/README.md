# App icon sources

`siloquy-icon.svg` — the app icon. `siloquy-icon-dev.svg` — the DEV-banded
variant for local builds. Regenerate the macOS icon sets (16–1024) with:

    for s in 16 32 64 128 256 512 1024; do
      rsvg-convert -w $s -h $s design/icons/siloquy-icon.svg \
        -o Siloquy/Assets.xcassets/AppIcon.appiconset/$s-mac.png
      rsvg-convert -w $s -h $s design/icons/siloquy-icon-dev.svg \
        -o Siloquy/Assets.xcassets/AppIcon-Dev.appiconset/$s-mac.png
    done

(needs `rsvg-convert`: `brew install librsvg`)
