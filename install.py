"""Adds the randomizer to a copy of BLACK SOULS. Seed and options are set on the game's title screen."""
import json
import os
import random
import re
import shutil
import struct
import sys
import zlib
from pathlib import Path

SCRIPTS_NAME = "Data/Scripts.rvdata2"
MOD_SCRIPT_TITLE = "Randomizer"
BUNDLE = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent))
VERSION = re.search(r'VERSION = "([^"]+)"', (BUNDLE / "game" / "rando.rb").read_text(encoding="utf-8")).group(1)


def read_archive(archive):
    raw = Path(archive).read_bytes()
    if raw[:8] != b"RGSSAD\x00\x03":
        raise ValueError("Game.rgss3a is not an RGSS3 archive")
    seed = struct.unpack_from("<I", raw, 8)[0]
    key = (seed * 9 + 3) & 0xFFFFFFFF
    kb = struct.pack("<I", key)
    entries = []
    pos = 12
    while True:
        offset, size, file_key, name_len = (v ^ key for v in struct.unpack_from("<4I", raw, pos))
        pos += 16
        if offset == 0:
            break
        name = bytes(b ^ kb[i % 4] for i, b in enumerate(raw[pos:pos + name_len]))
        pos += name_len
        entries.append([name, file_key, raw[offset:offset + size]])
    return seed, entries


def write_archive(path, seed, entries):
    key = (seed * 9 + 3) & 0xFFFFFFFF
    kb = struct.pack("<I", key)
    offset = 12 + sum(16 + len(name) for name, _, _ in entries) + 16
    with open(path, "wb") as f:
        f.write(b"RGSSAD\x00\x03" + struct.pack("<I", seed))
        for name, file_key, blob in entries:
            f.write(struct.pack("<4I", offset ^ key, len(blob) ^ key, file_key ^ key, len(name) ^ key))
            f.write(bytes(b ^ kb[i % 4] for i, b in enumerate(name)))
            offset += len(blob)
        f.write(struct.pack("<4I", key, key, key, key))
        for _, _, blob in entries:
            f.write(blob)


def decrypt(data, key):
    out = bytearray(len(data))
    padded = data + bytes(-len(data) % 4)
    for i in range(0, len(padded), 4):
        (word,) = struct.unpack_from("<I", padded, i)
        n = min(4, len(data) - i)
        out[i:i + n] = struct.pack("<I", word ^ key)[:n]
        key = (key * 7 + 3) & 0xFFFFFFFF
    return bytes(out)


class Reader:
    def __init__(self, data):
        self.d = data
        self.p = 2
        self.syms = []

    def byte(self):
        b = self.d[self.p]
        self.p += 1
        return b

    def long(self):
        c = struct.unpack_from("b", self.d, self.p)[0]
        self.p += 1
        if c == 0:
            return 0
        if 5 <= c <= 127:
            return c - 5
        if -128 <= c <= -5:
            return c + 5
        n = abs(c)
        v = int.from_bytes(self.d[self.p:self.p + n], "little")
        self.p += n
        return v if c > 0 else v - (1 << (8 * n))

    def raw(self):
        n = self.long()
        b = self.d[self.p:self.p + n]
        self.p += n
        return b

    def sym(self):
        t = chr(self.byte())
        if t == ":":
            s = self.raw().decode("utf-8", "replace")
            self.syms.append(s)
            return s
        if t == ";":
            return self.syms[self.long()]
        raise ValueError("unexpected symbol type " + t)

    def read(self):
        t = chr(self.byte())
        if t == "i":
            return self.long()
        if t == "I":
            v = self.read()
            for _ in range(self.long()):
                self.sym()
                self.read()
            return v
        if t == '"':
            return self.raw()
        if t == "[":
            return [self.read() for _ in range(self.long())]
        if t in "TF0":
            return {"T": True, "F": False, "0": None}[t]
        raise ValueError("unexpected marshal type " + t)


