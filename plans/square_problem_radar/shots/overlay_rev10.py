# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""Paste the new Problem Radar windows (2026-10-14 screenshots) over the old windows in the 2026-10-10 5K captures,
so the slides keep their map edges, titles and crops. Rects are the window surface (measured with winrect.py)."""
from PIL import Image, ImageDraw, ImageFilter
import numpy as np

S = "plans/square_problem_radar/shots/new/"  # the user's 2026-10-14 window screenshots (copied there to rerun)
P = "plans/square_problem_radar/shots/"
R = 26  # corner radius of the window surface at 5K
CW, CH = 150, 150  # top-right corner box: the frame curves around the close button there (map shows in the notch)

def ui_mask(rgb):
    """255 where a pixel of the new screenshot is window UI (dark grey frame, the blue-grey close button, the white
    cross), 0 where it is the map seen through the notch around the close button."""
    a = np.asarray(rgb).astype(int)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    hi, lo = a.max(axis=2), a.min(axis=2)
    grey = (hi - lo < 14) & (hi < 110)
    button = (b > r + 12) & (b >= g) & (b > 60)
    white = lo > 170
    m = Image.fromarray(((grey | button | white) * 255).astype(np.uint8))
    return m.filter(ImageFilter.GaussianBlur(0.8))

def rounded_mask(w, h, r):
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w - 1, h - 1], r, fill=255)
    return m

def paste(old_file, new_file, out_file, new_rect, old_xy, old_bottom=None):
    old = Image.open(P + old_file).convert("RGB")
    new = Image.open(S + new_file).convert("RGB")
    x0, y0, x1, y1 = new_rect
    w, h = x1 - x0 + 1, y1 - y0 + 1
    ox, oy = old_xy
    if old_bottom is not None and old_bottom > oy + h - 1:
        # the new window is shorter: move the old window's bottom edge (frame, corners, map below) up to it
        band_top = old_bottom - 40
        band = old.crop((ox - 60, band_top, ox + w + 60, old_bottom + 80))
        old.paste(band, (ox - 60, oy + h - 1 - 40))
    # inset by I px: the old frame edge stays (no new-map rim); keep the old top-right corner (close button and
    # its notch, identical because the window widths match)
    I = 3
    win = new.crop((x0 + I, y0 + I, x1 + 1 - I, y1 + 1 - I))
    mask = rounded_mask(w - 2 * I, h - 2 * I, R)
    # top-right corner: new UI pixels only, the old map in the notch
    cw = w - 2 * I
    corner = win.crop((cw - CW, 0, cw, CH))
    mask.paste(Image.fromarray(np.minimum(np.asarray(ui_mask(corner)), np.asarray(mask.crop((cw - CW, 0, cw, CH))))), (cw - CW, 0))
    old.paste(win, (ox + I, oy + I), mask)
    old.save(P + out_file, quality=95)
    print(out_file, "window at", (ox, oy, w, h))

paste("01-all-tab.jpg", "new-all.jpg", "11-all-tab.jpg", (18, 44, 2979, 1407), (1080, 690))
paste("06-snoozed.jpg", "new-snoozed.jpg", "16-snoozed.jpg", (28, 36, 2989, 1399), (1080, 690))
paste("07-settings.jpg", "new-settings.jpg", "17-settings.jpg", (60, 48, 3021, 1411), (1080, 690))
paste("03-fleet-window-trucks.jpg", "new-fleet.jpg", "13-fleet-window.jpg", (78, 72, 2091, 1185), (2066, 674), old_bottom=2065)
