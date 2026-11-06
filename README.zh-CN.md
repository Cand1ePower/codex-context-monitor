# Codex Context Monitor

简体中文 · [English](README.md)

一个贴在 Windows Codex 窗口旁的轻量状态条，显示上下文占用、最近响应的估算 Token 速率、缓存命中率、各模型累计用量和 API 费用估算。

<img src="docs/images/panel-zh.png" width="348" alt="中文上下文与模型使用面板">
<img src="docs/images/panel-en.png" width="348" alt="英文上下文与模型使用面板">

演示图使用示例数据，由实际 WPF 界面渲染。

## 功能

- 自动读取 Codex 当前窗口打开的聊天，切换聊天后更新。
- 收起时为透明的小状态条；点击展开，点击弹窗外收起。
- 显示缓存输入、非缓存输入、输出（含思考）及剩余上下文。
- 按模型汇总本对话累计 Token，并估算对应的 API 费用。
- 根据 Windows 显示语言选择中文或英文，其他语言默认英文。
- 无托盘图标，悬浮窗随 Codex 窗口启动和退出。

<img src="docs/images/bar-zh.png" width="254" alt="收起后的状态条">

## 安装

需要 Windows 10/11、Windows PowerShell 5.1，以及已加入 PATH 的 Python 3.10 或更高版本。无需安装第三方 Python 包。

从[最新版本](https://github.com/Cand1ePower/codex-context-monitor/releases/latest)下载 ZIP，解压后运行文件夹中的 `Install.ps1`。也可通过 Git 安装：

```powershell
git clone https://github.com/Cand1ePower/codex-context-monitor.git
cd codex-context-monitor
powershell.exe -NoProfile -File .\Install.ps1
```

安装到 `%LOCALAPPDATA%\CodexContextMonitor\app`，并为当前用户添加启动项，无需管理员权限。Codex 已打开时立即启动悬浮窗。

后台有一个无界面的监听进程，每两秒检查 Codex 窗口。Codex 关闭时，悬浮窗和 Python 数据读取进程结束；监听进程继续等待下次打开。整个工具不显示托盘图标。Codex 最小化或切到其他应用时，悬浮窗隐藏。

不安装也可直接双击 `Launch.vbs`。运行 `Quit.ps1` 可退出悬浮窗及监听进程；运行 `Uninstall.ps1` 可同时取消自启动。卸载脚本保留程序文件和偏好设置，方便恢复。

## 使用与设置

点击圆环或数值展开面板，点击弹窗外任意位置收起。鼠标移到状态条左侧可显示拖动把手，位置按 Codex 窗口保存。

鼠标悬停在模型行上，可查看完整的输入、缓存输入、输出、累计 Token 和响应次数。点击“API 估算”打开官方定价页。

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
