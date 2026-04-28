# 求职助手 Skill Suite 设计文档

**日期**: 2026-04-29
**形态**: Claude Code Skill Suite（1 主 + 3 子）
**目标平台**: Boss 直聘（v1 仅此一家）

---

## 1. 项目目标

为 Claude Code 用户提供一套求职辅助工具，闭环流程：

1. 从 Boss 直聘按用户偏好抓取 JD
2. 用 STAR 法则把简历与每条 JD 做交叉比对，输出多维匹配度评分
3. 为高匹配度的 JD 生成定制版简历 + 给 HR 的开场白 + 改动 changelog
4. 按"匹配度 × 偏好契合 × HR 活跃度"排序，生成 shortlist
5. 用户在 shortlist 上挑岗 → 回填简历占位符 → 转 PDF → 打开 JD 链接 → 在 Boss IM 里手动投递

**v1 用户预期**：作者本人 + 会用 Claude Code 的朋友。验证"AI 辅助求职"流程是否真有用，再决定是否产品化。

## 2. 核心边界与约束

### 2.1 不做的事（YAGNI）

- ❌ 自动投递 / 自动回复 HR（违反平台 ToS、易封号）
- ❌ 多招聘网站（v1 仅 Boss 直聘）
- ❌ 跨用户/云同步
- ❌ 投递状态跟踪（用户层状态全部不做）
- ❌ docx 反向输出（定制简历仅 MD，用户自己转 PDF）
- ❌ 多简历版本切换（v1 一份主简历）
- ❌ 自动化测试套件（v1 人工评审）

### 2.2 改写伦理红线（写进 analyzer 和 tailor 的 prompt）

| 行为 | 是否允许 |
|---|---|
| 改写措辞、调整顺序、合并/拆分句子 | ✅ |
| 把已有经历中和 JD 相关的部分往醒目位置放 | ✅ |
| 用 STAR 法则重写已有项目描述 | ✅ |
| 已有经历"显然蕴含"但没明说的合理信息 | ✅（标注 `[需用户确认]`） |
| 凭空增加项目、技能、公司经历 | ❌ |
| 编造具体数字（用户量、增长率、收入） | ❌（必须留 `[请填写：xxx]` 占位） |
| 修改过往工作时间、职级 | ❌ |

`[需用户确认]` 和 `[请填写：xxx]` 是关键透明度标记——让用户清楚看到"这是建议，不是事实"。

### 2.3 投递降级

Boss 直聘的实际投递流程不是表单提交，而是 IM 沟通：
1. 用户点 JD 页面"立即沟通"
2. 用户给 HR 发开场白
3. HR 通过后用户上传简历 PDF

**自动化止于"准备产物"**：系统准备好 JD 链接 + 定制简历 md + 开场白文本，**点击"立即沟通"及之后所有 IM 操作均由用户人手完成**。

## 3. 形态选择：Skill Suite

### 3.1 拆分

```
job-hunt              ← 主入口，编排整条流程
├── job-hunt-fetcher  ← Boss 直聘抓取（bb-browser）
├── job-hunt-analyzer ← STAR 预处理 + 4 维匹配度 + 改写建议
└── job-hunt-tailor   ← 定制简历三件套（resume/opener/changelog）
```

**不做** `job-hunt-shared`：v1 单数据源，schema 约定写在主 skill 文档中即可。扩展到 LinkedIn/拉勾时再独立。

### 3.2 各 skill 职责

#### `job-hunt`（主）
- 加载 `preferences.yaml` 和 `resume.md`
- 三层缓存检查与管理（JD / 分析 / STAR）
- **硬过滤**（纯规则，不调 LLM）
- 断点检测 + 恢复（读 `state.json`）
- 编排调度子 skill
- **排序 + 生成 `shortlist.md`**（纯算分公式，不调 LLM）
- 自动清理过期缓存
- 用户交互入口（slash command + 自然语言描述触发）

#### `job-hunt-fetcher`（子）
- 唯一职责：从 Boss 直聘抓取 JD，输出标准化 md
- 检查登录态、检测验证码、节奏控制、断点续抓
- 输出到 `~/.job-hunt/.work/jd-pool/<jobId>.md`
- **不做**任何过滤、分析、改写

