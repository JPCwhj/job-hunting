# Job-Hunt Skill Suite 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建 4 个协作 Claude Code Skill（job-hunt / job-hunt-fetcher / job-hunt-analyzer / job-hunt-tailor），实现从 Boss 直聘抓取 JD → STAR 匹配分析 → 定制简历三件套 → 排序 shortlist 的完整求职辅助流程。

**Architecture:** 所有状态以人类可读的 Markdown + YAML 文件存储在磁盘上（jd-pool、analysis、tailored 目录）。四个 skill 通过文件系统耦合：fetcher 写 JD 文件，analyzer 读 JD 写 analysis 文件，tailor 读两者生成三件套，main 编排全程并输出 shortlist.md。没有数据库、没有服务器、没有网络 API。

**Tech Stack:** Claude Code Skill files（Markdown + YAML frontmatter）、bb-browser MCP（真实浏览器自动化）、docx skill（Word 简历解析）、Claude Code 文件系统工具（Read / Write / Edit / Bash）。

**设计文档:** `docs/superpowers/specs/2026-04-29-job-hunt-skill-design.md`（所有设计决策在此，计划与 spec 保持引用关系）。

---

## 文件结构

```
skills/
├── job-hunt/
│   └── index.md              ← 主编排 skill（Task 5）
├── job-hunt-fetcher/
│   └── index.md              ← Boss 直聘抓取 skill（Task 2）
├── job-hunt-analyzer/
│   └── index.md              ← STAR 匹配分析 skill（Task 3）
└── job-hunt-tailor/
    └── index.md              ← 定制简历三件套 skill（Task 4）

templates/
└── preferences.yaml          ← 用户配置模板（Task 1）

scripts/
└── install.sh                ← 安装 skill 到 Claude Code（Task 6）
```

**安装路径：** `~/.claude/plugins/local/job-hunt/1.0.0/skills/`  
每个 skill 对应子目录：`job-hunt/`、`job-hunt-fetcher/`、`job-hunt-analyzer/`、`job-hunt-tailor/`

---

## Task 1：脚手架 + 用户配置模板

**Files:**
- Create: `templates/preferences.yaml`

- [ ] **Step 1: 写 preferences.yaml 模板**

```yaml
# ~/.job-hunt/preferences.yaml
# 求职偏好配置。把这个文件复制到 ~/.job-hunt/ 或你的求职项目目录，按注释填写。

# ── 必填：搜索条件 ──────────────────────────────────────
search:
  cities:               # 目标城市（支持多个）
    - 北京
    # - 杭州
    # - 上海
  keywords:             # 岗位关键词（支持多个，每个独立搜一轮）
    - 产品经理
    # - 高级产品经理
  experience: 3-5年      # Boss 直聘年限档位（如：1-3年 / 3-5年 / 5-10年 / 10年以上）
  salary: 20-40K         # 薪资筛选（可选，留空则不过滤）

# ── 硬过滤：命中即淘汰，不消耗 LLM ─────────────────────
hard_filters:
  exclude_companies:     # 公司黑名单（精确名称）
    # - XX 外包
  exclude_keywords:      # JD 标题或正文含这些词即跳过
    - 外包
    - 驻场
    # - 实习
  min_company_size: C    # 最小规模门槛（A=<20人 B=20-99 C=100-499 D=500-999 E=1000-9999 F=10000+）

# ── 软偏好：影响排序权重，不淘汰 ───────────────────────
soft_preferences:
  prefer_industries:     # 偏好行业（命中加分）
    - 互联网
    # - SaaS
    # - 人工智能
  avoid_industries:      # 不偏好行业（命中减分，但不淘汰）
    # - 教培
  prefer_company_size:   # 偏好规模档位
    - C
    - D

# ── 排序权重 ────────────────────────────────────────────
ranking:
  match_weight: 0.7          # 简历×JD 匹配度的权重（0-1）
  preference_weight: 0.3     # 偏好契合度的权重（0-1，两者之和应为 1）
  top_n_for_tailor: 10       # 为前几名 JD 生成定制简历（影响运行时长和 token 消耗）
```

- [ ] **Step 2: 创建目录占位文件**

在 `skills/job-hunt-fetcher/`、`skills/job-hunt-analyzer/`、`skills/job-hunt-tailor/`、`skills/job-hunt/` 各创建一个空的 `index.md`（内容仅 `# placeholder`），让 git 能追踪这些目录。

- [ ] **Step 3: Commit**

```bash
git add templates/ skills/ scripts/
git commit -m "feat: 项目脚手架 + preferences.yaml 模板"
git push
```

---

## Task 2：job-hunt-fetcher Skill

**Files:**
- Create: `skills/job-hunt-fetcher/index.md`

这是整个套件最复杂的 skill。必须精确指导 Claude 如何使用 bb-browser 操作 Boss 直聘，处理登录态、节奏控制、去重、失败降级，并输出严格格式的 JD 文件。

- [ ] **Step 1: 写 skill 文件**

