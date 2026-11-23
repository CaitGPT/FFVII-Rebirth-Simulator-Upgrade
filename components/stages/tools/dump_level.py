"""Dump exports of legacy-converted levels (read-only). Usage: dump_level.py <umap> [class-substring ...]

Needs the FF7R_Indexer tools from the FFVII-Modding repo: set FF7R_INDEXER to that folder.
"""
import os, sys, json
if not os.environ.get("FF7R_INDEXER"):
    raise SystemExit("set FF7R_INDEXER to the FF7R_Indexer folder of the FFVII-Modding repo")
sys.path.insert(0, os.environ["FF7R_INDEXER"])
import level_layout_points as L
from pathlib import Path

_orig = L._Properties.value
def value(self, reader, kind, tag, nested):
    if kind == "SoftObjectProperty":
        return [self.fname(reader), reader.string()]
    if kind == "StructProperty" and tag.get("struct") in ("SoftObjectPath", "SoftClassPath"):
        return [self.fname(reader), reader.string()]
    if kind == "StructProperty" and tag.get("struct") == "Transform":
        return self.read(reader)
    return _orig(self, reader, kind, tag, nested)
L._Properties.value = value

p = L.LegacyPackage(Path(sys.argv[1]))
filters = sys.argv[2:]
for i, e in enumerate(p.exports, 1):
    cls = p.class_name(i)
    if filters and not any(f.lower() in (cls + " " + e["name"]).lower() for f in filters):
        continue
    try:
        props = p.properties(i)
    except Exception as ex:
        props = {"_error": str(ex)}
    outer = p.exports[e["outer"]-1]["name"] if e["outer"] > 0 else ""
    print(f"#{i} {cls} {e['name']} outer={outer}")
    s = json.dumps(props, default=str)
    print("   ", s)
