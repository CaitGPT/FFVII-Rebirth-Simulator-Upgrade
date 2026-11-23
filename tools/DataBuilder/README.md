# DataBuilder

Our reader and writer for FF7 Rebirth DataObject tables, with no third-party dependencies (MIT). This is the shared copy:
improve it here, then copy it into the mod that needs it.

It started in Training Dummy, was copied into Biome Randomizer, and grew in Junon Colosseum. This copy is Junon Colosseum's
committed version (`experiments/junon-foyer/tools/DataBuilder` at `35ca76b`, 2026-11-08), with the assembly renamed
`DataBuilder` and the usage text updated. Compared with Training Dummy's copy it:

- checks that every row, old and new, can be found through its hash chain, not just by a linear scan;
- hashes non-ASCII row names the way FName does (UTF-16LE);
- adds `inspect`;
- adds Junon's packaging and battle-plan commands (below). These are written for Junon's own container and arena, so
  generalise them before another mod uses them.

It reads and writes both package formats the game has shipped: the 2024 Steam build's versioned exports and the Epic
1.005 build's unversioned ones. A table is saved in the format it was read in, so a mod can still be rebuilt from an
older export. What changed, and what to check after the next game update, is in [GAME-UPDATES.md](GAME-UPDATES.md).

Checked on 2026-11-13 against both vanilla exports (`D:\FF7RebirthModding\GameExports`): `roundtrip` over the 1,814
tables gives 1,732 byte-identical, 5 with identical rows, 0 failed, for `vanilla-2026-07-10` and for
`vanilla-epic-1.005-2026-11-13` alike. The 77 it skips are the `LocationPack`, `ResidentPack` and
`CondorFortUnitPreset` packages, which it has never been able to read, in either build. On 2026-11-08 `build` with
Training Dummy's `data/training-dummy.json` reproduced its five released tables byte for byte.

## Use

Needs the .NET 8 SDK. Build outside the repo:

```powershell
dotnet build Tools/ff7r-databuilder/src -c Release -o <somewhere outside the repo>
```

The tests need no game data and run from the repo root:

```powershell
python -m unittest discover Tools/ff7r-databuilder
```

| Command | Does |
| --- | --- |
| `build <spec.json> <vanilla-root> <output-root>` | Applies a spec: clones rows, repurposes rows, verifies the result |
| `export <input.uasset> <output.csv>` | Dumps a table to read |
| `inspect <input.uasset> <row> <field regex>` | Prints one row's matching fields as JSON |
| `roundtrip <folder>` | Re-saves every table under a folder and compares bytes; reads only |
| `compare <a.uasset> <b.uasset>` | Compares two tables row by row; exits 1 when any row differs |
| `diff <a.uasset> <b.uasset> [max detail lines]` | Compares the same table from two game builds, matching rows and properties by name and reporting the schema first; exits 1 when anything differs |
| `stage-raw-container`, `prefix-container` | Junon's packaging for **new** assets (below) |
| `clone-battle-plan`, `layout-arrival` | Junon's battle-plan and arrival-point cloning. The plan loads in the game, but no battle has started in it yet |

### Packaging new assets

UnrealReZen is enough for overriding existing tables: Training Dummy and Junon's table rows load. It silently leaves out
brand-new packages, though. For Junon it printed "29 files packed" while the archive held only the 27 existing paths and no
package registrations. The old step of copying 10 bytes over the start of the `.ucas` also corrupts the compressed container
header. Nobody has checked Training Dummy's archive for this; it loads, but that doesn't prove the header is intact.

Junon's pipeline (`Build-Foyer.ps1` in that repo) loads new assets in the game:

1. `stage-raw-container` stages every raw package and registers the new ones in the game's Initial ContainerHeader.
2. The FF7R retoc fork (`D:\FF7RebirthModding\Tools\retoc-ff7r-src\target\release\retoc.exe`) runs `pack-raw`.
3. `prefix-container` **prepends** Rebirth's 16-byte prefix and shifts every block offset, instead of overwriting bytes.
4. `retoc verify`, then an `unpack-raw` readback compared chunk by chunk.

"Mounted" or "packed" lines in a log don't prove an asset is included. List the container's paths and package
registrations.

Roots contain `End/Content/<asset path>`, the layout UnrealReZen packs from. The game's tables are exported, permanently
and hash-verified, under `D:\FF7RebirthModding\GameExports`, one dated folder per game build, each with its own README:

| Export | Build |
| --- | --- |
| `vanilla-epic-1.005-2026-11-13\Exports` | Epic `1.005_2026_0528_2133`, `D:\Epic Games\FinalFantasyVIIRebirth`. Build every mod against this one |
| `vanilla-2026-07-10\Exports` | the 2024 Steam build, `D:\Games\FINAL FANTASY VII REBIRTH`. Kept so an older release stays reproducible |

A mod is built against one export and must record which. The two builds ship the same 1,814 tables, but no package is
byte-identical between them: a pak built from the old export puts a versioned package over an unversioned one. Whether
the Epic build accepts that has not been tested in the game, so rebuild against the Epic export rather than assume it.

The file format, and which tables accept new rows, are in Training Dummy's `docs/HOW-IT-WORKS.md` and the mod skill's
`skills/create-rebirth-mod/references/cookbook.md`.

## Copies in mod repos

Public mod repos keep their own copy, so anyone can build them without this private repo. When you copy it, say in the mod
repo which commit of this folder it came from. When a mod improves its copy, bring the change back here.

`check_copies.py` compares copies with this one, ignoring line endings:

```powershell
python Tools/ff7r-databuilder/check_copies.py `
  <our mods folder>\FFVII-Rebirth-Training-Dummy\tools\DataBuilder `
  <our mods folder>\FFVII-Rebirth-Biome-Randomizer\research\fixed-package\tools\DataBuilder `
  <our mods folder>\FFVII-Rebirth-Junon-Colosseum\experiments\junon-foyer\tools\DataBuilder
```

On 2026-11-08 the Training Dummy and Biome Randomizer copies were older (no hash-chain checks or non-ASCII names), and
Junon Colosseum's had uncommitted work in progress. Their released builds are unaffected: Training Dummy's tables are
byte-identical with either copy.

Every copy is now behind on the Epic 1.005 package format as well. A mod cannot be rebuilt against
`vanilla-epic-1.005-2026-11-13` until its copy is updated from here.
