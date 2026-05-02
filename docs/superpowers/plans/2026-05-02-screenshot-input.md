# Screenshot Input Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 job-hunt-fetcher 从 bb-browser 自动抓取改为截图解析，并同步简化主 skill 编排逻辑。

**Architecture:** 只改 `job-hunt-fetcher/SKILL.md` 和 `job-hunt/SKILL.md` 两个文件，新 fetcher 接收截图、分组确认、解析写入 jd-pool；主 skill 去掉配置向导、硬过滤、batch_size，改为引导用户提供简历和上传截图。analyzer 和 tailor 完全不动，jd-pool 文件格式不变。

**Tech Stack:** Markdown skill 文件；无传统代码，无单元测试；验证方式为人工阅读文件内容 + 安装后手动运行。

---

## 文件改动清单

| 操作 | 文件 |
|---|---|
| 完全重写 | `skills/job-hunt-fetcher/SKILL.md` |
| 完全重写 | `skills/job-hunt/SKILL.md` |
| 删除 | `templates/preferences.yaml` |
| 修改 | `scripts/install.sh` |
| 修改 | `CLAUDE.md` |
| 不动 | `skills/job-hunt-analyzer/SKILL.md` |
| 不动 | `skills/job-hunt-tailor/SKILL.md` |

---

## Task 1：重写 job-hunt-fetcher/SKILL.md

**Files:**
- Modify: `skills/job-hunt-fetcher/SKILL.md`

- [ ] **Step 1：用以下内容完整覆盖 `skills/job-hunt-fetcher/SKILL.md`**

```markdown
---
name: job-hunt-fetcher
description: Internal sub-skill for job-hunt suite. Parses JD information from user-provided screenshots of Boss 直聘 job detail pages and writes structured JD markdown files to jd-pool. Do NOT invoke directly — use the job-hunt main skill instead.
---

# job-hunt-fetcher

你是 job-hunt 套件的截图解析组件。**唯一职责**：从用户提供的 Boss 直聘详情页截图中解析 JD 信息，输出标准化 Markdown 文件到 jd-pool。你不做筛选、不做分析、不做改写。

调用方（job-hunt 主 skill）会传给你以下上下文：
- `work_dir`：工作根目录路径
- `run_id`：本次 run 的时间戳 ID（格式 YYYY-MM-DD-HHMM）
- `screenshots`：本批次用户提供的截图

## Step 1：分组 + 完整性确认

收到截图后，识别截图涉及几个岗位：

### 多个岗位（批量模式）

逐张识别「职位名称 + 公司名称」，将属于同一岗位的截图归为一组，展示分组结果请用户确认：

```
我识别出 N 个岗位，分组如下：
- 组1：<公司名> · <职位名>（X张）
- 组2：<公司名> · <职位名>（X张）
- 组N：<公司名> · <职位名>（X张，截图疑似不完整，缺少<字段名>）

