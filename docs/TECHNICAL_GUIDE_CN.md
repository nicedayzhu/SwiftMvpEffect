# SwiftMvpEffect 技术指南

[项目主页](../README_CN.md) | [English](TECHNICAL_GUIDE.md) | **简体中文**

本指南集中说明实现架构、资源构建、部署与运维细节；这些内容从项目主页迁出，以保持
主页简洁。

## 运行时架构

SwiftMvpEffect 监听 CS2 的 `round_mvp` 事件，为每名目标观看者创建一个 owner-only
`info_particle_system`。服务器只负责设置可见性、一次性写入控制点、启动及清理实体；
位置、缩放和透明度动画由客户端根据 VPCF collection age 本地计算。

设计复用了以下本地项目中已经验证的模式：

- `bj`：sequence atlas、屏幕 overlay、CP assignment 与 Start 前配置。
- `ptext`：独立会话及连接变化后的 transmit 隔离。
- `smb`：多实体生命周期与失败清理。

每个效果实例遵循以下顺序：

1. 以 `start_active=false` 创建 `info_particle_system`。
2. Spawn 实体并设置 schema 字段。
3. 为目标观看者开启 transmit，并对其他所有玩家明确关闭。
4. 分配并写入 CP34。
5. 启动粒子系统。
6. 通过共享的幂等清理路径停止并移除实体。

断线、回合开始、重复触发、重载与卸载都会使用同一清理契约。

## 配置

编辑已部署插件目录中的 `mvp_effect.json`：

```json
{
  "enabled": true,
  "audience": "all",
  "scale": 0.50,
  "offsetY": 0.04
}
```

`audience` 支持：

- `all`：向所有在线玩家展示。
- `mvp`：仅向 MVP 玩家展示。

配置在插件启动时读取，修改后需要重载插件。

## 粒子与纹理流水线

默认效果使用一张透明金色 MVP 主视觉。生成器会保持比例，将其放入 1024×1024
透明 carrier，并生成无损 RGBA8888 1024 纹理，避免默认 `round_mvp` 路径承担大图集
首帧开销。

保留的测试效果由
`assets/source/clean_gold_operator_mvp_animation_pack_60f.zip` 生成：

```text
60 张源帧
  -> 60 张 512x512 透明 carrier 帧
  -> MKS sequence
  -> 无损 4096 atlas VTEX
  -> mvp_atlas_overlay.vpcf
```

它只由 `swift_mvp_test_atlas` 播放，不替换默认效果。

源码与生成资源边界：

- `assets/source/`：用户提供的源素材，生成器禁止覆盖。
- `assets/generated/`：默认效果使用的、经授权生成的美术资源。
- `tools/templates/`：VTEX/VPCF 模板。
- `resources_src/`：生成的 Source 2 源资源，禁止手改。
- `build/`：插件输出、清单和临时编译列表，不纳入 Git。
- `docs/`：文档媒体，包括 MP4 演示及其封面，不进入游戏资源包。

公开发布美术或衍生资源前，请先阅读
[THIRD_PARTY_ASSETS.md](../THIRD_PARTY_ASSETS.md)。

## 动画与控制点契约

根的 `m_flDepthSortBias` 固定为 `0`。CP34 在 `Start` 前只写一次：

- `x`：缩放。
- `z`：纵向偏移。

VPCF 的集合 renderer 动画统一使用 `PF_TYPE_COLLECTION_AGE`。不要在
`CParticleCollectionRendererFloatInput` 中使用
`PF_TYPE_PARTICLE_AGE_NORMALIZED`，否则客户端可能将其退化为静态值。

13 个连续 renderer 时间段构成完整运动：

- 0.00–0.52 秒：从左侧进入并回弹。
- 0.52–1.62 秒：停留在屏幕中心。
- 1.62–2.24 秒：向右加速飞出。
- 剩余生命周期：在屏幕外完成淡出。

`m_flRadiusScale` 实现入场回弹与离场收缩；`C_OP_FadeInSimple` 和
`C_OP_FadeOutSimple` 控制粒子 alpha。Atlas 版本使用相同运动，并以
`ANIMATION_TYPE_FIT_LIFETIME`、25 FPS 播放 60 帧 sequence，无需服务器逐 Tick
复制控制点。

## 构建与验证

环境要求：

- .NET 10 SDK。
- PowerShell 7 或更高版本。
- SwiftlyS2.CS2 1.4.3。
- 编译 Source 2 资源时需要 CS2 Workshop Tools 与 `resourcecompiler.exe`。