完整写入 `skills/job-hunt-fetcher/index.md`：

```markdown
---
name: job-hunt-fetcher
description: Internal sub-skill for job-hunt suite. Fetches job listings from Boss 直聘 using bb-browser and writes structured JD markdown files to jd-pool. Do NOT invoke directly — use the job-hunt main skill instead.
---

# job-hunt-fetcher

你是 job-hunt 套件的抓取组件。**唯一职责**：从 Boss 直聘抓取 JD，输出标准化 Markdown 文件。你不做过滤、不做分析、不做改写。

调用方（job-hunt 主 skill）会传给你以下上下文：
- `work_dir`：工作根目录路径（当前目录或 ~/.job-hunt/）
- `preferences`：已解析的 preferences.yaml 内容
- `run_id`：本次 run 的时间戳 ID（格式 YYYY-MM-DD-HHMM）
- `state`：state.json 的当前内容（含断点信息）

## 第 0 步：读取 bb-browser skill

调用 Skill 工具，加载 `bb-browser` skill，获取浏览器操作能力。

## 第 1 步：检查 Boss 直聘登录态

使用 bb-browser 导航到 `https://www.zhipin.com`。
等待页面完全加载（等待顶部导航栏出现）。

观察页面右上角：
- 如果出现「登录 / 注册」按钮 → **立刻停止**，告诉用户：
  「请先在浏览器中登录 Boss 直聘（zhipin.com），登录完成后告诉我继续。」
  等待用户确认后再继续。
- 如果顶部显示用户头像或昵称 → 已登录，继续下一步。

## 第 2 步：构建搜索矩阵并恢复断点

从 `preferences.search` 中读取：
- `cities`：目标城市列表
- `keywords`：关键词列表
- `experience`（可选）
- `salary`（可选）

构建笛卡尔积：每个 keyword × 每个 city = 一个搜索轮次。

从 `state.search_progress.completed` 中读取已完成的轮次（格式：`"城市-关键词"`），跳过已完成的。

## 第 3 步：逐轮执行搜索

对每个待处理的 `城市-关键词` 组合，执行以下子步骤：

### 3.1 在 Boss 直聘搜索

使用 bb-browser 导航到 Boss 直聘首页，然后：
1. 在搜索框中输入关键词
2. 在城市选择器中选择目标城市（通常在搜索框旁边的下拉菜单）
3. 如果 preferences 中有 `experience` → 找到「经验」筛选器，选择对应档位
4. 如果 preferences 中有 `salary` → 找到「薪资」筛选器，选择对应范围
5. 点击搜索或按回车
6. 等待搜索结果加载（3-5 秒）

### 3.2 从列表页提取 10 条基础信息

对页面上前 10 个职位卡片，逐一提取：

```
title: 职位名称
company_name: 公司名称
company_size: 规模（原始文本，如"500-999人"）
company_industry: 行业标签
company_stage: 融资阶段（如"已上市"、"D轮及以上"，没有则留空）
salary_range: 薪资文本（如"20-40K"）
salary_months: 月数（如有"16薪"则提取 16，否则留空）
location_city: 城市
location_district: 区域（如"海淀区"）
experience_req: 经验要求文本
education_req: 学历要求文本
hr_active: HR 活跃状态文本（如"刚刚活跃"、"今日活跃"、"3天内活跃"、"本周活跃"）
detail_url: 职位详情页完整 URL
job_id: 从 detail_url 中提取 jobId（URL 格式为 /job_detail/<jobId>.html）
```

公司规模文本 → 档位映射：
- 20人以下 → A
- 20-99人 → B
- 100-499人 → C
- 500-999人 → D
- 1000-9999人 → E
- 10000人以上 → F

### 3.3 硬过滤（列表阶段，不进详情页）

对每条 JD，依次检查 `preferences.hard_filters`：

1. **公司黑名单**：`company_name` 是否在 `exclude_companies` 中 → 是则跳过，记录原因 `"公司在黑名单中"`
2. **关键词过滤**：`title` 是否包含 `exclude_keywords` 中的任意词 → 是则跳过，记录原因 `"标题含屏蔽词: [词]"`
3. **规模过滤**：`company_size` 档位是否低于 `min_company_size` → 是则跳过，记录原因 `"公司规模 [X] 低于要求 [Y]"`

被过滤的 JD 写入 `./output/<run_id>/raw/filtered-list.md`（格式见下方「过滤记录格式」），不进行后续处理。

### 3.4 缓存检查（通过过滤的 JD）

对通过过滤的每条 JD：
- 检查 `<work_dir>/.work/jd-pool/boss-<job_id>.md` 是否存在
- 读取文件中 `fetched_at` 字段
- 如果文件存在且 `fetched_at` 距今 **≤ 7 天** → 跳过详情页抓取，标记为「缓存命中」，更新 state
- 否则 → 进入 Step 3.5 抓取详情页

### 3.5 抓取详情页

对需要抓取的每条 JD：

