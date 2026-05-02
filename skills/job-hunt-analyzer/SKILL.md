---
name: job-hunt-analyzer
description: Internal sub-skill for job-hunt suite. Performs STAR decomposition of resume and scores JD-resume match across 4 dimensions. Does NOT generate tailoring suggestions (handled by tailor). Do NOT invoke directly — use the job-hunt main skill instead.
---

# job-hunt-analyzer

你是 job-hunt 套件的分析组件。职责：对每条 JD 与用户简历进行多维度匹配评分。**你只输出评分和分析，不生成改写建议（改写建议由 tailor 负责）。**

调用方传入：
- `work_dir`：工作根目录
- `resume_path`：标准化简历路径（`<work_dir>/.work/resume.md`）
- `jd_ids`：待分析的 JD ID 列表
- `preferences`：偏好配置（当前版本传入空 stub，评分不使用偏好权重）
- `run_id`：本次 run ID

## 第 1 步：简历 STAR 预处理

检查 `<work_dir>/.work/resume.star.md` 是否存在：

计算简历 hash：
```bash
md5 -q <work_dir>/.work/resume.md
```
读取 `<work_dir>/.work/resume.md.hash`。

如果 hash 文件不存在 OR hash 不匹配 → 重新拆解 STAR，更新 hash 文件。
如果 hash 匹配 → 直接读取 `resume.star.md`，跳过拆解。

### STAR 拆解规则

读取 `resume.md`，对每段**工作经历**和**项目经验**，按以下格式拆解：

```markdown
## [公司/项目名称] · [职位/角色] · [时间段]

- **S (Situation 背景)**: 当时的业务背景、团队状况、面临的挑战
- **T (Task 任务)**: 你被赋予的具体目标/职责
- **A (Action 行动)**: 你具体做了什么（技术方法/流程设计/协作方式）
- **R (Result 结果)**: 可量化的成果（数字/百分比/规模）；无数字则标注 ⚠️ 缺数字

技能关键词：[从该段经历提取的技能词，用于硬技能匹配]
```

拆解后写入 `<work_dir>/.work/resume.star.md`，同时更新 `<work_dir>/.work/resume.md.hash`。

## 第 2 步：逐条 JD 分析

记录待分析总数 `total = len(jd_ids)`，计数器 `n = 0`。

对 `jd_ids` 中每个 JD ID（记为 `<id>`）：

**缓存检查**：读取 `<work_dir>/.work/jd-pool/<id>.analysis.md`（若存在），校验：
- frontmatter 中 `jd_fetched_at` 与 JD 文件的 `fetched_at` 一致
- `resume_hash` 与当前 `resume.md.hash` 一致

两项均满足 → 跳过，复用缓存，`n++`，输出：`⚡ <公司名>·<职位名> — 复用缓存（<n>/<total>）`，继续下一条。

否则 → 重新分析：

### 2.1 读取 JD

读取 `<work_dir>/.work/jd-pool/<id>.md` 全文。

### 2.2 计算 4 维匹配度（0-100 分）

**维度 1：硬技能匹配（hard_skills）**

从 JD「任职要求」提取所有技能/工具关键词。与 `resume.star.md` 中所有段落的「技能关键词」对比。

评分规则：
- JD 要求的技能中，简历命中率 × 100 = 基础分
- JD 中标注为「加分项」的技能，命中每项 +5（不超过 100）
- 简历有但 JD 没要求的技能不加分

记录：
```
✅ 命中：[技能列表]
⚠️ 缺失（JD 强调）：[技能列表]
🎯 已有但未突出（JD 提及）：[技能列表]
```

**维度 2：经验深度（experience_depth）**

对比 JD 要求年限 vs 简历实际年限：
- 差距 ±1 年内：90-100 分
- 简历比要求多 1-3 年：85-95 分
- 简历比要求少 1 年：70-80 分
- 简历比要求少 2 年：50-65 分
- 差距超过 2 年：30-50 分

同时考察项目复杂度：相近 +5，明显低于 -10。

**维度 3：行业/领域契合（domain_fit）**

对比 JD 行业 + 业务场景 vs 简历工作行业 + 项目背景：
- 完全匹配（同行业同场景）：90-100
- 行业相近（如同属 B 端 SaaS）：75-90
- 行业不同但技能可迁移：60-75
- 行业差异大，迁移难度高：40-60
- 几乎无关联：20-40

**维度 4：软性匹配（soft_fit）**

从 JD 提取软性要求（如「优秀的沟通能力」「有 0-1 经验」「能独立推动跨团队项目」），从简历找对应具体事例。

评分（从 0 分开始累加）：
- JD 强调的软技能在简历中有具体事例支撑：每项 +15（上限 100）
- JD 提到的加分项（学历/证书/特定背景）命中：+5 每项
- 钳制在 0-100 范围内

### 2.3 计算总分

```
scores.total = round((hard_skills + experience_depth + domain_fit + soft_fit) / 4)
```

### 2.4 写入 analysis 文件

写入 `<work_dir>/.work/jd-pool/<id>.analysis.md`：

```markdown
---
jd_id: <id>
analyzed_at: <ISO 8601 时间>
jd_fetched_at: <从 JD 文件 frontmatter 读取的 fetched_at>
resume_hash: <当前 resume.md.hash 内容>
scores:
  total: <整数>
  hard_skills: <分数>
  experience_depth: <分数>
  domain_fit: <分数>
  soft_fit: <分数>
---

## 一句话评估
<30 字以内，说明核心优势、主要差距、是否值得投递>

## 维度分析

### 硬技能 <分数>/100
✅ 命中：<技能列表>
⚠️ 缺失（JD 强调）：<技能列表>
🎯 已有但未突出：<技能列表>

### 经验深度 <分数>/100
<1-2 句说明差距原因>

### 行业契合 <分数>/100
<1-2 句说明行业相关性>

### 软性匹配 <分数>/100
<列出 JD 软性要求 vs 简历是否有具体事例>
```

同时更新 JD 文件 frontmatter 中的 `status.analyzed: true`。

`n++`，将 `<id>` 加入 `state.json` 的 `stages.analyzed`，更新 `checkpoint_at`。

**输出进度**：`✅ <company.name>·<title> — 匹配度 <scores.total> 分（<n>/<total> 完成）`

若单条 JD 分析出现异常（文件读取失败、字段缺失等），将该 ID 加入 `state.stages.analysis_errors`，记录失败原因，继续处理其余 JD，不整体中止。

## 第 3 步：完成报告

所有 JD 处理完成后，将 `state.json` 的 `phase` 设为 `"analyzed"`。

告知调用方：
- 新分析完成的 JD 数量
- 复用缓存的数量
- 分析失败的 JD（若有）
