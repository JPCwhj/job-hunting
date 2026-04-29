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

## Skill 文件约定

- **文件名必须是 `SKILL.md`**（不是 index.md）
- **开发目录**：`skills/<name>/SKILL.md`
- **安装方式**：`bash scripts/install.sh` → 复制到 `~/.claude/skills/<name>/SKILL.md`
- **不需要 plugin 包装**：直接放 `~/.claude/skills/` 即可被 Claude Code 识别

## Skill 拆分（不要随意调整）

```
job-hunt              ← 主：编排 + 缓存管理 + 硬过滤 + 排序 + shortlist
├── job-hunt-fetcher  ← Boss 抓取（bb-browser），不做任何过滤/分析/改写
├── job-hunt-analyzer ← STAR 拆解 + 4 维匹配度，不直接改写简历（只生成"建议"）
└── job-hunt-tailor   ← 定制简历三件套 (resume/opener/changelog)，严守伦理边界
```

**硬过滤和排序故意放在主 skill** 而非独立子 skill —— 这两步不调 LLM，独立成 skill 是过度拆分。

**子 skill 不直接暴露给用户**，全部由主 skill 内部调用，避免用户跳过编排逻辑。

## 改写伦理红线（写进 prompt 的硬约束）

| 行为 | 是否允许 |
|---|---|
| 改写措辞、调整顺序、用 STAR 重写已有项目描述 | ✅ |
| 凭空增加项目/技能/经历 | ❌ |
| 编造具体数字（用户量、增长率、收入） | ❌ → 必须用 `[请填写：xxx]` 占位 |
| 修改工作时间/职级 | ❌ |

`changelog.md` 是**伦理保险**，必须如实列出 AI 改了什么、为什么——不允许偷偷改。

## 目录约定

- **work_dir = Claude 启动时的当前目录（`pwd`）**，无任何 fallback，不再使用 `~/.job-hunt/`
- 首次运行向导会自动创建 `preferences.yaml`（通过对话收集）和引导放置简历（扫描当前目录）
- 用户简历支持 `.md` 或 `.docx`（`.docx` 用 `docx` skill 解析），内部统一为 MD
- 定制简历输出**只 MD**，用户自己转 PDF 投递
- JD 缓存：`<work_dir>/.work/jd-pool/boss-<jobId>.md`
- 输出：`<work_dir>/output/<run_id>/`

## 风控策略（fetcher 必须遵守）

- **禁止并发**：每次只调一个 bb-browser 工具，严格串行
- 详情页间隔：**10-15 秒随机**
- 轮次间隔：**30-60 秒随机**
- 列表页读取后停留：**5-8 秒**（模拟人类浏览）
- 详情页数据采集完立即**关闭标签页**
- 不使用 `bb-browser site boss/*` 适配器（会触发风控）

## 依赖的外部 skill

- `bb-browser`（控制用户真实 Chrome 抓取 Boss 直聘）
- `docx`（解析用户提供的 Word 简历）

## 当前状态

- ✅ 设计文档、实现计划已完成
- ✅ 4 个 skill 全部实现，安装到 `~/.claude/skills/`
- ✅ 首次运行向导（自动建目录 + 对话配置 + 简历引导）
- ✅ 风控优化（串行 + 长间隔 + 关标签）
- ⏳ 用户真实跑完整流程自测中
- ⏳ PR 待合并：https://github.com/JPCwhj/job-hunting/compare/main...feat/skill-suite