#### `job-hunt-analyzer`（子）
- 首次运行：拆解主简历为 STAR，缓存到 `.work/resume.star.md`
- 对每个 JD：4 维打分 + 一句话评估 + STAR 修改建议
- 输出 `<jobId>.analysis.md`
- **严守边界**：只生成"建议"，不直接改写简历

#### `job-hunt-tailor`（子）
- 输入：1 个 JD + 1 份分析报告 + 主简历
- 输出三件套：`resume.md` / `opener.md` / `changelog.md`
- 严格遵守改写边界（占位符 `[请填写：xxx]` / `[需用户确认]`）
- 默认只为 Top 10 跑

### 3.3 入口设计

主 skill 注册为 slash command + description 触发：

```
/job-hunt          → 全流程
/job-hunt fetch    → 只抓取
/job-hunt analyze  → 只分析（用现有 raw）
/job-hunt tailor   → 只为 Top N 生成定制简历
/job-hunt resume   → 接续上次未完成 run
/job-hunt status   → 查看当前 run 状态
/job-hunt clean    → 强制清理缓存
```

子 skill 不直接暴露给用户，由主 skill 内部调用——避免跳过编排逻辑。

## 4. 数据流

```
preferences.yaml + resume.md (md/docx)
        ↓
   ┌─────────┐
   │job-hunt │ (主) ── 加载 / 检查缓存 / 检查断点
   └────┬────┘
        ↓
   ┌──────────────────┐
   │job-hunt-fetcher  │ ── bb-browser → Boss 直聘
   └────┬─────────────┘
        ↓
   jd-pool/*.md（~60 条候选）
        ↓
   主 skill: 硬过滤
        ↓
   ~30 条通过
        ↓
   ┌──────────────────┐
   │job-hunt-analyzer │ ── 首次拆 STAR + 逐条打分
   └────┬─────────────┘
        ↓
   *.analysis.md（30 份）
        ↓
   主 skill: 排序（HR 系数 × 公式）
        ↓
   Top 10
        ↓
   ┌────────────────┐
   │job-hunt-tailor │ ── 三件套
   └────┬───────────┘
        ↓
   tailored/<jobId>/{resume,opener,changelog}.md
        ↓
   主 skill: 生成 shortlist.md
        ↓
   用户挑 → 回填占位 → 转 PDF → 打开 JD 链接 → IM 沟通投递
```

## 5. 文件与目录结构

### 5.1 全局工作目录（fallback）

```
~/.job-hunt/
├── resume.md / resume.docx        # 主简历（用户提供，二选一）
├── preferences.yaml               # 求职偏好
└── .work/
    ├── resume.md                  # 标准化主简历（docx → md 的工作副本）
    ├── resume.md.hash             # md5，检测主简历变化
    ├── resume.star.md             # STAR 预处理缓存
    ├── preferences.yaml.hash      # md5，检测偏好变化
    └── jd-pool/                   # 跨 run 的 JD 池（去重核心）
        ├── boss-abc123def.md
        └── boss-abc123def.analysis.md
```

### 5.2 目录解析策略

`./` 当前目录优先 → `~/.job-hunt/` fallback。

- 当前目录有 `resume.md`/`resume.docx` 和/或 `preferences.yaml` → 当前目录就是工作根
- 没有 → 回退到 `~/.job-hunt/`
- 自用方便，朋友/不同求职项目隔离也方便

### 5.3 简历输入处理

- **支持**：`.md` 或 `.docx`（用现有的 `docx` skill 解析）
- **内部工作格式**：始终是 MD（标准化到 `.work/resume.md`）
- **冲突**：md 和 docx 同时存在 → 警告并要求用户指定唯一 source of truth
- **变更检测**：对比 docx mtime vs `.work/resume.md` mtime，docx 更新则重转

### 5.4 per-run 输出目录