生成资源并运行离线验证：

```powershell
pwsh -NoProfile -File .\tools\generate_assets.ps1
dotnet restore --ignore-failed-sources
pwsh -NoProfile -File .\tools\verify.ps1
```

编译 Source 2 资源：

```powershell
pwsh -NoProfile -File .\tools\build_source2_assets.ps1 -Force
```

默认 addon namespace 为 `swift_mvp_effect`，编译后的游戏资源为：

```text
game/csgo_addons/swift_mvp_effect/
  materials/swift_mvp_effect/mvp_animation_60f.vtex_c
  materials/swift_mvp_effect/mvp_emblem.vtex_c
  particles/swift_mvp_effect/mvp_atlas_overlay.vpcf_c
  particles/swift_mvp_effect/mvp_overlay.vpcf_c
```

`dotnet publish -c Release` 会将插件 DLL 与配置输出到：

```text
build/publish/SwiftMvpEffect/
```

验证流程会拒绝未解析的模板 token、错误的 renderer age 输入、意外的根/子级数量、
错误的 depth-sort 值与资源路径、时间窗间隙以及非预期 VPK 内容。

## Override 测试部署

Override 流程只用于本地开发、测试服联调和发布前验收，不是正式玩家安装方式。

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\build_and_deploy.ps1 `
  -ForceAssetRebuild
```

部署脚本会：

1. 执行离线资源与 C# 验证。
2. 发布 `SwiftMvpEffect.dll` 和 `mvp_effect.json`。
3. 编译 2 个 VTEX_C 与 2 个 VPCF_C。
4. 只将上述 4 个 `_c` 文件打包为 `swift_mvp_effect.vpk`。
5. 验证 checksum、CS2 v2 单文件 VPK 头、无 archive-MD5 chunk 区段及解包清单。
6. 向客户端和专用服务器安装完全相同的 VPK。
7. 备份并更新两端 `gameinfo.gi`。
8. 部署服务器插件，并比较 VPK、DLL 与配置的 SHA-256。

不要启用 `vpkeditcli --gen-md5-entries`；它可能生成 archive-MD5 chunk 布局，导致
专用服务器报 `Chunk hash not found`。

服务器 SearchPaths 必须保证 SwiftlyS2 位于所有 override VPK 之前：

```text
Game_LowViolence  csgo_lv
Game              csgo/addons/swiftlys2
Game              csgo/overrides/<existing-test-pack>.vpk
Game              csgo/overrides/swift_mvp_effect.vpk
Game              csgo
```

如果 `csgo/addons/swiftlys2` 位于任何 override VPK 之后，部署验证会直接拒绝。

部署后必须完整重启客户端和服务器。只热重载 DLL 不会刷新缓存的 VTEX/VPCF。

在游戏控制台执行测试：

```text
swift_mvp_test
swift_mvp_test_atlas
```

不重建，仅验证现有部署：

```powershell
pwsh -NoProfile -File .\tools\verify_deployment.ps1
```

仅移除本项目的测试挂载、两端 VPK 与服务器插件：

```powershell
pwsh -NoProfile -File .\tools\uninstall_test_deployment.ps1
```

卸载脚本在修改 `gameinfo.gi` 前会创建时间戳备份。

## 正式发布

| 场景 | 粒子资源 | SwiftlyS2 插件 |
|---|---|---|
| 本地开发/测试服 | 客户端和服务器都在 `overrides` 中挂载 `swift_mvp_effect.vpk` | 部署脚本将 DLL 与配置复制到测试服 |
| 正式发布 | 通过 CS2 Workshop 发布审核后的编译资源 | 服主单独部署 DLL 与配置 |

正式发布检查清单：

1. 确认素材授权、addon namespace 与版本信息。
2. 使用本项目已有流程生成并验证 VTEX_C/VPCF_C。
3. Workshop payload 只包含获准发布的编译资源；排除私有源素材、文档媒体、开发
   脚本、本机路径、服务器配置和 SwiftlyS2 DLL。
4. 创建或更新 Workshop 项目，记录 Item ID、版本及变更说明。
5. 配置服务器获取 Workshop 内容，同时单独部署 `SwiftMvpEffect.dll` 与
   `mvp_effect.json`。
6. 使用干净客户端验证 Workshop 下载、precache、MVP 自动触发与双客户端 transmit
   隔离。
7. 验收通过后再从 override 测试环境切换到正式分发。

在发布账号、Workshop 项目和素材授权确认前，仓库不会写入正式 Item ID 或上传
自动化。
