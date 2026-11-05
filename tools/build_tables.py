# Builds game/rando_data.rb from an unpacked BLACK SOULS Data folder and data/locations.json
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from rbmarshal import load, text

DATA = Path(sys.argv[1])
OUT = ROOT / "game" / "rando_data.rb"

# area, parent, rule
REGIONS = [
    ("Holy Forest", None, None),
    ("Watched River", "Holy Forest", None),
    ("Red Hood's House", "Watched River", None),
    ("Forest of the Abandoned", "Holy Forest", None),
    ("Dust Sea", "Forest of the Abandoned", None),
    ("Forest of Sabbath", "Dust Sea", None),
    ("Sewers", "Forest of the Abandoned", None),
    ("Rotten Burg", "Sewers", None),
    ("Rotten Burg Locked Rooms", "Rotten Burg", None),
    ("Old Rotten Burg", "Rotten Burg", None),
    ("Fort Ivern", "Rotten Burg", None),
    ("Lost Empire", "Fort Ivern", "princesses"),
    ("Behemoth Ranch", "Holy Forest", None),
    ("Jacob's Disused Mine", "Behemoth Ranch", None),
    ("Valley Checkpoint", "Jacob's Disused Mine", None),
    ("Gothel's Tower", "Valley Checkpoint", None),
    ("Helsa Desert", "Behemoth Ranch", None),
    ("Garden of Snow", "Helsa Desert", None),
    ("Wonderland", "Garden of Snow", None),
    ("Alice's Library", "Wonderland", None),
    ("Graveyard Town Elixir", "Holy Forest", None),
    ("Elixir Locked House", "Graveyard Town Elixir", None),
    ("Skeleton Maze", "Graveyard Town Elixir", None),
    ("Abandoned Beach", "Skeleton Maze", None),
    ("Atlantica", "Abandoned Beach", "invitation"),
    ("Atlantica Locked House", "Atlantica", None),
    ("Hotel Poseidon", "Atlantica", None),
    ("Hotel Poseidon Locked Room", "Hotel Poseidon", None),
    ("Wilhelm Bridge", "Graveyard Town Elixir", None),
    ("Secret Garden", "Wilhelm Bridge", None),
    # the bog opens after the Fort Ivern dragon, the prologue win is never assumed
    ("Tainted Bog", "Wilhelm Bridge", "ivern"),
    ("Kun-Yan", "Tainted Bog", None),
]
PRINCESS_REGIONS = ["Tainted Bog", "Atlantica", "Gothel's Tower", "Garden of Snow"]

PRINCESSES = [
    dict(name="Princess Frog", map=82, ev=44, troop=156, ret=[82, 18, 5]),
    dict(name="Rapunzel", map=66, ev=5, troop=157, ret=[66, 12, 23]),
    dict(name="Snow White", map=53, ev=5, troop=158, ret=[53, 41, 25]),
    dict(name="Little Mermaid", map=76, ev=43, troop=159, ret=[76, 10, 23]),
]