def w_long(n):
    if n == 0:
        return b"\x00"
    if 0 < n < 123:
        return struct.pack("b", n + 5)
    if -124 < n < 0:
        return struct.pack("b", n - 5)
    for size in range(1, 5):
        if 0 < n < (1 << (8 * size)):
            return struct.pack("b", size) + n.to_bytes(size, "little")
        if -(1 << (8 * size)) <= n < 0:
            return struct.pack("b", -size) + (n + (1 << (8 * size))).to_bytes(size, "little")
    raise ValueError("number too large")


def dump_scripts(scripts):
    out = bytearray(b"\x04\x08[") + w_long(len(scripts))
    sym_written = False

    def utf8(value):
        nonlocal sym_written
        part = b'I"' + w_long(len(value)) + value + w_long(1)
        part += b";" + w_long(0) if sym_written else b":" + w_long(1) + b"E"
        sym_written = True
        return part + b"T"

    for sid, name, code in scripts:
        out += b"[" + w_long(3)
        out += b"i" + w_long(sid) if isinstance(sid, int) else utf8(sid)
        out += utf8(name)
        out += b'"' + w_long(len(code)) + code
    return bytes(out)


def mod_source():
    parts = [(BUNDLE / "game" / name).read_text(encoding="utf-8") for name in ("rando_pad.rb", "rando_data.rb", "rando.rb", "rando_overlay.rb", "rando_window.rb")]
    return "\n".join(parts)


def build_scripts(original, source):
    scripts = [e for e in Reader(original).read() if e[1] != MOD_SCRIPT_TITLE.encode()]
    entry = [str(random.randint(10000000, 99999999)).encode(), MOD_SCRIPT_TITLE.encode(),
             zlib.compress(source.replace("\r\n", "\n").encode("utf-8"))]
    # right before Main so every game script is already loaded
    scripts.insert(len(scripts) - 1, entry)
    return dump_scripts(scripts)


def find_game_root(folder):
    folder = Path(folder)
    if (folder / "Game.rgss3a").exists():
        return folder
    for child in folder.iterdir():
        if child.is_dir() and (child / "Game.rgss3a").exists():
            return child
    raise FileNotFoundError(f"No Game.rgss3a in {folder}, pick the folder that holds Game.exe")


def install_overlay(target, entries, log):
    """Copies the stream overlay next to the game and the walking sprites its cards draw."""
    folder = target / "Randomizer" / "overlay"
    (folder / "reveals.html").unlink(missing_ok=True)
    shutil.copytree(BUNDLE / "game" / "overlay", folder, dirs_exist_ok=True)
    (folder / "img").mkdir(exist_ok=True)
    text = (folder / "sprites.js").read_text(encoding="utf-8")
    sprites = json.loads(text.split("=", 1)[1].strip().rstrip(";"))
    wanted = {"Graphics/Characters/" + info["sheet"] + ".png": info["file"] for info in sprites.values()}
    for name, file_key, blob in entries:
        out = wanted.pop(name.decode("utf-8").replace("\\", "/"), None)
        if out:
            (folder / "img" / out).write_bytes(decrypt(blob, file_key))
    # sheets the game borrows from the RPG Maker runtime are not in its archive
    for name, out in wanted.items():
        for root in (target, rtp_folder()):
            if root and (root / name).is_file():
                shutil.copy2(root / name, folder / "img" / out)
                break
        else:
            log(f"Could not find {name} for the overlay")
    log(f"Stream overlay in {folder}")


def rtp_folder():
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Enterbrain\RGSS3\RTP") as key:
            return Path(winreg.QueryValueEx(key, "RPGVXAce")[0])
    except OSError:
        default = Path(r"C:\Program Files (x86)\Common Files\Enterbrain\RGSS3\RPGVXAce")
        return default if default.is_dir() else None


def install_sharp(target, log):
    """The engine smooths the picture when the window is bigger, this dll keeps the pixels sharp. Delete it to go back."""
    (target / "Randomizer").mkdir(exist_ok=True)
    # an earlier version tried this with a d3d9.dll the engine never loads
    (target / "d3d9.dll").unlink(missing_ok=True)
    shutil.copy2(BUNDLE / "game" / "sharp" / "rando_sharp.dll", target / "Randomizer" / "rando_sharp.dll")
    shutil.copytree(BUNDLE / "game" / "upscale", target / "Randomizer" / "upscale", dirs_exist_ok=True)
    log("Sharp window scaling added")


