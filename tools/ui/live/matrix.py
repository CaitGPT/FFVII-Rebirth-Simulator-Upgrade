"""Screenshots of the settings menu in every state it can be in (owner, 2026-11-20: judged from screenshots, nothing
clipped, overlapping, unreadable or off-screen): the main window with the shortest and longest opponent name of every
kind (and a former boss), each behaviour, difficulty, number and meter; with mixed groups, three different long names,
three copies and None rows; with pre-built rounds, Round mode with the longest and shortest course; every value list;
the opponent list's kinds (with None for Opponent 2), each kind's ranges and the names window holding its longest name;
the round list's tabs, each tab's courses (and their ranges) and the rounds of the course with the longest round text.

Run in a Custom Training fight with the menu closed and the ui development install. The menu is opened with the
development "menu" command (or the pad chord with --chord), values are set with "draft ...", and windows are stepped
with "pick N" (0-based; -1 is Back or Cancel). Which main-window row is which is read from the mod's log, so the same
script serves the menu with and without groups and rounds. Screenshots land in docs/workstreams/ui/matrix/.

    python matrix.py [--chord] [--only main|values|lists|rounds|stage]
"""
import math, os, re, sys, time

sys.path.insert(0, os.path.dirname(__file__))
import ui_live  # noqa: E402

OUT = "matrix/"
STAGE = {"name": "", "room": None}  # the stage loaded, from ui-rounds.txt
PAGE = 12  # ui_model.PAGE
CATALOGUE = os.path.join(ui_live.REPO, "ue4ss", "SimOverhaulCustomTraining", "Scripts", "ct_catalogue.lua")


def former_bosses():
    """The opponents Custom Training's catalogue marks boss = true. The lists no longer say so (owner, 2026-11-21: no
    "(boss)" tag, one to three copies of anyone), but the matrix still shoots them: they have the longest names."""
    with open(CATALOGUE, encoding="utf-8") as f:
        return {m.group(1) for m in re.finditer(r'id = "([^"]+)"[^\n]*boss = true', f.read())}


def lists():
    """ui-lists.txt (the development "lists" command): name length, kind, kind name, the opponent's own copy cap (empty
    when it has none), id, name."""
    ui_live.command("lists")
    time.sleep(1.0)
    rows = []
    with open(os.path.join(ui_live.MOD, "ui-lists.txt"), encoding="utf-8") as f:
        for line in f:
            f_ = line.rstrip("\n").split("\t")
            n, kind, kind_name, cap, oid, name = f_[:6]
            needs = float(f_[6]) if len(f_) > 6 and f_[6] else None
            rows.append({"len": int(n), "kind": int(kind), "kind_name": kind_name, "cap": cap, "id": oid, "name": name,
                         "needs": needs})
    bosses = former_bosses()
    for r in rows:
        r["boss"] = r["id"] in bosses
    return rows


def rounds():
    """ui-rounds.txt (written with ui-lists.txt): tabs in Custom Training's order, then courses with their rounds and
    each round's row text. Empty without pre-built rounds."""
    tabs, courses = [], []
    global STAGE
    try:
        with open(os.path.join(ui_live.MOD, "ui-rounds.txt"), encoding="utf-8") as f:
            for line in f:
                f_ = line.rstrip("\n").split("\t")
                if f_[0] == "stage":
                    STAGE = {"name": f_[1], "room": float(f_[2]) if len(f_) > 2 and f_[2] else None}
                elif f_[0] == "tab":
                    tabs.append(f_[1])
                elif f_[0] == "course":
                    courses.append({"tab": f_[1], "id": f_[2], "name": f_[3], "rounds": []})
                elif f_[0] == "round" and courses:
                    courses[-1]["rounds"].append({"id": f_[3], "label": f_[4],
                                                  "needs": float(f_[5]) if len(f_) > 5 and f_[5] else None})
    except OSError:
        pass
    for c in courses:  # tabs Custom Training didn't list come after, as in ui_model
        if c["tab"] not in tabs:
            tabs.append(c["tab"])
    by_tab = [(t, [c for c in courses if c["tab"] == t]) for t in tabs]
    return [(t, cs) for t, cs in by_tab if cs]


def split(items, size):
    """ui_model's split: the fewest parts of at most size items, as even as they can be."""
    parts = max(1, math.ceil(len(items) / size))
    each = math.ceil(len(items) / parts)
    return [items[i:i + each] for i in range(0, len(items), each)]


