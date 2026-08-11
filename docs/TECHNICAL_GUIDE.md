# SwiftMvpEffect Technical Guide

[Project home](../README.md) | **English** | [简体中文](TECHNICAL_GUIDE_CN.md)

This guide contains the implementation, resource-build, deployment, and
operations details intentionally kept out of the project homepage.

## Runtime architecture

SwiftMvpEffect listens for the CS2 `round_mvp` event and creates one owner-only
`info_particle_system` per target viewer. The server configures visibility and
control points once, starts the system, and later cleans it up. Position, scale,
and alpha animation run locally on the client from VPCF collection age.

The design reuses proven patterns from these local projects:

- `bj`: sequence atlas, screen overlay, CP assignment, and configuration before
  `Start`.
- `ptext`: independent sessions and transmit isolation after connection changes.
- `smb`: multi-entity lifecycle and failure cleanup.

Each effect instance follows this order:

1. Create `info_particle_system` with `start_active=false`.
2. Spawn it and set schema fields.
3. Enable transmit for the intended viewer and explicitly disable it for every
   other player.
4. Assign and write CP34.
5. Start the particle system.
6. Stop and remove it through the shared idempotent cleanup path.

Disconnect, round start, repeated activation, reload, and unload all use the same
cleanup contract.

## Configuration

Edit `mvp_effect.json` in the deployed plugin directory:

```json
{
  "enabled": true,
  "audience": "all",
  "scale": 0.50,
  "offsetY": 0.04
}
```

`audience` accepts:

- `all`: show the effect to every online player.
- `mvp`: show it only to the MVP player.

The configuration is loaded when the plugin starts. Reload the plugin after
making changes.

## Particle and texture pipeline

The default effect uses one transparent gold MVP emblem. The generator preserves
its aspect ratio inside a 1024×1024 transparent carrier and produces a lossless
RGBA8888 1024 texture, avoiding the first-frame overhead of a large atlas on the
normal `round_mvp` path.

The preserved test effect is generated from
`assets/source/clean_gold_operator_mvp_animation_pack_60f.zip`:

```text
60 source frames
  -> 60 512x512 transparent carrier frames
  -> MKS sequence
  -> lossless 4096 atlas VTEX
  -> mvp_atlas_overlay.vpcf
```

It is played only by `swift_mvp_test_atlas` and does not replace the default
effect.

Source and generated asset boundaries:

- `assets/source/`: user-provided source assets; generators must not overwrite
  them.
- `assets/generated/`: authorized generated artwork used by the default effect.
- `tools/templates/`: VTEX/VPCF templates.
- `resources_src/`: generated Source 2 source resources; do not edit by hand.
- `build/`: plugin output, manifests, and temporary compilation lists; ignored by
  Git.
- `docs/`: documentation media, including the MP4 demo and its poster; excluded
  from the game resource package.

See [THIRD_PARTY_ASSETS.md](../THIRD_PARTY_ASSETS.md) before publishing any
artwork or derived resources.

## Animation and control-point contract

The root's `m_flDepthSortBias` is fixed at `0`. CP34 is written once before
`Start`:

- `x`: scale.
- `z`: vertical offset.

The VPCF uses `PF_TYPE_COLLECTION_AGE` for all collection renderer animation.
Do not use `PF_TYPE_PARTICLE_AGE_NORMALIZED` inside
`CParticleCollectionRendererFloatInput`; the client can collapse that input to a
static value.

Thirteen continuous renderer intervals implement the full movement:

- 0.00–0.52 seconds: enter from the left and bounce.
- 0.52–1.62 seconds: hold in the center.
- 1.62–2.24 seconds: accelerate out to the right.
- Remaining lifetime: finish fading off-screen.

`m_flRadiusScale` provides the entry bounce and exit shrink.
`C_OP_FadeInSimple` and `C_OP_FadeOutSimple` control particle alpha. The atlas
variant uses the same movement and plays its 60-frame sequence with
`ANIMATION_TYPE_FIT_LIFETIME` at 25 FPS. No per-tick server CP replication is
required.

## Build and verification

Requirements:

- .NET 10 SDK.
- PowerShell 7 or newer.
- SwiftlyS2.CS2 1.4.3.
- CS2 Workshop Tools and `resourcecompiler.exe` for Source 2 resource builds.

