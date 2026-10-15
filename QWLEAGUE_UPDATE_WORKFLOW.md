# QWLeague Update Workflow

This fork combines two independently moving code lines:

- QWLeague matchmaking gamecode from `niQQe/ktx`, branch `qwleague`.
- Antilag 1 and its CSQC support ported from `dusty-qw/ktx`, branch `master`.

Neither side may be replaced wholesale. Every QWLeague update must be merged into
this fork while preserving the dusty-qw Antilag 1 implementation and the matching
client-side CSQC program.

## Required Inputs

Record these before starting:

- QWLeague source commit.
- dusty-qw source commit used as the Antilag 1 reference.
- Current production agent version.
- Current `qwprogs.so`, `csprogs.dat`, and MVDSV SHA-256 hashes.

Do not migrate from an unversioned tarball or an unidentified binary. If the
QWLeague source commit is unavailable, stop and request it.

## Merge Procedure

1. Fetch `niQQe/ktx:qwleague` and `dusty-qw/ktx:master`.
2. Create a dedicated integration branch from the latest validated fork.
3. Merge the new QWLeague commits. Never replace the fork with their branch.
4. Review every conflict and every change touching:
   - `src/antilag.c`
   - `src/weapons.c`
   - `src/weaponpred_defs.c`
   - `src/client.c`
   - `src/world.c`
   - `src/match.c`
   - `src/commands.c`
   - `src/stats_json.c`
   - `qcsrc/`
5. Compare Antilag 1 behavior with dusty-qw, not just symbol names. Preserve
   projectile rewind, player rewind, precise frame timing, EZCSQC readiness,
   projectile runtime marking, and the matching CSQC wire format.
6. Preserve all QWLeague behavior: token validation, forced teams/names/colors,
   series state, reconnect/forfeit handling, stats POSTs, shutdown, demos, and QTV.

## Build Gates

Build both artifacts from the same merged commit:

```bash
cmake -B build .
cmake --build build
cd qcsrc
fteqcc64 -srcfile progs.src
```

Run the audit from the repository root:

```bash
tools/audit-qwleague-antilag-build.sh niqqe/qwleague
```

The audit must confirm:

- The requested QWLeague commit is an ancestor of the merged branch.
- `qwprogs.so` and `csprogs.dat` both exist.
- Required Antilag 1, CSQC, and QWLeague symbols exist in `qwprogs.so`.
- The source still gates Antilag 1 rewind on `sv_antilag == 1`.
- Artifact hashes are recorded.

`SV_ANTILAG=1` in `.env` or a generated CFG is not proof that the custom
implementation is present.

## Runtime Gates

Deploy first to one idle QWLeague test region and validate:

1. Agent starts and adopts the server.
2. Generated CFG contains `sv_antilag 1`.
3. The running process maps the expected `qwprogs.so` hash.
4. Two clients with different latency test hitscan, rockets, grenades, and
   rocket jumps without jitter, duplication, or smoke near the camera.
5. `csprogs.dat` matches the same merged commit.
6. Connect, reconnect, technical timeout, proceed, abort, and forfeit work.
7. A complete series changes maps and recreates its join/abandon watchdog.
8. Stats POSTs arrive with the correct pinned player tokens.
9. MVD finalization, QTV playback, Hub registration, and graceful shutdown work.

Only after these gates pass may the same immutable artifacts be deployed to the
other QWLeague regions. Never compile independently on each production host.

## Post-Deployment Guard

For every region, record and monitor:

- Agent version.
- MVDSV SHA-256.
- On-disk `qwprogs.so` SHA-256.
- Hash of the `qwprogs.so` mapped by each newly spawned MVDSV process.
- `csprogs.dat` SHA-256.
- Merged QWLeague and dusty-qw commit IDs.

If a managed update changes `qwprogs.so`, mark the region as needing review.
Do not silently restore an old custom binary: merge the new QWLeague source into
this fork, rebuild both artifacts, repeat the gates, and then deploy.

## Rollback

Keep the last validated artifact set and its manifest. Roll back `qwprogs.so`,
`csprogs.dat`, and the compatible MVDSV as one tested set. A rollback is complete
only after a fresh server process maps the expected hashes.

