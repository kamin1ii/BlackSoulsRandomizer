# Cuts the overlay borders out of the stream background so they are the same pixels as the scene frame
# python tools/build_frame.py <background png>
import sys
from pathlib import Path

from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "game" / "overlay"
CHAT_WINDOW = (1486, 38, 1892, 512)
TAB_WINDOW = (1488, 0, 1652, 40)
# a column inside the tab with no letters in it
TAB_CLEAR_COLUMN = 15


def is_frame(pixel):
    # every shade of the band has the same orange hue, the red checker and the grey inside do not
    r, g, b = pixel[:3]
    return r >= 20 and g >= r * 0.5 and b <= r * 0.42


def cut(source, window, name, cover_column=None):
    crop = source.crop(window).convert("RGBA")
    w, h = crop.size
    px = crop.load()
    originals = crop.copy().load()
    frame = {(x, y) for x in range(w) for y in range(h) if is_frame(px[x, y])}
    # a stray gold pixel outside is not part of the frame, keep the biggest connected piece
    best = set()
    left = set(frame)
    while left:
        start = left.pop()
        piece = {start}
        stack = [start]
        while stack:
            x, y = stack.pop()
            for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1), (x + 1, y + 1), (x - 1, y - 1), (x + 1, y - 1), (x - 1, y + 1)):
                if n in left:
                    left.remove(n)
                    piece.add(n)
                    stack.append(n)
        if len(piece) > len(best):
            best = piece
    outside = set()
    stack = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for x in (0, w - 1) for y in range(h)]
    while stack:
        p = stack.pop()
        if p in outside or p in best or not (0 <= p[0] < w and 0 <= p[1] < h):
            continue
        outside.add(p)
        x, y = p
        stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    for x in range(w):
        for y in range(h):
            if (x, y) in outside:
                px[x, y] = (0, 0, 0, 0)
            elif (x, y) not in best:
                # the big frame stays clear so the chat box art shows through, the tab has to hide its old label
                px[x, y] = originals[cover_column, y] if cover_column else (0, 0, 0, 0)
    box = crop.getbbox()
    crop.crop(box).save(OUT / name)
    print(name, "size", box[2] - box[0], box[3] - box[1], "at", window[0] + box[0], window[1] + box[1])


src = Image.open(sys.argv[1]).convert("RGBA")
cut(src, CHAT_WINDOW, "frame.png")
cut(src, TAB_WINDOW, "tab.png", TAB_CLEAR_COLUMN)
