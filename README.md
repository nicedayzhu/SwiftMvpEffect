# SwiftMvpEffect

**English** | [简体中文](README_CN.md)

A SwiftlyS2 plugin that presents a client-animated MVP particle overlay when CS2
emits `round_mvp`. Each viewer receives an isolated effect, while the server only
handles creation, visibility, and cleanup.

## Demo

<video controls preload="metadata" poster="docs/mvp_effect_demo_poster.png" width="960">
  <source src="docs/mvp_effect_demo.mp4" type="video/mp4">
  Your Markdown viewer does not support embedded video.
  <a href="docs/mvp_effect_demo.mp4">Open the MP4 demo</a>.
</video>

[Open or download the in-game demo (MP4)](docs/mvp_effect_demo.mp4)

## Highlights

- Automatically responds to `round_mvp`.
- Shows the effect to all players or only the MVP player.
- Uses owner-only transmit isolation for every viewer.
- Animates movement, scale, and fading locally on the client.
- Includes a transparent default emblem and an optional 60-frame atlas test.
- Cleans up safely on repeated activation, disconnect, round start, and unload.
- Provides automated Source 2 resource generation, verification, and test
  deployment.

## Quick start

Requires .NET 10, PowerShell 7+, SwiftlyS2.CS2 1.4.3, and CS2 Workshop Tools
when compiling game resources.

```powershell
pwsh -NoProfile -File .\tools\generate_assets.ps1
dotnet restore --ignore-failed-sources
pwsh -NoProfile -File .\tools\verify.ps1
```

For Source 2 compilation, test deployment, SearchPaths, and Workshop release
guidance, see the [technical guide](docs/TECHNICAL_GUIDE.md).

## Configuration

The plugin reads `mvp_effect.json` at startup. It supports enabling/disabling the
effect, selecting `all` or `mvp` as the audience, and adjusting scale and vertical
offset. Reload the plugin after changing the file.

[Configuration reference](docs/TECHNICAL_GUIDE.md#configuration)

## Test commands

| Command | Purpose |
|---|---|
| `swift_mvp_test` | Play the default transparent MVP effect for one player |
| `swift_mvp_test_atlas` | Play the preserved 60-frame atlas variant |

## Documentation

- [Technical guide](docs/TECHNICAL_GUIDE.md): architecture, asset pipeline,
  build, verification, deployment, and production distribution.
- [中文技术指南](docs/TECHNICAL_GUIDE_CN.md).
- [Third-party asset notes](THIRD_PARTY_ASSETS.md): source material and
  redistribution considerations.

## Distribution note

The included `gameinfo.gi + overrides/*.vpk` workflow is intended only for local
development, test servers, and release acceptance. Production particle resources
should be distributed through CS2 Workshop, while the SwiftlyS2 DLL and
configuration are deployed separately by the server owner.