1. 等待随机 **2-5 秒**（每次都要随机，不要固定值）
2. 使用 bb-browser 导航到 `detail_url`
3. 等待页面加载（等待「岗位职责」标题出现，超时 15 秒则记录失败并跳过）

检查是否出现验证码 / 滑块：
- 如果出现「请完成安全验证」或滑块弹窗 → **立刻停止当前轮次**，告诉用户：
  「Boss 直聘触发了验证码，请在浏览器中手动通过验证，完成后告诉我继续。」
  等待用户确认后继续。

从详情页提取：
```
tags: 技能标签列表（页面上的 pill 标签，通常在职位名称下方）
benefits: 福利标签列表（通常在岗位职责前的标签区）
hr_name: HR 姓名
hr_title: HR 职称
hr_active: HR 活跃状态（详情页上可能比列表页更准确）
posted_at: 发布时间（如"3天前"→ 换算为具体日期；"2026-04-26"→ 直接用）
job_description: 「岗位职责」部分全文
job_requirements: 「任职要求」部分全文
company_intro: 「公司介绍」部分全文（若无则留空）
```

### 3.6 写入 JD 文件

写入 `<work_dir>/.work/jd-pool/boss-<job_id>.md`：

```markdown
---
id: boss-<job_id>
url: <detail_url>
fetched_at: <当前 ISO 8601 时间，如 2026-04-29T14:23:11>
run_id: <run_id>

source:
  keyword: <keyword>
  city: <city>

title: <title>
company:
  name: <company_name>
  size: <档位字母，如 D>
  industry: <company_industry>
  stage: <company_stage，无则留空>
salary:
  range: "<salary_range>"
  monthly_count: <salary_months，无则 null>
location:
  city: <location_city>
  district: <location_district>
  area: <更细的地址，如能提取>
requirements:
  experience: <experience_req>
  education: <education_req>

tags: [<tag1>, <tag2>, ...]
benefits: [<benefit1>, <benefit2>, ...]
hr:
  name: <hr_name>
  title: <hr_title>
  active_status: <hr_active>
posted_at: <posted_at>

status:
  hard_filter: passed
  detail_fetched: true
  analyzed: false
---

## 岗位职责

<job_description 原文>

## 任职要求

<job_requirements 原文>

## 公司介绍

<company_intro 原文，若无则删除此节>
```

写入完成后，立即更新 `./output/<run_id>/state.json`：
- 将 `boss-<job_id>` 加入 `stages.fetched` 数组
- 更新 `checkpoint_at` 为当前时间

### 3.7 轮次间隔

当前 keyword×city 轮次的所有 10 条处理完毕后：
- 将此轮次标记为完成（加入 `state.search_progress.completed`）
- 等待随机 **5-10 秒** 再开始下一轮次

## 第 4 步：生成抓取摘要

所有轮次完成后，写入 `./output/<run_id>/search.summary.md`：

```markdown
# 抓取摘要 · <run_id>

## 统计
- 搜索轮次：<N> 轮（<cities> × <keywords>）
- 候选总数：<total_found>
- 通过硬过滤：<passed>
- 缓存命中（复用）：<cache_hits>
- 新抓取详情：<new_fetched>
- 失败/跳过：<failed>

## 失败列表
<逐条列出失败的 JD，含原因>

## 被过滤列表
<逐条列出硬过滤掉的 JD，含过滤原因>
```

更新 `state.json`，将 `phase` 设为 `"fetched"`。

## 过滤记录格式（写入 filtered-list.md）

```markdown
| 公司 | 职位 | 过滤原因 | 来源轮次 |
|---|---|---|---|
| XX 公司 | 产品经理 | 标题含屏蔽词: 外包 | 北京-产品经理 |
```

## 异常处理摘要

| 异常 | 处理方式 |
|---|---|
| 未登录 | 停止，提示用户登录后继续 |
| 验证码 / 滑块 | 停止当前轮次，提示用户过验证后继续 |
| 详情页加载超时（>15s） | 跳过该 JD，记录到 summary 失败列表 |
| 单个字段提取失败 | 该字段置为 null，不中断整条 JD |
| 0 结果的搜索轮次 | 记录 warning，继续下一轮次 |
```

- [ ] **Step 2: 手动验证场景**

创建测试场景文件 `tests/scenarios/01-fetcher.md`，记录期望行为：

```markdown
# Fetcher 验证场景

## 前置条件
- Chrome 中已登录 Boss 直聘
- preferences.yaml 配置：城市=北京，关键词=产品经理，min_company_size=C
- .work/jd-pool/ 为空（首次运行）

## 期望行为
1. skill 启动后，首先用 bb-browser 检查 zhipin.com 登录态
2. 搜索"北京 × 产品经理"，找到前 10 条结果
3. 规模小于 C 的公司（<100人）被过滤，不进详情页
4. 通过过滤的 JD 进入详情页，每次访问前随机等待 2-5 秒
5. 每条 JD 写入 .work/jd-pool/boss-<id>.md 后立刻继续（不等所有抓完再写）
6. 抓完后生成 search.summary.md

