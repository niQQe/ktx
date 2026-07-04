## 🎯 Summary

This PR ports **both antilag systems** from [dusty-qw/ktx](https://github.com/dusty-qw/ktx) into `qwleague`, giving server operators a choice between:

- 🛰️ **Antilag 1** — dusty-qw's new CSQC-native antilag (EZCSQC-based weapon prediction/rewind). **⚠️ Requires a companion MVDSV with EZCSQC support — see [Server Requirements](#-server-requirements-read-this-this-is-not-optional) below.**
- 🕹️ **Antilag 2** — the official QW-Group MVDSV-native antilag (`sv_antilag 2`, engine-side rewind, no KTX code involved). Works with **any stock MVDSV**.

Selection between the two (and off) is done through the existing dusty-qw 3-way vote/cvar mechanism, ported as-is, unmodified.

**Note on scope:** the code in this PR is a **direct, unmodified port of dusty-qw/ktx**. Nothing was changed, hardened, or "fixed" during the port — it reproduces dusty-qw's implementation as-is, including its assumption that it always runs paired with dusty-qw's own MVDSV. See the risk note below.

## 📦 What's included

Source: [dusty-qw/ktx](https://github.com/dusty-qw/ktx) branches `master` and `antilag-new` (built on top of `master`), diffed against `non-antilag` to isolate a clean patch set, then reapplied on top of `qwleague`.

### Core antilag/rewind + weapon prediction (dusty-qw `master` + `antilag-new`) — new files
- `src/antilag.c` (828 lines) — hitscan and projectile rewind core: lag compensation, grenade launcher physics, rocket knockback fixes, teleporter/moving-platform edge cases, extrapolation.
- `src/weaponpred_defs.c` (464 lines) + `qcsrc/weaponpred.qc` (1127 lines) — client-side weapon prediction plumbing (axe, GL, LG made predictable).

### Core integration
- `src/vote.c` — 3-way antilag vote (off / antilag 1 / antilag 2), ported from dusty-qw.
- `src/combat.c`, `src/world.c`, `src/g_utils.c`, `src/g_main.c`, `src/commands.c`, `src/match.c` — hooks wiring antilag state into damage, knockback, spawn/frame handling and commands.
- `src/g_syscalls.c` / `src/g_syscalls.asm` — new QC syscalls required by the antilag/weapon-prediction code (e.g. `SetLastRuntime`).
- `include/g_consts.h`, `include/g_local.h`, `include/g_syscalls.h` — supporting fields/consts.

### Antilag 1 — CSQC/EZCSQC layer (dusty-qw `antilag-new` only)
- `qcsrc/main.qc` (314 lines, new), `qcsrc/fteextensions.qc` (3709 lines, new), `qcsrc/progs.src` — CSQC/FTE extension groundwork required for native CSQC entity handling.
- `src/client.c` (+297 lines), `src/player.c` (+215 lines), `src/weapons.c` (+346 lines) — native CSQC weapon-definition setup (`MSG_CSQC`, `MSG_ONE_NORECORD`), prediction flags, weapon animation redirection.
- `CMakeLists.txt` — build wiring for the new C sources (`antilag.c`, `weaponpred_defs.c`).

**Total diff vs `qwleague`:** 23 files changed, +7511 / -79 lines.

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

## ✅ Validation performed

- **Build**: compiled clean from scratch (WSL/Debian, gcc 14.2 + CMake) — 0 errors, no new warnings. Also validated CMake configuration succeeds standalone.
- **Runtime**: loaded the compiled `qwprogs.so` into a freshly-built **stock QW-Group MVDSV** (no dusty-qw changes), map `aerowalk`. Server initializes, loads the library, and runs stable with no crash — with no client connected. This does **not** exercise the CSQC/`MSG_CSQC` code paths described in the risk note above (those only trigger once a client sets the relevant userinfo keys).
- **Not tested**: live hit-registration/rewind behavior with a real or bot player in combat (requires a connected QW client, not set up in this validation pass); Antilag 1 end-to-end (requires the dusty-qw MVDSV companion, out of scope here); the crash scenario described above (not deliberately reproduced, only identified by code review).
- Recommend a manual smoke test with a real client, and pairing with dusty-qw's MVDSV before enabling Antilag 1 anywhere.

## 🚫 Not touched
- `qwleague`'s own matchmaking/tournament code (tokens, Bo3 series, match flow, spectator/stats) — untouched and unaffected.
- MVDSV — this PR is KTX-only, as scoped. No changes were made to dusty-qw's original antilag/CSQC logic during the port.

## 🔀 How to select antilag mode
Reuses dusty-qw's existing 3-way vote/cvar mechanism (off / antilag 1 / antilag 2) — no new UI or command surface introduced.
