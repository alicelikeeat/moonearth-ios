# Moon Earth document v1

文件类型：`.pxworld`、`.pxregion`、`.pxbuilding`。当前均为**单个 JSON 信封文件**，不是 ZIP，也不加载远程资源。

信封字段：`format="earth.moon.document"`、`version=1`、`kind=world|region|building`、`checksum`、`payload`。payload 为 World JSON 的 Base64。checksum 是 payload 原始字节的 FNV-1a 64-bit 十六进制，用于检测意外损坏，不用于签名或证明可信来源。限制文件 32 MB。

坐标：右手系、Y 向上。世界 X/Z 格为 1 米，地表顶面为 `height+1`。默认未显式存储地块为高度 0 草地。建筑 origin 为旋转后占地的最小 X/Z 角；elevation 单位米。width/depth、room x/z/width/depth、VoxelEdit x/y/z 单位 0.25 米。楼高 12 细节格，即 3 米。家具位置为建筑局部米，世界物件为世界米。turns 取 0…3，绕 Y 正向每步 90°。

世界包含稳定 UUID、名称、尺寸、种子、tiles、buildings、props、generations、extensions。Building 保存房间、家具和覆盖基础结构的体素修改。VoxelEdit material=null 表示挖空；其他值为共享调色板索引。房间是闭合矩形内墙，默认南侧门洞，可用体素工具修改。没有结构安全或真实流体语义。

128 个内置物件为 32 种程序几何 × 4 个不同尺寸规格，ID `builtin.kind.variant`。12 栋房屋模板保存为完整 Building 数据。它们不是 128 套独立美术模型；尺寸变体在界面明确标注。未知素材使用粉色替代块，同时保留 ID 并在分析中报告。

区域包含选区所有地表（包括默认草地），建筑不得被边界截断。导入合并采用新 UUID，遇到建筑重叠、越界或未知扩展时拒绝，不做无提示的覆盖。世界导入默认生成新的项目 ID，不覆盖原项目。数据版本不是 1 时拒绝打开。未来需要扩展的数据放入 `extensions`（每键 Data 原样存储），未知顶层 JSON 字段不属于可保证保留的扩展机制。

本地保存：每项目一个 UUID 文件，原子写入；覆盖前保留上一有效版本 `.backup`。重开时主文件损坏会尝试恢复上一份备份。自动保存延迟 600ms；系统强杀前未落盘的操作仍可能丢失。没有声称实现持久化每笔操作日志。
