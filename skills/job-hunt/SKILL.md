---
name: job-hunt
description: 求职助手主入口。上传招聘平台岗位详情页截图（Boss直聘、智联招聘、前程无忧等均可），与你的简历做 STAR 匹配分析，生成定制简历和开场白，按匹配度排序产出 shortlist。支持子命令：fetch / analyze / tailor / status / clean。
---

# job-hunt 求职助手

## ⚡ 全流程自动执行约束（最高优先级，全程有效）

**仅适用于 `/job-hunt` 无参数的全流程模式。**

用户提供简历 + 说出「开始分析」之后，**剩余所有步骤全部自动连续执行，直到输出 shortlist**。

- **Step 4 到 Step 7 之间：严禁输出任何文字**。输出文字 = turn 结束 = 等待用户 = 流程中断
- 每一步结束后，立即调用下一步所需的工具（Skill / Bash / Read / Write），不插入任何文字
- 子 skill（fetcher / analyzer / tailor）的返回结果是内部数据，**不向用户展开汇报，直接用于下一步**
- **禁止**在步骤之间询问用户「是否继续」「要不要开始下一步」

违反上述约束 = 流程中断，用户体验完全崩溃。

---

## 子命令路由

根据用户输入判断执行路径：

| 用户输入 | 执行 |
|---|---|
| `/job-hunt` 无参数 | 全流程（Step 1→7） |
| `/job-hunt fetch` | 只执行截图导入（Step 1+2+3） |
| `/job-hunt analyze` | 只执行分析（Step 1+4） |
| `/job-hunt tailor` | 执行排序（Step 5）+ 定制（Step 6） |
| `/job-hunt status` | 输出当前 run 状态（Step 7b） |
| `/job-hunt clean` | 强制清理所有缓存和产物（Step 8） |

---

## Step 1：确定工作目录与初始化

`work_dir` = Claude 启动时所在的当前目录（`./` 的绝对路径）。

用 Bash 获取：`pwd`，将结果作为 `work_dir`。

`data_dir` = `<data_dir>/jobHuntSkillData`（所有数据文件统一放在这一层目录下，不直接写入 `work_dir`）。

确保以下目录存在（用 Bash `mkdir -p` 创建）：
```
<data_dir>/.work/jd-pool/
<data_dir>/output/
```

生成 `run_id`（格式：`YYYY-MM-DD-HHMM`，使用当前本地时间）。
创建目录 `<data_dir>/output/<run_id>/`。

初始化 `<data_dir>/output/<run_id>/state.json`：
```json
{
  "run_id": "<run_id>",
  "phase": "init",
  "stages": {
    "fetched": [],
    "analyzed": [],
    "analysis_errors": [],
    "tailored": []
  },
  "last_error": null,
  "checkpoint_at": "<当前 ISO 8601 时间>"
}
```

**后续所有步骤中凡涉及路径的地方，一律使用 `data_dir` 代替 `work_dir`**。传给子 skill 的 `work_dir` 参数也传入 `data_dir` 的值。

**子命令特殊处理**：若当前子命令为 `analyze`、`tailor` 或 `status`，在生成新 run_id 之前，先扫描 `<data_dir>/output/` 下已有的 run 目录（格式 `YYYY-MM-DD-HHMM`），若存在则**复用最新一个 run_id**（不创建新目录，读取已有 state.json 继续使用）；若不存在，则按上述流程创建新 run_id。

---

## Step 2：获取简历

（全流程、fetch、analyze 子命令时执行）

检查 `<data_dir>/.work/resume.md` 是否存在：

**若已存在**：告知用户：

「已检测到上次保存的简历，继续使用。
如需更换简历，直接把新简历发给我（支持文件 / 路径 / 粘贴文本），我会帮你替换并重新评估。
如果继续用当前简历，告诉我「继续」。」

停止执行，等待用户回复：
- 用户发来新简历 → 按下方「若不存在」的方式处理，覆盖保存 `resume.md`，**进入 Step 2.5 重新评估**
- 用户说「继续」或其他非简历内容 → 跳过本步骤，跳过 Step 2.5，直接进入 Step 3

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

将最终 Markdown 内容写入 `<data_dir>/.work/resume.md`。
告知用户：「✅ 简历已保存。」

进入 Step 2.5。

---

## Step 2.5：简历质量评估

（仅在用户本次会话中新提供了简历时执行；复用缓存的直接跳到 Step 3）

读取 `<data_dir>/.work/resume.md`，找出所有**可评估单元**，逐一打分，输出结果。

**三条判断规则，按顺序执行，全部满足才评估：**

---

