---
name: job-hunt-fetcher
description: Internal sub-skill for job-hunt suite. Fetches job listings from Boss 直聘 using bb-browser and writes structured JD markdown files to jd-pool. Do NOT invoke directly — use the job-hunt main skill instead.
---

# job-hunt-fetcher

你是 job-hunt 套件的抓取组件。**唯一职责**：从 Boss 直聘抓取 JD，输出标准化 Markdown 文件。你不做过滤、不做分析、不做改写。

调用方（job-hunt 主 skill）会传给你以下上下文：
- `work_dir`：工作根目录路径
- `preferences`：已解析的 preferences.yaml 内容
- `run_id`：本次 run 的时间戳 ID（格式 YYYY-MM-DD-HHMM）
- `state`：state.json 的当前内容（含断点信息）
- `batch_size`：本次每个搜索组合要采集的新岗位数量

## 第 0 步：读取 bb-browser skill

调用 Skill 工具，加载 `bb-browser` skill，获取浏览器操作能力。

## 第 0.5 步：构建已见 JD 集合

扫描 `<work_dir>/.work/jd-pool/` 下所有 `boss-*.md` 文件，从每个文件的 frontmatter 中提取 `id` 字段，取其中的 jobId 部分，构建 `seen_ids` 集合。

**这个集合是本次 run 全程的去重依据**：job_id 已在 `seen_ids` 中的条目一律跳过，不进详情页，不写文件。在同一 run 内，每当一个新 job_id 通过去重加入待处理队列时，立即将其加入 `seen_ids`，防止同 run 内跨轮次重复。

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

从上下文中读取 `batch_size`（本次每个组合要新增的岗位数量）。

## 第 3 步：逐轮执行搜索

对每个待处理的 `城市-关键词` 组合，执行以下子步骤：

### 3.1 在 Boss 直聘搜索（首页导航 + 条件设置）

使用 bb-browser 导航到 Boss 直聘首页，然后：
1. 在搜索框中输入关键词
2. 在城市选择器中选择目标城市（通常在搜索框旁边的下拉菜单）
3. 如果 preferences 中有 `experience` → 找到「经验」筛选器，选择对应档位
4. 如果 preferences 中有 `salary` → 找到「薪资」筛选器，选择对应范围
5. 点击搜索或按回车
6. 等待搜索结果加载（3-5 秒）

初始化本轮次状态：
- `page = 1`（当前页码）
- `new_jobs = []`（本轮次收集的新 JD 基础信息列表）
- `exhausted = false`

### 3.2 分页采集循环

**重复执行以下步骤，直到 `len(new_jobs) >= batch_size` 或 `exhausted = true`：**

#### 3.2.1 提取当前页所有职位卡片基础信息

对当前页所有职位卡片（通常每页约 30 条），逐一提取：

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

**若当前页结果为 0 条**：
→ `exhausted = true`，退出循环。

#### 3.2.2 去重过滤

对本页每个条目，按顺序检查：
- 若 `job_id` 已在 `seen_ids` 中 → 跳过（已在之前的批次或本 run 内采集过）
- 若不在 → 将该条目加入 `new_jobs`，**同时立即将 `job_id` 加入 `seen_ids`**（防止同 run 内重复）
- 若 `len(new_jobs) >= batch_size` → **立即退出循环**，不继续处理本页剩余条目

#### 3.2.3 判断是否到达最后一页

若满足以下任意条件，且 `len(new_jobs) < batch_size`：
- 本页实际条目数 ≤ 5
- 「下一页」按钮不存在或置灰

→ `exhausted = true`，退出循环。

#### 3.2.4 列表页停留 + 翻页

若还需要继续（`len(new_jobs) < batch_size` 且 `exhausted = false`）：
1. 等待随机 **5-8 秒**（模拟用户在列表页浏览停留）
2. 点击「下一页」按钮，等待新页面加载（3-5 秒）
3. `page += 1`，返回 3.2.1 继续

#### 3.2.5 exhausted 处理

退出循环后，若 `exhausted = true` 且 `len(new_jobs) < batch_size`：
→ 在 `search.summary.md` 的「组合收录完毕」节中追加：
  `「<城市>×<关键词>：已全部收录，本次新增 <len(new_jobs)> 个（搜索结果已无更多）」`
→ 用 `new_jobs` 中已有的继续后续步骤（不等待更多）

若 `new_jobs` 为空（整个组合一个新 JD 都没有）：
→ 跳过该组合的后续步骤，直接进入下一组合。

### 3.3 硬过滤（列表阶段，不进详情页）

对 `new_jobs` 中每条 JD，依次检查 `preferences.hard_filters`：

1. **公司黑名单**：`company_name` 是否在 `exclude_companies` 中 → 是则跳过，记录原因 `"公司在黑名单中"`
2. **关键词过滤**：`title` 是否包含 `exclude_keywords` 中的任意词 → 是则跳过，记录原因 `"标题含屏蔽词: [词]"`
3. **规模过滤**：`company_size` 档位是否低于 `min_company_size` → 是则跳过，记录原因 `"公司规模 [X] 低于要求 [Y]"`