# the recruit encounters that can change hands
# trigger switches and the learn call are what the encounter grants, hub switches are what the real
# character needs to appear at her vanilla spot, learn None means her hub event teaches the summon itself
# needs is a companion whose recruit the encounter waits on, after are switches the spot sets for its own
# heroine whoever it grants, lost are her death and capture switches, kept apart from the real character
COMPANIONS = [
    dict(actor=13, name="Leaf", main=71, fight=71, learn=59, hub=[3001], triggers=[], cond=None,
         slot_map=15, slot_events=[6, 11], sprite_maps=[15], chars=[["妖精小", 3]], hub_event=[10, 27]),
    dict(actor=19, name="Dorothy", main=224, fight=223, learn=63, hub=[111], triggers=[111], cond=111,
         slot_map=22, slot_events=[8], sprite_maps=[22], chars=[["$ドロシー", 0]], hub_event=[10, 28]),
    dict(actor=21, name="Elma", main=151, fight=None, learn=None, hub=[118], triggers=[118], cond=None,
         slot_map=32, slot_events=[7], sprite_maps=[32], chars=[["$マッチ売り", 0], ["$マッチ売りpng", 0]], hub_event=[11, 16]),
    dict(actor=18, name="Victoria", main=228, fight=None, learn=147, hub=[122], triggers=[122], cond=122,
         slot_map=111, slot_events=[2, 4], sprite_maps=[111], chars=[["$メイド", 0]], hub_event=[10, 29]),
    dict(actor=17, name="Goose", main=226, fight=226, learn=None, hub=[125], triggers=[124], cond=125,
         slot_map=37, slot_events=[55], sprite_maps=[37], chars=[["$グース", 0]], hub_event=[11, 15]),
    dict(actor=12, name="Jeanne", main=227, fight=None, learn=167, hub=[212], triggers=[212], cond=212,
         slot_map=119, slot_events=[10], sprite_maps=[98, 99, 100, 119], chars=[["jnu", 0]], hub_event=[10, 30]),
    dict(actor=15, name="Miranda", main=192, fight=192, learn=172, hub=[217], triggers=[217], cond=217,
         slot_map=82, slot_events=[41, 42], sprite_maps=[82], chars=[["$ミランダ", 0]], hub_event=[11, 17]),
    # paying her the second time upstairs is the recruit, Poro beside her leaves with it
    dict(actor=20, name="Red Hood", main=231, fight=None, learn=205, hub=[408], triggers=[408], cond=408,
         lost=[309, 310], slot_map=5, slot_events=[11, 10], sprite_maps=[3, 5], chars=[["紅", 1]], hub_event=[10, 32]),
    # the cathedral scene where she summons Jeanne, so it waits on Jeanne's encounter rather than the real Jeanne
    dict(actor=16, name="Catherine", main=197, fight=None, learn=None, hub=[214], triggers=[214], cond=214, needs=12,
         lost=[194, 158], slot_map=68, slot_events=[66, 67], sprite_maps=[68, 113], chars=[["Actor5", 5]],
         hub_event=[10, 21]),
    # her hub event is the soul shop, so handing her the ring by the lake is the encounter
    dict(actor=28, name="Elisabeth", main=221, fight=None, learn=157, hub=[156], triggers=[155], cond=155,
         after=[157], lost=[193], slot_map=15, slot_events=[13], sprite_maps=[15], chars=[["$ごすろり", 0]],
         hub_event=[10, 26]),
]
# heroine fights outside a recruit encounter stay as they are, the real character is in them
COMPANION_TROOPS = {71, 224, 223, 151, 228, 226, 221, 222, 197, 199, 227, 192, 231, 232}

# final bosses and fights whose battle script drives the story
FIXED_TROOPS = {161, 315, 236, 313, 257}
# chests that bite stay chests that bite
UNSHUFFLED = {64, 119}
PRINCESS_TROOPS = {p["troop"] for p in PRINCESSES}
EVENT_ENEMIES = {3, 7, 14, 23, 26, 27, 28, 49, 50, 55, 62, 203, 204, 205, 208, 291, 292, 293, 296, 308}
# centaur groups that flip switches from their battle script
SKIP_ENEMIES = {47, 48}
# consumables with many sources, the two key items are placed by logic
SHARED_ITEMS = {1, 3, 4, 25, 47, 49, 52}
BOOK_IDS = set(range(273, 305))
HANSEL_TROOP = 136
BEAUTY_TROOP = 150
# the favor rings of the princesses, Baphomet and Cinderella
COVENANT_RINGS = {105, 106, 107, 108, 113, 128}
# quest items handed out in several spots
QUEST_STACKS = {(0, 53), (0, 54)}
PROLOGUE_MAPS = {98, 99}
DEBUG_MAP = 29
# events that wipe and restore the whole inventory
WIPE_COMMONS = {266, 267, 268, 201}
PRINCESS_KEYS = {f"{p['map']}:{p['ev']}:" for p in PRINCESSES}