```
./output/<run-id>/                  # run-id = 时间戳（如 2026-04-29-1420）
├── state.json                     # 断点续抓状态
├── run.meta.yaml                  # 本次运行元数据快照
├── raw/jds/                       # 软链/引用到 jd-pool
├── analysis/                      # 软链/引用到 jd-pool
├── tailored/
│   └── <jobId>/
│       ├── resume.md              # 定制简历
│       ├── opener.md              # 给 HR 的开场白
│       └── changelog.md           # vs 主简历的改动列表
├── search.summary.md              # 抓取统计
└── shortlist.md                   # 主产物
```

## 6. 求职偏好 schema (`preferences.yaml`)

```yaml
# 必填：搜索条件
search:
  cities:                          # 多选
    - 北京
    - 杭州
  keywords:                        # 多选，每个独立搜一轮
    - 产品经理
    - 高级产品经理
  experience: 3-5年                 # Boss 档位
  salary: 20-40K                   # 可选

# 硬过滤：不满足直接淘汰，不进 LLM 分析
hard_filters:
  exclude_companies:
    - XX 外包
  exclude_keywords:                # JD/标题命中即跳过
    - 外包
    - 驻场
  min_company_size: D              # A=20人以下 ... E=10000人+

# 软偏好：影响最终排序权重，不淘汰
soft_preferences:
  prefer_industries:
    - 互联网
    - SaaS
  avoid_industries:
    - 教培
  prefer_company_size: [C, D]

# 排序权重
ranking:
  match_weight: 0.7                # 匹配度权重
  preference_weight: 0.3           # 偏好契合权重
  top_n_for_tailor: 10             # 为前几名生成定制简历
```

**关键设计**：
- 硬过滤 vs 软偏好分两层（让用户分清"绝对不去" vs "不太想去"）
- 排序公式简单可控（两个权重，不引入复杂多目标优化）
- `keyword × city` 笛卡尔积独立搜索（搜全度优先）

## 7. 抓取策略 (fetcher)

### 7.1 数量

`6 轮搜索 (2 城市 × 3 关键词) × Top 10 = ~60 条候选`

### 7.2 两阶段抓取

```
阶段 1: 列表页 → 拿基础字段（标题/公司/薪资/规模等）
   ↓
   主 skill 硬过滤
   ↓
阶段 2: 通过过滤的（~30 条）才进详情页
   ↓
   完整 JD 内容写入 jd-pool/<jobId>.md
```

理由：详情页慢且耗反爬额度。先用列表信息淘汰一半再进详情，时间和风险都减半。

### 7.3 节奏（避免反爬）

- 详情页之间随机停顿 **2-5 秒**
- 列表翻页之间停顿 **3-6 秒**
- 每轮搜索之间停顿 **5-10 秒**
- 严格单线程（bb-browser 本来就单浏览器单 tab）

总耗时估算：**15-20 分钟**完成一轮 60 条抓取。

### 7.4 失败处理

| 场景 | 处理 |
|---|---|
| 用户未登录 Boss | 启动时检测，提示用户登录后回来 |
| 触发滑块 / 验证码 | 暂停抓取，提示用户去浏览器手动过验证 |
| 详情页加载失败 / 超时 | 跳过，记 `failed.log`，最后汇总 |
| 单轮搜索 0 结果 | warning 继续 |
| 抓取被中断 | 抓一条立刻写盘，断点续抓时从 `state.json` 恢复 |

**核心原则**：抓一条写一条，绝不在内存堆 60 条最后一次性写。

### 7.5 去重

- **抓取去重 key**：Boss 的 `jobId`（详情页 URL `/job_detail/<jobId>.html` 中提取）
- **历史去重**：抓列表后立刻查 `jd-pool/<jobId>.md`
  - 不存在 → 新抓
  - 存在且 `fetched_at` 在 7 天内 → 复用
  - 存在但超过 7 天 → 重抓

## 8. JD 数据 schema

每条 JD 一份 md 文件：YAML frontmatter + 原文正文。

