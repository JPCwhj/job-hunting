---
name: job-hunt
description: 求职助手主入口。从 Boss 直聘抓取目标 JD，与你的简历做 STAR 匹配分析，生成定制简历和开场白，按匹配度排序产出 shortlist。首次运行会自动引导完成配置。支持子命令：fetch / analyze / tailor / resume / status / clean。
---

# job-hunt 求职助手

## 子命令路由

根据用户输入判断执行路径：

| 用户输入 | 执行 |
|---|---|
| `/job-hunt` 或 `/job-hunt` 无参数 | 全流程 |
| `/job-hunt fetch` | 只执行抓取（Step 3） |
| `/job-hunt analyze` | 只执行分析（Step 5），基于现有 jd-pool |
| `/job-hunt tailor` | 执行排序（Step 6）+ 定制（Step 7），基于现有 analysis |
| `/job-hunt resume` | 接续上次未完成 run（Step 2 断点恢复） |
| `/job-hunt status` | 输出当前 run 状态（Step 1 + 输出 state.json 摘要） |
| `/job-hunt clean` | 强制清理所有缓存和产物（Step 9） |

## Step 1：确定工作目录

`work_dir` = Claude 启动时所在的当前目录（`./` 的绝对路径）。

用 Bash 获取：`pwd`，将结果作为 `work_dir`，**不做任何回退，不再使用 `~/.job-hunt/`**。

## Step 2：配置向导 / 加载配置

### 2.1 preferences.yaml

检查 `<work_dir>/preferences.yaml` 是否存在。

**若已存在**：直接读取，验证 `search.cities` 和 `search.keywords` 均为非空列表；若缺字段告知用户并停止。

**若不存在（首次运行）**：进入配置向导，通过对话收集信息，最后自动生成文件。向导步骤：

**向导第 1 步 — 目标城市**
问：「你打算在哪些城市找工作？（可多选，也可直接输入）
① 北京  ② 上海  ③ 杭州  ④ 深圳  ⑤ 广州  ⑥ 成都  ⑦ 武汉  ⑧ 其他（请注明）」
等待用户回复后继续。

**向导第 2 步 — 岗位关键词**
问：「你想搜索哪些岗位名称？（每个关键词会单独搜一轮，建议 2-4 个，例如：产品经理、高级产品经理）」
等待用户回复后继续。

**向导第 3 步 — 工作年限**
问：「你的工作年限对应哪个档位？（Boss 直聘的筛选档位）
① 1-3年  ② 3-5年  ③ 5-10年  ④ 10年以上」
等待用户回复后继续。

**向导第 4 步 — 薪资范围**
问：「期望薪资范围是多少？（格式如 20-40K，不过滤可以直接回复"不限"）」
等待用户回复后继续。

**向导第 5 步 — 公司规模**
问：「公司规模要求？以下是 Boss 直聘的档位划分：
A = 20人以下  B = 20-99人  C = 100-499人  D = 500-999人  E = 1000-9999人  F = 1万人以上
请问最低接受哪个档位？（例如：C）」
等待用户回复后继续。

**向导第 6 步 — 排除关键词**
问：「有没有需要从搜索结果中排除的 JD 关键词？标题或正文含这些词的岗位会被直接跳过。
常见的例子：外包、驻场、外派、实习。
如果不想排除任何词，回复"不用"即可。」
等待用户回复后继续。

向导结束后，根据收集到的信息生成 `<work_dir>/preferences.yaml`，格式如下：

```yaml
# 由 job-hunt 向导自动生成

search:
  cities: [<用户填写的城市列表，用英文逗号分隔>]
  keywords: [<用户填写的关键词列表>]
  experience: <用户选择的年限档位>
  salary: <用户填写的薪资，若"不限"则注释掉此行>

hard_filters:
  exclude_keywords:
    <用户指定的关键词，每行一个 "- 关键词"；若用户回复"不用"则留空，写成空列表 []>
  min_company_size: <用户填写的规模字母>

soft_preferences:
  prefer_industries: []
  avoid_industries: []
  prefer_company_size: []

ranking:
  match_weight: 0.7
  preference_weight: 0.3
  top_n_for_tailor: 10
```

写入完成后告知用户：「✅ 配置已保存到 <work_dir>/preferences.yaml，之后可以直接编辑这个文件来修改偏好。」

### 2.2 简历获取

检查 `<work_dir>` 下是否存在 `resume.md` 或 `resume.docx`：

**若已存在**：
- 两个都存在 → 告知用户「同时检测到 resume.md 和 resume.docx，请删除其中一个」，停止。
- 只有一个 → 直接使用，跳到 2.3。

**若都不存在（首次运行）**：进入简历获取流程：

第 1 步：告知用户：「请把你的简历文件（.md 或 .docx，文件名不限）放到当前目录（<当前目录绝对路径>），放好后告诉我。」

等待用户回复"放好了"或类似确认后：

第 2 步：扫描当前目录中所有 `.md` 和 `.docx` 文件，排除以下已知非简历文件：
- `CLAUDE.md`、`README.md`、`readme.md`
- `preferences.yaml`
- 路径含 `.work/` 或 `output/` 的文件