## 验证检查点
- [ ] jd-pool 中有文件，每个文件 frontmatter 字段完整（id/url/fetched_at/hr/status 等）
- [ ] 被过滤的 JD 出现在 filtered-list.md 中，含原因
- [ ] HR active_status 字段被正确提取（不是空字符串）
- [ ] 详情页原文（岗位职责/任职要求）出现在 md 正文中，未被改写
- [ ] state.json 的 stages.fetched 包含所有成功抓取的 jobId
```

- [ ] **Step 3: Commit**

```bash
git add skills/job-hunt-fetcher/ tests/
git commit -m "feat: job-hunt-fetcher skill - Boss 直聘 JD 抓取"
git push
```

---

## Task 3：job-hunt-analyzer Skill

**Files:**
- Create: `skills/job-hunt-analyzer/index.md`

- [ ] **Step 1: 写 skill 文件**

完整写入 `skills/job-hunt-analyzer/index.md`：

```markdown
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

拆解后写入 `<work_dir>/.work/resume.star.md`，同时更新 `resume.md.hash`。

## 第 2 步：逐条 JD 分析

对 `jd_ids` 中每个 JD（从 state.json 的 stages.filtered_in 中取）：

检查 `<work_dir>/.work/jd-pool/boss-<id>.analysis.md` 是否存在且有效：
- 文件存在 AND JD 的 `fetched_at` 未变（即 JD 内容未更新）AND `resume.md.hash` 与当前一致 → 跳过，复用缓存
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

- `prefer_industries` 命中：+30
- `avoid_industries` 命中：-30
- `prefer_company_size` 命中：+20
- 无偏好字段匹配：50 分（中性）

### 2.4 计算最终排序分

```
total_match = (hard_skills + experience_depth + domain_fit + soft_fit) / 4

hr_factor:
  "刚刚活跃" 或 "今日活跃" → 1.0
  "3天内活跃" → 0.9
  "本周活跃" → 0.75
  其他 / 空 → 0.5

match_weight = preferences.ranking.match_weight  (默认 0.7)
pref_weight = preferences.ranking.preference_weight  (默认 0.3)

base_score = total_match * match_weight + preference_score * pref_weight
final_rank_score = round(base_score * hr_factor, 2)
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
resume_hash: <当前 resume.md.hash>
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

更新 `state.json`：将 `boss-<id>` 加入 `stages.analyzed`，更新 `checkpoint_at`。

## 第 3 步：完成报告

所有 JD 分析完成后，更新 `state.json`，将 `phase` 设为 `"analyzed"`。

告知调用方：
- 分析完成的 JD 数量
- 使用缓存复用的数量
- 分析失败的 JD（若有）
```

- [ ] **Step 2: 写验证场景**

创建 `tests/scenarios/02-analyzer.md`：

```markdown
# Analyzer 验证场景

## 前置条件
- .work/jd-pool/ 中至少有 2 条 JD（来自 Task 2 的 fetcher 测试）
- .work/resume.md 是一份真实简历

## 验证检查点
- [ ] resume.star.md 被生成，每段工作经历都有 STAR 四要素
- [ ] 分数在 0-100 范围内，4 维子分与总分逻辑一致
- [ ] analysis.md 中没有出现「请增加 [从未提到的] 经历」之类的建议
- [ ] Result 段若简历缺数字，建议中使用了 `[请填写：xxx]` 而非编造
- [ ] final_rank_score 的公式计算正确（可手算验证一条）
- [ ] HR 活跃度系数被正确应用（刚刚活跃的 JD final_rank_score 不低于本周活跃的同分 JD）
```

- [ ] **Step 3: Commit**

```bash
git add skills/job-hunt-analyzer/ tests/scenarios/02-analyzer.md
git commit -m "feat: job-hunt-analyzer skill - STAR 匹配分析"
git push
```

---

## Task 4：job-hunt-tailor Skill

**Files:**
- Create: `skills/job-hunt-tailor/index.md`

- [ ] **Step 1: 写 skill 文件**

完整写入 `skills/job-hunt-tailor/index.md`：

