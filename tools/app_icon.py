#!/usr/bin/env python3
"""App icons: a shooting journal with the Swiss A5 target.

    python3 tools/app_icon.py OUT_DIR

Writes {AppIcon,AppIconHardcover}{,-Dark,-Tinted}.svg (1024x1024):
AppIcon is the open journal (default), AppIconHardcover the closed notebook.
Deliberately no olive green / plain booklet, so it does not look like the
military Schiessbüchlein.
Render them to PNG (e.g. with a browser or rsvg-convert) and copy the PNGs into
Schiesstagebuch/Resources/Assets.xcassets/AppIcon.appiconset/.
"""
import os, sys

S = 1024
RED = "#D52B1E"
# Backgrounds: beige in light mode, navy in dark mode, black for tinted (grayscale).
BEIGE = ("#F1E6D2", "#DCC9A8")
NAVY = ("#2B3A55", "#18233A")
BLACK = ("#000000", "#000000")


def target(cx, cy, r, face, ink, hole, holes=((0.07, -0.05), (-0.12, 0.10), (0.20, 0.16)), rings=5):
    """Swiss A target (300 m, 100 cm): `rings` rings of equal width (A5: 5, A10: 10).
    The black aiming field is 60 cm across, i.e. rings 3-5 on the A5."""
    sw = 6.5
    black = r * 0.6
    out = [f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{face}"/>',
           f'<circle cx="{cx}" cy="{cy}" r="{black}" fill="{ink}"/>']
    for n in range(1, rings):
        rr = r * (rings - n) / rings
        if abs(rr - black) < 0.1:
            continue  # edge of the black field
        col = face if rr < black else ink
        out.append(f'<circle cx="{cx}" cy="{cy}" r="{rr:.1f}" fill="none" stroke="{col}" stroke-width="{sw}"/>')
    out.append(f'<circle cx="{cx}" cy="{cy}" r="{r - sw / 2}" fill="none" stroke="{ink}" stroke-width="{sw}"/>')
    for dx, dy in holes:
        out.append(f'<circle cx="{cx + dx * r:.1f}" cy="{cy + dy * r:.1f}" r="{r * 0.055:.1f}" '
                   f'fill="{hole}" stroke="{face}" stroke-width="{r * 0.018:.1f}"/>')
    return "".join(out)


def _svg(body, top, bottom):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">'
            f'<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{top}"/>'
            f'<stop offset="1" stop-color="{bottom}"/></linearGradient></defs>'
            f'<rect width="{S}" height="{S}" fill="url(#bg)"/>{body}</svg>')


def open_journal(p):
    b = (f'<path d="M120 270 Q120 240 150 240 H874 Q904 240 904 270 V860 Q904 890 874 890 H560 '
         f'Q512 890 512 900 Q512 890 464 890 H150 Q120 890 120 860 Z" fill="{p["cover"]}"/>'
         f'<path d="M512 230 C420 185 270 180 160 210 V830 C270 800 420 805 512 850 Z" fill="{p["face"]}"/>'
         f'<path d="M512 230 C604 185 754 180 864 210 V830 C754 800 604 805 512 850 Z" fill="{p["face"]}"/>')
    b += target(688, 515, 150, p["face"], p["ink"], p["hole"])
    for i in range(5):
        y = 330 + i * 92
        b += (f'<path d="M215 {y} C300 {y - 12} 390 {y - 12} 460 {y + 4}" fill="none" '
              f'stroke="{p["lines"]}" stroke-width="16" stroke-linecap="round"/>')
    b += '<path d="M512 232 V848" stroke="#00000030" stroke-width="12"/>'
    return _svg(b, *p["bg_open"])


def hardcover(p):
    b = (f'<rect x="232" y="150" width="590" height="740" rx="44" fill="{p["pages"]}"/>'
         f'<rect x="210" y="140" width="590" height="740" rx="44" fill="{p["cover"]}"/>'
         f'<rect x="210" y="140" width="70" height="740" rx="30" fill="{p["spine"]}"/>'
         f'<path d="M640 870 v110 l-30 -26 l-30 26 v-110 z" fill="{p["ribbon"]}"/>')
    b += target(505, 500, 195, p["face"], p["ink"], p["hole"])
    b += f'<rect x="730" y="140" width="34" height="740" fill="{p["band"]}"/>'
    return _svg(b, *p["bg_hard"])


PALETTES = {
    "": dict(bg_open=BEIGE, bg_hard=BEIGE, cover="#7A2E2A",
             spine="#5E2220", band="#3E1614", pages="#E9E4D6", face="#F4F1E8", ink="#141414",
             hole=RED, ribbon="#E3A230", lines="#9AA6B2"),
    "-Dark": dict(bg_open=NAVY, bg_hard=NAVY, cover="#6E2A26",
                  spine="#521F1C", band="#2E100F", pages="#5C584E", face="#D9D5CA", ink="#0D0D0D",
                  hole="#FF5A45", ribbon="#E3A230", lines="#7E8790"),
    # Tinted: grayscale on black; iOS maps luminance onto the user's tint colour.
    "-Tinted": dict(bg_open=BLACK, bg_hard=BLACK, cover="#4A4A4A",
                    spine="#383838", band="#222222", pages="#8A8A8A", face="#D0D0D0", ink="#000000",
                    hole="#FFFFFF", ribbon="#FFFFFF", lines="#A0A0A0"),
}

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    for suffix, p in PALETTES.items():
        for name, draw in (("AppIcon", open_journal), ("AppIconHardcover", hardcover)):
            with open(os.path.join(out, name + suffix + ".svg"), "w") as f:
                f.write(draw(p))