**规则一：整个区块跳过（不看内容，直接略过）**

下列区块不论写了什么，整体跳过，不评估：
- 个人信息 / 基本信息 / 联系方式
- 专业技能 / 技能特长 / 技术能力 / 工具使用 / 技术栈
- 教育背景 / 教育经历 / 学历
- 自我评价 / 个人简介 / 求职意向
- 证书 / 奖项 / 荣誉

**区块名不限于以上文字**，只要语义属于上述类型（如「我的技能」「掌握的工具」「所获奖励」），同样整体跳过。

**其他所有区块**（工作经历、项目经历、实习经历、创业经历、兼职经历，或任何自定义名称的经历类区块）进入规则二。

---

**规则二：区块内的标题行跳过**

经历类区块内，每一行单独判断。如果这一行**同时满足以下两点**，跳过：
- 没有行动动词（负责、主导、设计、推动、搭建、优化、完成、实现、带领等）
- 没有结果描述（提升、降低、增长、减少、达到、超过、节省，或具体数字/百分比）

例如：
- 「字节跳动 · 产品经理 · 2021.03—2023.06」→ ❌ 跳过（无动词无结果）
- 「项目名称：xxx 平台 | 角色：负责人 | 2022.01—2022.06」→ ❌ 跳过（无动词无结果）
- 「A 公司，高级运营，2019 年到 2021 年」→ ❌ 跳过（无动词无结果）

---

**规则三：剩下的内容才评估**

通过前两条规则筛选后剩下的句子/条目，即为**可评估单元**，进入下方三维度打分。

⚠️ 标题行与描述混写在同一行时，按规则二判断：只要含有行动动词或结果描述，就评估。
- 「在字节跳动担任产品经理期间主导了 xx 项目落地，DAU 提升 40%」→ ✅ 评估（含动词+结果）

### 评估维度

每段描述内容按以下三个维度打分（✅ 合格 / ⚠️ 薄弱 / ❌ 缺失）：

| 维度 | ✅ 合格 | ⚠️ 薄弱 | ❌ 缺失 |
|---|---|---|---|
| **场景/问题**（S/P） | 有明确业务背景或要解决的问题 | 背景模糊，一笔带过 | 无任何场景描述 |
| **行动**（A） | 具体描述「我做了什么」，有方法/手段 | 只写职责，没有行动细节 | 缺失 |
| **结果**（R） | 有量化数字，或明确的业务价值 | 结果模糊（如"效果不错"） | 无结果描述 |

额外检查：
- 是否大量使用「负责」「参与」「协助」等被动词（减分项，建议改为主动动词）
- 是否有明显可量化但留白的指标（tailor 阶段会插入 `[请填写：xxx]` 占位）

### 输出格式

```
📋 简历质量评估

整体：<一句话总结，如"行动描述较充分，但结果量化普遍缺失，建议优先补充">

逐段分析：

【公司名 · 职位名】
  场景/问题 ✅  行动 ⚠️  结果 ❌
  问题：<具体说明薄弱点>
  建议：<一句话改写方向>

【项目名 · 角色】
  场景/问题 ⚠️  行动 ✅  结果 ⚠️
  问题：<说明>
  建议：<建议>

（…其他段落）

⚡ 最值得优先改的 1-2 件事：
1. <最高优先级>
2. <次优先级>

---
如何继续？
A. 我自己去改简历，改完发给你重新评估
B. 先不改，用当前简历继续
```

### 用户选择处理

**选 A（修改简历）**：
- 告知用户：「好的，修改完后直接把新简历发给我（支持文件 / 路径 / 粘贴文本）。」
- 停止执行，等待用户重新发送简历
- 收到后按 Step 2 同样方式处理，覆盖保存 `resume.md`
- **重新执行 Step 2.5**（循环，直到用户选 B）

**选 B（继续）**：
- 告知用户：「好的，继续。」
- 执行 Step 3

---

## Step 3：截图收集与导入

（全流程、fetch 子命令时执行）

提示用户：

「请上传你感兴趣的岗位详情页截图（Boss直聘、智联招聘、前程无忧、猎聘、拉勾等均可），一次发完即可。」

发出上方提示后，停止执行，等待用户发送截图。

收到截图后：
1. 调用 Skill 工具，加载 `job-hunt-fetcher` skill，传入：
   - `work_dir`：<解析好的绝对路径>
   - `run_id`：<当前 run_id>
   - `screenshots`：<本批次截图>
2. fetcher 内部处理（含分组确认交互），完成后返回写入的 JD 文件 ID 列表
3. 将 ID 列表追加到 `state.json` 的 `stages.fetched`，更新 `checkpoint_at` 和 `phase` 为 `"fetched"`