第 3 步：
- 若找到 **1 个** → 问用户：「找到了 <文件名>，这是你的简历吗？(是/否)」
  - 是 → 确认，进入下一步
  - 否 → 回到第 1 步重新等待
- 若找到 **多个** → 列出所有文件，问用户：「找到了以下文件，哪个是你的简历？」让用户选择
- 若 **一个都没找到** → 告知用户「当前目录没有找到 .md 或 .docx 文件，请确认文件已放入 <当前目录> 并告诉我。」回到等待

第 4 步：将确认的简历文件复制到 `<work_dir>/resume<原扩展名>`（保留扩展名，例如原文件是 .docx 就复制为 resume.docx），然后继续 2.3。

计算 resume.md 的 hash：
```bash
md5 -q <work_dir>/.work/resume.md
```
写入 `<work_dir>/.work/resume.md.hash`。

计算 preferences.yaml 的 hash：
```bash
md5 -q <work_dir>/preferences.yaml
```
写入 `<work_dir>/.work/preferences.yaml.hash`。

### 2.3 创建工作目录

确保以下目录存在（用 Bash mkdir -p 创建）：
```
<work_dir>/.work/jd-pool/
<work_dir>/output/
```

### 2.4 断点检测

扫描 `<work_dir>/output/` 下所有子目录，找名字格式为 `YYYY-MM-DD-HHMM` 的目录，读取其中的 `state.json`，找最新的一个（按 run_id 时间戳降序）。

若找到 state.json 且 `phase` 不是 `"done"`：
- 计算 `checkpoint_at` 距今时长（UTC，单位小时）
- 若 < 24 小时 → 询问用户：「上次 run（<run_id>）未完成，当前阶段：<phase>。要继续、重新开始，还是放弃？(继续/重开/放弃)」
  - 继续 → 复用该 run_id，从断点 phase 继续执行
  - 重开 → 生成新 run_id，全新开始
  - 放弃 → 停止
- 若 ≥ 24 小时 → 告知用户上次 run（<run_id>）超过 24 小时未完成，将开始新 run

新建 run 时，生成 `run_id`（格式：`YYYY-MM-DD-HHMM`，使用当前本地时间）。
创建目录 `<work_dir>/output/<run_id>/`。
初始化 `<work_dir>/output/<run_id>/state.json`：
```json
{
  "run_id": "<run_id>",
  "phase": "init",
  "search_progress": { "completed": [], "pending": [], "filtered_in": [] },
  "stages": { "fetched": [], "filtered_in": [], "analyzed": [], "analysis_errors": [], "tailored": [] },
  "last_error": null,
  "checkpoint_at": "<当前 ISO 8601 时间>"
}
```

## Step 2.5：批次大小

（子命令 `fetch` 或全流程时执行，在启动抓取前询问）

询问用户：

「本次每个搜索组合要采集多少个**新**岗位？（建议 10-20，数字越大耗时越长）
提示：每个详情页约需 10-15 秒，组合数 × 批次大小决定总时长
例如：6 个组合 × 15 个 = 最多 90 个详情页，约 15-25 分钟
不确定的话输入 10 即可。」

等待用户回复，将数值记为 `batch_size`。若用户回复非数字或回复"默认"，使用 `10`。

## Step 3：抓取（job-hunt-fetcher）

（子命令 `fetch` 或全流程时执行）

告知用户：「开始从 Boss 直聘抓取 JD，预计时间取决于批次大小，请保持 Chrome 打开并保持登录状态...」

调用 Skill 工具，加载 `job-hunt-fetcher` skill，传入以下上下文（在消息中直接提供这些变量的值）：
- `work_dir`：<解析好的绝对路径>
- `preferences`：<preferences.yaml 的完整内容>
- `run_id`：<当前 run_id>
- `state`：<state.json 的当前内容>
- `batch_size`：<用户本次指定的数值>

等待 fetcher 完成。重新读取 `<work_dir>/output/<run_id>/state.json` 获取更新后的 state。

注：fetcher 内部利用 state.json 的 `search_progress.completed` 实现断点续跑——若 `/job-hunt fetch` 中断后再次运行，只需重新调用 fetcher 并传入已有 state，fetcher 会自动跳过已完成的轮次。

## Step 4：自动清理过期缓存

（全流程每次都执行，静默进行，不阻塞主流程）

扫描 `<work_dir>/.work/jd-pool/`：
- 读取每个 `boss-*.md` 文件的 `fetched_at` frontmatter 字段
- 将 `fetched_at` 解析为 UTC 时间，与当前 UTC 时间作差
- 差值 > 30×24 小时（720 小时）的文件：同时删除 `boss-<id>.md` 和 `boss-<id>.analysis.md`（若存在）

扫描 `<work_dir>/output/`：
- 读取每个 run 目录名的时间戳（YYYY-MM-DD-HHMM）
- 距今超过 14×24 小时（336 小时）的 run 目录：整体删除

