# AGENTS.md — SwiftMvpEffect

SwiftlyS2 回合 MVP 屏幕粒子插件。运行时使用 owner-only
`info_particle_system`，客户端 VPCF 播放透明 MVP 主视觉并以粒子年龄本地驱动运动。

## 技术栈

- .NET 10 / C#
- SwiftlyS2.CS2 1.4.3
- PowerShell 7+
- CS2 Workshop Tools `resourcecompiler.exe`

## 资源分层

- `assets/source/`：用户提供的原始素材包，禁止生成脚本覆盖。
- `assets/generated/`：经用户授权生成的透明 MVP 主视觉；生成器以此为输入。
- `tools/templates/`：VTEX/VPCF 结构源。
- `resources_src/`：由 `tools/generate_assets.ps1` 生成，禁止手改。
- `build/`：插件、清单和临时编译列表，不纳入 Git。

## 关键契约

- 素材为一张透明金色 MVP 主视觉；生成器等比放入 1024×1024 透明 carrier，产出无损
  `RGBA8888` 1024 纹理，避免黑底、MKS 降采样与大图集首帧卡顿。
- 横向移动必须用 `PF_TYPE_PARTICLE_AGE_NORMALIZED` 在客户端本地推进；不要以服务器 Tick
  反复复制位置/alpha。
- 单个根的 `m_flDepthSortBias` 固定为 `0`。
- 每个观看者只创建一个短生命周期实体，并对其他玩家显式关闭 transmit。
- 根的 CP34：`x=scale`、`z=offsetY`；Start 前只写一次。横向移动与淡入淡出完全由 VPCF
  生命周期计算，完成左侧滑入、右侧滑出。
- Start 前必须完成 transmit、CP assignment 和 CP value。
- 断线、回合开始、重复触发、卸载都必须走同一个幂等清理入口。
- 资源变化后必须重启客户端和服务器；DLL 热重载不会刷新客户端粒子缓存。

## 常用命令

```powershell
pwsh -NoProfile -File .\tools\generate_assets.ps1
pwsh -NoProfile -File .\tools\verify.ps1
dotnet build .\SwiftMvpEffect.csproj
pwsh -NoProfile -File .\tools\build_source2_assets.ps1
pwsh -NoProfile -File .\build_and_deploy.ps1 -ForceAssetRebuild
pwsh -NoProfile -File .\tools\verify_deployment.ps1
pwsh -NoProfile -File .\tools\uninstall_test_deployment.ps1
```

部署流程只允许把 2 个编译 `_c` 文件打进 override VPK。原始 ZIP、PNG、MKS、
VTEX/VPCF source 不得进入 VPK。客户端和服务器必须挂载同名、同 SHA-256 的 VPK。
override VPK 必须是 CS2 可加载的 v2 单文件布局，且不能生成 archive-MD5 chunk 区段；
`vpkeditcli --gen-md5-entries` 会造成专用服务器启动时出现 `Chunk hash not found`。

override VPK 和 `gameinfo.gi` 修改只用于本地开发、测试服联调及发布前验收。正式资源
分发必须走 CS2 Workshop；Workshop payload 只包含获准发布的编译资源，SwiftlyS2
DLL 与配置仍由服主单独部署。正式 Item ID 和上传自动化必须等发布账号、Workshop
项目及素材授权确定后再补充，不能把测试挂载流程描述为玩家安装方案。

测试服 `gameinfo.gi` 中，`Game csgo/addons/swiftlys2` 必须位于任意
`Game csgo/overrides/*.vpk` 之前。部署脚本负责修正并验证此顺序；不能仅检查 MVP
VPK 是否存在。
