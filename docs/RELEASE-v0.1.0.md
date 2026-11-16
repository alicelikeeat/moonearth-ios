# Moon Earth v0.1.0 · 未签名测试版

独立 iPhone / iPad 原生 3D 像素地图与室内设计 App。

- iOS / iPadOS 26.0 及以上，arm64 真机版本。
- SwiftUI 原生 Liquid Glass + RealityKit。
- 地图编辑、房屋楼层与房间、家具摆放、体素开洞、自动保存和文件导入导出。
- 设备端 Apple Foundation Models 生成方案，预览确认后应用；需要设备上的系统模型可用。
- 17 项核心测试、模拟器编辑保存测试、模拟器及无签名真机构建均通过。

IPA 来源为已验证提交 `96a9d9fd3d17f67d6852f6e283250597b9239b58` 的 iPhoneOS Release 构建，工作流 https://github.com/alicelikeeat/moonearth-ios/actions/runs/43821255131 。重新打包时检查了平台、arm64 架构、Payload 结构、可执行权限并移除签名，附 SHA-256 校验文件。

**这是未签名 IPA，需要使用自己的有效签名方式重新签名后安装；不能直接点击安装。** 不含开发者证书或描述文件。

首版限制：MoonPixel 完整双向互通尚待接入；设备端 AI 实际生成质量和真机帧率尚未实测。不是完整任务书所有功能的完成声明。详情参见源码 README。
