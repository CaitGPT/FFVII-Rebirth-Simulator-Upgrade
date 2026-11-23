# After a game update

Our data mods replace whole DataObject tables, so each one is built against a particular game build's tables. A new
build means a new vanilla export and a rebuild of every pak mod. It can also mean a new package format: the Epic
1.005 build re-cooks the same tables with unversioned properties, which DataBuilder could not read until it learned
that header (2026-11-13).

This is the order to work in. Everything here is offline and read-only on the game install; nothing needs the game
running.

## 1. Export the new build's tables

Each DataObject package lives in exactly one base container, so a listing and one `retoc get` per package is the whole
job (about three minutes for 1,814 tables). Use the FF7R retoc fork at
`D:\FF7RebirthModding\Tools\retoc-ff7r-src\target\release\retoc.exe`.

```bash
RETOC="D:/FF7RebirthModding/Tools/retoc-ff7r-src/target/release/retoc.exe"
PAKS="<game>/End/Content/Paks"
OUT="D:/FF7RebirthModding/GameExports/vanilla-<build>-<date>"
mkdir -p "$OUT"

# Base containers only. ~mods and LogicMods hold our own paks and must never enter a vanilla export.
for utoc in "$PAKS"/pakchunk*.utoc; do
  "$RETOC" list --path --package "$utoc" 2>/dev/null | awk -v c="$(basename "$utoc")" '{
    n = split($0, f, /[ \t]+/); id = f[2]; path = f[n]
    if (path ~ /\/End\/Content\/DataObject\/.*\.uasset$/) { sub(/^.*\/End\/Content\//, "End/Content/", path); print c "\t" id "\t" path } }'
done | sort -k3,3 > "$OUT/containers.tsv"

while IFS=$'\t' read -r container id path; do
  mkdir -p "$OUT/Exports/$(dirname "$path")"
  "$RETOC" get "$PAKS/$container" "$id" "$OUT/Exports/$path"
done < "$OUT/containers.tsv"
```

A new export goes in its own dated folder beside the existing ones, with a README naming the build version, the source
containers and the command, and a `SHA256SUMS.txt`. Never edit or replace an existing export: a released mod is only
reproducible against the export it was built from. Exports stay out of Git (`ProjectKnowledge/AGENTS.md`).

## 2. Round-trip the new export, and the old one

```powershell
dotnet build Tools/ff7r-databuilder/src -c Release -o <somewhere outside the repo>
dotnet <that>/DataBuilder.dll roundtrip D:\FF7RebirthModding\GameExports\<new>\Exports\End\Content\DataObject
dotnet <that>/DataBuilder.dll roundtrip D:\FF7RebirthModding\GameExports\vanilla-2026-07-10\Exports\End\Content\DataObject
```

`roundtrip` re-saves every table without changing it and compares bytes. **`failed` must be 0 in both**, and the old
export must not get worse than the last recorded run (README has the current numbers). A table that is not
byte-identical but reads back with the same rows is reported as "same rows, different bytes" and is acceptable; a
table DataBuilder cannot read at all is counted as *skipped*, so a jump in the skipped count is a failure in disguise.

Then the unit tests, which cover both header formats without needing any game data:

```powershell
python -m unittest discover Tools/ff7r-databuilder
```

## 3. Tell a format change from a content change

Read the failures before changing anything.

**A format change** stops DataBuilder from reading the table at all. It shows up as a rise in `skipped`, or as one of
these messages from `export`/`build` on a single table:

| Message | What it means |
| --- | --- |
| `frozen image runs past the export` | the frozen size was read from the wrong offset, so the export's header shape changed |
| `unnamed key 0`, `unnamed property 0` | the name patch table was not where the reader looked, usually downstream of the same wrong size |
| `34846 names but 61604 hashes` | the name batch was misparsed: a name's length header, encoding or alignment changed |
| `not a zen package with the expected layout` | the summary's block offsets no longer follow names, hashes, imports |

