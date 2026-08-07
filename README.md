[中文文档](README/v2.0.0-cn_README.md) | [English Document](README/v2.0.0-en_README.md) | [历史更新日志](update/)

---

## 📖 项目简介 / Project Introduction

<table>
<tr>
<td valign="top" width="50%">

### 📖 项目简介

GG-AI Modifier 是一个基于 **Flutter + Kotlin** 开发的 Android 游戏内存修改器，结合了传统 GG 修改器的内存操作能力和 AI 大语言模型的智能辅助功能。

用户可以通过自然语言与 AI 对话，AI 会自动理解用户意图并调用内存搜索、写入、冻结等操作，极大降低了内存修改的技术门槛。

> ⚠️ **免责声明**：本工具仅供学习研究和个人单机游戏使用，禁止用于在线竞技游戏。修改游戏数据可能违反游戏服务条款。

---

### ✨ 核心功能

#### 🧠 AI 智能对话
- 集成 DeepSeek、OpenAI、小米 MiMo 等 LLM API
- 支持 Function Calling，AI 自动调用内存操作函数
- 多轮对话上下文，AI 引导用户逐步定位目标数据
- Markdown/LaTeX/Mermaid 渲染，AI 回复支持代码高亮和图表

#### 🔍 内存搜索引擎
- **精确搜索**：搜索指定数值的内存地址
- **模糊搜索**：未知值搜索，支持 changed/increased/decreased 等 8 种对比操作
- **特征码搜索（AOB Scan）**：字节模式匹配，支持游戏重启后自动重定位
- **内存段智能筛选**：优先搜索 `[heap]`、`[anon:*]` 等高价值区域
- **分块读取**：2MB chunk 避免 OOM，支持 1 字节精细扫描

#### 🎮 内存操作
- **内存读写**：支持 byte/word/dword/qword/float/double 数据类型
- **内存冻结**：后台线程每 100ms 持续写入，防止游戏自动修改
- **批量操作**：支持批量写入和批量冻结

#### 📜 Lua 脚本引擎
- 集成 LuaJ (luaj-jse-3.0.2)，在 JVM 中执行 Lua 脚本
- 完整 GG API 桥接：`gg.choice()`、`gg.prompt()`、`gg.searchNumber()` 等
- 交互式对话框：脚本中的选择菜单会弹出真正的 Android 对话框
- 脚本运行日志自动保存

</td>
<td valign="top" width="50%">

### 📖 Project Introduction

GG-AI Modifier is an Android game memory editor developed with **Flutter + Kotlin**. It combines the memory manipulation capabilities of traditional GG game modifiers with the intelligent assistance of large language models (LLMs).

Users can interact with the AI using natural language. The AI automatically understands the user's intent and invokes memory search, writing, freezing, and other operations, greatly lowering the technical barrier for memory modification.

> ⚠️ **Disclaimer**: This tool is for educational research and personal single-player games only. It must not be used in online competitive games. Modifying game data may violate the game's terms of service.

---

### ✨ Core Features

#### 🧠 AI Intelligent Conversations
- Integrates DeepSeek, OpenAI, Xiaomi MiMo, and other LLM APIs
- Supports Function Calling; the AI automatically invokes memory operation functions
- Multi-turn conversation context guides users step-by-step to locate target data
- Markdown/LaTeX/Mermaid rendering; AI replies support code highlighting and diagrams

#### 🔍 Memory Search Engine
- **Exact Search**: Searches for memory addresses containing the specified value
- **Fuzzy Search** (Unknown value): Supports 8 comparison operations such as changed/increased/decreased
- **AOB Scan** (Signature Scan): Byte pattern matching with automatic relocation after game restart
- **Smart Memory Segment Filtering**: Prioritizes high-value regions like `[heap]`, `[anon:*]`
- **Chunked Reading**: 2MB chunk processing avoids OOM, supports 1-byte fine-grained scanning

#### 🎮 Memory Operations
- **Read/Write**: Supports byte/word/dword/qword/float/double data types
- **Memory Freezing**: Background thread continuously writes every 100ms to prevent reverts
- **Batch Operations**: Supports batch write and batch freeze

#### 📜 Lua Script Engine
- Integrates LuaJ (luaj-jse-3.0.2), executing Lua scripts inside the JVM
- Complete GG API bridge: `gg.choice()`, `gg.prompt()`, `gg.searchNumber()`, and more
- Interactive dialogs: In-script choice menus trigger real Android dialogs
- Automatic saving of script run logs

</td>
</tr>
</table>

---

## ☕ 捐赠支持 / Donation

如果您觉得本项目对您有帮助，欢迎捐赠支持开发者~  
If you find this project helpful, donations are warmly welcomed~

**币安 USDT (TRC20) 收款地址**  
`TXAgg43gZhE62VYHgBEaLt1WXVP8LNYEYP`

![币安 USDT 收款](img/币安收款捐赠usdt.png)

**微信收款 / WeChat Pay**

![微信收款](img/wx.png)