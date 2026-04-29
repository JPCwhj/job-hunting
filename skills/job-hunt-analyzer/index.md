---
name: job-hunt-analyzer
description: Internal sub-skill for job-hunt suite. Performs STAR decomposition of resume, scores JD-resume match across 4 dimensions, and generates tailoring suggestions. Do NOT invoke directly — use the job-hunt main skill instead.
---

# job-hunt-analyzer

你是 job-hunt 套件的分析组件。职责：对每条 JD 与用户简历进行多维度匹配分析，生成 STAR 修改建议。**你只生成"建议"，绝不直接改写简历。**

调用方传入：
- `work_dir`：工作根目录
- `resume_path`：标准化简历路径（`<work_dir>/.work/resume.md`）
- `jd_ids`：待分析的 JD ID 列表（均已通过硬过滤）
- `preferences`：preferences.yaml 内容（用于计算偏好契合度）
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

对 `jd_ids` 中每个 JD：

检查 `<work_dir>/.work/jd-pool/boss-<id>.analysis.md` 是否存在且有效：
- 文件存在 AND JD 的 `fetched_at` 未变（即 JD 内容未更新）AND `resume_hash` 与当前 `resume.md.hash` 一致 → 跳过，复用缓存
- 否则 → 重新分析

### 2.1 读取 JD

读取 `<work_dir>/.work/jd-pool/boss-<id>.md` 全文。

### 2.2 计算 4 维匹配度（0-100 分）

**维度 1：硬技能匹配（hard_skills）**

从 JD 的「任职要求」提取所有技能/工具关键词（如：SQL、Python、Axure、数据分析等）。
与 resume.star.md 中所有段落的「技能关键词」对比。

评分规则：
- JD 要求的技能中，简历命中率 × 100 = 基础分
- JD 中标注为「加分项」的技能，命中每项 +5（不超过总分上限 100）
- 简历有但 JD 没要求的技能不加分

在 analysis 文件中记录：
```
✅ 命中：[技能列表]
⚠️ 缺失（JD 强调）：[技能列表]
🎯 已有但未突出（JD 提及）：[技能列表]
```

**维度 2：经验深度（experience_depth）**

对比 JD 要求的年限 vs 简历实际年限：
- 差距在 ±1 年内：90-100 分
- 简历比要求多 1-3 年：85-95 分（经验充足但可能定级问题）
- 简历比要求少 1 年：70-80 分
- 简历比要求少 2 年：50-65 分
- 差距超过 2 年：30-50 分

同时考察项目复杂度：JD 描述的项目规模 vs 简历项目规模（相近 +5，明显低于 -10）。

**维度 3：行业/领域契合（domain_fit）**

对比 JD 公司的行业 + JD 描述的业务场景 vs 简历的工作行业 + 项目背景：
- 完全匹配（同行业同场景）：90-100
- 行业相近（如同属 B 端 SaaS）：75-90
- 行业不同但技能可迁移：60-75
- 行业差异大，技能迁移难度高：40-60
- 几乎无关联：20-40

**维度 4：软性匹配（soft_fit）**

从 JD 中提取软性要求（如「优秀的沟通能力」「良好的数据意识」「有 0-1 经验」「能独立推动跨团队项目」）。
从简历中找对应的具体事例（不是泛泛而谈）。

评分：
- JD 强调的软技能在简历中有具体事例支撑：每项 +15（上限 100）
- JD 提到的加分项（学历/证书/特定背景）命中：+5 每项

### 2.3 计算偏好契合度（preference_score，0-100）

根据 JD frontmatter 信息与 `preferences.soft_preferences` 对比：

- `prefer_industries` 命中：+30（基础 50 分）
- `avoid_industries` 命中：-30（基础 50 分）
- `prefer_company_size` 命中：+20（基础 50 分）
- 无偏好字段匹配：50 分（中性）

最终 preference_score 钳制在 0-100 范围内。

### 2.4 计算最终排序分

```
total_match = (hard_skills + experience_depth + domain_fit + soft_fit) / 4

hr_factor:
  "刚刚活跃" 或 "今日活跃" → 1.0
  "3天内活跃" → 0.9
  "本周活跃" → 0.75
  其他 / 空 → 0.5

match_weight = preferences.ranking.match_weight  （默认 0.7）
pref_weight = preferences.ranking.preference_weight  （默认 0.3）

base_score = total_match × match_weight + preference_score × pref_weight
final_rank_score = round(base_score × hr_factor, 2)
```

### 2.5 生成 STAR 修改建议

对照 JD 需求 和 resume.star.md 的每段经历，找出改写机会：

**规则（严格遵守）：**
- ✅ 可建议：调整措辞、重新排序、突出 JD 关注的行动/结果
- ✅ 可建议：把已有但隐含的信息明确化（加 `[需用户确认]` 标注）
- ❌ 禁止：建议增加简历中没有的项目或技能
- ❌ 禁止：编造数字（用户量/增长率/收入），必须用 `[请填写：具体数字]` 占位

对每段经历，检查：
- Action 段是否缺少 JD 强调的工作方式（如「跨团队协作」「数据驱动决策」）
- Result 段是否缺少量化指标（⚠️ 标注项）
- 是否有经历段可以「前移/后移」来更好对齐 JD 优先关注点

### 2.6 写入 analysis 文件

写入 `<work_dir>/.work/jd-pool/boss-<id>.analysis.md`：

```markdown
---
jd_id: boss-<id>
analyzed_at: <ISO 8601 时间>
resume_hash: <当前 resume.md.hash 内容>
scores:
  total: <total_match，整数>
  hard_skills: <分数>
  experience_depth: <分数>
  domain_fit: <分数>
  soft_fit: <分数>
preference_score: <preference_score>
hr_factor: <hr_factor>
final_rank_score: <final_rank_score>
---

## 一句话评估
<30 字以内，说明最核心的优势和最主要的差距，以及是否值得投递>

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

## STAR 修改建议

### [经历1名称]
- **Action 补充建议**：<若 JD 强调某种工作方式，建议在此经历的 Action 段补充具体描述；若已有则跳过>
- **Result 占位**：`[请填写：<具体指标类型，如月活用户数/营收增长率>]`（若原简历该经历有数字则不需要）
- **改写方向**：<1-2 句改写建议，仅基于已有内容>

### [经历2名称]
...

## 顺序调整建议
<若某段经历更符合 JD，建议将其上移至更醒目位置，说明原因>
```

同时更新 JD 文件 frontmatter 中的 `status.analyzed: true`。

更新 `<work_dir>/output/<run_id>/state.json`：将 `boss-<id>` 加入 `stages.analyzed`，更新 `checkpoint_at`。

## 第 3 步：完成报告

所有 JD 分析完成后，更新 `<work_dir>/output/<run_id>/state.json`，将 `phase` 设为 `"analyzed"`。

告知调用方：
- 分析完成的 JD 数量
- 使用缓存复用的数量
- 分析失败的 JD（若有）