分组有误或需要补截图吗？没问题直接说「继续」。
```

用户确认（或纠正分组）后进入 Step 2。

### 单个岗位（流式模式）

先确认完整性：

```
我看到了「<公司名> · <职位名>」的截图，这些截图已经包含完整的 JD 信息了吗？
（岗位职责、任职要求都截到了？）
如果还有截图没发，继续发过来；都发完了告诉我「完整了」，我开始解析。
```

用户继续发截图 → 追加到当前组 → 重复询问。
用户说「完整了」→ 进入 Step 2。

**只有 1 张截图且内容完整明确时**，跳过确认直接进入 Step 2。

## Step 2：解析并写入 jd-pool

对每组截图，合并阅读所有图片，提取以下字段：

```
title: 职位名称
company.name: 公司名称
company.size: 规模档位（A/B/C/D/E/F，见映射表）
company.industry: 行业标签
company.stage: 融资阶段（无则 null）
salary.range: 薪资文本（如"20-40K"）
salary.monthly_count: 月数（如"16薪"则 16，无则 null）
location.city: 城市
location.district: 区域
requirements.experience: 经验要求
requirements.education: 学历要求
tags: 技能标签列表
benefits: 福利标签列表
hr.name: HR 姓名
hr.title: HR 职称
hr.active_status: HR 活跃状态文本（如"今日活跃"）
posted_at: 发布时间
job_description: 岗位职责全文
job_requirements: 任职要求全文
company_intro: 公司介绍全文（无则 null）
```

规模文本 → 档位映射：
- 20人以下 → A，20-99人 → B，100-499人 → C
- 500-999人 → D，1000-9999人 → E，10000人以上 → F

**字段缺失处理**：截图截不全时，能提取的字段正常写，提取不到的置为 `null`，不中断写入。

**文件命名规则**：

| 情况 | 文件名 |
|---|---|
| 能提取到公司名 + 职位名 | `公司名-职位名-YYYYMMDDTHHmm.md` |
| 提取不到任何名称 | `screenshot-YYYYMMDDTHHmm.md` |

写入路径：`<work_dir>/.work/jd-pool/<文件名>`

写入格式：

```markdown
---
id: <文件名去掉 .md>
fetched_at: <当前 ISO 8601 时间，如 2026-05-02T14:23:11>
run_id: <run_id>
source: screenshot

title: <title>
company:
  name: <company.name>
  size: <档位字母，如 D>
  industry: <company.industry>
  stage: <company.stage，无则 null>
salary:
  range: "<salary.range>"
  monthly_count: <salary.monthly_count，无则 null>
location:
  city: <location.city>
  district: <location.district>
requirements:
  experience: <requirements.experience>
  education: <requirements.education>

tags: [<tag1>, <tag2>, ...]
benefits: [<benefit1>, <benefit2>, ...]
hr:
  name: <hr.name>
  title: <hr.title>
  active_status: <hr.active_status>
posted_at: <posted_at>

status:
  detail_fetched: true
  analyzed: false
---

## 岗位职责

<job_description 原文>

## 任职要求

<job_requirements 原文>

## 公司介绍

<company_intro 原文，若 null 则删除此节>
```

**解析完成后汇报并返回 ID 列表**：

```
已解析完成：
- ✅ <公司名>·<职位名>（字段完整）→ 文件：<文件名>
- ✅ <公司名>·<职位名>（字段完整）→ 文件：<文件名>
- ⚠️ <公司名>·<职位名>（<缺失字段>未截到，已置 null）→ 文件：<文件名>
```

向调用方报告本批次写入的所有文件 ID（`id` 字段值）列表。

## 异常处理

| 异常 | 处理方式 |
|---|---|
| 截图完全无法识别（非 Boss 直聘页面、图片损坏等） | 跳过该截图，汇报中标注「❌ 第X张截图无法识别，已跳过」 |
| 截图包含多个岗位内容混合无法归组 | 在分组确认时告知用户，请求重新截图 |
| 单个字段提取失败 | 该字段置为 null，不中断整条 JD |
```

- [ ] **Step 2：确认文件写入成功**

```bash
wc -l skills/job-hunt-fetcher/SKILL.md
```

预期输出：行数在 90-120 行之间（视格式而定）。确认文件不为空且包含 `Step 1`、`Step 2`、`异常处理` 三个章节标题。

- [ ] **Step 3：commit**

```bash
git add skills/job-hunt-fetcher/SKILL.md
git commit -m "feat: 重写 fetcher，改为截图解析模式"
```

---

## Task 2：重写 job-hunt/SKILL.md

**Files:**
- Modify: `skills/job-hunt/SKILL.md`

- [ ] **Step 1：用以下内容完整覆盖 `skills/job-hunt/SKILL.md`**