Generate resources and run offline verification:

```powershell
pwsh -NoProfile -File .\tools\generate_assets.ps1
dotnet restore --ignore-failed-sources
pwsh -NoProfile -File .\tools\verify.ps1
```

Compile Source 2 resources:

```powershell
pwsh -NoProfile -File .\tools\build_source2_assets.ps1 -Force
```

The default addon namespace is `swift_mvp_effect`. The compiled game resources
are:

```text
game/csgo_addons/swift_mvp_effect/
  materials/swift_mvp_effect/mvp_animation_60f.vtex_c
  materials/swift_mvp_effect/mvp_emblem.vtex_c
  particles/swift_mvp_effect/mvp_atlas_overlay.vpcf_c
  particles/swift_mvp_effect/mvp_overlay.vpcf_c
```

`dotnet publish -c Release` writes the plugin DLL and configuration to:

```text
build/publish/SwiftMvpEffect/
```

The verification workflow rejects unresolved template tokens, invalid renderer
age inputs, unexpected root/child counts, incorrect depth-sort values, bad
resource paths, time-window gaps, and unexpected VPK contents.

## Override test deployment

The override workflow is only for local development, test-server integration,
and release acceptance. It is not a production player installation method.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\build_and_deploy.ps1 `
  -ForceAssetRebuild
```

The deployment script:

1. Runs offline resource and C# verification.
2. Publishes `SwiftMvpEffect.dll` and `mvp_effect.json`.
3. Compiles two VTEX_C and two VPCF_C files.
4. Packages only those four `_c` files into `swift_mvp_effect.vpk`.
5. Verifies checksums, the CS2 v2 single-file VPK header, the absence of an
   archive-MD5 chunk section, and the extracted file list.
6. Installs identical VPKs on the client and dedicated server.
7. Backs up and updates both `gameinfo.gi` files.
8. Deploys the server plugin and compares the VPK, DLL, and configuration
   SHA-256 hashes.

Do not enable `vpkeditcli --gen-md5-entries`; it can create an archive-MD5 chunk
layout that causes a dedicated server `Chunk hash not found` failure.

The server SearchPaths must keep SwiftlyS2 ahead of every override VPK:

```text
Game_LowViolence  csgo_lv
Game              csgo/addons/swiftlys2
Game              csgo/overrides/<existing-test-pack>.vpk
Game              csgo/overrides/swift_mvp_effect.vpk
Game              csgo
```

Deployment verification rejects a server configuration where
`csgo/addons/swiftlys2` appears after any override VPK.

After deployment, fully restart both the client and server. A DLL hot reload does
not refresh cached VTEX/VPCF resources.

Run the game-console tests:

```text
swift_mvp_test
swift_mvp_test_atlas
```

Verify an existing deployment without rebuilding:

```powershell
pwsh -NoProfile -File .\tools\verify_deployment.ps1
```

Remove only this project's test mount, VPKs, and server plugin:

```powershell
pwsh -NoProfile -File .\tools\uninstall_test_deployment.ps1
```

The uninstall script creates a timestamped backup before editing `gameinfo.gi`.

## Production distribution

| Scenario | Particle resources | SwiftlyS2 plugin |
|---|---|---|
| Local development/test server | Mount `swift_mvp_effect.vpk` in `overrides` on both client and server | Deployment script copies the DLL and configuration to the test server |
| Production | Publish reviewed compiled resources through CS2 Workshop | Server owner deploys the DLL and configuration separately |

Production release checklist:

1. Confirm asset rights, addon namespace, and version information.
2. Generate and verify VTEX_C/VPCF_C resources with this project's existing
   workflow.
3. Build a Workshop payload containing only approved compiled resources. Exclude
   private source assets, documentation media, development scripts, local paths,
   server configuration, and the SwiftlyS2 DLL.
4. Create or update the Workshop item and record its Item ID, version, and change
   notes.
5. Configure the server to obtain the Workshop content while deploying
   `SwiftMvpEffect.dll` and `mvp_effect.json` separately.
6. Test Workshop download, precaching, automatic MVP activation, and two-client
   transmit isolation on a clean client.
7. Switch from the override test environment only after acceptance passes.

The repository intentionally has no production Workshop Item ID or upload
automation until the publishing account, Workshop project, and asset permissions
are confirmed.