def sections(rows):
    out = []
    for kind in sorted({r["kind"] for r in rows}):
        members = [r for r in rows if r["kind"] == kind]
        out.extend(split(members, PAGE * PAGE))
    return out


def targets(rows):
    t = {}
    for kind in sorted({r["kind"] for r in rows}):
        of = [r for r in rows if r["kind"] == kind]
        t[f"k{kind}-shortest"] = min(of, key=lambda r: r["len"])
        t[f"k{kind}-longest"] = max(of, key=lambda r: r["len"])
        bosses = [r for r in of if r["boss"]]
        if bosses:
            t[f"k{kind}-boss-longest"] = max(bosses, key=lambda r: r["len"])
    return t


def shot(name, wait=0.6):
    time.sleep(wait)
    return ui_live.shot(OUT + name)


def pick(n, wait=1.2):
    ui_live.command(f"pick {n}")
    time.sleep(wait)


def main_rows():
    """The main window's rows as last shown, from the mod's log."""
    for line in reversed(ui_live.log(80)):
        parts = line.split("\t")
        if len(parts) > 5 and parts[1] == "window" and parts[2] == "main":
            return parts[5].split(" | ")
    return []


def row(label):
    """The 0-based main-window row whose text is label or starts with "label:", or None."""
    for i, r in enumerate(main_rows()):
        if r == label or r.startswith(label + ":"):
            return i
    return None


def draft(text, wait=1.0):
    ui_live.command("draft " + text)
    time.sleep(wait)


