# Codex Context Monitor — Windows 上下文窗口与 Token 用量监控

简体中文 · [English](README.md)

**Codex Context Monitor** 是适用于 **Windows Codex 桌面应用**的上下文窗口与 Token 用量监控工具。

悬浮状态条显示当前聊天的上下文占用、估算 Token 速率、提示词缓存命中率、各模型累计 Token 和 API 费用估算。工具自动跟随当前聊天，根据系统语言切换中英文。

**默认显示小状态条。** 点击圆环或数值展开面板，点击弹窗外任意位置收起。

![默认收起状态的完整 Codex 窗口](docs/images/collapsed.png)

<details>
<summary>查看点击后展开详情的完整窗口演示</summary>

![点击后展开详情的完整 Codex 窗口](docs/images/expanded.png)

</details>

示意图使用示例聊天和用量，悬浮界面由实际程序渲染。

## 功能

- 自动读取 Codex 当前窗口打开的聊天，切换聊天后更新。
- 收起时为透明的小状态条；点击展开，点击弹窗外收起。
- 显示缓存输入、非缓存输入、输出（含思考）及剩余上下文。
- 按模型汇总本对话累计 Token，并估算对应的 API 费用。
- 根据 Windows 显示语言选择中文或英文，其他语言默认英文。
- 无托盘图标，悬浮窗随 Codex 窗口启动和退出。

## 安装

复制给 Codex：

```text
请在这台电脑上安装 https://github.com/Cand1ePower/codex-context-monitor。阅读 README 和安装脚本。
```

后台监听进程每两秒检查 Codex 窗口。Codex 关闭后，悬浮窗和数据读取进程结束，监听进程继续等待下次启动。

## 使用与设置

点击圆环或数值展开面板，点击弹窗外任意位置收起。鼠标移到状态条左侧可显示拖动把手，位置按 Codex 窗口保存。

鼠标悬停在模型行上，可查看完整的输入、缓存输入、输出、累计 Token 和响应次数。点击“API 估算”打开官方定价页。

运行 `Quit.ps1` 退出工具，运行 `Uninstall.ps1` 取消自启动。

<details>
<summary>查看中英文面板细节和收起后的状态条</summary>

![中英文面板及收起后的状态条](docs/images/panels.png)

</details>

## 数据含义

上下文占用取最近一次响应的输入与输出 Token 之和，除以上报的上下文窗口。缓存 Token 仍占上下文。缓存命中率为缓存输入除以全部输入。速率根据本地生成时间和输出 Token 估算，包含思考，随响应记录更新，不是逐 Token 的瞬时解码速度。

费用是美元计价的 API Token 估算，不代表 ChatGPT 订阅账单或实际扣款。来源为[官方定价页](https://developers.openai.com/api/docs/pricing)和 `pricing.json` 中对应的模型页面。目前支持 GPT-6 Astra、GPT-6.1 Sol、GPT-6.1 Terra、GPT-6 Sol、GPT-6 Luna；未知模型或不支持的服务档位显示“未定价”，合计会标明不完整。

每次响应分别计算普通输入、缓存输入、缓存写入和输出费用；思考已包含在输出中，不重复计费。单次输入超过 272K 时应用长上下文价格。支持记录中明确提供的 Fast/priority、Flex、Batch 档位；缺少档位时按 Standard 估算，缓存保留期缺失时按 30 分钟估算。工具费用、地区加价及订阅额度未计入。面板的费用悬停提示保留了这些计算条件。