被过滤的 JD 写入 `<work_dir>/output/<run_id>/raw/filtered-list.md`（格式见下方「过滤记录格式」），不进行后续处理。

对通过所有过滤条件的 JD，立即将其 `boss-<job_id>` 追加到 `state.search_progress.filtered_in` 数组，并更新 `checkpoint_at`。

### 3.4 缓存检查（通过过滤的 JD）

对通过过滤的每条 JD：
- 检查 `<work_dir>/.work/jd-pool/boss-<job_id>.md` 是否存在
- 读取文件中 `fetched_at` 字段
- 将 `fetched_at` 解析为 UTC 时间，与当前 UTC 时间作差；若差值 **≤ 168 小时**，视为有效缓存 → 跳过详情页抓取，标记为「缓存命中」，将 `boss-<job_id>` 加入 `stages.fetched`，更新 `checkpoint_at`
- 否则（差值 > 168 小时）→ 视为过期，进入 Step 3.5 重新抓取

### 3.5 抓取详情页

**串行铁律**：每次只调用一个 bb-browser 工具，必须等上一个返回结果后再发下一个。绝不并发调用多个 bb-browser 工具。

对需要抓取的每条 JD：

1. 等待随机 **10-15 秒**（每次都要随机，不要固定值）
2. 使用 bb-browser 导航到 `detail_url`
3. 等待页面加载（等待「岗位职责」标题出现，超时 15 秒则记录失败并跳过）

检查是否出现验证码 / 滑块：
- 如果出现「请完成安全验证」或滑块弹窗 → 告诉用户：
  「Boss 直聘触发了验证码，请在浏览器中手动通过验证，完成后告诉我继续。」
  等待用户确认后，**重新导航到同一 `detail_url`，从第 3.5 步第 1 行开始重试该条 JD**。若重试后仍出现验证码，则跳过该条 JD，记录到摘要失败列表，继续同轮次下一条。

从详情页提取：
```
tags: 技能标签列表（页面上的 pill 标签，通常在职位名称下方）
benefits: 福利标签列表（通常在岗位职责前的标签区）
hr_name: HR 姓名
hr_title: HR 职称
hr_active: HR 活跃状态（详情页上可能比列表页更准确）
posted_at: 发布时间，换算规则：
  - "刚刚"或"1小时内" → 当前日期
  - "X小时前" → 当前日期
  - "昨天" → 当前日期 - 1 天
  - "X天前" → 当前日期 - X 天
  - "X周前" → 当前日期 - X×7 天
  - "YYYY-MM-DD" 格式 → 直接用
  - 其他无法识别的格式 → 保留原始文本
job_description: 「岗位职责」部分全文
job_requirements: 「任职要求」部分全文
company_intro: 「公司介绍」部分全文（若无则留空）
```

完成数据提取后，立即关闭该详情页标签（`browser_tab_close` 或等效操作），只保留主标签页。

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

写入完成后，立即更新 `<work_dir>/output/<run_id>/state.json`：
- 将 `boss-<job_id>` 加入 `stages.fetched` 数组
- 将 `boss-<job_id>` 加入 `stages.filtered_in` 数组（供 analyzer 读取候选集）
- 更新 `checkpoint_at` 为当前时间

### 3.7 轮次间隔

当前 keyword×city 轮次处理完毕后：
- 将此轮次标记为完成（加入 `state.search_progress.completed`）
- 等待随机 **30-60 秒** 再开始下一轮次

## 第 4 步：生成抓取摘要

所有轮次完成后，写入 `<work_dir>/output/<run_id>/search.summary.md`：

```markdown
# 抓取摘要 · <run_id>

## 统计
- 搜索轮次：<N> 轮（<cities> × <keywords>）
- 本次 batch_size：每组合 <batch_size> 个新岗位
- 扫描列表页：共 <total_pages_scanned> 页（跨所有组合）
- 候选总数（去重后新增）：<total_new>
- 通过硬过滤：<passed>
- 缓存命中（复用）：<cache_hits>
- 新抓取详情：<new_fetched>
- 失败/跳过：<failed>

## 组合收录完毕（已无更多新岗位）
<列出 exhausted 的组合，含本次新增数；若无则省略此节>

## 失败列表
<逐条列出失败的 JD，含原因；若无则省略此节>

## 被过滤列表
<逐条列出硬过滤掉的 JD，含过滤原因；若无则省略此节>
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
| 验证码 / 滑块 | 停止，提示用户过验证后继续；重试仍失败则跳过该 JD |
| 详情页加载超时（>15s） | 跳过该 JD，记录到 summary 失败列表 |
| 单个字段提取失败 | 该字段置为 null，不中断整条 JD |
| 搜索结果为 0 条 | 标记 exhausted，记录，继续下一组合 |
| 翻页按钮不存在 / 置灰 | 标记 exhausted，用已收集的继续处理 |
