# Codex Context Monitor — Windows 上下文窗口与 Token 用量监控

简体中文 · [English](README.md)

**Codex Context Monitor** 是适用于 **Windows 版 OpenAI Codex 桌面应用**的非官方上下文窗口与 Token 用量监控工具。悬浮状态条显示当前聊天的上下文占用、估算 Token 速率、提示词缓存命中率、各模型累计 Token 和 API 费用估算。

工具自动跟随当前聊天，根据系统语言切换中英文，使用 PowerShell、WPF 和 Python 在本地运行，无需 API Key。

**默认只显示小状态条。** 点击圆环或数值才展开大面板，点击面板外任意位置即可收起。

![默认收起状态的 Codex 完整窗口：右下角只显示上下文小圆环、估算 Token 速率和缓存命中率](docs/images/full-window-collapsed-zh.png)

<details>
<summary>查看点击后展开详情的完整窗口演示</summary>

![点击后展开的 Codex 完整窗口场景示意：上下文用量、缓存命中率、各模型 Token 和 API 费用估算](docs/images/full-window-zh.png)

</details>

完整窗口场景示意图，使用示例聊天和示例数据；悬浮面板与状态条由实际 WPF 界面渲染。

## 功能

- 自动读取 Codex 当前窗口打开的聊天，切换聊天后更新。
- 收起时为透明的小状态条；点击展开，点击弹窗外收起。
- 显示缓存输入、非缓存输入、输出（含思考）及剩余上下文。
- 按模型汇总本对话累计 Token，并估算对应的 API 费用。
- 根据 Windows 显示语言选择中文或英文，其他语言默认英文。
- 无托盘图标，悬浮窗随 Codex 窗口启动和退出。

<img src="docs/images/bar-zh.png" width="254" alt="收起后的状态条">

## 交给 AI Agent 安装

把下面这段话复制给能操作本机的 Codex 或其他编程 Agent：

```text
请在这台 Windows 电脑上安装 Codex Context Monitor：https://github.com/Cand1ePower/codex-context-monitor。先阅读仓库 README 和安装脚本，检查 Windows PowerShell 5.1 与 Python 3.10+，优先复用现有 Python。下载最新 Release 的 ZIP，解压后运行 Install.ps1，为当前用户启用随 Codex 启停，语言保持 auto。安装后检查启动项与监听进程，在 Codex 已打开时确认悬浮条正常显示，并告诉我退出和卸载方法。不要重启正在运行的 Codex；缺少依赖时告诉我具体缺什么。
```

