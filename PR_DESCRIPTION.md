## 🎯 Summary

This PR ports **both antilag systems** from [dusty-qw/ktx](https://github.com/dusty-qw/ktx) into `qwleague`, giving server operators a choice between:

- 🛰️ **Antilag 1** — dusty-qw's new CSQC-native antilag (EZCSQC-based weapon prediction/rewind). **⚠️ Requires a companion MVDSV with EZCSQC support — see [Server Requirements](#-server-requirements-read-this-this-is-not-optional) below.**
- 🕹️ **Antilag 2** — the official QW-Group MVDSV-native antilag (`sv_antilag 2`, engine-side rewind). Works with **any stock MVDSV** and does not run the rewind logic in `antilag.c` — **but see the known grenade visual bug below, which is a real KTX-side side effect that isn't fully gated by the antilag mode.**

Selection between the two (and off) is done through the existing dusty-qw 3-way vote/cvar mechanism, ported as-is, unmodified.

**Note on scope:** the code in this PR is a **direct, unmodified port of dusty-qw/ktx**. Nothing was changed, hardened, or "fixed" during the port — it reproduces dusty-qw's implementation as-is, including its assumption that it always runs paired with dusty-qw's own MVDSV. See the risk note below.

## 📦 What's included

Source: **[dusty-qw/ktx](https://github.com/dusty-qw/ktx) branch `master`** (the `antilag-new` branch used in an earlier revision of this PR turned out to be stale — `master` already contains everything `antilag-new` had plus additional fixes, e.g. weapon-prediction-on-respawn and EZCSQC readiness tracking — this PR now ports from `master`). Diffed against dusty-qw's `non-antilag` branch (a "no antilag at all" baseline) to isolate a clean patch set, then reapplied on top of `qwleague`.

**Scope:** everything in the `non-antilag..master` diff is included **except sprays** (`src/sprays.c`, `src/sv_sprays.c`, `G_SPRAYCLEAR`/`G_SPRAYCLEARALL` — an unrelated decal feature, deliberately left out). That means a few small non-antilag things rode along in the same dusty-qw commits and are included here too:

- **`k_drp` / `dropmessage`** — a chat message announcing which weapon was dropped in a backpack on death. **This does not exist in [QW-Group/ktx](https://github.com/QW-Group/ktx) upstream** — it's dusty-qw-specific. Purely cosmetic, doesn't touch antilag/timing/physics. **Happy to drop this on request** if you'd rather not carry it — it's isolated to `commands.c` (`ToggleDropMessage`, `CD_DROPMSG`), `items.c` (`DropBackpack`), `match.c` (status line), and one `RegisterCvar` in `world.c`.
- socd/strafe-detection counters and `ToggleToT`/`sv_time` reordering — these already exist in QW-Group/ktx upstream (confirmed), the dusty-qw diff just touches the same lines incidentally.
- **`safestrafe` command / `sv_safestrafe` cvar** — see the dedicated section below. **Not approved/reviewed by QW-Group, and has a real permission gap. We recommend removing it.**

### ⚠️ `safestrafe` — present, not vetted by QW-Group, any player can toggle it server-wide

This PR carries over dusty-qw's `safestrafe` feature (anti-strafe-jump/SOCD enforcement): a `sv_safestrafe` mvdsv cvar plus a KTX-side `safestrafe` player command (`src/commands.c`: `{ "safestrafe", ToggleSafeStrafe, 0, CF_PLAYER | CF_SPC_ADMIN, CD_SAFESTRAFE }`, implemented in `src/admin.c`'s `ToggleSafeStrafe()`).

**It is not gated by antilag mode** — confirmed by code inspection on both sides (KTX and dusty-qw/mvdsv): `safestrafe`/`SV_ApplySafestrafe` has zero references to `sv_antilag`, `ezcsqc`, or `csqc` anywhere, and the antilag rewind code (`antilag.c`, `SV_CurrentAntilagRewindMsec`, etc.) has zero references to `safestrafe`. **It behaves identically whether Antilag 1, Antilag 2, or antilag off is selected.**

**🔴 Permission gap, confirmed by code inspection:** the `CF_SPC_ADMIN` flag on the `safestrafe` command only requires admin rights *if the caller is a spectator* (`CF_SPC_ADMIN` = "client is spectator, so this command requires admin rights" per the flag's own definition in `g_local.h`). For a regular **player** (`CF_PLAYER`), there is **no admin check at all**. Combined with `ToggleSafeStrafe()`'s own guard (`if (match_in_progress) return;` — the only restriction is that it can't be toggled mid-match), this means: **any connected player, with no admin rights, can toggle `sv_safestrafe` on/off for the entire server** outside of an active match, changing movement-enforcement behavior for everyone.

This isn't part of the antilag work this PR is about — it rode along in the same `non-antilag..master` diff. **We recommend removing `safestrafe` entirely** (or at minimum gating it behind real admin rights) since it hasn't been reviewed/approved by QW-Group and introduces an unreviewed, ungated server-wide toggle. Happy to strip it out if you'd rather not carry it — same offer as `k_drp` above.

### Core antilag/rewind + weapon prediction — new files
- `src/antilag.c` (853 lines) — hitscan and projectile rewind core: lag compensation, grenade launcher physics, rocket knockback fixes, teleporter/moving-platform edge cases, extrapolation.
- `src/weaponpred_defs.c` (464 lines) + `qcsrc/weaponpred.qc` (1127 lines) — client-side weapon prediction plumbing (axe, GL, LG made predictable).

### Core integration
- `src/vote.c` — 3-way antilag vote (off / antilag 1 / antilag 2), ported from dusty-qw.
- `src/combat.c`, `src/world.c`, `src/g_utils.c`, `src/g_main.c`, `src/commands.c`, `src/match.c`, `src/items.c`, `src/player.c` — hooks wiring antilag state into damage, knockback, spawn/frame handling, weapon-animation timing, and commands.
- `src/g_syscalls.c` / `src/g_syscalls.h` / `src/g_syscalls.asm` — new QC syscalls required by the antilag/weapon-prediction code (e.g. `SetLastRuntime`), plus a `trap_AddBot` signature change (adds a `skill` param) that came from the same upstream commits.
- `include/g_consts.h`, `include/g_local.h`, `include/g_syscalls.h` — supporting fields/consts.
- Small supporting fixes in `bot_commands.c`, `bot_aim.c`, `bot_botjump.c`, `bot_botpath.c`, `bot_botweap.c`, `bot_world.c`, `clan_arena.c`, `doors.c`, `fb_globals.c`, `func_bob.c`, `func_laser.c`, `hiprot.c`, `plats.c`, `race.c`, `triggers.c` — mostly switching from `g_globalvars.time` to `client_time` so gameplay timing respects antilag rewind, plus registering antilag-owned world entities.

### Antilag 1 — CSQC/EZCSQC layer
- `qcsrc/main.qc` (314 lines, new), `qcsrc/fteextensions.qc` (3709 lines, new), `qcsrc/progs.src`, `qcsrc/fteqcc.ini` — CSQC/FTE extension groundwork required for native CSQC entity handling. (Not `qcsrc/fteqcc64` — that's a prebuilt QuakeC compiler binary, deliberately excluded; you'll need your own toolchain to build the `.qc` sources into `csprogs.dat`.)
- `src/client.c`, `src/player.c`, `src/weapons.c` — native CSQC weapon-definition setup (`MSG_CSQC`, `MSG_ONE_NORECORD`), prediction flags, weapon animation redirection.
- `CMakeLists.txt` — build wiring for the new C sources (`antilag.c`, `weaponpred_defs.c`).

## ⚠️ Server requirements (READ THIS — this is not optional)

| System | Works with stock MVDSV? | Notes |
|---|---|---|
| **Antilag 2** (QW-Group official) | ✅ Yes | Engine-native (`sv_antilag 2`). No KTX-side dependency, no server changes needed. |
| **Antilag 1** (dusty-qw EZCSQC) | ❌ **No — and it is not merely inert, see risk below** | **Requires [dusty-qw/mvdsv](https://github.com/dusty-qw/mvdsv) branch `antilag-new`** (or an MVDSV build that incorporates its ~11 commits ahead of dusty-qw's own `master`). |

Antilag 1 depends on server-side protocol support that stock/QW-Group MVDSV does not implement:
- Native EZCSQC protocol advertisement.
- Per-client `ezcsqc_ready` readiness tracking (client must ack reliable native CSQC setup before antilag-1 state is trusted).
- The `SetLastRuntime` QC extension exposed by `pr2_cmds.c`.
- `MSG_CSQC` and `MSG_ONE_NORECORD` as valid `WriteByte`/`WriteFloat` destinations — both are dusty-qw/mvdsv-specific additions.

**🔴 Risk, not just a limitation:** the CSQC weapon-prediction code gates on the `ezcsqc` / `ezcsqc_ready` **userinfo keys**, which are set by the *client*, not verified against the server. On stock/QW-Group MVDSV, `WriteByte`/`WriteFloat` to `MSG_CSQC` or `MSG_ONE_NORECORD` are not implemented destinations — sending to them errors out in the QuakeC VM. In practice this means: **if a client sets `ezcsqc`/`ezcsqc_ready` in its userinfo while connected to a server running this KTX build on stock MVDSV, it can trigger a server-side progs error/crash.** This is inherited as-is from dusty-qw/ktx (unmodified in this port) — dusty-qw's code assumes it is always paired with dusty-qw's MVDSV and never runs on anything else. **Do not enable Antilag 1 / run this build on a server exposed to untrusted clients unless it is paired with dusty-qw's MVDSV (`antilag-new`).**

If you want to test Antilag 1, you'll need to run dusty-qw's MVDSV (`antilag-new` branch) alongside this KTX build. Antilag 2 works today with whatever MVDSV `qwleague` already uses.

**Path forward:** since **Antilag 1 needs dusty-qw's MVDSV to function correctly and safely**, the two options going forward are: (1) run dusty-qw's MVDSV (`antilag-new`) alongside this KTX as a companion server build, or (2) port the specific MVDSV-side changes it depends on (EZCSQC protocol advertisement, `ezcsqc_ready` tracking, `SetLastRuntime`, `MSG_CSQC`/`MSG_ONE_NORECORD` support — roughly `src/sv_ents.c`, `src/sv_user.c`, `src/pr2_cmds.c`, `src/server.h`, `src/qwprot` from dusty-qw/mvdsv) into whatever MVDSV `qwleague` runs. That MVDSV-side port is a separate, follow-up effort — happy to scope it if useful.

## 🐛 Known bug: grenade visual glitch (jumps/duplicates), even under Antilag 2

**Observed while testing**: with `sv_antilag 2` (QW-Group native antilag, KTX rewind code supposedly inactive) and a connected client, thrown grenades visually **jump/teleport or appear duplicated** in flight.

**Root cause, confirmed by code inspection — this is inherited from dusty-qw/ktx `master` unmodified, not something introduced by this port:**

- `W_FireGrenade()` in `src/weapons.c` unconditionally calls `ScheduleProjectileSendIfLive(newmis)` for every grenade thrown, **regardless of `sv_antilag`'s value**. This registers the grenade as a CSQC-networked entity (`ExtFieldSetSendEntity(projectile, SendEntity_Projectile)` + `SetSendNeeded(projectile, PROJECTILE_INITIAL, 0)`), and `UpdateProjectileSendNeeded()` (called every server frame from `world.c`'s `StartFrame`) keeps re-sending its origin via `MSG_CSQC` for as long as it's alive — again with no `sv_antilag` check.
- Only the **rewind/lag-compensation** side (`antilag_lagmove_all_proj_bounce()` in `src/antilag.c`) is correctly gated on `if (cvar("sv_antilag") != 1) return;` — confirmed by direct inspection, matches `dusty-qw/ktx` master line-for-line.
- Net effect: **even in Antilag 2 (or antilag off)**, the server keeps sending CSQC entity updates for grenades via `MSG_CSQC`/`SendEntity_Projectile`. A client that renders CSQC entities (e.g. an EZCSQC-aware ezquake build) ends up drawing the grenade from **two sources at once**: the normal QW baseline/delta entity update, and the CSQC projectile mirror — which don't agree on interpolation, causing the jump/duplicate artifact. This is **not** exclusive to Antilag 1; it's a side effect of KTX always arming the CSQC mirror for grenades.
- Compounding factor in this test environment specifically: the `csprogs.dat` loaded on the test server was a stale prebuilt binary (~2 days older than the `qcsrc/*.qc` sources in this port), so the client-side CSQC code and the server's wire format may not even agree — this alone could produce visual desync independent of the above. **This is an artifact of the local test setup, not something this PR ships** (this PR does not include a prebuilt `csprogs.dat` — see the "Antilag 1 — CSQC/EZCSQC layer" section above).
- **Confirmed this is not a QW-Group/ktx behavior**: `src/antilag.c` (where the rewind logic lives) does not exist at all in [QW-Group/ktx](https://github.com/QW-Group/ktx) upstream, so this grenade-CSQC-always-on behavior is dusty-qw-specific, present in `master` before this port and carried over unmodified per the "no fixes during port" scope decision for this PR.

**This was not fixed in this PR** (per the earlier decision to port dusty-qw/ktx unmodified and document risks instead of patching them). If this needs a fix, the smallest safe change would be gating `ScheduleProjectileSendIfLive()`/`UpdateProjectileSendNeeded()`'s grenade path behind `sv_antilag == 1` (or behind a CSQC-capability check per client) so Antilag 2 and antilag-off behave identically to stock QW-Group KTX. Happy to make that change if desired — just say so, since it would be a deviation from the "unmodified port" approach used everywhere else in this PR.

## ✅ Validation performed

- **Build**: compiled clean from scratch (WSL/Debian, gcc 14.2 + CMake) — 0 errors, no new warnings. Also validated CMake configuration succeeds standalone. Also compiled dusty-qw/mvdsv `master` from scratch for local testing.
- **Runtime, with a real connected client**: ran this KTX build against a freshly-built **dusty-qw/mvdsv `master`** (chosen over `antilag-new`, which turned out to be stale relative to `master` — see the branch note above), map `aerowalk`, both `sv_antilag 1` and `sv_antilag 2`. Server stayed up, a real player connected and played (no crash observed in this session). **Found the grenade visual bug documented above** while doing this — reproduced under `sv_antilag 2`.
- **Also tested**: loaded the compiled `qwprogs.so` into a freshly-built **stock QW-Group MVDSV** (no dusty-qw changes) with no client connected — server initializes, loads the library, and runs stable with no crash. This does **not** exercise the CSQC/`MSG_CSQC` code paths described in the risk note above (those only trigger once a client sets the relevant userinfo keys or the server sends CSQC entity updates, as in the grenade bug above).
- **Not tested**: the MSG_CSQC/MSG_ONE_NORECORD crash scenario on stock MVDSV described in the risk note above (not deliberately reproduced with a malicious client, only identified by code review); full hit-registration accuracy validation for Antilag 1 rewind (requires more structured testing than a single manual session).
- Recommend further manual testing with real clients on both antilag modes, and pairing with dusty-qw's MVDSV before enabling Antilag 1 anywhere.

## 🚫 Not touched
- `qwleague`'s own matchmaking/tournament code (tokens, Bo3 series, match flow, spectator/stats) — untouched and unaffected.
- MVDSV — this PR is KTX-only, as scoped. No changes were made to dusty-qw's original antilag/CSQC logic during the port.

## 🔀 How to select antilag mode
Reuses dusty-qw's existing 3-way vote/cvar mechanism (off / antilag 1 / antilag 2) — no new UI or command surface introduced.
