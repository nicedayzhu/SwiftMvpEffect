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

## 架构来源

- `bj`：序列图、屏幕 overlay、CP assignment 和 Start 前配置
- `ptext`：独立会话、连接变化后的 transmit 隔离
- `smb`：多实体生命周期与失败清理

MVP 动画本身不需要服务端逐帧更新；每个阶段的 VPCF 使用
`ANIMATION_TYPE_FIT_LIFETIME` 播放 15 帧，服务端只在 0.6 秒阶段边界启动下一个
实体。每个实体只用 CP34 的一个网络向量传 scale 与屏幕偏移。
