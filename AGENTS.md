# AGENTS.md — SwiftMvpEffect

SwiftlyS2 回合 MVP 屏幕粒子插件。运行时使用 owner-only
`info_particle_system`，客户端 VPCF 播放 60 帧序列图。

## 技术栈

- .NET 10 / C#
- SwiftlyS2.CS2 1.4.3
- PowerShell 7+
- CS2 Workshop Tools `resourcecompiler.exe`

## 资源分层

- `assets/source/`：用户提供的原始素材包，禁止生成脚本覆盖。
- `tools/templates/`：VTEX/VPCF 结构源。
- `resources_src/`：由 `tools/generate_assets.ps1` 生成，禁止手改。
- `build/`：插件、清单和临时编译列表，不纳入 Git。

## 关键契约

- 素材固定为 60 帧、25 FPS、2.4 秒，拆成 4 个 15 帧阶段。
- 原图 1280×512；生成器等比放入 512×512 透明 carrier，避免 overlay 拉伸。
- 四个阶段的 `m_flDepthSortBias` 固定为 `0/-1/-2/-3`；后续阶段位于前方。
- 每个观看者预建四个短生命周期实体，并对其他玩家显式关闭 transmit。
- 每个阶段的 CP34：`x=scale`、`y=offsetX`、`z=offsetY`；只占一个网络槽。
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

部署流程只允许把 8 个编译 `_c` 文件打进 override VPK。原始 ZIP、PNG、MKS、
VTEX/VPCF source 不得进入 VPK。客户端和服务器必须挂载同名、同 SHA-256 的 VPK。

override VPK 和 `gameinfo.gi` 修改只用于本地开发、测试服联调及发布前验收。正式资源
分发必须走 CS2 Workshop；Workshop payload 只包含获准发布的编译资源，SwiftlyS2
DLL 与配置仍由服主单独部署。正式 Item ID 和上传自动化必须等发布账号、Workshop
项目及素材授权确定后再补充，不能把测试挂载流程描述为玩家安装方案。