troops = load(DATA / "Troops.rvdata2")
enemies = load(DATA / "Enemies.rvdata2")
infos = load(DATA / "MapInfos.rvdata2")
commons = load(DATA / "CommonEvents.rvdata2")
maps = {mid: load(DATA / f"Map{mid:03d}.rvdata2") for mid in infos}

refs = set()
event_troops = set()
encounter_troops = set()


def scan_refs(cmds):
    for c in cmds:
        p = c["parameters"]
        if c["code"] == 111 and p[0] in (8, 9, 10):
            refs.add((p[0] - 8, p[1]))
        elif c["code"] in (126, 127, 128) and p[1] == 1:
            refs.add((c["code"] - 126, p[0]))
        elif c["code"] == 122 and p[3] == 3 and p[4] in (0, 1, 2):
            refs.add((p[4], p[5]))


for mid, m in maps.items():
    if mid != DEBUG_MAP:
        for enc in m["encounter_list"] or []:
            encounter_troops.add(enc["troop_id"])
    for ev in (m["events"] or {}).values():
        for page in ev["pages"]:
            if page["condition"]["item_valid"]:
                refs.add((0, page["condition"]["item_id"]))
            scan_refs(page["list"])
            if mid != DEBUG_MAP:
                for c in page["list"]:
                    if c["code"] == 301 and c["parameters"][0] == 0:
                        event_troops.add(c["parameters"][1])
for i, ce in enumerate(commons):
    if ce and i not in WIPE_COMMONS:
        scan_refs(ce["list"])
locations = json.loads((ROOT / "data" / "locations.json").read_text(encoding="utf-8"))
KINDS = {"item": 0, "weapon": 1, "armor": 2}
sources = Counter((KINDS[l["kind"]], l["id"]) for l in locations)
# only quest pieces stay put, gear and crafting items still exist wherever they land
keep_items = {r for r in refs if r[0] != 1 and r[1] not in SHARED_ITEMS and sources[r] <= 1} | QUEST_STACKS


def troop_stats(tid):
    t = troops[tid] if 0 < tid < len(troops) else None
    if not t or not t["members"]:
        return None
    mem = [enemies[x["enemy_id"]] for x in t["members"]]
    hp = sum(e["params"][0] for e in mem)
    if hp <= 0:
        return None
    visible = max(1, sum(0 if x["hidden"] else 1 for x in t["members"]))
    return [tid, hp, max(max(e["params"][2], e["params"][4]) for e in mem) or 1,
            max(max(e["params"][3], e["params"][5]) for e in mem) or 1,
            max(e["params"][6] for e in mem) or 1, sum(e["gold"] for e in mem), visible, len(mem), text(mem[0]["name"])]


def side_effects(tid):
    for page in troops[tid]["pages"]:
        for c in page["list"]:
            if c["code"] == 121 and not (c["parameters"][0] in (23, 24, 27) and c["parameters"][1] in (23, 24, 27)):
                return True
            if c["code"] in (201, 353, 126, 127, 128, 355):
                return True
    return False


enemy_ids = sorted(t for t in (encounter_troops | EVENT_ENEMIES) - SKIP_ENEMIES - FIXED_TROOPS - PRINCESS_TROOPS
                   - UNSHUFFLED - {73}
                   if troop_stats(t) and not side_effects(t))
boss_ids = sorted(t for t in event_troops - set(enemy_ids) - FIXED_TROOPS - PRINCESS_TROOPS - UNSHUFFLED
                  - SKIP_ENEMIES if troop_stats(t))
PROLOGUE_TROOPS = sorted({e["troop_id"] for e in maps[99]["encounter_list"]} | {3, 134})

def troop_enemy_ids(tid):
    ids = [m["enemy_id"] for m in troops[tid]["members"]]
    for page in troops[tid]["pages"]:
        for c in page["list"]:
            if c["code"] == 336:
                ids.append(c["parameters"][1])
    return ids


# fairytale bosses only trade arenas with each other, a book comes from the drop or the win branch
def books_dropped(tid):
    return {d["data_id"] for e in troop_enemy_ids(tid) for d in enemies[e]["drop_items"]
            if d["kind"] == 1 and d["data_id"] in BOOK_IDS}


