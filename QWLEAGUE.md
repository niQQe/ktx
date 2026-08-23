# QWLeague — KTX matchmaking mods

This is the **`qwleague`** branch: a fork of
[QW-Group/ktx](https://github.com/QW-Group/ktx) carrying the server-side mods
that power [QWLeague](https://qwleague.com)'s matchmade games. It tracks upstream
KTX and layers the league logic on top.

## What it adds

- **Match-token connect gate** — only rostered players' tokens may join a
  matchmade server. IP-to-token binding was removed so players connecting through
  qwfwd / UDP proxies aren't locked out.
- **Bo3/BoN series** — one server plays an ordered map list via `k_series_*`.
- **Recoverable-disconnect match flow** — ready-gate warmup, per-map forfeit,
  `reconnect` / `proceed` / `abort`, and a no-fault early-abort window (`k_mm_*`).
- **Spectator auto-promote** + **QWLeague stats POST** (`/ServerApi/*`).
- Assorted `motd` / `vote` / `world` tweaks for matchmade servers.

Most behaviour is gated behind `k_qwleague_*` / `k_mm_*` cvars (off by default),
so it stays inert on non-matchmade servers.

## Use these mods in your own KTX build

```bash
git remote add qwleague https://github.com/niQQe/ktx.git
git fetch qwleague
git merge qwleague/qwleague        # bring the mods onto your branch
# …or replay just the mod commits onto any base:
#   git cherry-pick <upstream-base>..qwleague/qwleague
```

Then build `qwprogs.so` as usual (see upstream KTX build docs).

---
Based on upstream KTX; this branch is periodically rebased onto the latest
`master`. Issues/PRs for the league mods go here, not upstream.