```markdown
---
# ===== 唯一标识 =====
id: boss-<jobId>
url: https://www.zhipin.com/job_detail/xxx.html
fetched_at: 2026-04-29T14:23:11
run_id: 2026-04-29-1420

# ===== 来源 =====
source:
  keyword: 产品经理
  city: 北京

# ===== 列表页字段（快速过滤） =====
title: 高级产品经理-AI 方向
company:
  name: 字节跳动
  size: E                          # A-F 档（Boss 规模）
  industry: 互联网
  stage: 已上市
salary:
  range: "30-50K"
  monthly_count: 16
location:
  city: 北京
  district: 海淀区
  area: 中关村
requirements:
  experience: 3-5年
  education: 本科

# ===== 详情页字段 =====
tags: [大模型, AI 产品, B 端]
benefits: [六险一金, 弹性工作, 餐补]
hr:
  name: 张三
  title: HR 经理
  active_status: 刚刚活跃            # 影响最终排序系数
posted_at: 2026-04-25

# ===== 流程状态（直接写进 frontmatter） =====
status:
  hard_filter: passed              # passed | filtered_out（附原因）
  detail_fetched: true
  analyzed: false
---

## 岗位职责
（详情页原文，不改写）

## 任职要求
（详情页原文，不改写）

## 公司介绍
（详情页原文，可选）
```

**关键设计**：
- `id` 用 Boss 的 `jobId`（全平台唯一，跨 run 稳定去重）
- 正文保留原始文本，**抓取阶段不做总结/精炼**
- 状态字段 inline 在 frontmatter（简单可视化，git 友好）
- HR 活跃度字段是 Boss 上的关键隐性信号

## 9. 匹配度评分模型 (analyzer)

### 9.1 评分粒度：1 总分 + 4 维子分

| 维度 | 含义 |
|---|---|
| `hard_skills` | JD 要求的技能/工具，简历命中率 |
| `experience_depth` | 年限 + 岗位级别 + 项目复杂度 |
| `domain_fit` | 行业、业务场景对口程度 |
| `soft_fit` | 软技能、加分项、文化匹配 |

总分 = 4 维等权综合（默认 25% × 4，可微调）

### 9.2 HR 活跃度：乘法系数

```
最终排序分 = (匹配度 × match_weight + 偏好契合度 × preference_weight) × HR 活跃系数

HR 活跃系数：
  刚刚 / 今日活跃: 1.0
  3 日内: 0.9
  本周: 0.75
  更早 / 未知: 0.5
```

匹配度本身不变，但 JD 的"实际投递价值"按活跃度打折。

### 9.3 STAR 应用方式

**Step 1：简历预处理（首次运行，缓存）**

把主简历每段项目经验拆成 STAR 四要素，存到 `.work/resume.star.md`：

```markdown
## 项目 1：XX SaaS 产品 0-1
- **S (背景)**: 公司从工具型转 SaaS,无成熟产品方法论
- **T (任务)**: 主导核心模块 0-1
- **A (行动)**: 需求调研 X 次/竞品分析 Y 个/PRD Z 份/...
- **R (结果)**: 上线 → ⚠️ 缺数字
```

主简历 hash 不变 → 复用，token 省一半。

**Step 2：每个 JD 单独分析**

输出 `analysis/<jobId>.analysis.md`：

```markdown
---
jd_id: boss-abc123def
analyzed_at: 2026-04-29T15:00
scores:
  total: 82
  hard_skills: 90
  experience_depth: 75
  domain_fit: 85
  soft_fit: 80
preference_score: 75
hr_factor: 1.0
final_rank_score: 79.45
---

## 一句话评估
SaaS 产品经验高度相关，主要差距在大模型应用。值得投。

## 维度分析
### 硬技能 90/100
✅ 命中：产品规划、需求分析、SQL、A/B 测试
⚠️ 缺失：大模型应用、Prompt Engineering（JD 强调）
🎯 已有但没突出：跨团队协作

### 经验深度 75/100
...

## STAR 修改建议（给 tailor 用）
### 项目 1：XX SaaS 产品 0-1
- A 缺：与算法团队协作细节（JD 强调）
- R 缺：具体数字 → ⚠️ 需用户回填，不替编
- 建议改写方向（仅改写已有内容，不新增）：
  - 突出"与算法团队协作"
  - Result 段保留占位 `[请填写：用户量/留存/收入数字]`
```