# a developer chest in an unreachable map corner that hands out everything
DEV_CHEST = (10, 37)

book_sources = {}
for t in event_troops:
    if troops[t]:
        for b in books_dropped(t):
            book_sources.setdefault(b, set()).add(f"troop {t}")


def scan_book_grants(label, cmds):
    for c in cmds:
        if c["code"] == 126 and c["parameters"][1] == 0 and c["parameters"][2] == 0 and c["parameters"][0] in BOOK_IDS:
            book_sources.setdefault(c["parameters"][0], set()).add(label)


for mid, m in maps.items():
    if mid != DEBUG_MAP:
        for eid, ev in (m["events"] or {}).items():
            if (mid, eid) == DEV_CHEST:
                continue
            for page in ev["pages"]:
                scan_book_grants(f"map {mid} event {eid}", page["list"])
for i, ce in enumerate(commons):
    if ce and i not in WIPE_COMMONS:
        scan_book_grants(f"common {i}", ce["list"])


book_grant_troops = set()
for m in maps.values():
    for ev in (m["events"] or {}).values():
        for page in ev["pages"]:
            cmds = page["list"]
            for i, c in enumerate(cmds):
                if c["code"] != 301 or c["parameters"][0] != 0:
                    continue
                for d in cmds[i + 1:]:
                    if d["indent"] < c["indent"] or (d["indent"] == c["indent"] and d["code"] == 604):
                        break
                    if d["code"] == 126 and d["parameters"][1] == 0 and d["parameters"][0] in BOOK_IDS:
                        book_grant_troops.add(c["parameters"][1])
# a book with a second source can be skipped in the normal game, so its fight may never happen
# and any book moved onto that fight could be lost, those fights keep paying out their own book
shared_books = {b: s for b, s in book_sources.items() if len(s) > 1}
boss_ids = [t for t in boss_ids if t not in COMPANION_TROOPS]
fairy_bosses = sorted(t for t in boss_ids if books_dropped(t) and not books_dropped(t) & set(shared_books))
# the witch's house flame hands out the book of whoever moved in, so skipping that fight loses nothing
# every way to the Beauty and Beast book goes through her fight, so a book moved there is safe
fairy_bosses = sorted(set(fairy_bosses) | {HANSEL_TROOP, BEAUTY_TROOP})
fairy_books = {t: sorted(books_dropped(t))[0] for t in fairy_bosses if books_dropped(t)}

# boss rewards only trade with boss rewards so regular enemies cannot be farmed for them
boss_enemies = {e for t in boss_ids + sorted(PRINCESS_TROOPS) for e in troop_enemy_ids(t)}
vanilla_enemies = {e for t in FIXED_TROOPS | UNSHUFFLED for e in troop_enemy_ids(t)}
drops = []
for e in enemies:
    if not e or e["id"] in vanilla_enemies - boss_enemies:
        continue
    for index, d in enumerate(e["drop_items"]):
        if not d["kind"]:
            continue
        kind = d["kind"] - 1
        if (kind, d["data_id"]) in keep_items or (kind == 0 and (d["data_id"] in BOOK_IDS or d["data_id"] in (47, 52))):
            continue
        drops.append([e["id"], index, kind, d["data_id"], 1 if d["denominator"] <= 1 else 0, 1 if e["id"] in boss_enemies else 0])

rows = []
kept = Counter()
region_index = {r[0]: i for i, r in enumerate(REGIONS)}
for loc in locations:
    key = loc["key"]
    if any(key.startswith(k) for k in PRINCESS_KEYS):
        continue
    kind = KINDS[loc["kind"]]
    is_book = kind == 0 and loc["id"] in BOOK_IDS
    if (kind, loc["id"]) in keep_items and not is_book:
        kept[loc["item"]] += 1
        continue
    src_map = int(key.split(":")[0])
    flags = (1 if loc["quest"] else 0)
    flags |= (4 if src_map in PROLOGUE_MAPS else 0) | (8 if is_book else 0)
    flags |= 16 if kind == 2 and loc["id"] in COVENANT_RINGS else 0
    rows.append([[key] + loc.get("alt_keys", []), region_index[loc["area"]], kind, loc["id"], loc["amount"], flags,
                 loc["name"].replace("Fort Ivern - Prologue", "Prologue -")])