```markdown
---
name: job-hunt-tailor
description: Internal sub-skill for job-hunt suite. Generates 3-piece tailored output (resume.md / opener.md / changelog.md) for top-ranked JDs. Enforces strict ethical boundaries — never fabricates experience or numbers. Do NOT invoke directly — use the job-hunt main skill instead.
---

# job-hunt-tailor

你是 job-hunt 套件的定制组件。职责：为每个 Top N JD 生成三件套产物。**你有最严格的伦理边界约束。**

调用方传入：
- `work_dir`：工作根目录
- `resume_path`：`<work_dir>/.work/resume.md`
- `jd_ids`：Top N JD 的 ID 列表（已排好序）
- `run_id`：本次 run ID

## ⛔ 伦理红线（每次生成前必须内化这些规则）

**允许：**
- 改写措辞、调整语句顺序、合并/拆分句子
- 把简历中已有经历里和 JD 相关的部分移到更醒目的位置
- 用 STAR 法则重写已有项目描述（基于 analysis 中的建议）
- 若简历某段经历「显然蕴含」某信息但未明说，可轻度补充，**加 `[需用户确认]` 标注**

**禁止（遇到就停，不替用户做）：**
- 凭空增加简历中没有提到的项目、技能、公司经历
- 编造具体数字（用户量、增长率、营收），**必须用 `[请填写：<描述>]` 占位**
- 修改工作时间段、职级、公司名称
- 在 opener.md 中提及简历中没有的经历

## 第 1 步：对每个 JD 依次生成三件套

对 `jd_ids` 中每个 ID，创建目录 `./output/<run_id>/tailored/boss-<id>/`，生成以下三个文件。

### 1.1 生成 resume.md（定制简历）

读取：
- `<work_dir>/.work/resume.md`（主简历）
- `<work_dir>/.work/jd-pool/boss-<id>.md`（JD 内容）
- `<work_dir>/.work/jd-pool/boss-<id>.analysis.md`（分析建议）

按照 analysis 中的「顺序调整建议」和「STAR 修改建议」，改写主简历：

1. 调整经历段的顺序（把与 JD 最相关的放前面）
2. 对每段经历，按建议重写 Action 和 Result（保持事实，不增加内容）
3. 技能列表：把 JD 强调的已有技能移到最前
4. 若 analysis 中有「Result 占位」建议，在对应位置插入 `[请填写：<描述>]`
5. 若有「需用户确认」的推断，加 `[需用户确认]` 标注

输出格式：完整的 Markdown 简历，与主简历结构一致，只改内容不改结构。

写入 `./output/<run_id>/tailored/boss-<id>/resume.md`。

### 1.2 生成 opener.md（HR 开场白）

Boss 直聘 IM 第一条消息，给 HR 发的开场白。严格限制 **200 字以内**。

结构：
1. 称呼 + 简短自我介绍（1 句）
2. 点出**一个**与该 JD 最相关的具体经历（必须是简历中真实存在的）
3. 表达沟通意愿（1 句）

规则：
- 只提简历中有的经历，不造
- 若某经历有 `[请填写：xxx]` 占位，开场白中**不引用**该经历的数字
- 保留占位 `[请填写：xxx]` 若开场白中必须提到这个经历

写入 `./output/<run_id>/tailored/boss-<id>/opener.md`：

```markdown
# 开场白 · <company_name> · <title>

<正文，200 字以内>
```

### 1.3 生成 changelog.md（改动列表）

逐条记录对主简历做的所有改动，每条注明原因。这是给用户的「透明度报告」。

格式：

```markdown
# 改动列表 · 对比主简历

## ✏️ 措辞调整
1. [段落名称]：「<原文>」→「<改后>」
   - 原因：<JD 中哪里触发了这个改动>

## 🔼 顺序调整
1. 将「<段落>」上移至「<新位置>」
   - 原因：<JD 最关注这个方向>

## ⚠️ 需用户回填
1. [段落名称] Result 段：`[请填写：<具体描述>]`
   - 原因：<简历此处缺具体数字，JD 强调数据驱动>

## 🔵 需用户确认
1. [段落名称]：「<改写内容>」[需用户确认]
   - 原因：<推断依据>

## ❌ 弱化/后移
1. 将「<段落>」后移或精简
   - 原因：<该经历与 JD 相关性低>
```

若无某类改动，省略该节。

写入 `./output/<run_id>/tailored/boss-<id>/changelog.md`。

## 第 2 步：更新 state.json

每完成一个 JD 的三件套，立即将 `boss-<id>` 加入 `stages.tailored`，更新 `checkpoint_at`。

三件套全部完成后，告知调用方完成的 JD 数量及产物路径。
```

- [ ] **Step 2: 写验证场景**

创建 `tests/scenarios/03-tailor.md`：

```markdown
# Tailor 验证场景

## 验证检查点（每个生成的三件套都要检查）

### resume.md
- [ ] 与主简历段落结构一致，不多不少
- [ ] 没有出现主简历中从未提到过的公司、项目、技能
- [ ] 有数字出现时，数字与主简历一致（没有被修改或放大）
- [ ] 若有 `[请填写：xxx]`，旁边有清晰描述

### opener.md
- [ ] 字数 ≤ 200 字（汉字计数）
- [ ] 提到的经历可以在主简历中找到
- [ ] 没有编造数字

### changelog.md
- [ ] 每一条改动都有「原因」
- [ ] 所有在 resume.md 中的改动，changelog 都有对应记录
- [ ] 没有漏记改动（改动数量大致吻合）
```

- [ ] **Step 3: Commit**

```bash
git add skills/job-hunt-tailor/ tests/scenarios/03-tailor.md
git commit -m "feat: job-hunt-tailor skill - 定制简历三件套"
git push
```

---

## Task 5：job-hunt 主 Skill

**Files:**
- Create: `skills/job-hunt/index.md`

- [ ] **Step 1: 写 skill 文件**

