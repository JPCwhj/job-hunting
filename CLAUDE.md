# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目性质

这是一个 **Claude Code Skill Suite**（不是普通应用，不是 Web 服务，不是 CLI 工具）。最终产物是 4 个互相协作的 skill 文件，安装后用户在 Claude Code 里通过 `/job-hunt` 触发使用。

**核心约束**：第一版**仅支持 Boss 直聘**，且**不做自动投递**——系统准备好定制简历和开场白，最后"点击立即沟通 + IM 沟通 + 上传 PDF" 由用户人手完成（避免封号 + 守住伦理边界）。

## 阅读顺序

任何代码或细节实现之前，**必读** [docs/superpowers/specs/2026-04-29-job-hunt-skill-design.md](docs/superpowers/specs/2026-04-29-job-hunt-skill-design.md)。这份 spec 定义了：
- 4 个 skill 的职责边界（不要跨界）
- 完整数据流（从 preferences.yaml 到 shortlist.md）
- 三处关键 schema：`preferences.yaml` / JD frontmatter / analysis frontmatter
- 三层缓存策略（JD pool / analysis / STAR 预处理）
- 改写伦理红线（写进 analyzer/tailor 的 prompt）

## Skill 拆分（不要随意调整）

```
job-hunt              ← 主：编排 + 缓存管理 + 硬过滤 + 排序 + shortlist
├── job-hunt-fetcher  ← Boss 抓取（bb-browser），不做任何过滤/分析/改写
├── job-hunt-analyzer ← STAR 拆解 + 4 维匹配度，不直接改写简历（只生成"建议"）
└── job-hunt-tailor   ← 定制简历三件套 (resume/opener/changelog)，严守伦理边界
```

**硬过滤和排序故意放在主 skill** 而非独立子 skill —— 这两步不调 LLM，独立成 skill 是过度拆分。

**子 skill 不直接暴露给用户**，全部由主 skill 内部调用，避免用户跳过编排逻辑（如 preferences 没配好就直接调 fetcher）。

## 改写伦理红线（写进 prompt 的硬约束）

| 行为 | 是否允许 |
|---|---|
| 改写措辞、调整顺序、用 STAR 重写已有项目描述 | ✅ |
| 凭空增加项目/技能/经历 | ❌ |
| 编造具体数字（用户量、增长率、收入） | ❌ → 必须用 `[请填写：xxx]` 占位 |
| 修改工作时间/职级 | ❌ |

`changelog.md` 是**伦理保险**，必须如实列出 AI 改了什么、为什么——不允许偷偷改。

## 目录约定

- **当前目录优先，`~/.job-hunt/` fallback**——自用方便，朋友/不同求职项目隔离也方便
- 用户主简历支持 `.md` 或 `.docx`（`.docx` 用现有的 `docx` skill 解析），**内部统一为 MD**
- 定制简历输出**只 MD**，用户自己转 PDF 投递
- 完整目录结构见 spec 第 5 节

## 依赖的外部 skill

- `bb-browser`（控制用户真实 Chrome 抓取 Boss 直聘）
- `docx`（解析用户提供的 Word 简历）

## 当前状态

- ✅ 设计文档已完成
- ⏳ 实现计划（plan）待写
- ⏳ 4 个 skill 待开发
- 项目尚未初始化为 git repo
