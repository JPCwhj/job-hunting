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

写入格式（这是写入 jd-pool 文件时使用的模板，不是 fetcher skill 本身的格式）：

```
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