运行环境为 Windows 10/11、Windows PowerShell 5.1 和 Python 3.10+，无需第三方 Python 包或管理员权限。[最新版本](https://github.com/Cand1ePower/codex-context-monitor/releases/latest)附 ZIP 和 SHA-256 校验文件。

安装到 `%LOCALAPPDATA%\CodexContextMonitor\app`，并为当前用户添加启动项，无需管理员权限。Codex 已打开时立即启动悬浮窗。

后台有一个无界面的监听进程，每两秒检查 Codex 窗口。Codex 关闭时，悬浮窗和 Python 数据读取进程结束；监听进程继续等待下次打开。整个工具不显示托盘图标。Codex 最小化或切到其他应用时，悬浮窗隐藏。

不安装也可直接双击 `Launch.vbs`。运行 `Quit.ps1` 可退出悬浮窗及监听进程；运行 `Uninstall.ps1` 可同时取消自启动。卸载脚本保留程序文件和偏好设置，方便恢复。

## 使用与设置

点击圆环或数值展开面板，点击弹窗外任意位置收起。鼠标移到状态条左侧可显示拖动把手，位置按 Codex 窗口保存。

鼠标悬停在模型行上，可查看完整的输入、缓存输入、输出、累计 Token 和响应次数。点击“API 估算”打开官方定价页。

<details>
<summary>查看中英文面板细节</summary>

<img src="docs/images/panel-zh.png" width="348" alt="Codex 上下文监控中文面板">
<img src="docs/images/panel-en.png" width="348" alt="Codex 上下文监控英文面板">

</details>

可在 `%LOCALAPPDATA%\CodexContextMonitor\settings.json` 覆盖默认设置：

```json
{"language": "zh-CN"}
```

`zh-CN` 为中文，`en-US` 为英文，`auto` 跟随 Windows 显示语言。找不到 Python 时，可增加 `python` 字段，填写 Python 可执行文件的绝对路径。修改后重启工具。

## 数据含义

上下文占用取最近一次响应的输入与输出 Token 之和，除以上报的上下文窗口。缓存 Token 仍占上下文。缓存命中率为缓存输入除以全部输入。速率根据本地生成时间和输出 Token 估算，包含思考，随响应记录更新，不是逐 Token 的瞬时解码速度。

“模型使用情况”累计本对话本地记录中的每次响应，包括重复输入，因此累计数通常大于当前上下文占用。重复事件不会二次计数，压缩上下文不会清空累计数；独立子聊天不计入。

费用是美元计价的 API Token 估算，不代表 ChatGPT 订阅账单或实际扣款。价格于 **2026-11-06** 核对，来源为[官方定价页](https://developers.openai.com/api/docs/pricing)和 `pricing.json` 中对应的模型页面。目前支持 GPT-6 Astra、GPT-6.1 Sol、GPT-6.1 Terra、GPT-6 Sol、GPT-6 Luna；未知模型或不支持的服务档位显示“未定价”，合计会标明不完整。

每次响应分别计算普通输入、缓存输入、缓存写入和输出费用；思考已包含在输出中，不重复计费。单次输入超过 272K 时应用长上下文价格。支持记录中明确提供的 Fast/priority、Flex、Batch 档位；缺少档位时按 Standard 估算，缓存保留期缺失时按 30 分钟估算。工具费用、地区加价及订阅额度未计入。面板的费用悬停提示保留了这些计算条件。

## 数据与兼容性

这是非官方伴随工具，不是 Codex 原生扩展。它不修改 Codex 安装包、不调用模型、不读取凭据，也不上传聊天。程序只读当前用户的桌面日志、聊天索引和用量记录，只保留统计元数据，不保存消息正文。仅点击定价链接时会打开浏览器。

当前聊天识别来自客户端记录的窗口路径，不会把后台刚更新的其他任务当成当前聊天。新建聊天页或不支持的页面会清空选择。这些本地格式可能随 Codex 升级变化；当前测试版本为 Windows Codex `26.1027.51404`。没有本地用量记录的云端聊天不能估价；多个窗口的识别依赖客户端写出的焦点记录。

## 常见问题

### Windows Codex 怎么查看上下文窗口占用和 Token 数？

安装后打开一个本地 Codex 聊天，圆环显示最近上报的上下文占用。点击可查看已用与剩余 Token，以及缓存输入、非缓存输入和包含思考的输出。

### 这是 Codex 插件、桌面悬浮窗，还是 CLI 状态栏？

这是独立运行的 Windows 桌面悬浮窗，适合寻找 Codex 上下文插件或 Token 计数器的用户。它不向输入栏注入原生扩展，也不配置 Codex CLI 状态栏，不修改 Codex 安装文件。当前 WPF 版本不支持 macOS 和 Linux。

### Token 速率和缓存命中率会实时更新吗？

本地用量记录更新后，面板随之刷新。速率取最近一次响应的估算 Tokens/s，包含思考，不是逐 Token 的瞬时输出速率；缓存命中率取缓存输入除以全部输入。

### API 费用估算能当作 Codex 或 ChatGPT 的实际账单吗？

不能。它按记录中的模型和用量估算 API Token 费用，未计入订阅额度、工具费用与独立子聊天。没有对应价格时显示“未定价”，不会记为零费用。

## 项目信息

| 项目 | 说明 |
| --- | --- |
| 目标应用 | Windows 版 OpenAI Codex 桌面应用 |
| 工具类型 | 本地上下文窗口监控、Token 用量悬浮窗 |
| 监控指标 | 上下文百分比、估算 Tokens/s、缓存命中率、各模型 Token、API 费用估算 |
| 界面语言 | 根据 Windows 显示语言自动选择中文或英文 |
| 运行环境 | Windows PowerShell 5.1、WPF、Python 3.10+ 标准库 |
| 数据来源 | 本地 Codex 桌面日志、聊天索引和用量记录 |
| 程序入口 | `Install.ps1`、`Launch.vbs`、`Quit.ps1`、`Uninstall.ps1` |

[供 AI 工具读取的纯文本索引](llms.txt) · [反馈问题](https://github.com/Cand1ePower/codex-context-monitor/issues)

## 开发检查

```powershell
python -m unittest discover -s tests -p "test_*.py"
powershell.exe -NoProfile -File .\tests\test_ui.ps1
powershell.exe -NoProfile -STA -File .\Overlay.ps1 -ValidateOnly
```

用示例数据渲染演示图：

```powershell
powershell.exe -NoProfile -STA -File .\Overlay.ps1 -RenderPreview -Language zh-CN -PreviewState .\tests\demo-state.json -PreviewOutput .\preview
```

自动检查涵盖价格计算、去重、模型切换、压缩、文件截断、完整历史读取、窗口跟随、语言选择和生命周期判断。Codex 或 Windows 更新后的实际界面仍需检查。