Confirm it against the bytes before patching anything:

- Package summary: `+0x10` is the package flags. `0x2000` (PKG_UnversionedProperties) means the export carries no
  property tags, which moves the frozen size from `+0x0c` to `+0x06`. The 2024 Steam build has `0x80800200`, the Epic
  1.005 build `0x80802200`.
- Export prefix: dump the 0x20 bytes at the end of the package's graph data. The frozen size is the only 32-bit value
  there that equals the remaining length minus the patch table and the 12 trailing bytes; in both known formats the
  frozen image still starts at `+0x20`.
- Name batch: each name is a 2-byte big-endian length header (high bit = UTF-16) and then its characters, with a
  padding byte before UTF-16 characters that would otherwise start at an odd offset. Only a handful of tables have a
  UTF-16 name at all, so a build can look fine until one of them is read.

Keep both shapes: `ZenPackage.Unversioned` decides what `DataTable.FrozenSizeOffset` reads and writes, so each package
is saved in the format it was read in and an old-build mod can still be rebuilt from the old export.

**A content change** reads fine and shows up in the rows. Compare the same table from the two exports:

```powershell
dotnet <that>/DataBuilder.dll diff <old export>\...\Resident\Colosseum.uasset <new export>\...\Resident\Colosseum.uasset
```

`diff` matches rows and properties by name (unlike `compare`, which walks both row lists in step, so one inserted row
makes every later row look changed). It prints the schema first:

- `schema SAME` and `rows changed: 0` - the table is the same data, re-cooked. Rebuilding the mod against the new
  export is enough.
- `schema SAME` with changed, added or removed rows - content moved. Check that each row a mod clones or repurposes
  still exists and still means the same thing; `rows at a different index` warns that row order moved, which matters
  wherever an index was recorded instead of a name.
- `schema DIFFERENT` - a property was added, removed or reordered. Every spec that sets that property needs revisiting,
  and a mod that cloned a row cannot be assumed to still be valid.

Over a whole folder, loop `diff` per table and keep the output; the summary lines (`RESULT:`) are enough to spot which
tables moved.

## 4. Rebuild the mods

`diff` the tables each mod replaces first, then build the mod against the new export's `Exports` folder as its vanilla
root and `compare` the result with the previously released table, to see exactly what the update moved. Record which
export a release was built from in the mod's own repo.

## What the Epic 1.005 check found (2026-11-13)

Both fixes are in the shared copy and each format is kept on save.

- Epic packages set PKG_UnversionedProperties, so the frozen size moved from `+0x0c` to `+0x06`. The frozen image still
  starts at `+0x20`, and for the 30 tables our mods replace the columns, types, offsets, row size, imports and exports
  are unchanged.
- UTF-16 names are 2-byte aligned in the name batch. This is not new in the Epic build: the same seven tables in the
  2026-07 export were unreadable before the fix and now round-trip byte for byte.
- Both exports round-trip to 1,732 byte-identical, 5 with identical rows, 0 failed, 77 skipped. The 77 are the same
  packages in both builds (75 `LocationPack`, plus `ResidentPack` and `CondorFortUnitPreset`), so no table became
  unreadable in the Epic build; those were never readable, through `row map is not dense`, `frozen image runs past the
  export` and one unknown property type. They are not row tables and no mod has needed them.
- The two builds ship the same 1,814 tables, and no package is byte-identical between them. Of the 30 tables our mods
  replace, all 30 keep the same schema, and 10 also changed content that a rebuild picks up: `Resident\Item` (5 rows'
  `CategoryDetail`), `Resident\Action`, `Field\1300-JUNOA\StateChange`, `Field\1350-JNONT\StateChange` (1 added, 2
  changed), and added rows in `Resident\ResidentStateChange` (4), `ResidentStateTrigger` (2), `StoryFlag` (2),
  `StateTrigger`, `ResidentObject` and `ObjectEntryAttributeList`.