def rb(v):
    if v is None:
        return "nil"
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("#", "\\#") + '"'
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, list):
        return "[" + ",".join(rb(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{" + ",".join(f":{k}=>{rb(x)}" for k, x in v.items()) + "}"
    return str(v)


# the music and background an event sets up right before a fight belong to the boss, not the room
def battle_looks():
    music, backs = {}, {}
    lists = [m["events"][e]["pages"][p]["list"] for m in maps.values() for e in (m["events"] or {})
             for p in range(len(m["events"][e]["pages"]))]
    for cmds in lists:
        for i, c in enumerate(cmds):
            if c["code"] != 301 or c["parameters"][0] != 0:
                continue
            tid = c["parameters"][1]
            bgm = back = None
            for x in reversed(cmds[:i]):
                if bgm is None and x["code"] == 132:
                    b = x["parameters"][0]
                    bgm = (text(b["name"]), b["volume"], b["pitch"])
                if back is None and x["code"] == 283:
                    back = (text(x["parameters"][0]), text(x["parameters"][1]))
            music.setdefault(tid, set()).add(bgm)
            backs.setdefault(tid, set()).add(back)
    # only a fight that always looks the same is carried, an unset one keeps the room's
    pick = lambda found: {t: list(v.pop()) for t, v in sorted(found.items()) if len(v) == 1 and None not in v}
    return pick(music), pick(backs)


battle_music, battle_backs = battle_looks()

# final bosses and chests that bite can join the boss shuffle by option
SPECIAL_TROOPS = sorted(FIXED_TROOPS | UNSHUFFLED)


def phase_switches(tid):
    """Switches a fight's own battle script turns on to run its phases. The game only ever turns them off outside
    battle, to reset them before the fight, so a moved boss gets the same reset."""
    out = []
    for page in troops[tid]["pages"]:
        for c in page["list"]:
            p = c["parameters"]
            if c["code"] == 121 and p[2] == 0:
                out += [sw for sw in range(p[0], p[1] + 1) if sw not in (23, 24, 27) and sw not in out]
    return out


companions = [dict(c, main_stats=troop_stats(c["main"]), fight_stats=troop_stats(c["fight"]) if c["fight"] else None)
              for c in COMPANIONS]
princesses = [dict(p, stats=troop_stats(p["troop"])) for p in PRINCESSES]
regions = [[r[0], region_index[r[1]] if r[1] else -1, r[2]] for r in REGIONS]

HEADER = """# Do not edit by hand. tools/build_tables.py writes this file from the game's own Data folder.
# It is a lookup table of troops, enemies, drops and pickups, the randomizer code that uses it is rando.rb.
#
# REGIONS      [name, parent region index or -1, what the way in needs or nil]
# PRINCESSES   one per demonic princess, her room map and event, her troop and the spot her room sends you back to
# COMPANIONS   one per recruit encounter, see the COMPANIONS comment in tools/build_tables.py for each field
# BOSSES and ENEMIES   [troop, hp, attack, defense, agility, gold, members you can see, members, first name]
# SPECIAL_BOSSES  the same rows for final bosses and chests that bite, they only move with their option on
# PHASE_SWITCHES  troop => the switches its battle script turns on for its phases, reset before a moved fight
# FAIRY_BOOKS  fairytale boss troop => the book item it drops
# BATTLE_MUSIC troop => [music file, volume, pitch] its fight event plays
# BATTLE_BACKS troop => [floor picture, wall picture] its fight event shows, some bosses are drawn in it
# DROPS        [enemy, drop slot, kind 0 item 1 weapon 2 armor, item id, always drops 1 or 0, boss 1 or 0]
# LOCATIONS    [[event keys], region index, kind, item id, amount, flags, name]
#              an event key joins the map, event, page and command numbers, flags add up 1 quest 4 prologue 8 book 16 covenant ring"""


def table(name, items):
    return [f"  {name} = ["] + ["    " + rb(x) + "," for x in items] + ["  ]"]


lines = HEADER.split("\n") + ["module RandoData"]
lines += table("REGIONS", regions)
lines.append("  PRINCESS_REGIONS = " + rb([region_index[r] for r in PRINCESS_REGIONS]))
lines.append("  IVERN_REGION = " + str(region_index["Fort Ivern"]))
lines += table("PRINCESSES", princesses)
lines += table("COMPANIONS", companions)
lines.append("  COMPANION_TROOPS = " + rb(sorted(COMPANION_TROOPS)))
lines += table("BOSSES", [troop_stats(t) for t in boss_ids])
lines += table("ENEMIES", [troop_stats(t) for t in enemy_ids])
lines += table("SPECIAL_BOSSES", [troop_stats(t) for t in SPECIAL_TROOPS if troop_stats(t)])
lines += ["  PHASE_SWITCHES = {"] + [f"    {t} => {rb(phase_switches(t))}," for t in SPECIAL_TROOPS if phase_switches(t)] + ["  }"]
lines.append("  PROLOGUE_TROOPS = " + rb(PROLOGUE_TROOPS))
lines.append("  FAIRY_BOSSES = " + rb(fairy_bosses))
lines.append("  FAIRY_BOOKS = {" + ", ".join(f"{t} => {b}" for t, b in fairy_books.items()) + "}")
lines += ["  BATTLE_MUSIC = {"] + [f"    {t} => {rb(v)}," for t, v in battle_music.items()] + ["  }"]
lines += ["  BATTLE_BACKS = {"] + [f"    {t} => {rb(v)}," for t, v in battle_backs.items()] + ["  }"]
lines += table("DROPS", drops)
lines += table("LOCATIONS", rows)
lines += ["end", ""]
OUT.write_text("\n".join(lines), encoding="utf-8", newline="\n")

# walking sprites the overlay cards draw, the installer copies them out of the game archive
PRINCESS_SPRITES = {"Princess Frog": ("$カエル姫", 0), "Rapunzel": ("ラプンツェル", 0), "Snow White": ("$白雪姫", 0), "Little Mermaid": ("Spiritual", 1)}
sprites = {name: dict(sheet=sheet, index=index) for name, (sheet, index) in PRINCESS_SPRITES.items()}
for c in COMPANIONS:
    sprites[c["name"]] = dict(sheet=c["chars"][0][0], index=c["chars"][0][1])
for i, info in enumerate(sprites.values()):
    info.update(file=f"sprite{i}.png", big=info["sheet"].startswith("$"))
(ROOT / "game" / "overlay" / "sprites.js").write_text(
    "window.RANDO_SPRITES = " + json.dumps(sprites, ensure_ascii=False, indent=1) + ";\n", encoding="utf-8", newline="\n")
for label, ids in (("bosses", boss_ids), ("fairy", fairy_bosses), ("enemies", enemy_ids)):
    solo = [t for t in ids if troop_stats(t)[7] == 1]
    print(label, "solo", len(solo), "group", len(ids) - len(solo))
print("recruit fights", [(c["name"], c["fight"], troop_stats(c["fight"])[7] if c["fight"] else None, c["main"], troop_stats(c["main"])[7]) for c in COMPANIONS])
print(len(rows), "locations", sum(1 for r in rows if r[5] & 4), "prologue", len(boss_ids), "bosses", len(enemy_ids), "enemies")
print("kept in place", dict(kept))
print(len(drops), "drops", sum(1 for d in drops if d[5]), "from bosses", sum(1 for d in drops if d[2]), "gear")
print(len(fairy_bosses), "fairytale bosses", [text(troops[t]["name"])[:18] for t in fairy_bosses])
print("win branch books", sorted(book_grant_troops))
print("left out of the group", [t for t in boss_ids if books_dropped(t) and t not in fairy_bosses])
print("left out of the boss shuffle as companion fights", sorted(COMPANION_TROOPS))
