## Windows: draw terminal text with grayscale antialiasing

### Problem

Terminal text looked sharper and more jagged than the rest of the app, with coloured fringes around the letters. It's most visible on Windows 10 at 100% scaling.

The xterm WebGL renderer rasterizes glyphs into an opaque texture atlas, so Chromium uses ClearType (sub-pixel) antialiasing for them. The WinUI text around the terminal uses grayscale smoothing.

### Change

`allowTransparency: true` in the xterm options (`windows/tools/terminal-assets/terminal.js`):

- The glyph atlas gets an alpha channel, so glyphs are drawn with grayscale antialiasing, matching the rest of the app and the Mac.
- The page background already paints the theme colour, so the terminal looks the same otherwise.

The bundle (`Assets/terminal/terminal.js`) was rebuilt with the pinned toolchain (`npm ci --ignore-scripts`, `node build.mjs`). Rebuilding the unchanged source first reproduced the committed bundle byte for byte, so this option is the only change in the bundle.

### How it was tested

This was tested on Windows 10 22H2 (19045) at 100% scaling with a Debug x64 build. In magnified screenshots of the same terminal text, the letters have coloured fringes before the change and grey edges after it.

Not tested: Windows 11, scaling above 100%.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