若子命令为 `fetch`：告知用户「✅ JD 导入完成，共 <N> 个岗位。运行 /job-hunt analyze 开始分析。」并停止。

**【全流程】不得输出任何文字，立即调用 Skill 工具执行 Step 4。**

---

## Step 4：分析（job-hunt-analyzer）

（全流程、analyze 子命令时执行）

确定待分析 JD 列表：
- 扫描 `<data_dir>/.work/jd-pool/` 下所有 `.md` 文件（排除 `.analysis.md` 结尾的文件）
- 读取每个文件的 frontmatter，筛选 `status.analyzed: false` 的文件，提取其 `id` 字段
- 排除 `state.json.stages.analysis_errors` 中已记录失败的 ID

若列表为空，告知用户「jd-pool 中没有待分析的 JD，请先上传截图。」并停止。

调用 Skill 工具，加载 `job-hunt-analyzer` skill，传入：
- `work_dir`：<绝对路径>
- `resume_path`：`<data_dir>/.work/resume.md`
- `jd_ids`：<待分析 JD ID 列表>
- `preferences`：`{"soft_preferences": {"prefer_industries": [], "avoid_industries": [], "prefer_company_size": []}, "ranking": {"match_weight": 1.0, "preference_weight": 0.0}}`
- `run_id`：<当前 run_id>

analyzer 返回后，更新 state.json `phase` 为 `"analyzed"`。

**【全流程】不输出任何文本，立即执行 Step 5。**

---

## Step 5：排序

（全流程或 tailor 子命令前执行，不调用 LLM）

读取所有 analysis 文件（`<data_dir>/.work/jd-pool/*.analysis.md`），提取每个文件中的 `scores.total` 字段，按降序排列。

**所有已分析 JD 全部参与排序，不截断。**

将排序结果（JD ID 有序列表）写入 `state.json` 的 `stages.sorted_ids` 字段，同时保留在内存中供 Step 6 直接使用。Step 6 断点续跑时，若内存中无排序结果，从 `state.json.stages.sorted_ids` 读取。

**【全流程】排序完成后立即执行 Step 6，不等待用户。**

---

## Step 6：定制简历（job-hunt-tailor）

（全流程或 tailor 子命令时执行）

检查 `<data_dir>/.work/resume.md` 是否存在，若不存在则执行 Step 2 获取简历流程后再继续。

取 Step 5 排序后的完整 JD ID 列表。
排除 state.json 中已在 `stages.tailored` 的（断点续跑时跳过）。

调用 Skill 工具，加载 `job-hunt-tailor` skill，传入：
- `work_dir`：<绝对路径>
- `resume_path`：`<data_dir>/.work/resume.md`
- `jd_ids`：<完整排序后的 JD ID 列表>
- `run_id`：<当前 run_id>

tailor 返回后，更新 state.json `phase` 为 `"tailored"`。

**【全流程】不输出任何文本，立即执行 Step 7。**

---

## Step 7：生成 shortlist.md

（全流程最后一步）

读取所有 analysis 文件和对应 JD frontmatter，生成 `<data_dir>/output/<run_id>/shortlist.md`，**同时在聊天消息中输出完整内容**：

```markdown
# 求职 Shortlist · <run_id>

## 概况
- 导入岗位：<stages.fetched 数量> 个
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
告知用户：「✅ 全部完成！shortlist 已保存到 <data_dir>/output/<run_id>/shortlist.md，并在上方展示。」

---

## Step 7b（status 子命令）：输出运行状态

扫描 `<data_dir>/output/` 下所有子目录，找名字格式为 `YYYY-MM-DD-HHMM` 的目录，读取最新一个的 `state.json`，按以下格式输出：

```
Job-Hunt 状态报告
==================
Run ID：<run_id>
当前阶段：<phase>
工作目录：<data_dir>

进度统计：
  已导入 JD：<stages.fetched 数量> 个
  完成分析：<stages.analyzed 数量> 个
  分析失败：<stages.analysis_errors 数量> 个
  生成三件套：<stages.tailored 数量> 个

最后更新：<checkpoint_at>
```

若无任何 run 记录，告知用户「尚未运行过 /job-hunt，请先运行完整流程。」

---

## Step 8（clean 子命令）：强制清理

删除 `<data_dir>/.work/jd-pool/` 下所有文件（含 .analysis.md）。
删除 `<data_dir>/output/` 下所有 run 目录。
删除 `<data_dir>/.work/resume.md`（若存在）。
统计并告知用户清理了多少文件/目录。
