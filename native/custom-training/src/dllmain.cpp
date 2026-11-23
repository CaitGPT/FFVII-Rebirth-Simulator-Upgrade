// Custom Training Native: reads and sets the game's difficulty for Custom Training's in-course settings menu.
//
// A UE4SS 3.0.1 C++ mod. The game reflects no way to set the difficulty (only UEndDataBaseDataBaseAPI.IsDifficulty
// reads it). IsDifficulty asks a native function, GetDifficulty, which reads one global object: when its byte +0xbca
// is set, the difficulty is its byte +0xbc9; otherwise the system setting. This mod finds GetDifficulty by its code
// (the same bytes in the 2024 Steam build and Epic 1.005, with the addresses masked), takes the global's address from
// it, and lets the Lua side read and set those two bytes:
//
//   CustomTrainingNativeStatus() -> "ok" or why it is off
//   CustomTrainingGetDifficulty() -> current (what the game answers), value (+0xbc9), set (+0xbca), system
//   CustomTrainingSetDifficulty(value, set) -> true when written (value 0..3, set 0 or 1)
//
// And the course's opponent. A simulator round can only start the 16 reinforcement waves of its own territory row
// (higher wave numbers crashed the game), but the game reads a wave's template and level from the loaded EnemyTerritory
// table when the wave starts (seen 2026-11-20). So the helper finds Custom Training's territory row in memory by the
// exact contents of its 16-wave template list and level list, and rewrites one slot before the Lua side starts it:
//
//   CustomTrainingFindWaves(templates_hex, levels_hex) -> "searching", "found", or why not (a background search of the
//       game's committed read/write memory, once per game session; the patterns are the row's own 16 FNames
//       (comparison index, number) and 16 int32 levels, which only this row holds)
//   CustomTrainingSetWave(slot, comparison_index, number, level) -> true when written
//
// It writes nothing else, calls no game function besides GetDifficulty and changes no save: these are the game's own
// in-memory state, and the Lua side puts back what it found when the course ends.
#include <Windows.h>
#include <Mod/CppUserModBase.hpp>
#include <LuaMadeSimple/LuaMadeSimple.hpp>

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <cstring>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace CustomTrainingNative
{
    // GetDifficulty: mov rax,[rip+G]; test rax,rax; je; test cl,cl; jne; cmp [rax+0BCAh],cl; jne;
    // mov rax,[rax+100h]; mov rax,[rax+28h]; add rax,10h; je; cmp byte [rip+F],0; jne; mov al,[rax+20h]; ret;
    // mov al,[rax+0BC9h]; ret; mov al,2; ret; mov al,1; ret.   0x100 marks a byte that may differ.
    constexpr int W = 0x100;
    const int pattern[] = {
        0x48, 0x8b, 0x05, W, W, W, W, 0x48, 0x85, 0xc0, 0x74, W, 0x84, 0xc9, 0x75, W, 0x38, 0x88, 0xca, 0x0b, 0x00, 0x00,
        0x75, W, 0x48, 0x8b, 0x80, 0x00, 0x01, 0x00, 0x00, 0x48, 0x8b, 0x40, 0x28, 0x48, 0x83, 0xc0, 0x10, 0x74, W, 0x80,
        0x3d, W, W, W, W, 0x00, 0x75, W, 0x8a, 0x40, 0x20, 0xc3, 0x8a, 0x80, 0xc9, 0x0b, 0x00, 0x00, 0xc3, 0xb0, 0x02,
        0xc3, 0xb0, 0x01, 0xc3};
    constexpr size_t VALUE = 0xbc9, SET = 0xbca;

    std::atomic<uint8_t**> g_global{nullptr};   // address of the game's pointer to its difficulty object
    std::atomic<uint8_t*> g_function{nullptr};  // GetDifficulty, to ask the game what it answers
    std::string g_status = "not started";

    uint8_t* find_get_difficulty()
    {
        auto* base = reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
        auto* dos = reinterpret_cast<IMAGE_DOS_HEADER*>(base);
        auto* nt = reinterpret_cast<IMAGE_NT_HEADERS*>(base + dos->e_lfanew);
        auto* section = IMAGE_FIRST_SECTION(nt);
        constexpr size_t n = sizeof(pattern) / sizeof(pattern[0]);
        uint8_t* found = nullptr;
        for (int s = 0; s < nt->FileHeader.NumberOfSections; ++s, ++section)
        {
            if (!(section->Characteristics & IMAGE_SCN_MEM_EXECUTE)) continue;
            uint8_t* start = base + section->VirtualAddress;
            size_t size = section->Misc.VirtualSize;
            for (size_t i = 0; i + n <= size; ++i)
            {
                if (start[i] != 0x48) continue;
                size_t k = 0;
                while (k < n && (pattern[k] == W || start[i + k] == pattern[k])) ++k;
                if (k != n) continue;
                if (found) return nullptr; // not unique: refuse
                found = start + i;
            }
        }
        return found;
    }

    // SEH cannot share a function with C++ objects that need unwinding (MSVC C2712), so the search is guarded here.
    uint8_t* guarded_find(bool* faulted)
    {
        __try
        {
            return find_get_difficulty();
        }
        __except (EXCEPTION_EXECUTE_HANDLER)
        {
            *faulted = true;
            return nullptr;
        }
    }

    uint8_t* object()
    {
        uint8_t** global = g_global.load();
        return global ? *global : nullptr;
    }

    int lua_status(const RC::LuaMadeSimple::Lua& lua)
    {
        lua.set_string(g_status);
        return 1;
    }

    int lua_get(const RC::LuaMadeSimple::Lua& lua)
    {
        uint8_t* o = object();
        auto* fn = reinterpret_cast<uint8_t (*)(bool)>(g_function.load());
        if (!o || !fn)
        {
            lua.set_nil();
            return 1;
        }
        lua.set_integer(fn(false));
        lua.set_integer(o[VALUE]);
        lua.set_integer(o[SET]);
        lua.set_integer(fn(true));
        return 4;
    }

    int lua_set(const RC::LuaMadeSimple::Lua& lua)
    {
        int64_t value = -1, set = 1;
        if (lua.is_integer()) value = lua.get_integer();
        if (lua.is_integer()) set = lua.get_integer();
        uint8_t* o = object();
        if (!o || value < 0 || value > 3 || (set != 0 && set != 1))
        {
            lua.set_bool(false);
            return 1;
        }
        o[VALUE] = static_cast<uint8_t>(value);
        o[SET] = static_cast<uint8_t>(set);
        lua.set_bool(true);
        return 1;
    }


    // ---- Wave slots -------------------------------------------------------------------------------------------
    constexpr int SLOTS = 16;
    std::mutex g_wave_lock;
    std::string g_wave_state = "idle";
    std::atomic<uint64_t*> g_names{nullptr};   // the row's 16 template FNames (8 bytes each)
    std::atomic<int32_t*> g_levels{nullptr};   // the row's 16 levels

    int nibble(char c)
    {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        if (c >= 'A' && c <= 'F') return c - 'A' + 10;
        return -1;
    }

    bool parse_hex(std::string_view hex, std::vector<uint8_t>& out)
    {
        if (hex.size() % 2) return false;
        out.clear();
        for (size_t i = 0; i < hex.size(); i += 2)
        {
            const int hi = nibble(hex[i]), lo = nibble(hex[i + 1]);
            if (hi < 0 || lo < 0) return false;
            out.push_back(static_cast<uint8_t>(hi * 16 + lo));
        }
        return true;
    }

    // Every address in committed private read/write memory where `pattern` starts on an `align` boundary, outside the
    // buffers this search uses itself. Memory is copied with ReadProcessMemory, which fails instead of faulting when a
    // page goes away under it.
    std::vector<uintptr_t> search(const std::vector<uint8_t>& pattern, size_t align,
                                  const std::vector<std::pair<uintptr_t, size_t>>& own)
    {
        std::vector<uintptr_t> hits;
        constexpr size_t CHUNK = 8u << 20;
        std::vector<uint8_t> buffer(CHUNK + pattern.size());
        const uintptr_t buf_lo = reinterpret_cast<uintptr_t>(buffer.data()), buf_hi = buf_lo + buffer.size();
        HANDLE self = GetCurrentProcess();
        MEMORY_BASIC_INFORMATION mbi{};
        uintptr_t address = 0x10000;
        // Both patterns start with a nonzero 32-bit value (an FName index, a level) but end in zero bytes, which made
        // a Boyer-Moore-Horspool search crawl through zero-filled memory (minutes, 2026-11-20). So: every aligned
        // position whose first 32 bits match, then the whole pattern.
        uint32_t first = 0;
        std::memcpy(&first, pattern.data(), 4);
        while (VirtualQuery(reinterpret_cast<void*>(address), &mbi, sizeof(mbi)) == sizeof(mbi))
        {
            const uintptr_t base = reinterpret_cast<uintptr_t>(mbi.BaseAddress);
            const size_t size = mbi.RegionSize;
            if (mbi.State == MEM_COMMIT && mbi.Type == MEM_PRIVATE && mbi.Protect == PAGE_READWRITE)
            {
                for (size_t offset = 0; offset < size; offset += CHUNK)
                {
                    const size_t want = std::min(size - offset, CHUNK + pattern.size());
                    SIZE_T got = 0;
                    if (!ReadProcessMemory(self, reinterpret_cast<void*>(base + offset), buffer.data(), want, &got) ||
                        got < pattern.size())
                        continue;
                    const uint8_t* bytes = buffer.data();
                    const uintptr_t at0 = base + offset;
                    for (size_t i = (align - at0 % align) % align; i + pattern.size() <= got; i += align)
                    {
                        uint32_t v;
                        std::memcpy(&v, bytes + i, 4);
                        if (v != first || std::memcmp(bytes + i, pattern.data(), pattern.size()) != 0) continue;
                        const uintptr_t at = at0 + i;
                        if (at >= buf_lo && at < buf_hi) continue;
                        bool mine = false;
                        for (auto& [lo, n] : own) if (at >= lo && at < lo + n) mine = true;
                        if (!mine && std::find(hits.begin(), hits.end(), at) == hits.end()) hits.push_back(at);
                    }
                }
            }
            const uintptr_t next = base + size;
            if (next <= address) break;
            address = next;
        }
        return hits;
    }

    // No raw copy of the patterns may stay in memory: a freed copy is found by the next search (2026-11-21: the
    // search found two template lists, refused, and was started again every second). So the request is kept as hex
    // text, and every binary copy is wiped as soon as it is used.
    void wipe(std::vector<uint8_t>& v)
    {
        if (!v.empty()) SecureZeroMemory(v.data(), v.size());
        v.clear();
        v.shrink_to_fit();
    }

    // In the table the level list follows the template list a few KB on (2,964 bytes in Epic 1.005); any copy left
    // elsewhere is either far away or right beside its twin. So with more than one hit, take the one pair 1 KB to 64 KB
    // apart.
    bool pick(const std::vector<uintptr_t>& names, const std::vector<uintptr_t>& levels, uintptr_t& n, uintptr_t& l)
    {
        // One of each: that is the row (2026-11-21: in one build they were not 1-64 KB apart).
        if (names.size() == 1 && levels.size() == 1) { n = names[0]; l = levels[0]; return true; }
        int found = 0;
        for (uintptr_t a : names)
            for (uintptr_t b : levels)
                if (b > a && b - a >= 1024 && b - a <= (64u << 10)) { n = a; l = b; ++found; }
        if (found == 1) return true;
        // One template list and several level lists (a stale copy: "not found: templates 1, levels 2", ui's run on
        // Cave of the Gi, 2026-11-21): the row's own level list is the nearest one after its template list, within
        // 1 MB.
        if (names.size() == 1)
        {
            uintptr_t best = 0;
            for (uintptr_t b : levels)
                if (b > names[0] && b - names[0] <= (1u << 20) && (best == 0 || b < best)) best = b;
            if (best) { n = names[0]; l = best; return true; }
        }
        return false;
    }

    std::string g_want_key; // the last request, as hex text

    void find_waves(std::string key)
    {
        std::string result;
        std::vector<uint8_t> names, levels;
        try
        {
            const size_t bar = key.find('|');
            parse_hex(std::string_view(key).substr(0, bar), names);
            parse_hex(std::string_view(key).substr(bar + 1), levels);
            std::vector<std::pair<uintptr_t, size_t>> own{
                {reinterpret_cast<uintptr_t>(names.data()), names.size()},
                {reinterpret_cast<uintptr_t>(levels.data()), levels.size()}};
            auto name_hits = search(names, 8, own);
            auto level_hits = search(levels, 4, own);
            uintptr_t n = 0, l = 0;
            if (pick(name_hits, level_hits, n, l))
            {
                g_names = reinterpret_cast<uint64_t*>(n);
                g_levels = reinterpret_cast<int32_t*>(l);
                result = "found";
            }
            else
            {
                result = "not found: templates " + std::to_string(name_hits.size()) + ", levels " +
                         std::to_string(level_hits.size());
            }
        }
        catch (...)
        {
            result = "search failed";
        }
        wipe(names);
        wipe(levels);
        std::lock_guard hold(g_wave_lock);
        g_wave_state = result;
    }

    int lua_find_waves(const RC::LuaMadeSimple::Lua& lua)
    {
        std::string names_hex, levels_hex;
        if (lua.is_string()) names_hex = std::string(lua.get_string());
        if (lua.is_string()) levels_hex = std::string(lua.get_string());
        std::vector<uint8_t> check;
        const bool ok = names_hex.size() == SLOTS * 16 && levels_hex.size() == SLOTS * 8 && parse_hex(names_hex, check) &&
                        parse_hex(levels_hex, check);
        wipe(check);
        if (!ok)
        {
            lua.set_string("bad arguments");
            return 1;
        }
        const std::string key = names_hex + "|" + levels_hex;
        std::lock_guard hold(g_wave_lock);
        // The same row asked for again: answer what is known (found or searching). After a "not found" it is searched
        // again: the table can be loaded later, or a stale copy gone (ui's run on Cave of the Gi, 2026-11-21).
        const bool failed = g_wave_state.rfind("not found", 0) == 0 || g_wave_state.rfind("error", 0) == 0;
        if (key == g_want_key && g_wave_state != "idle" && !failed)
        {
            lua.set_string(g_wave_state);
            return 1;
        }
        g_want_key = key;
        g_names = nullptr;
        g_levels = nullptr;
        g_wave_state = "searching";
        std::thread(find_waves, key).detach();
        lua.set_string(g_wave_state);
        return 1;
    }

    int lua_set_wave(const RC::LuaMadeSimple::Lua& lua)
    {
        int64_t slot = -1, index = -1, number = -1, level = -1;
        if (lua.is_integer()) slot = lua.get_integer();
        if (lua.is_integer()) index = lua.get_integer();
        if (lua.is_integer()) number = lua.get_integer();
        if (lua.is_integer()) level = lua.get_integer();
        uint64_t* names = g_names.load();
        int32_t* levels = g_levels.load();
        if (!names || !levels || slot < 0 || slot >= SLOTS || index <= 0 || index > 0xffffffffLL || number < 0 ||
            number > 0xffffffffLL || level < 1 || level > 99)
        {
            lua.set_bool(false);
            return 1;
        }
        const uint64_t value = static_cast<uint64_t>(index) | (static_cast<uint64_t>(number) << 32);
        InterlockedExchange64(reinterpret_cast<volatile LONG64*>(names + slot), static_cast<LONG64>(value));
        InterlockedExchange(reinterpret_cast<volatile LONG*>(levels + slot), static_cast<LONG>(level));
        lua.set_bool(true);
        return 1;
    }

    class Mod : public RC::CppUserModBase
    {
    public:
        Mod()
        {
            ModName = STR("SimOverhaulCustomTraining");
            ModVersion = STR("0.1.0");
            ModAuthors = STR("CaitGPT");
            ModDescription = STR("Reads and sets the difficulty for Simulator Upgrade's Custom Training");
        }

        void on_unreal_init() override
        {
            bool faulted = false;
            uint8_t* fn = guarded_find(&faulted);
            if (!fn)
            {
                g_status = faulted ? "searching the game's code failed"
                                   : "GetDifficulty not found (or not unique) in this game build";
                return;
            }
            int32_t rel = 0;
            std::memcpy(&rel, fn + 3, 4);
            g_global = reinterpret_cast<uint8_t**>(fn + 7 + rel);
            g_function = fn;
            g_status = "ok";
        }

        // The Lua side starts after the C++ mods, so these exist before its main.lua runs (Battle Meters).
        void on_lua_start(StringViewType mod_name, RC::LuaMadeSimple::Lua& lua, RC::LuaMadeSimple::Lua&,
                          RC::LuaMadeSimple::Lua&, std::vector<RC::LuaMadeSimple::Lua*>&) override
        {
            // The combined SimulatorUpgradeNative (native/overhaul, which #includes this file) registers only for the
            // integrated mod, so installed beside this development DLL nothing is registered twice.
#ifdef SIM_OVERHAUL_COMBINED
            if (mod_name != STR("SimulatorUpgrade")) return;
#else
            if (mod_name != STR("SimOverhaulCustomTraining") && mod_name != STR("SimulatorUpgrade")) return;
#endif
            lua.register_function("CustomTrainingNativeStatus", lua_status);
            lua.register_function("CustomTrainingGetDifficulty", lua_get);
            lua.register_function("CustomTrainingSetDifficulty", lua_set);
            lua.register_function("CustomTrainingFindWaves", lua_find_waves);
            lua.register_function("CustomTrainingSetWave", lua_set_wave);
        }
    };
}

#define MOD_EXPORT __declspec(dllexport)
extern "C"
{
    MOD_EXPORT RC::CppUserModBase* start_mod() { return new CustomTrainingNative::Mod(); }
    MOD_EXPORT void uninstall_mod(RC::CppUserModBase* mod) { delete mod; }
}