清理结果静默处理，若删除文件超过 50 个，提示用户：「已自动清理 <N> 个过期文件」。

## Step 5：分析（job-hunt-analyzer）

（子命令 `analyze` 或全流程时执行）

确定待分析 JD 列表：
- 从 state.json 的 `stages.filtered_in` 中取（fetcher 写入的通过过滤的 JD）
- 排除 `stages.analyzed` 中已分析的（断点续跑时跳过）
- 若 `stages.filtered_in` 为空（直接运行 `analyze` 子命令时），扫描 jd-pool 中 frontmatter `status.hard_filter: passed` 且 `status.analyzed: false` 的文件

调用 Skill 工具，加载 `job-hunt-analyzer` skill，传入：
- `work_dir`：<绝对路径>
- `resume_path`：`<work_dir>/.work/resume.md`
- `jd_ids`：<待分析 JD ID 列表>
- `preferences`：<preferences.yaml 完整内容>
- `run_id`：<当前 run_id>

等待 analyzer 完成。重新读取 state.json。

## Step 6：排序

（全流程或 `tailor` 子命令前执行，不调用 LLM）

读取所有 analysis 文件（`<work_dir>/.work/jd-pool/boss-*.analysis.md`），提取 `final_rank_score`，按降序排列。

取前 `preferences.ranking.top_n_for_tailor`（默认 10）条作为 Top N，记录其 JD ID 列表。

## Step 7：定制简历（job-hunt-tailor）

（子命令 `tailor` 或全流程时执行）

取 Step 6 的 Top N JD ID 列表。
排除 state.json 中已在 `stages.tailored` 的（断点续跑时跳过）。

调用 Skill 工具，加载 `job-hunt-tailor` skill，传入：
- `work_dir`：<绝对路径>
- `resume_path`：`<work_dir>/.work/resume.md`
- `jd_ids`：<Top N JD ID 列表>
- `run_id`：<当前 run_id>

## Step 8：生成 shortlist.md

（全流程最后一步）

读取所有 analysis 文件，读取对应 JD frontmatter，生成 `<work_dir>/output/<run_id>/shortlist.md`：

```markdown
# 求职 Shortlist · <run_id>

## 概况
- 搜索：<cities 列表> × <keywords 列表>（<N> 轮）
- 候选：<stages.fetched 数量> 抓取 → <stages.filtered_in 数量> 通过过滤 → <stages.analyzed 数量> 完成分析
- Top <top_n_for_tailor> 已生成定制简历

## Top 推荐（按最终排序分倒序）

### 🥇 1. <company.name> · <title> · <final_rank_score> 分
- 💰 <salary.range><若 monthly_count 不为 null 则追加"·<monthly_count>薪"> | 📍 <location.city>·<location.district>
- 👤 HR <hr.name>（<hr.active_status><若为"刚刚活跃"或"今日活跃"则追加" ✨">）
- 📊 匹配 <scores.total>（硬技能 <hard_skills> / 经验 <experience_depth> / 行业 <domain_fit> / 软性 <soft_fit>）
- 💡 <analysis 文件中的「一句话评估」内容>
- 🔗 [打开 JD](<url>)
- 📄 [定制简历](tailored/boss-<id>/resume.md) · 💬 [开场白](tailored/boss-<id>/opener.md) · 📋 [改动](tailored/boss-<id>/changelog.md)
- ⚠️ 投递前：<从 tailored/boss-<id>/changelog.md 的「⚠️ 需用户回填」节中提取第一条，≤ 1 行；若该节不存在则省略此行>

<重复以上格式直到 Top N>

## 其余 JD（仅参考，未生成定制简历）

| 公司 | 职位 | 匹配分 | 主要不匹配点 |
|---|---|---|---|
<按 final_rank_score 降序列出其余所有已分析的 JD，从 analysis 的「一句话评估」中提取主要不匹配点>
```

更新 state.json，将 `phase` 设为 `"done"`。

告知用户：「✅ 完成！shortlist 在 <work_dir>/output/<run_id>/shortlist.md」

## Step 8b（status 子命令）：输出运行状态

按以下格式输出当前最新 run 的状态摘要：

```
Job-Hunt 状态报告
==================
Run ID：<run_id>
当前阶段：<phase>
工作目录：<work_dir>

进度统计：
  已抓取 JD：<stages.fetched 数量> 条
  通过过滤：<stages.filtered_in 数量> 条
  完成分析：<stages.analyzed 数量> 条
  分析失败：<stages.analysis_errors 数量> 条
  生成三件套：<stages.tailored 数量> 条

最后更新：<checkpoint_at>
```

若无任何 run 记录，告知用户「尚未运行过 /job-hunt，请先运行完整流程。」

## Step 9（clean 子命令）：强制清理

删除 `<work_dir>/.work/jd-pool/` 下所有文件（含 analysis）。
删除 `<work_dir>/output/` 下所有 run 目录。
删除 `<work_dir>/.work/resume.star.md`、`<work_dir>/.work/resume.md.hash`、`<work_dir>/.work/preferences.yaml.hash`。
统计并告知用户清理了多少文件/目录。
