# MoonPixel 互通核验

核验日期：2026-11-16。只读检查，没有修改 MoonPixel。

- 仓库：`alicelikeeat/moonpixel`
- `main` SHA `2412079c6fa22776bae583e8452cc68435a6267d` 只有 README。
- 检查开发分支 `claude/upbeat-gates-vu0ssd`，SHA `e0bf6b40db63c4a70d8518060b433f83c08af90a`。
- `ios/Sources/MoonPixelCore/World.swift`：`Chunk.Saved` v1，32×32 格，`l0...l3` 四个 1024 字节 Data，另含 timers、props、revision。JSON 的 Data 为 Base64。
- `ios/Sources/MoonPixelCore/Store.swift`：WorldStore format 3，HEAD + generation manifest + content-addressed blobs。单块不是完整游戏存档。
- `ios/Sources/MoonPixelCore/Recipe.swift`：现有文字世界生成器为关键词／规则解析，不是大模型。

| MoonPixel | Moon Earth | 状态 |
| --- | --- | --- |
| cx / cy、块内索引 | 地面 x / z | 可转换；导入单块原点归零，原坐标保存在源字节中 |
| l0 UInt8 tile ID | Surface | 必须提供显式 tile-ID 表，未知 ID 拒绝 |
| l1、l2、l3 | 未映射 | 原始块字节保留，不伪造显示 |
| timers、props、其他字段 | opaque extensions | 原样保留，不解释、不修改 |
| format 3 完整存档 | .pxworld | 尚无安全双向转换器 |
| 房间、楼层、家具、体素开洞 | Building / Room / Prop / VoxelEdit | Moon Earth 原生数据，不能假设 MoonPixel 已支持 |

目前 `MoonPixelBridge` 实现底层单块解析、显式地表映射、原始字节保留、未修改块的原样导出。编辑后拒绝原样回写，避免静默丢失编辑。这个桥接 API 有测试，但没有向普通用户开放一个会误导其认为完整互通的导入按钮。

端到端互通仍依赖 MoonPixel 侧增加明确的地图交换入口，并约定 3D／室内扩展。不得直接把 `.pxworld` 放进其存档目录。当前 App 菜单明确显示这一限制。