完整写入 `skills/job-hunt/index.md`：

```markdown
---
name: job-hunt
description: 求职助手主入口。从 Boss 直聘抓取目标 JD，与你的简历做 STAR 匹配分析，生成定制简历和开场白，按匹配度排序产出 shortlist。使用前需配置 preferences.yaml 和 resume.md。支持子命令：fetch / analyze / tailor / resume / status / clean。
---

# job-hunt 求职助手

## 子命令路由

根据用户输入判断执行路径：

| 用户输入 | 执行 |
|---|---|
| `/job-hunt` 或 `/job-hunt` 无参数 | 全流程 |
| `/job-hunt fetch` | 只执行抓取（Step 3） |
| `/job-hunt analyze` | 只执行分析（Step 5），基于现有 jd-pool |
| `/job-hunt tailor` | 只执行定制（Step 6），基于现有 analysis |
| `/job-hunt resume` | 接续上次未完成 run（Step 2 断点恢复） |
| `/job-hunt status` | 输出当前 run 状态（Step 1 + 输出 state.json 摘要） |
| `/job-hunt clean` | 清理过期缓存（Step 8） |

## Step 1：确定工作目录

按以下顺序查找工作目录（`work_dir`）：
1. 当前目录（`./`）下存在 `resume.md`、`resume.docx` 或 `preferences.yaml` 中的任何一个 → 当前目录为 `work_dir`
2. 都不存在 → `~/.job-hunt/` 为 `work_dir`（若不存在则提示用户创建）

## Step 2：检查配置文件与断点

### 2.1 读取 preferences.yaml

读取 `<work_dir>/preferences.yaml`。若不存在：
告诉用户：「找不到 preferences.yaml，请把模板（templates/preferences.yaml）复制到 <work_dir>/，填写后再运行。」停止。

验证必填字段存在：`search.cities`（非空列表）、`search.keywords`（非空列表）。
若缺少则告知用户具体缺少哪个字段，停止。

### 2.2 读取/标准化简历

检查 `<work_dir>/resume.md` 和 `<work_dir>/resume.docx` 是否存在：

- 两个都存在 → 告知用户：「同时检测到 resume.md 和 resume.docx，请删除或重命名其中一个，保留唯一的简历文件。」停止。
- 只有 resume.md → 复制到 `<work_dir>/.work/resume.md`（若已存在则比较 mtime，更新的覆盖）
- 只有 resume.docx → 调用 `docx` skill 将其转换为 Markdown，写入 `<work_dir>/.work/resume.md`
- 两个都不存在 → 告知用户需要提供简历文件，停止。

计算 hash：
```bash
md5 -q <work_dir>/.work/resume.md
```
写入 `<work_dir>/.work/resume.md.hash`。

同样计算 preferences.yaml 的 hash：
```bash
md5 -q <work_dir>/preferences.yaml
```
写入 `<work_dir>/.work/preferences.yaml.hash`。

### 2.3 创建工作目录

确保以下目录存在（Bash mkdir -p）：
```
<work_dir>/.work/jd-pool/
./output/
```

### 2.4 断点检测

查找 `./output/` 下所有 `state.json`，找最新的一个（按 run_id 时间戳排序）。

若找到 state.json 且 `phase` 不是 `"done"`：
- 计算 checkpoint_at 距今时长
- 若 < 24 小时 → 询问用户：「上次 run（<run_id>）未完成，当前阶段：<phase>。要继续、重新开始，还是放弃？(继续/重开/放弃)」
  - 继续 → 复用该 run_id，从断点 phase 继续
  - 重开 → 生成新 run_id，全新开始
  - 放弃 → 停止
- 若 ≥ 24 小时 → 告知用户上次 run 超时，默认开始新 run

新建 run 时，生成 `run_id`（格式：`YYYY-MM-DD-HHMM`，使用当前时间）。
创建目录 `./output/<run_id>/`。
初始化 `./output/<run_id>/state.json`：
```json
{
  "run_id": "<run_id>",
  "phase": "init",
  "search_progress": { "completed": [], "pending": [] },
  "stages": { "fetched": [], "filtered_in": [], "analyzed": [], "tailored": [] },
  "last_error": null,
  "checkpoint_at": "<当前 ISO 时间>"
}
```

## Step 3：抓取（job-hunt-fetcher）

（子命令 `fetch` 或全流程时执行）

告知用户：「开始从 Boss 直聘抓取 JD，预计 15-20 分钟，请保持 Chrome 打开...」

调用 Skill 工具，加载 `job-hunt-fetcher`，传入：
- work_dir、preferences、run_id、state

等待 fetcher 完成。读取更新后的 state.json。

## Step 4：自动清理过期缓存

（全流程每次都执行，静默进行）

扫描 `<work_dir>/.work/jd-pool/`：
- 读取每个文件的 `fetched_at`
- 距今超过 **30 天** 的文件：同时删除 `boss-<id>.md` 和 `boss-<id>.analysis.md`（若存在）

扫描 `./output/`：
- 读取每个 run 目录名的时间戳
- 距今超过 **14 天** 的 run 目录：整体删除

清理结果静默记录，不打扰用户（除非清理了大量文件，超过 50 个，则提示一下）。

## Step 5：分析（job-hunt-analyzer）

（子命令 `analyze` 或全流程时执行）

确定待分析 JD 列表：
- 从 state.json 的 `stages.filtered_in` 中取（fetcher 已过滤的 JD）
- 排除 `stages.analyzed` 中已分析的（断点续跑）
- 若 `stages.filtered_in` 为空（直接运行 analyze 子命令时），扫描 jd-pool 中 `status.hard_filter: passed` 且 `status.analyzed: false` 的文件

调用 Skill 工具，加载 `job-hunt-analyzer`，传入：
- work_dir、resume_path、jd_ids、preferences、run_id

## Step 6：排序

（全流程或 tailor 子命令前执行，不调用 LLM，纯计算）

读取所有 analysis 文件，按 `final_rank_score` 降序排列。

取前 `preferences.ranking.top_n_for_tailor`（默认 10）条作为 Top N。

## Step 7：定制简历（job-hunt-tailor）

（子命令 `tailor` 或全流程时执行）

取 Step 6 的 Top N JD ID 列表。
排除已在 `stages.tailored` 中的（断点续跑）。

调用 Skill 工具，加载 `job-hunt-tailor`，传入：
- work_dir、resume_path、jd_ids（Top N）、run_id

## Step 8：生成 shortlist.md

（全流程最后一步）

读取所有 analysis 文件和所有 JD frontmatter，生成 `./output/<run_id>/shortlist.md`：

```markdown
# 求职 Shortlist · <run_id>

