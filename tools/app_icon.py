#!/usr/bin/env python3
"""App icon: a desk calendar page with the Swiss A10 target on it.

    python3 tools/app_icon.py OUT_DIR

Writes AppIcon.svg, AppIcon-Dark.svg and AppIcon-Tinted.svg (1024x1024).
Render them to PNG (e.g. with a browser or rsvg-convert) and copy the PNGs into
Schiesstagebuch/Resources/Assets.xcassets/AppIcon.appiconset/.
"""
import os, sys

S = 1024
RED = "#D52B1E"


def target(cx, cy, r, face, ink, hole, holes=((0.07, -0.05), (-0.12, 0.10), (0.20, 0.16))):
    """A10: ten rings of equal width; the black aiming field covers rings 5-10."""
    sw = 5.5
    black = r * 0.6
    out = [f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{face}"/>',
           f'<circle cx="{cx}" cy="{cy}" r="{black}" fill="{ink}"/>']
    for n in (1, 2, 3, 5, 6, 7, 8):  # ring lines (4 is the edge of the black field)
        rr = r * (10 - n) / 10
        col = face if rr < black - 0.1 else ink
        out.append(f'<circle cx="{cx}" cy="{cy}" r="{rr:.1f}" fill="none" stroke="{col}" stroke-width="{sw}"/>')
    out.append(f'<circle cx="{cx}" cy="{cy}" r="{r * 0.1:.1f}" fill="none" stroke="{face}" stroke-width="{sw}"/>')
    out.append(f'<circle cx="{cx}" cy="{cy}" r="{r - sw / 2}" fill="none" stroke="{ink}" stroke-width="{sw}"/>')
    for dx, dy in holes:
        out.append(f'<circle cx="{cx + dx * r:.1f}" cy="{cy + dy * r:.1f}" r="{r * 0.055:.1f}" '
                   f'fill="{hole}" stroke="{face}" stroke-width="{r * 0.018:.1f}"/>')
    return "".join(out)


def icon(bg_top, bg_bottom, page, header, binder, face, ink, hole):
    x, y, w, h, rad, head = 172, 200, 680, 680, 96, 180
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">',
        f'<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{bg_top}"/><stop offset="1" stop-color="{bg_bottom}"/></linearGradient></defs>',
        f'<rect width="{S}" height="{S}" fill="url(#bg)"/>',
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rad}" fill="{page}"/>',
        f'<path d="M{x} {y + rad} a{rad} {rad} 0 0 1 {rad} -{rad} h{w - 2 * rad} a{rad} {rad} 0 0 1 {rad} {rad} '
        f'v{head - rad} h-{w} z" fill="{header}"/>',
    ]
    for bx in (x + w * 0.25, x + w * 0.75):
        parts.append(f'<rect x="{bx - 16}" y="{y - 64}" width="32" height="124" rx="16" fill="{binder}"/>')
    parts.append(target(512, 630, 232, face, ink, hole))
    parts.append("</svg>")
    return "".join(parts)


VARIANTS = {
    "AppIcon": dict(bg_top="#33402F", bg_bottom="#1B241A", page="#F4F1E8", header=RED,
                    binder="#2A2A2A", face="#F4F1E8", ink="#141414", hole=RED),
    # Dark: near-black background, dimmed page, same red so it stays recognisable.
    "AppIcon-Dark": dict(bg_top="#1C1F1B", bg_bottom="#0A0B0A", page="#2C2E2B", header="#E0402F",
                         binder="#8A8A8A", face="#D9D5CA", ink="#0D0D0D", hole="#FF5A45"),
    # Tinted: grayscale on black; iOS maps luminance onto the user's tint colour.
    "AppIcon-Tinted": dict(bg_top="#000000", bg_bottom="#000000", page="#5A5A5A", header="#FFFFFF",
                           binder="#9A9A9A", face="#D0D0D0", ink="#000000", hole="#FFFFFF"),
}

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    for name, v in VARIANTS.items():
        with open(os.path.join(out, name + ".svg"), "w") as f:
            f.write(icon(**v))