## 10. 定制简历产物 (tailor)

每个 Top N JD 一个目录，三件套：

### 10.1 `resume.md` — 定制简历

基于主简历改写，严守第 2.2 节边界。

### 10.2 `opener.md` — 开场白

给 HR 的第一条 IM 消息（≤ 200 字），具体匹配点 + 真实经历，不编造。

```markdown
# 开场白 - 字节跳动·高级产品经理 AI 方向

张三您好，我是 XX。看到贵司这个 AI 产品岗位，我有 4 年 SaaS
产品经验，曾主导 XX 模块 0-1 落地，最近一年也在跟进大模型
应用方向（[请填写：具体项目/学习经历]）。期待和您聊聊这个
机会，我的定制简历也已经准备好了。
```

### 10.3 `changelog.md` — 改动列表（伦理保险）

让用户一眼看到 AI 改了什么，每条带原因。

```markdown
# 改动列表 - vs 主简历

## ✏️ 措辞调整
1. 项目1标题：「主导 XX 模块」→「主导 XX 模块 0-1，与算法团队协作」
   - 原因: JD 强调跨团队协作

## 🔼 顺序调整
1. 把"AI/大模型相关项目"上移到工作经历最前
   - 原因: JD 第一硬要求

## ⚠️ 需用户回填
1. 项目1 Result 段: `[请填写：用户量/留存/收入]`
   - 原因: 主简历缺数字，JD 要求"数据驱动"

## ❌ 删除/弱化
1. 弱化"教培行业产品经验"段落
   - 原因: 该公司对教培背景偏好低（你的 avoid_industries 命中）
```

### 10.4 成本控制

- 默认只为 **Top 10**（或 `top_n_for_tailor` 配置）生成三件套
- 其余 JD 在 shortlist "不推荐"区仅展示分数，不生成

## 11. 主产物 `shortlist.md`

```markdown
# 求职 Shortlist · 2026-04-29 14:20

## 概况
- 搜索: 北京/杭州 × 产品经理/高级产品经理 (6 轮)
- 候选: 60 抓取 → 32 通过硬过滤 → 32 完成分析
- 耗时: 抓取 18min · 分析 6min

## Top 推荐（按最终排序分倒序）

### 🥇 1. 字节跳动 · 高级产品经理-AI 方向 · 79.5 分
- 💰 30-50K · 16薪 | 📍 北京·海淀
- 👤 HR 张三（**刚刚活跃** ✨）
- 📊 匹配 82（硬技能 90 / 经验 75 / 行业 85 / 软性 80）
- 💡 SaaS 经验高度相关，主要差距大模型应用，值得投。
- 🔗 [打开 JD](https://www.zhipin.com/job_detail/abc123def.html)
- 📄 [定制简历](./tailored/boss-abc123/resume.md) · 💬 [开场白](./tailored/boss-abc123/opener.md) · 📋 [改动](./tailored/boss-abc123/changelog.md)
- ⚠️ 投递前: 回填项目1数字 + 复习"大模型应用"相关案例

### 🥈 2. ...

## 不推荐（仅参考，未生成定制简历）

| 公司 | 岗位 | 总分 | 主要不匹配点 |
|---|---|---|---|
| XX | YY | 45 | 要求 5 年+，你 4 年 |
```

## 12. 缓存与多次运行

### 12.1 三层缓存

| 缓存层 | Key | 失效条件 |
|---|---|---|
| **JD 抓取** | `jobId` | 不存在，或 `fetched_at` > 7 天 |
| **分析** | `(jobId, resume.md.hash, preferences.yaml.hash)` | 任一变化 |
| **STAR 预处理** | `resume.md.hash` | hash 变化 |

任何一项变化即 invalidate 相关下游缓存（不做精细依赖追踪，YAGNI）。

### 12.2 断点续抓 `state.json`

