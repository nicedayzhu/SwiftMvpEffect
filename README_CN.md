# SwiftMvpEffect

基于 Swift Particle Menu 已验证架构制作的 SwiftlyS2 回合 MVP 屏幕粒子插件。
CS2 发出 `round_mvp` 事件时，插件为目标观看者创建 owner-only
`info_particle_system`，客户端以 25 FPS 播放 60 帧金色 MVP 横幅。动画被拆成
4 个 15 帧阶段，避免 Source 2 把单张大型 sheet 自动降采样。

![MVP 动画关键帧预览](docs/mvp_contact_sheet.jpg)

## 已实现

- 自动监听 `round_mvp`
- 默认向所有在线玩家展示，可配置为只向 MVP 玩家展示
- `swift_mvp_test` 单人测试命令
- 4×15 帧 atlas、VTEX、VPCF 自动生成
- 1280×512 → 512×512 透明 carrier，保持横幅比例
- 每名观看者独立 transmit，其他玩家明确不可见
- 重复触发、断线、下一回合、卸载时幂等清理
- Source 2 资源编译与严格验证脚本

## 配置

编辑插件目录里的 `mvp_effect.json`：

```json
{
  "enabled": true,
  "audience": "all",
  "scale": 0.86,
  "offsetX": 0.0,
  "offsetY": 0.04
}
```

`audience` 可为：

- `all`：所有在线玩家
- `mvp`：仅 MVP 玩家

配置在插件加载时读取，修改后请重载插件。

## 构建

```powershell
pwsh -NoProfile -File .\tools\generate_assets.ps1
dotnet restore --ignore-failed-sources
pwsh -NoProfile -File .\tools\verify.ps1
```

编译 Source 2 资源（需要已安装 CS2 Workshop Tools）：

```powershell
pwsh -NoProfile -File .\tools\build_source2_assets.ps1 -Force
```

默认 addon namespace 为 `swift_mvp_effect`。编译后关键文件是：

```text
game/csgo_addons/swift_mvp_effect/
  materials/swift_mvp_effect/mvp_animation_stage_1.vtex_c
  materials/swift_mvp_effect/mvp_animation_stage_2.vtex_c
  materials/swift_mvp_effect/mvp_animation_stage_3.vtex_c
  materials/swift_mvp_effect/mvp_animation_stage_4.vtex_c
  particles/swift_mvp_effect/mvp_overlay_stage_1.vpcf_c
  particles/swift_mvp_effect/mvp_overlay_stage_2.vpcf_c
  particles/swift_mvp_effect/mvp_overlay_stage_3.vpcf_c
  particles/swift_mvp_effect/mvp_overlay_stage_4.vpcf_c
```

插件 DLL 与 `mvp_effect.json` 由 `dotnet publish -c Release` 生成在：

```text
build/publish/SwiftMvpEffect/
```

## 部署注意

客户端和服务器都必须挂载同一份已编译资源。资源或 VPK 更新后要同时重启客户端与
服务器；只热重载 DLL 不会刷新客户端缓存的 VTEX/VPCF。

### 发布渠道说明（重要）

本项目当前提供的 `gameinfo.gi + overrides/*.vpk` 流程只用于本地开发、测试服联调和
上线前验收，不是最终面向玩家的正式分发方式。不要要求正式服玩家手工修改
`gameinfo.gi` 或复制本地 VPK。

| 场景 | 粒子资源交付 | SwiftlyS2 插件交付 |
|---|---|---|
| 本地开发/测试服 | `swift_mvp_effect.vpk` 挂载到客户端和服务器的 `overrides` | 由部署脚本复制 DLL 与配置到测试服 |
| 正式发布 | 将审核后的编译资源作为 CS2 Workshop 内容上传并按 Workshop 项目版本更新 | DLL 与配置仍由服主部署到服务器，不放入 Workshop 资源包 |

正式发布预期流程：

1. 完成素材授权、命名空间和版本检查。
2. 继续使用本项目的验证与 Source 2 编译流程生成 VTEX_C/VPCF_C。
3. 制作仅含获准发布资源的 Workshop payload；不得包含原始私有素材、开发脚本、
   本机路径、服务器配置或 SwiftlyS2 DLL。
4. 通过 CS2 Workshop Tools/Steam Workshop 创建或更新正式项目，记录 Workshop
   Item ID、发布版本和变更说明。
5. 服务器按运营环境配置 Workshop 内容的订阅/下载，同时单独部署
   `SwiftMvpEffect.dll` 与 `mvp_effect.json`。
6. 在干净客户端验证 Workshop 下载、资源 precache、MVP 自动触发和双客户端
   transmit 隔离；资源更新后重启客户端与服务器。
7. 验收通过后再从测试用 override 环境切换到 Workshop 分发，不把本地
   `gameinfo.gi` 修改作为正式安装步骤。

当前仓库尚未包含 Workshop 上传脚本和正式 Item ID；这些内容应在确定发布账号、
Workshop 项目及素材授权后单独补充。现有 VPK 脚本会继续保留，作为快速联调和正式
发布前的资源验收工具。

### 一键 override 测试部署（仅开发/验收）

默认路径与当前 Swift Particle Menu 测试环境一致：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\build_and_deploy.ps1 `
  -ForceAssetRebuild
```

脚本依次执行：

1. 离线资源与 C# 验证。
2. 发布 `SwiftMvpEffect.dll` 与配置。
3. 编译 4 个 VTEX_C 和 4 个 VPCF_C。
4. 只把上述 8 个 `_c` 文件打包为 `swift_mvp_effect.vpk`。
5. 校验 VPK checksums、CS2 v2 单文件容器头（无 archive-MD5 chunk 区段），并解包核对文件清单。
6. 安装相同 VPK 到客户端和专用服务器。
7. 备份并修改两端 `gameinfo.gi` SearchPaths；服务器会把
   `Game csgo/addons/swiftlys2` 固定在所有 override VPK 之前，避免 SwiftlyS2
   的服务器资源路径被测试包抢占。
8. 部署 SwiftlyS2 插件，并比较 VPK、DLL、配置的 SHA-256。

部署完成后完整重启客户端和服务器，然后在游戏控制台执行：

```text
swift_mvp_test
```

只复核现有部署，不重建：

```powershell
pwsh -NoProfile -File .\tools\verify_deployment.ps1
```

移除测试挂载、两端 VPK 与服务器插件：

```powershell
pwsh -NoProfile -File .\tools\uninstall_test_deployment.ps1
```

卸载脚本只删除该项目的精确路径，修改 `gameinfo.gi` 前仍会生成时间戳备份。

服务器的 SearchPaths 需要保持如下优先级（其他已有 override 包可继续保留）：

```text
Game_LowViolence  csgo_lv
Game              csgo/addons/swiftlys2
Game              csgo/overrides/<existing-test-pack>.vpk
Game              csgo/overrides/swift_mvp_effect.vpk
Game              csgo
```

部署验证会拒绝 `csgo/addons/swiftlys2` 位于任意 override VPK 之后的服务器配置。

## 架构来源

- `bj`：序列图、屏幕 overlay、CP assignment 和 Start 前配置
- `ptext`：独立会话、连接变化后的 transmit 隔离
- `smb`：多实体生命周期与失败清理

MVP 动画本身不需要服务端逐帧更新；每个阶段的 VPCF 使用
`ANIMATION_TYPE_FIT_LIFETIME`、`m_bAnimateInFPS=true` 和
`m_flAnimationRate=25` 播放 15 帧，服务端只在 0.6 秒阶段边界启动下一个实体。
每个实体只用 CP34 的一个网络向量传 scale 与屏幕偏移。