## 概况
- 搜索：<cities> × <keywords>（<N> 轮）
- 候选：<total_fetched> 抓取 → <filtered_in> 通过过滤 → <analyzed> 完成分析
- Top <top_n> 已生成定制简历

## Top 推荐（按最终排序分倒序）

### 🥇 1. <company.name> · <title> · <final_rank_score> 分
- 💰 <salary.range><若有 monthly_count 则加"·Xsalary_months>薪"> | 📍 <location.city>·<location.district>
- 👤 HR <hr.name>（<hr.active_status> <若活跃度为"刚刚活跃"或"今日活跃"则加"✨">）
- 📊 匹配 <scores.total>（硬技能 <hard_skills> / 经验 <experience_depth> / 行业 <domain_fit> / 软性 <soft_fit>）
- 💡 <analysis 中的一句话评估>
- 🔗 [打开 JD](<url>)
- 📄 [定制简历](./tailored/boss-<id>/resume.md) · 💬 [开场白](./tailored/boss-<id>/opener.md) · 📋 [改动](./tailored/boss-<id>/changelog.md)
- ⚠️ 投递前：<从 analysis 中提取的「需用户回填」项摘要，≤ 1 行>

<重复以上格式直到 Top N>

## 其余 JD（仅参考，未生成定制简历）

| 公司 | 职位 | 匹配分 | 主要不匹配点 |
|---|---|---|---|
<按 final_rank_score 降序列出剩余 JD>
```

更新 state.json，将 `phase` 设为 `"done"`。

告知用户：「✅ 完成！shortlist 在 ./output/<run_id>/shortlist.md」

## Step 8（clean 子命令）：强制清理

删除 `<work_dir>/.work/jd-pool/` 下所有文件（含 analysis）。
删除 `./output/` 下所有 run 目录。
删除 `<work_dir>/.work/resume.star.md`、`*.hash` 文件。
告知用户清理了多少文件。
```

- [ ] **Step 2: 写验证场景**

创建 `tests/scenarios/04-integration.md`：

```markdown
# 端到端验证场景

## 首次运行完整流程
- [ ] 工作目录下有 preferences.yaml 和 resume.md
- [ ] 运行 `/job-hunt`
- [ ] 被提示检查 Chrome 登录态
- [ ] 开始抓取，有实时进度提示
- [ ] 若有验证码，被正确提示暂停并等待
- [ ] 抓取完成后自动进入分析阶段
- [ ] 分析完成后自动进入定制阶段（只为 Top 10）
- [ ] 最终生成 shortlist.md，结构与 spec 第 11 节一致

## 断点续跑
- [ ] 中途 Ctrl+C 中断
- [ ] 再次运行 `/job-hunt`
- [ ] 被询问「继续还是重开」
- [ ] 选择继续后，从断点 phase 接续，已完成的 JD 不重复处理

## 缓存验证
- [ ] 24 小时内第二次运行，绝大多数 JD 走缓存（fetcher 应显著快于首次）
- [ ] 修改 resume.md 后运行，analysis 缓存被 invalidate，重新分析

## 子命令
- [ ] `/job-hunt status` 输出当前 run 状态和进度
- [ ] `/job-hunt fetch` 只抓取，不分析
- [ ] `/job-hunt clean` 清理缓存后确认文件消失
```