```json
{
  "run_id": "2026-04-29-1420",
  "phase": "analyzing",
  "search_progress": {
    "completed": ["北京-产品经理", "北京-高级产品经理"],
    "pending": ["杭州-产品经理", "杭州-高级产品经理"]
  },
  "stages": {
    "fetched": ["boss-abc", "boss-def"],
    "filtered_in": ["boss-abc"],
    "analyzed": ["boss-abc"],
    "tailored": []
  },
  "last_error": null,
  "checkpoint_at": "2026-04-29T14:35:22"
}
```

启动行为：
- 没 state.json 或 `phase: done` → 全新 run
- `phase != done` 且 checkpoint 在 **24 小时内** → 提示"上次没跑完（X/Y 阶段），继续/重开/放弃？"
- 超过 24 小时 → 默认放弃（数据可能过时），保留 raw 给用户参考

### 12.3 自动清理

主 skill 启动时静默执行：
- `jd-pool/` 中 `fetched_at` > **30 天**的文件删除（含对应 analysis）
- `./output/<run-id>/` 中 run-id 时间戳 > **14 天**的目录删除

强制清理：`/job-hunt clean`。

### 12.4 跨 run 的 shortlist：不合并

每次 run 独立产出。历史 run 留磁盘上，要查随时翻。不做"历史最佳合并"。

## 13. 用户工作流

### 13.1 首次设置

1. 创建 `~/.job-hunt/` 或在某个项目目录
2. 放入 `resume.md` 或 `resume.docx`
3. 创建 `preferences.yaml`
4. 确保已在 Chrome 登录 Boss 直聘
5. 运行 `/job-hunt`

### 13.2 日常循环

```
每天 1-2 次：
  /job-hunt
    → 抓取 + 分析 + 定制（15-20 min，多数 JD 走缓存后更快）
    → 看 shortlist.md
  挑 3-5 个真心想投的：
    → 打开 tailored/<jobId>/resume.md
    → 回填 [请填写：xxx] 占位符
    → 转 PDF（用户自选工具）
    → 点 shortlist 里的 JD 链接
    → 点"立即沟通"
    → 复制 opener.md 内容粘贴给 HR
    → HR 通过后上传 PDF 简历
    → 后续 IM 沟通约面试
```

## 14. 测试策略（v1）

不写自动化测试。靠人工评审 + 几份固定测试简历。

| 子 skill | 评审重点 |
|---|---|
| `fetcher` | `/job-hunt fetch` 单跑，肉眼检查 jd-pool 输出格式正确、字段齐全、HR 活跃度抓对 |
| `analyzer` | 手造 1 JD + 1 简历，跑分析，验证 4 维打分合理、修改建议不越界 |
| `tailor` | 肉眼审 changelog.md——任何"凭空增加经历/编造数字"都是 bug |
| 端到端 | 完整跑一次，看 shortlist 是否能用 |

LLM 输出的"质量"本来也很难自动化判断，v1 重点验证流程跑得通 + 改写不越界。后续如果验证有效再考虑加 eval 集。

## 15. 风险与未决问题

| 风险 | 缓解 |
|---|---|
| Boss 直聘改版导致选择器失效 | fetcher 用语义化定位（accessibility tree）而非 CSS 选择器；改版后只需更新 fetcher |
| Boss 检测异常行为封号 | 严格节奏控制 + 单 tab + 真实浏览器（bb-browser）；用户应用平时使用的同一浏览器 |
| LLM 改写越界（编造经历/数字） | changelog.md 全量披露 + 占位符机制 + prompt 内硬约束；用户最后人审 |
| 用户简历质量差导致建议无效 | 不在 v1 范围。文档提示"主简历越完整，建议越有价值" |
| 大模型 token 成本失控 | Top N 门槛 + 三层缓存 + 简历 STAR 预处理复用 |

## 16. 后续演进（不在 v1）

- 扩展数据源：LinkedIn / 拉勾 / 智联（每家一个 fetcher，可能引入 `job-hunt-shared`）
- 投递状态跟踪：`applied` / `replied` / `interviewed` 状态机
- 简历多版本：技术岗简历 vs 产品岗简历自动选择
- HR 沟通话术库：积累有效的开场白模板
- 形态升级：基于 Claude Agent SDK 包装成 CLI，让不会用 Claude Code 的人也能用