def update(target, log=print):
    """Swaps the mod inside an installed copy and leaves every other file in its archive alone, censor edits stay."""
    target = Path(target)
    archive = target / "Game.rgss3a"
    seed, entries = read_archive(archive)
    for entry in entries:
        name, file_key, blob = entry
        if name.decode("utf-8").replace("\\", "/") == SCRIPTS_NAME:
            entry[2] = decrypt(build_scripts(decrypt(blob, file_key), mod_source()), file_key)
            break
    else:
        raise FileNotFoundError(SCRIPTS_NAME)
    write_archive(archive.with_name(archive.name + ".tmp"), seed, entries)
    os.replace(archive.with_name(archive.name + ".tmp"), archive)
    install_overlay(target, entries, log)
    install_sharp(target, log)
    log(f"Updated to version {VERSION}")


def install(source, target=None, log=print):
    source = find_game_root(source)
    target = Path(target) if target else source.parent / (source.name + " Randomizer")
    if source.resolve() == target.resolve():
        raise ValueError("Pick a different folder for the randomizer copy, your normal game stays as it is")

    def skip_saves(_dir, names):
        return [n for n in names if n.lower().startswith("save") and ".rvdata2" in n.lower()]

    log(f"Copying the game to {target}")
    shutil.copytree(source, target, ignore=skip_saves, dirs_exist_ok=True)
    log("Adding the randomizer script")
    seed, entries = read_archive(source / "Game.rgss3a")
    for entry in entries:
        name, file_key, blob = entry
        if name.decode("utf-8").replace("\\", "/") == SCRIPTS_NAME:
            entry[2] = decrypt(build_scripts(decrypt(blob, file_key), mod_source()), file_key)
            break
    else:
        raise FileNotFoundError(SCRIPTS_NAME)
    write_archive(target / "Game.rgss3a.tmp", seed, entries)
    os.replace(target / "Game.rgss3a.tmp", target / "Game.rgss3a")
    (target / "Randomizer").mkdir(exist_ok=True)
    install_overlay(target, entries, log)
    install_sharp(target, log)
    log(f"Done, version {VERSION}. Start {target / 'Game.exe'} and open Randomizer Options on the title screen.")
    return target


def gui():
    import threading
    import tkinter as tk
    from tkinter import filedialog, messagebox

    root = tk.Tk()
    root.title(f"BLACK SOULS Randomizer v{VERSION}")
    root.resizable(False, False)
    path = tk.StringVar()
    status = tk.StringVar(value="Pick your BLACK SOULS folder. Your normal game and saves are not touched.")

    def browse():
        chosen = filedialog.askdirectory(title="Folder with Game.exe")
        if chosen:
            path.set(chosen)

    def run():
        if not path.get():
            messagebox.showerror("BLACK SOULS Randomizer", "Pick your BLACK SOULS folder first.")
            return
        button.config(state="disabled")

        def work():
            try:
                install(path.get(), log=lambda text: root.after(0, status.set, text))
            except Exception as error:
                root.after(0, messagebox.showerror, "BLACK SOULS Randomizer", str(error))
            root.after(0, lambda: button.config(state="normal"))

        threading.Thread(target=work, daemon=True).start()

    tk.Entry(root, textvariable=path, width=58).grid(row=0, column=0, padx=8, pady=8)
    tk.Button(root, text="Browse", command=browse).grid(row=0, column=1, padx=(0, 8))
    button = tk.Button(root, text="Install", command=run, width=14)
    button.grid(row=1, column=0, columnspan=2, pady=(0, 8))
    tk.Label(root, textvariable=status, wraplength=480).grid(row=2, column=0, columnspan=2, padx=8, pady=(0, 8))
    root.mainloop()


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--update":
        update(sys.argv[2])
    elif len(sys.argv) > 1:
        install(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
    else:
        gui()