- [ ] **Step 3: Commit**

```bash
git add skills/job-hunt/ tests/scenarios/04-integration.md
git commit -m "feat: job-hunt 主 skill - 编排 + shortlist 生成"
git push
```

---

## Task 6：安装 + 端到端验证

**Files:**
- Create: `scripts/install.sh`

- [ ] **Step 1: 写安装脚本**

写入 `scripts/install.sh`：

```bash
#!/bin/bash
# 将 job-hunt skill suite 安装到 Claude Code 插件目录

PLUGIN_DIR="$HOME/.claude/plugins/local/job-hunt/1.0.0/skills"

echo "安装 job-hunt skill suite 到 $PLUGIN_DIR ..."

mkdir -p "$PLUGIN_DIR/job-hunt"
mkdir -p "$PLUGIN_DIR/job-hunt-fetcher"
mkdir -p "$PLUGIN_DIR/job-hunt-analyzer"
mkdir -p "$PLUGIN_DIR/job-hunt-tailor"

# 复制 skill 文件
cp skills/job-hunt/index.md           "$PLUGIN_DIR/job-hunt/index.md"
cp skills/job-hunt-fetcher/index.md   "$PLUGIN_DIR/job-hunt-fetcher/index.md"
cp skills/job-hunt-analyzer/index.md  "$PLUGIN_DIR/job-hunt-analyzer/index.md"
cp skills/job-hunt-tailor/index.md    "$PLUGIN_DIR/job-hunt-tailor/index.md"

echo "✅ 安装完成。重启 Claude Code 后即可使用 /job-hunt。"
echo ""
echo "首次使用："
echo "  1. cp templates/preferences.yaml ~/.job-hunt/preferences.yaml"
echo "  2. 编辑 ~/.job-hunt/preferences.yaml，填入你的求职偏好"
echo "  3. 把简历放到 ~/.job-hunt/resume.md 或 ~/.job-hunt/resume.docx"
echo "  4. 确保 Chrome 已登录 Boss 直聘"
echo "  5. 在 Claude Code 中运行 /job-hunt"
```

```bash
chmod +x scripts/install.sh
```

- [ ] **Step 2: 验证安装路径是否正确**

运行脚本，检查文件是否出现在 Claude Code 插件目录：

```bash
bash scripts/install.sh
ls ~/.claude/plugins/local/job-hunt/1.0.0/skills/
```

预期输出：
```
job-hunt  job-hunt-analyzer  job-hunt-fetcher  job-hunt-tailor
```

若路径不对（提示目录不存在），尝试：
```bash
ls ~/.claude/plugins/
```
按实际结构调整 `PLUGIN_DIR`，更新 `install.sh`。

- [ ] **Step 3: 重启 Claude Code，尝试调用 `/job-hunt status`**

重启后在 Claude Code 中输入 `/job-hunt status`，观察：
- skill 是否被识别（输出 job-hunt skill 内容而非「命令不存在」）
- 能否正确找到工作目录和配置文件

- [ ] **Step 4: 端到端首次运行**

按 `tests/scenarios/04-integration.md` 的检查点逐一验证。

重点验证伦理边界：
- 找到一条 JD，运行完整流程
- 打开对应的 `tailored/<id>/changelog.md`
- 核查 changelog 中的每条改动能在主简历中找到原始依据
- 核查 resume.md 中没有出现主简历不存在的经历或数字

- [ ] **Step 5: 最终 Commit**

```bash
git add scripts/
git commit -m "feat: install.sh + 端到端验证完成"
git push
```

---

## 自审：Spec 覆盖检查

| Spec 节 | 计划覆盖 |
|---|---|
| §2.2 改写伦理红线 | ✅ Task 3（analyzer prompt）+ Task 4（tailor 红线节）|
| §5 目录结构 | ✅ Task 5 Step 1-3（work_dir 解析 + 目录创建）|
| §6 preferences schema | ✅ Task 1（模板文件）+ Task 5（加载与验证）|
| §7 两阶段抓取 + 节奏 + 去重 + 失败处理 | ✅ Task 2（fetcher 详细步骤）|
| §8 JD 数据 schema | ✅ Task 2 Step 3.6（写入格式）|
| §9 STAR 拆解 + 4 维评分 + HR 系数 | ✅ Task 3（analyzer 完整规则）|
| §10 三件套产物格式 | ✅ Task 4（tailor 三件套）|
| §11 shortlist 格式 | ✅ Task 5 Step 8（shortlist 生成）|
| §12.1 三层缓存 | ✅ Task 2（JD 缓存）+ Task 3（analysis 缓存）+ Task 3（STAR 缓存）|
| §12.2 断点续抓 state.json | ✅ Task 5 Step 2.4（断点检测）|
| §12.3 自动清理（30天/14天）| ✅ Task 5 Step 4（自动清理）|
| §3.3 子命令路由 | ✅ Task 5（子命令路由表）|
| §13.1 首次设置流程 | ✅ Task 6 install.sh 说明|
