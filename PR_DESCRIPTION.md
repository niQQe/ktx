## 🎯 Summary

This PR ports **both antilag systems** from [dusty-qw/ktx](https://github.com/dusty-qw/ktx) into `qwleague`, giving server operators a choice between:

- 🛰️ **Antilag 1** — dusty-qw's new CSQC-native antilag (EZCSQC-based weapon prediction/rewind). **⚠️ Requires a companion MVDSV with EZCSQC support — see [Server Requirements](#-server-requirements-read-this-this-is-not-optional) below.**
- 🕹️ **Antilag 2** — the official QW-Group MVDSV-native antilag (`sv_antilag 2`, engine-side rewind). The rewind logic itself does not run `antilag.c`'s code — **but see the crash section below: this does NOT mean it works safely on any stock MVDSV out of the box.**

Selection between the two (and off) is done through the existing dusty-qw 3-way vote/cvar mechanism, ported as-is, unmodified.

**Note on scope:** the code in this PR is a **direct, unmodified port of dusty-qw/ktx**. Nothing was changed, hardened, or "fixed" during the port — it reproduces dusty-qw's implementation as-is, including its assumption that it always runs paired with dusty-qw's own MVDSV. See the risk notes below — please read them, there are real crash scenarios described here, not just style nitpicks.

## 📦 What's included

Source: **[dusty-qw/ktx](https://github.com/dusty-qw/ktx) branch `master`** (the `antilag-new` branch used in an earlier revision of this PR turned out to be stale — `master` already contains everything `antilag-new` had plus additional fixes, e.g. weapon-prediction-on-respawn and EZCSQC readiness tracking — this PR now ports from `master`). Diffed against dusty-qw's `non-antilag` branch (a "no antilag at all" baseline) to isolate a clean patch set, then reapplied on top of `qwleague`.

**Scope:** everything in the `non-antilag..master` diff is included **except sprays** (`src/sprays.c`, `src/sv_sprays.c`, `G_SPRAYCLEAR`/`G_SPRAYCLEARALL` — an unrelated decal feature, deliberately left out). That means a few small non-antilag things rode along in the same dusty-qw commits and are included here too:

- **`k_drp` / `dropmessage`** — a chat message announcing which weapon was dropped in a backpack on death. **This does not exist in [QW-Group/ktx](https://github.com/QW-Group/ktx) upstream** — it's dusty-qw-specific. Purely cosmetic, doesn't touch antilag/timing/physics, and uses the exact same permission pattern as other pre-existing KTX toggles (e.g. `discharge`) — not a new gap. **Happy to drop this on request** if you'd rather not carry it — it's isolated to `commands.c` (`ToggleDropMessage`, `CD_DROPMSG`), `items.c` (`DropBackpack`), `match.c` (status line), and one `RegisterCvar` in `world.c`.
- socd/strafe-detection counters and `ToggleToT`/`sv_time` reordering — these already exist in QW-Group/ktx upstream (confirmed), the dusty-qw diff just touches the same lines incidentally.

**Not ported (found in a follow-up audit, listed for transparency — none of these touch antilag):**
- Gender-neutral pronoun support ("they/their/themself") in `src/g_utils.c` (`g_his`/`g_he`/`g_himself`).
- dusty-qw's `resources/example-configs/ktx/ktx.cfg` / `mvdsv.cfg` documentation comments about `k_vp_antilag` / `sv_antilag`.
- Misc repo/tooling files not relevant to a Linux/native build: `README.md` changes, `.pre-commit-config.yaml`, `tools/vs/ktx_mvs2019.vcxproj`/`.sln`.

### Core antilag/rewind + weapon prediction — new files
- `src/antilag.c` (853 lines) — hitscan and projectile rewind core: lag compensation, grenade launcher physics, rocket knockback fixes, teleporter/moving-platform edge cases, extrapolation.
- `src/weaponpred_defs.c` (464 lines) + `qcsrc/weaponpred.qc` (1127 lines) — client-side weapon prediction plumbing (axe, GL, LG made predictable).

### Core integration
- `src/vote.c` — 3-way antilag vote (off / antilag 1 / antilag 2), ported from dusty-qw.
- `src/combat.c`, `src/world.c`, `src/g_utils.c`, `src/g_main.c`, `src/commands.c`, `src/match.c`, `src/items.c`, `src/player.c` — hooks wiring antilag state into damage, knockback, spawn/frame handling, weapon-animation timing, and commands.
- `src/g_syscalls.c` / `src/g_syscalls.h` / `src/g_syscalls.asm` — new QC syscalls required by the antilag/weapon-prediction code (e.g. `SetLastRuntime`), plus a `trap_AddBot` signature change (adds a `skill` param) that came from the same upstream commits. Its only caller (`src/bot_commands.c`) was updated accordingly.
- `include/g_consts.h`, `include/g_local.h`, `include/g_syscalls.h` — supporting fields/consts.
- Small supporting fixes in `bot_commands.c`, `bot_aim.c`, `bot_botjump.c`, `bot_botpath.c`, `bot_botweap.c`, `bot_world.c`, `clan_arena.c`, `doors.c`, `fb_globals.c`, `func_bob.c`, `func_laser.c`, `hiprot.c`, `plats.c`, `race.c`, `triggers.c` — mostly switching from `g_globalvars.time` to `client_time` so gameplay timing respects antilag rewind, plus registering antilag-owned world entities.

### Antilag 1 — CSQC/EZCSQC layer
- `qcsrc/main.qc` (314 lines, new), `qcsrc/fteextensions.qc` (3709 lines, new), `qcsrc/progs.src`, `qcsrc/fteqcc.ini` — CSQC/FTE extension groundwork required for native CSQC entity handling. (Not `qcsrc/fteqcc64` — that's a prebuilt QuakeC compiler binary, deliberately excluded; you'll need your own toolchain to build the `.qc` sources into `csprogs.dat`.)
- `src/client.c`, `src/player.c`, `src/weapons.c` — native CSQC weapon-definition setup (`MSG_CSQC`, `MSG_ONE_NORECORD`), prediction flags, weapon animation redirection.
- `CMakeLists.txt` — build wiring for the new C sources (`antilag.c`, `weaponpred_defs.c`).

### ⚠️ Silent default change: every usermode now starts with `sv_antilag 1`
`common_um_init` (`src/commands.c`) changed from `"sv_antilag 2\n"` to `"sv_antilag 1\n"` — faithfully matching dusty-qw/ktx master, but worth flagging explicitly: **every usermode init (1on1, 2on2, etc.) now forces Antilag 1 (EZCSQC) by default**, overriding any prior vote, unless something else sets it back. Given the crash risk described below when the paired MVDSV doesn't have real EZCSQC support, **you may want to override this default back to `2` (or `0`) until a compatible MVDSV is deployed.**

## ⚠️ Server requirements and crash risks (READ THIS — this is not optional)

**Both antilag modes have a real crash risk against MVDSV builds that don't fully implement the extensions KTX assumes are present. This is not a hypothetical — both were reproduced or confirmed against actual server code during this port's validation.**

| System | Works with stock QW-Group MVDSV `master` (current, as of this PR)? | Notes |
|---|---|---|
| **Antilag 2** (QW-Group native rewind) | ❌ **No — server crashes on the first projectile fired by any player, see below** | Not a hypothetical: confirmed by direct code inspection against QW-Group/mvdsv `master` HEAD. |
| **Antilag 1** (dusty-qw EZCSQC) | ❌ **No** | Requires [dusty-qw/mvdsv](https://github.com/dusty-qw/mvdsv) (`master`, current — see branch note above) for its EZCSQC-specific extensions. |

### 🔴 Antilag 2 crash: unconditional, no malicious client needed

This is a bigger problem than "grenades look glitchy" (see the visual bug section below) — this is a **server crash**, and it doesn't require Antilag 1, EZCSQC, or any special client userinfo:

- QW-Group/mvdsv's current `master` **advertises** the `setsendneeded` extension by name (`src/pr2_cmds.c`, extension table) but its implementation is a stub: `EXT_SetSendNeeded()` calls `PR2_RunError("SetSendNeeded not implemented yet.")`, which is fatal (`SV_Error`).
- This KTX port detects server extensions **by name** (`G_InitExtensions` in `src/g_main.c`), so `HAVEEXTENSION(G_SETSENDNEEDED)` reads **true** against current QW-Group MVDSV, even though the underlying call isn't actually implemented.
- Every projectile fire path (`W_FireRocket`, `W_FireGrenade`, `launch_spike` — used by both nailgun variants) unconditionally calls `ScheduleProjectileSendIfLive()`, which calls `SetSendNeeded()` — **with no `sv_antilag` check, no userinfo check, nothing.**
- **Net effect: on current QW-Group/mvdsv `master`, the first rocket, grenade, or nail fired by any connected player crashes the server.** This is independent of antilag mode (0, 1, or 2) and independent of anything the client sets in its userinfo.
- Nuance: on older QW-Group MVDSV builds that don't advertise `setsendneeded` at all, this doesn't crash — instead `SetSendNeeded()`'s own fallback path prints `"SetSendNeeded needs support in server"` to global chat on every single projectile fired (spammy, but not fatal).
- **This was missed in earlier validation of this PR** because the "stock QW-Group MVDSV, no crash" test was done with no client connected — nobody fired a projectile. A subsequent audit (see the Fable audit note below) caught this by static analysis of the actual extension table and stub implementation.

### 🔴 Antilag 1 (EZCSQC) risk — as previously documented

Antilag 1 depends on server-side protocol support that stock/QW-Group MVDSV does not implement:
- Native EZCSQC protocol advertisement.
- Per-client `ezcsqc_ready` readiness tracking (client must ack reliable native CSQC setup before antilag-1 state is trusted).
- The `SetLastRuntime` QC extension exposed by `pr2_cmds.c`.
- `MSG_CSQC` and `MSG_ONE_NORECORD` as valid `WriteByte`/`WriteFloat` destinations — both are dusty-qw/mvdsv-specific additions.

**On stock/QW-Group MVDSV, this is a second, independent crash path**: the CSQC weapon-prediction code gates on the `ezcsqc` / `ezcsqc_ready` **userinfo keys**, which are set by the *client*, not verified against the server. `WriteByte`/`WriteFloat` to `MSG_CSQC` or `MSG_ONE_NORECORD` are not implemented destinations on stock MVDSV — sending to them errors out fatally. In practice: **if a client sets `ezcsqc`/`ezcsqc_ready` in its userinfo while connected to a server running this KTX build on stock MVDSV, it can trigger a server-side crash** — inherited as-is from dusty-qw/ktx, unmodified in this port. **Do not run this build on a server exposed to untrusted clients unless it is paired with dusty-qw's MVDSV.**

**Bottom line: don't run either antilag mode against stock QW-Group MVDSV in production.** Pair this KTX build with `dusty-qw/mvdsv` `master` (confirmed to implement `SetSendNeeded` and the EZCSQC extensions for real), or treat this as a work-in-progress that needs the MVDSV-side changes ported too (see "Path forward" below).

**Path forward:** since both antilag modes as implemented here need dusty-qw's MVDSV to function correctly and safely, the two options going forward are: (1) run dusty-qw's MVDSV (`master`) alongside this KTX as a companion server build, or (2) port the specific MVDSV-side changes both modes depend on (EZCSQC protocol advertisement, `ezcsqc_ready` tracking, `SetLastRuntime`, a real `SetSendNeeded` implementation, `MSG_CSQC`/`MSG_ONE_NORECORD` support — roughly `src/sv_ents.c`, `src/sv_user.c`, `src/pr2_cmds.c`, `src/server.h`, `src/qwprot` from dusty-qw/mvdsv) into whatever MVDSV `qwleague` runs. That MVDSV-side port is a separate, follow-up effort — happy to scope it if useful.

## ℹ️ Projectile CSQC networking is not gated by antilag mode (code fact) — but no visual glitch reproduced with a correct `csprogs.dat`

**Code-level fact, confirmed by inspection**: all four projectile-spawning paths in `src/weapons.c` (`W_FireRocket`, `W_FireGrenade`, `launch_spike` for both nailgun variants) unconditionally call `ScheduleProjectileSendIfLive()`, and `UpdateProjectileSendNeeded()` (every server frame) keeps re-sending projectile state via `MSG_CSQC` — **regardless of `sv_antilag`'s value (0, 1, or 2)**. Only the rewind/lag-compensation side (`antilag_lagmove_all_proj_bounce()` and friends in `src/antilag.c`) is actually gated on `if (cvar("sv_antilag") != 1) return;`. So the CSQC-networking switch and the rewind switch are two independent switches, and only the rewind one reads `sv_antilag`. This part is not in dispute — it's true of `dusty-qw/ktx` master unmodified, and `src/antilag.c` doesn't exist at all in QW-Group/ktx upstream, so this always-on CSQC networking is dusty-qw-specific.

**However**: an earlier test session reported a visual glitch (grenades appearing to jump/duplicate) under `sv_antilag 2`, and initially we assumed this was a direct, guaranteed consequence of the above. **We since rebuilt `csprogs.dat` directly from this PR's own `qcsrc/*.qc` (via `fteqcc`, not the stale prebuilt binary used in the first test session) and retested against dusty-qw/mvdsv `master` with `sv_antilag 2` — the visual glitch did not reproduce.** So:

- The always-on CSQC networking described above is real and unconditional at the code level.
- Whether it's *visually noticeable* seems to depend heavily on which `csprogs.dat` build the client is running — a mismatched/stale CSQC build was very likely the dominant cause of the glitch actually observed, not the missing `sv_antilag` gate by itself.
- We have **not** ruled out that the always-on networking causes some subtler effect (e.g. extra bandwidth, redundant entity updates, edge cases with prediction/interpolation under packet loss) even when nothing looks visually wrong in casual play. This wasn't stress-tested.
- We're leaving the underlying code behavior documented here for transparency, but **downgrading this from "known bug" to "known code-level quirk, not confirmed as a visible defect"** given the retest with matching client/server CSQC sources didn't show it.

If you want this gated properly regardless (so Antilag 0/2 send zero CSQC projectile traffic, matching stock QW-Group KTX byte-for-byte on the wire), the smallest safe fix would be `ScheduleProjectileSendIfLive()`/`UpdateProjectileSendNeeded()` behind `sv_antilag == 1`. Happy to make that change if desired — just say so, since it's a deviation from the "unmodified port" approach used elsewhere in this PR.

## 🐛 Additional bugs inherited from dusty-qw/ktx, found in a follow-up audit (not fixed, documented per the same policy)

- **World-entity antilag pool has no bounds check and is never reset**: `ANTILAG_MEMPOOL[256]` (`include/progs.h`), world-entity slots start at index 64 and `ANTILAG_MEMPOOL_WORLDSEEK` only ever increments, never resets or bounds-checks. Any map with more than ~192 antilag-registered world entities (doors, plats, trains, lasers, func_bob, movewalls — all call `antilag_create_world()` on spawn) silently overflows the pool. Additionally, world entities removed via `killtarget` never call `antilag_delete_world()`, leaving stale pointers walked by `antilag_updateworld()`; and `antilag_delete_player()` dereferences `e->antilag_data` with no NULL-check and doesn't clear the pointer afterward, so a double-delete would corrupt the list.
- **Bot AI clock mismatch**: `src/fb_globals.c`'s `enemy_shaft_attack()` compares `self->client_time < enemy->attack_finished` — mixing the *attacker* bot's clock against the *target*'s cooldown timer, which lives in the target's own `client_time` domain. The equivalent check in `bot_botweap.c` correctly uses `enemy->client_time`. Identical to dusty-qw/ktx master — not introduced by this port.
- **Incomplete `client_time` conversion, already present in dusty-qw upstream**: `src/grapple.c` and `src/doors.c` set a *player's* `attack_finished` from `g_globalvars.time` instead of `client_time` in a couple of spots; since `client_time ≤ g_globalvars.time`, this stretches those specific cooldowns by roughly the player's ping. Low severity, but real, and present in dusty-qw/ktx master before this port.
- **`g_syscalls.asm` trap numbering**: dusty-qw renumbered several QVM trap indices (`SetExtField`, `SetSendNeeded`, etc.) when adding `SetLastRuntime`; this port kept the pre-existing `qwleague` numbering and appended `SetLastRuntime` at the next free slot instead. This only matters for QVM (bytecode) builds — irrelevant for the native `.so` build this port was validated with, since extension resolution there is by name, not by fixed trap number. Flagging in case a QVM build is ever attempted against dusty-qw's MVDSV specifically.

## ✅ Validation performed

- **Build**: compiled clean from scratch (WSL/Debian, gcc 14.2 + CMake) — 0 errors, no new warnings. Also validated CMake configuration succeeds standalone. Also compiled dusty-qw/mvdsv `master` from scratch for local testing.
- **Runtime, with a real connected client**: ran this KTX build against a freshly-built **dusty-qw/mvdsv `master`** (chosen over `antilag-new`, which turned out to be stale relative to `master`), map `aerowalk`, both `sv_antilag 1` and `sv_antilag 2`, across two sessions. Server stayed up, a real player connected and played (no crash observed, since dusty-qw/mvdsv implements `SetSendNeeded` for real). First session (stale, mismatched `csprogs.dat`) showed a grenade visual glitch; second session (with `csprogs.dat` rebuilt directly from this PR's own `qcsrc/*.qc`) did **not** reproduce it — see the "Projectile CSQC networking" section above for the full writeup and what's still an open question.
- **Also tested**: loaded the compiled `qwprogs.so` into a freshly-built **stock QW-Group MVDSV** with no client connected — server initializes and stays up. **This test did not fire a projectile, so it did not catch the `SetSendNeeded` crash described above** — that crash was found afterward by static analysis of QW-Group/mvdsv's extension table and stub implementation, not reproduced live in this session. Treat it as confirmed-by-code-inspection, not confirmed-by-live-repro.
- **Not tested live**: the QW-Group-MVDSV `SetSendNeeded` crash (confirmed by code inspection, not reproduced against a live server with a firing client); the MSG_CSQC/MSG_ONE_NORECORD crash scenario with a malicious client's userinfo (also code-inspection only); full hit-registration accuracy validation for Antilag 1 rewind.
- Recommend testing directly against dusty-qw/mvdsv only, and not against stock/QW-Group MVDSV, until the "Path forward" MVDSV-side work is done.

## 🔍 Coverage audit

- **File coverage**: diffed the complete file list from `dusty-qw/ktx`'s `non-antilag..master` range (excluding sprays) against every file touched by this PR. Missing: `qcsrc/fteqcc64` (prebuilt compiler binary, deliberately excluded), the gender-neutral-pronoun support in `g_utils.c`, dusty's example-config doc comments, and a few repo/tooling files — all listed above under "Not ported."
- **Antilag 1 (KTX side) build**: clean from-scratch build of `qwprogs.so` (0 errors) and a clean from-scratch `fteqcc` compile of `qcsrc/*.qc` into `csprogs.dat` (0 warnings).
- **Antilag 2 (MVDSV side) parity**: diffed `dusty-qw/mvdsv`'s `master` directly against `QW-Group/mvdsv`'s `master` for every file that implements native antilag (`sv_phys.c`, `pr_cmds.c`, `sv_user.c`) — the `sv_antilag`/`sv_antilag_no_pred`/`sv_antilag_projectiles` cvars and the trace/physics logic that reads them are **byte-for-byte identical**; dusty-qw only adds new code alongside it (mostly behind `#ifdef`s for EZCSQC/sprays). It doesn't touch the existing antilag-2 code path itself — but see the `SetSendNeeded` stub issue above, which is on the QW-Group MVDSV side, not something dusty-qw changed.
- **Sync check**: confirmed the branch pushed to this PR (`port/antilag-1-and-2`) matches the local working copy and the private staging repo (`tibazera/antilagezqc-qwleague`) exactly.

**This coverage audit, and the crash/bug findings above (the `SetSendNeeded` stub crash, the always-on projectile CSQC networking, the antilag world-entity pool overflow, the bot clock mismatch, and the incomplete `client_time` conversions) were found by an independent review pass using Claude Fable 5, run specifically to catch anything missed in the initial port and self-review.**

## 🚫 Not touched
- `qwleague`'s own matchmaking/tournament code (tokens, Bo3 series, match flow, spectator/stats) — untouched and unaffected.
- MVDSV — this PR is KTX-only, as scoped. No changes were made to dusty-qw's original antilag/CSQC logic during the port.

## 🔀 How to select antilag mode
Reuses dusty-qw's existing 3-way vote/cvar mechanism (off / antilag 1 / antilag 2) — no new UI or command surface introduced. Note the new default of `sv_antilag 1` on usermode init (see above).