```markdown
---
name: job-hunt
description: 求职助手主入口。上传 Boss 直聘岗位详情页截图，与你的简历做 STAR 匹配分析，生成定制简历和开场白，按匹配度排序产出 shortlist。支持子命令：import / analyze / tailor / status / clean。
---

# job-hunt 求职助手

## 子命令路由

根据用户输入判断执行路径：

| 用户输入 | 执行 |
|---|---|
| `/job-hunt` 无参数 | 全流程（Step 1→7） |
| `/job-hunt import` | 只执行截图导入（Step 1+2+3） |
| `/job-hunt analyze` | 只执行分析（Step 1+4） |
| `/job-hunt tailor` | 执行排序（Step 5）+ 定制（Step 6） |
| `/job-hunt status` | 输出当前 run 状态（Step 7b） |
| `/job-hunt clean` | 强制清理所有缓存和产物（Step 8） |

## Step 1：确定工作目录与初始化

`work_dir` = Claude 启动时所在的当前目录（`./` 的绝对路径）。

用 Bash 获取：`pwd`，将结果作为 `work_dir`。

确保以下目录存在（用 Bash `mkdir -p` 创建）：
```
<work_dir>/.work/jd-pool/
<work_dir>/output/
```

生成 `run_id`（格式：`YYYY-MM-DD-HHMM`，使用当前本地时间）。
创建目录 `<work_dir>/output/<run_id>/`。

初始化 `<work_dir>/output/<run_id>/state.json`：
```json
{
  "run_id": "<run_id>",
  "phase": "init",
  "stages": {
    "imported": [],
    "analyzed": [],
    "analysis_errors": [],
    "tailored": []
  },
  "last_error": null,
  "checkpoint_at": "<当前 ISO 8601 时间>"
}
```

## Step 2：获取简历

（全流程、import、analyze 子命令时执行）

检查 `<work_dir>/.work/resume.md` 是否存在：

**若已存在**：告知用户「已检测到上次保存的简历，继续使用。如需更换，请运行 `/job-hunt clean` 后重新开始。」跳过本步骤。

**若不存在**：提示用户提供简历：

「请提供你的简历，支持以下三种方式：
① 发送简历文件（.md 或 .docx）
② 告诉我文件的本地路径（如 /Users/xxx/resume.md）
③ 直接将简历文字粘贴到消息框发送」

根据用户提供方式处理：
- **发文件（.docx）**：调用 Skill 工具加载 `docx` skill 解析，转为 Markdown 文本
- **发文件（.md）**：直接读取文件内容
- **文件路径（.docx）**：用 Bash 确认路径存在后，调用 `docx` skill 解析
- **文件路径（.md）**：用 Bash 读取文件内容
- **粘贴文本**：直接使用该文本内容

将最终 Markdown 内容写入 `<work_dir>/.work/resume.md`。
告知用户：「✅ 简历已保存到 <work_dir>/.work/resume.md。」

## Step 3：截图收集与导入

（全流程、import 子命令时执行）

提示用户：

「请上传你感兴趣的岗位截图（Boss 直聘详情页）。
可以一次发多张，也可以分批发送。
截图发完后告诉我「开始分析」。」

**循环处理截图批次：**

每次收到截图时：
1. 调用 Skill 工具，加载 `job-hunt-fetcher` skill，传入：
   - `work_dir`：<解析好的绝对路径>
   - `run_id`：<当前 run_id>
   - `screenshots`：<本批次截图>
2. 等待 fetcher 完成，获取本批次写入的 JD 文件 ID 列表
3. 将新增 ID 追加到 `state.json` 的 `stages.imported`，更新 `checkpoint_at`
4. 询问用户：「已处理这批截图。还有要补充的吗？发完了告诉我「开始分析」。」

用户说「开始分析」后退出循环，更新 state.json `phase` 为 `"imported"`。

若子命令为 `import`，完成后停止，告知用户：「✅ JD 导入完成，共 <N> 个岗位。运行 /job-hunt analyze 开始分析。」并停止。

## Step 4：分析（job-hunt-analyzer）

（全流程、analyze 子命令时执行）

确定待分析 JD 列表：
- 扫描 `<work_dir>/.work/jd-pool/` 下所有 `.md` 文件（排除 `.analysis.md` 结尾的文件）
- 读取每个文件的 frontmatter，筛选 `status.analyzed: false` 的文件，提取其 `id` 字段
- 排除 `state.json.stages.analysis_errors` 中已记录失败的 ID

若列表为空，告知用户「jd-pool 中没有待分析的 JD，请先上传截图。」并停止。

调用 Skill 工具，加载 `job-hunt-analyzer` skill，传入：
- `work_dir`：<绝对路径>
- `resume_path`：`<work_dir>/.work/resume.md`
- `jd_ids`：<待分析 JD ID 列表>
- `preferences`：`{"soft_preferences": {"prefer_industries": [], "avoid_industries": [], "prefer_company_size": []}, "ranking": {"match_weight": 1.0, "preference_weight": 0.0}}`
- `run_id`：<当前 run_id>

等待 analyzer 完成。重新读取 state.json。
更新 state.json `phase` 为 `"analyzed"`。

## Step 5：排序

（全流程或 tailor 子命令前执行，不调用 LLM）

读取所有 analysis 文件（`<work_dir>/.work/jd-pool/*.analysis.md`），提取每个文件中的 `scores.total` 字段作为 `match_score`，按降序排列。

**所有已分析 JD 全部参与排序，不截断。**

将排序结果（JD ID 有序列表）记录到内存中供 Step 6 使用。

## Step 6：定制简历（job-hunt-tailor）

（全流程或 tailor 子命令时执行）

取 Step 5 排序后的完整 JD ID 列表。
排除 state.json 中已在 `stages.tailored` 的（断点续跑时跳过）。

调用 Skill 工具，加载 `job-hunt-tailor` skill，传入：
- `work_dir`：<绝对路径>
- `resume_path`：`<work_dir>/.work/resume.md`
- `jd_ids`：<完整排序后的 JD ID 列表>
- `run_id`：<当前 run_id>

等待 tailor 完成。
更新 state.json `phase` 为 `"tailored"`。

## Step 7：生成 shortlist.md

（全流程最后一步）

读取所有 analysis 文件和对应 JD frontmatter，生成 `<work_dir>/output/<run_id>/shortlist.md`，**同时在聊天消息中输出完整内容**：

```markdown
# 求职 Shortlist · <run_id>

## 概况
- 导入岗位：<stages.imported 数量> 个
- 完成分析：<stages.analyzed 数量> 个
- 已生成定制简历：<stages.tailored 数量> 个

## 推荐排名（按匹配度）

### 🥇 1. <company.name> · <title> · 匹配度 <match_score> 分
- 💰 <salary.range><若 monthly_count 不为 null 追加"·<monthly_count>薪"> | 📍 <location.city>·<location.district>
- 👤 HR <hr.name>（<hr.active_status>）
- 📊 分项：硬技能 <scores.hard_skills> / 经验 <scores.experience_depth> / 行业 <scores.domain_fit> / 软性 <scores.soft_fit>
- 💡 <analysis 文件中的「一句话评估」>
- 📄 [定制简历](tailored/<id>/resume.md) · 💬 [开场白](tailored/<id>/opener.md) · 📋 [改动](tailored/<id>/changelog.md)
- ⚠️ 投递前：<从 tailored/<id>/changelog.md 的「⚠️ 需用户回填」节提取第一条；若该节不存在则省略此行>

<重复以上格式直到最后一名>
```

更新 state.json `phase` 为 `"done"`。
告知用户：「✅ 完成！shortlist 已保存到 <work_dir>/output/<run_id>/shortlist.md，并在上方展示。」

## Step 7b（status 子命令）：输出运行状态

扫描 `<work_dir>/output/` 下所有子目录，找名字格式为 `YYYY-MM-DD-HHMM` 的目录，读取最新一个的 `state.json`，按以下格式输出：

```
Job-Hunt 状态报告
==================
Run ID：<run_id>
当前阶段：<phase>
工作目录：<work_dir>

进度统计：
  已导入 JD：<stages.imported 数量> 个
  完成分析：<stages.analyzed 数量> 个
  分析失败：<stages.analysis_errors 数量> 个
  生成三件套：<stages.tailored 数量> 个

最后更新：<checkpoint_at>
```

若无任何 run 记录，告知用户「尚未运行过 /job-hunt，请先运行完整流程。」

## Step 8（clean 子命令）：强制清理

删除 `<work_dir>/.work/jd-pool/` 下所有文件（含 .analysis.md）。
删除 `<work_dir>/output/` 下所有 run 目录。
删除 `<work_dir>/.work/resume.md`（若存在）。
统计并告知用户清理了多少文件/目录。
```

- [ ] **Step 2：确认文件写入成功**

```bash
wc -l skills/job-hunt/SKILL.md
grep -n "## Step" skills/job-hunt/SKILL.md
```

预期：行数在 140-180 行之间；`grep` 输出应包含 Step 1 至 Step 8 共 9 个章节标题（含 7b）。
确认不含「preferences.yaml」「batch_size」「bb-browser」「向导」等旧关键词：

```bash
grep -n "preferences.yaml\|batch_size\|bb-browser\|向导第" skills/job-hunt/SKILL.md
```

预期：无输出（0 行）。

- [ ] **Step 3：commit**

```bash
git add skills/job-hunt/SKILL.md
git commit -m "feat: 重写主 skill，截图导入流程替换自动抓取"
```

---

## Task 3：清理支持文件

**Files:**
- Delete: `templates/preferences.yaml`
- Modify: `scripts/install.sh`
- Modify: `CLAUDE.md`

- [ ] **Step 1：删除 preferences.yaml 模板**

```bash
git rm templates/preferences.yaml
```

- [ ] **Step 2：更新 scripts/install.sh**

将文件末尾的「📝 后续步骤」提示替换为新内容。找到以下原始内容：

```bash
echo "📝 后续步骤："
echo "  1. 准备配置文件："
echo "     mkdir -p ~/.job-hunt"
echo "     cp $REPO_ROOT/templates/preferences.yaml ~/.job-hunt/preferences.yaml"
echo "  2. 编辑 ~/.job-hunt/preferences.yaml，填入你的求职偏好"
echo "  3. 把简历放到 ~/.job-hunt/resume.md 或 ~/.job-hunt/resume.docx"
echo "  4. 确保 Chrome 已登录 Boss 直聘（zhipin.com）"
echo "  5. 在 Claude Code 中运行 /job-hunt"
```

替换为：

```bash
echo "📝 使用方式："
echo "  1. 在 Claude Code（或其他支持 skill 的 agent）中运行 /job-hunt"
echo "  2. 按提示提供简历（发文件、告知路径，或直接粘贴文本）"
echo "  3. 上传 Boss 直聘岗位详情页截图"
echo "  4. 等待分析完成，查看 shortlist"
```

- [ ] **Step 3：更新 CLAUDE.md**

找到以下段落（「## 风控策略（fetcher 必须遵守）」整节）：

```
## 风控策略（fetcher 必须遵守）

- **禁止并发**：每次只调一个 bb-browser 工具，严格串行
- 详情页间隔：**10-15 秒随机**
- 轮次间隔：**30-60 秒随机**
- 列表页读取后停留：**5-8 秒**（模拟人类浏览）
- 详情页数据采集完立即**关闭标签页**
- 不使用 `bb-browser site boss/*` 适配器（会触发风控）
```

替换为：

```
## fetcher 截图解析约定

- 截图来源：用户提供的 Boss 直聘**详情页**截图（不限批量或流式）
- 分组：多张截图时先用视觉能力归组，确认后解析
- 完整性：流式单张时主动询问是否截完整
- 字段缺失：置 null，不中断写入
- 无 bb-browser 依赖，无防风控延迟
```

找到以下段落（「## 依赖的外部 skill」整节）：

```
## 依赖的外部 skill

- `bb-browser`（控制用户真实 Chrome 抓取 Boss 直聘）
- `docx`（解析用户提供的 Word 简历）
```

替换为：

```
## 依赖的外部 skill

- `docx`（解析用户提供的 .docx 简历）
```

找到「## 当前状态」节，将其中的 ✅ 列表更新为：

```
## 当前状态

- ✅ 设计文档、实现计划已完成（feat/screenshot-input 分支）
- ✅ 截图解析方案替换 bb-browser 抓取
- ✅ 去掉 preferences.yaml、首次运行向导、硬过滤
- ✅ 排序简化为 match score，shortlist 双路输出
- ⏳ 用户真实跑完整流程自测中
```

- [ ] **Step 4：确认 CLAUDE.md 不再包含旧内容**

```bash
grep -n "bb-browser\|preferences.yaml\|向导\|batch_size\|风控" CLAUDE.md
```

预期：只有 `CLAUDE.md` 中的「fetcher 截图解析约定」节下应有「无 bb-browser 依赖，无防风控延迟」，其余行无旧关键词。

- [ ] **Step 5：commit**

```bash
git add scripts/install.sh CLAUDE.md
git commit -m "chore: 删除 preferences.yaml 模板，更新 install.sh 和 CLAUDE.md"
```

---

## Task 4：重新安装并验证

**Files:** 无（操作 `~/.claude/skills/`）

- [ ] **Step 1：运行安装脚本**

```bash
bash scripts/install.sh
```

预期输出：
```
🔧 安装 job-hunt skill suite 到 /Users/<user>/.claude/skills ...

✅ 安装 job-hunt
✅ 安装 job-hunt-fetcher
✅ 安装 job-hunt-analyzer
✅ 安装 job-hunt-tailor

✅ 安装完成！无需重启 Claude Code，skill 立即生效。
```

- [ ] **Step 2：确认 ~/.claude/skills 中的文件已更新**

```bash
grep -n "截图解析" ~/.claude/skills/job-hunt-fetcher/SKILL.md | head -3
grep -n "截图收集与导入" ~/.claude/skills/job-hunt/SKILL.md | head -3
```

预期：两条命令各有 1 行输出，确认新内容已安装到位。

- [ ] **Step 3：确认旧内容已清除**

```bash
grep -c "bb-browser\|batch_size\|preferences.yaml" ~/.claude/skills/job-hunt/SKILL.md
grep -c "bb-browser\|batch_size\|preferences.yaml" ~/.claude/skills/job-hunt-fetcher/SKILL.md
```

预期：两条命令均输出 `0`。

- [ ] **Step 4：最终 commit（确认工作区干净）**

```bash
git status
```

预期：`无文件要提交，干净的工作区`。若有遗漏文件，补充 add + commit。

- [ ] **Step 5：推送到远端**

```bash
git push -u origin feat/screenshot-input
```

---

## 自检：Spec 覆盖确认

| Spec 要求 | 对应 Task |
|---|---|
| fetcher 接收截图、分组确认、完整性询问 | Task 1 |
| 批量模式：归组 + 展示确认 | Task 1 Step 1 |
| 流式模式：单岗位询问完整性 | Task 1 Step 1 |
| 字段提取、null 处理、文件命名规则 | Task 1 Step 2 |
| 主 skill 简历三种输入方式 | Task 2 Step 2 |
| 截图收集循环、调 fetcher、更新 state | Task 2 Step 3 |
| analyzer 调用（pass preferences stub） | Task 2 Step 4 |
| 排序仅用 match_score，全量不截断 | Task 2 Step 5 |
| tailor 全量 JD | Task 2 Step 6 |
| shortlist 双路输出（文件+聊天） | Task 2 Step 7 |
| HR 活跃状态作辅助展示（不参与计算） | Task 2 Step 7 |
| 删除 preferences.yaml | Task 3 Step 1 |
| 更新 install.sh 提示 | Task 3 Step 2 |
| 更新 CLAUDE.md | Task 3 Step 3 |