def main():
    chord = "--chord" in sys.argv
    only = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None
    rows = lists()
    courses = rounds()
    print(len(rows), "opponents;", sum(len(cs) for _, cs in courses), "courses")
    tg = targets(rows)
    for k, r in tg.items():
        print(k, r["len"], r["name"])
    if chord:
        ui_live.op("battle_pad_chord", hold="guard", press="shortcut")
    else:
        ui_live.command("menu")
    time.sleep(1.5)
    shot("00-opened")
    grouped = row("Opponent 1") is not None
    first = "Opponent 1" if grouped else "Opponent"
    alone = " opponent2=none opponent3=none" if grouped else ""
    normal = next(r for r in rows if not r["boss"])
    if courses:
        draft("mode=opponents")
    if only in (None, "main"):
        for k, r in tg.items():
            draft(f"opponent={r['id']}{alone}", 0.2)
            shot(f"main-{k}")
        if grouped:
            longest = sorted(tg.values(), key=lambda r: -r["len"])
            kinds_seen, three = set(), []
            for r in longest:
                if r["kind"] not in kinds_seen:
                    kinds_seen.add(r["kind"])
                    three.append(r)
            three = (three + longest)[:3]
            draft(f"opponent1={three[0]['id']} opponent2={three[1]['id']} opponent3={three[2]['id']}", 0.2)
            shot("main-group-longest-three")
            draft(f"opponent1={normal['id']} opponent2={normal['id']} opponent3={normal['id']}", 0.2)
            shot("main-group-copies")
            draft(f"opponent2={three[0]['id']} opponent3=none", 0.2)
            shot("main-group-two")
        if courses:
            every = [c for _, cs in courses for c in cs if c["rounds"]]
            for name, c in (("longest", max(every, key=lambda c: len(c["name"]))), ("shortest", min(every, key=lambda c: len(c["name"])))):
                last = c["rounds"][-1]
                draft(f"mode=round round={last['id']}", 0.2)
                shot(f"main-round-{name}")
            draft("mode=opponents")
        draft(f"opponent={normal['id']}{alone}")
        for b in ("passive", "aggressive", "healing"):
            draft(f"behaviour={b}", 0.2)
            shot(f"main-behaviour-{b}")
        for d in ("easy", "normal", "dynamic", "hard"):
            draft(f"difficulty={d}", 0.2)
            shot(f"main-difficulty-{d}")
        if not grouped:
            for n in (1, 2, 3):
                draft(f"count={n}", 0.2)
                shot(f"main-count-{n}")
        # The meter row, when the meters part is installed (nothing changes on screen otherwise).
        for mt in ("damage", "taken", "heal", "hidden"):
            draft(f"meter={mt}", 0.2)
            shot(f"main-meter-{mt}")
    if only in (None, "values"):
        draft(f"opponent={normal['id']}{alone}")
        for label, name in (("Mode", "mode"), ("Number", "count"), ("Behaviour", "behaviour"), ("Difficulty", "difficulty"), ("Meter", "meter")):
            at = row(label)
            if at is None:
                continue
            pick(at)
            shot(f"values-{name}")
            pick(-1)  # Back: the main window
    if only in (None, "lists"):
        secs = sections(rows)
        for s, members in enumerate(secs):
            longest = max(members, key=lambda r: r["len"])
            draft(f"opponent={longest['id']}{alone}")
            pick(row(first))  # the first opponent row: the kinds
            if s == 0:
                shot("list-kinds")
            pick(s)
            if len(members) > PAGE:
                shot(f"list-s{s + 1}-ranges")
                ranges = split(members, PAGE)
                r = next(i for i, part in enumerate(ranges) if longest in part)
                pick(r)
                shot(f"list-s{s + 1}-names")
                pick(-1)  # Back: the ranges
            else:
                shot(f"list-s{s + 1}-names")
            pick(-1)  # Back: the kinds (from the names or the ranges)
            pick(-1)  # Back: the main window
        if grouped:
            pick(row("Opponent 2"))  # the kinds with None
            shot("list-kinds-opponent2")
            pick(-1)
    if only in (None, "rounds") and courses:
        draft("mode=round")
        pick(row("Round"))
        shot("rounds-tabs")
        for t, (tab, cs) in enumerate(courses):
            pick(t)
            parts = split(cs, PAGE) if len(cs) > PAGE else [cs]
            if len(cs) > PAGE:
                shot(f"rounds-t{t + 1}-ranges")
            for p, part in enumerate(parts):
                if len(cs) > PAGE:
                    pick(p)
                shot(f"rounds-t{t + 1}-courses{p + 1 if len(parts) > 1 else ''}")
                # The course with the longest round text, its rounds (each window of them).
                c = max(range(len(part)), key=lambda i: max([len(r["label"]) for r in part[i]["rounds"]] or [0]))
                if part[c]["rounds"]:
                    pick(c)
                    rparts = split(part[c]["rounds"], PAGE) if len(part[c]["rounds"]) > PAGE else [part[c]["rounds"]]
                    if len(rparts) > 1:
                        shot(f"rounds-t{t + 1}-c{p + 1}-ranges")
                    for q in range(len(rparts)):
                        if len(rparts) > 1:
                            pick(q)
                        shot(f"rounds-t{t + 1}-c{p + 1}-rounds{q + 1 if len(rparts) > 1 else ''}")
                        if len(rparts) > 1:
                            pick(-1)  # Back: the rounds' windows
                    pick(-1)  # Back: the courses
                if len(cs) > PAGE:
                    pick(-1)  # Back: the course ranges
            pick(-1)  # Back: the tabs
        pick(-1)  # Back: the main window
        draft("mode=opponents")
    if only in (None, "stage") and STAGE["room"]:
        # On a stage: the main window's stage line, a names window with an opponent marked "(larger stage)", the
        # refusal when it is confirmed; the same for a round.
        too_big = lambda e: e["needs"] is not None and e["needs"] > STAGE["room"]
        draft(f"opponent={normal['id']}{alone}")
        shot("stage-main")
        big = [r for r in rows if too_big(r)]
        if big:
            b = big[0]
            secs = sections(rows)
            s = next(i for i, members in enumerate(secs) if b in members)
            pick(row(first))
            pick(s)
            if len(secs[s]) > PAGE:
                ranges = split(secs[s], PAGE)
                r = next(i for i, part in enumerate(ranges) if b in part)
                pick(r)
                names = ranges[r]
            else:
                names = secs[s]
            shot("stage-names-marked")
            pick(names.index(b))
            shot("stage-names-refused")
            pick(-1); pick(-1)
            if len(secs[s]) > PAGE:
                pick(-1)
        bigr = [(t, c, r) for t, (_, cs) in enumerate(courses) for c, course in enumerate(cs)
                for r, rd in enumerate(course["rounds"]) if too_big(rd)]
        if bigr:
            t, c, r = bigr[0]
            cs = courses[t][1]
            draft("mode=round")
            pick(row("Round"))
            pick(t)
            if len(cs) > PAGE:
                parts = split(cs, PAGE)
                p = next(i for i, part in enumerate(parts) if cs[c] in part)
                pick(p)
                c = parts[p].index(cs[c])
                cs = parts[p]
            pick(c)
            shot("stage-rounds-marked")
            pick(r)
            shot("stage-rounds-refused")
            pick(-1); pick(-1); pick(-1)
            if len(courses[t][1]) > PAGE:
                pick(-1)
            draft("mode=opponents")
    pick(-1)  # Cancel: closes without changes
    print("\n".join(ui_live.log(30)))


if __name__ == "__main__":
    main()
