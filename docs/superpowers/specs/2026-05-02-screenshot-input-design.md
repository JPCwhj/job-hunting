# job-hunt Screenshot Input 设计文档

## 背景与动机

原 `feat/skill-suite` 分支通过 `bb-browser` 自动控制 Chrome 抓取 Boss 直聘。新方案改为**用户手动截图上传**，由 AI 解析截图中的 JD 信息。

核心变化：
- 去掉浏览器自动化依赖（`bb-browser`）
- 去掉防风控延迟、分页逻辑、断点续传
- 去掉 preferences.yaml 和首次运行向导
- 用户的截图选择本身就是筛选，去掉硬过滤
- 排序简化为 match score

该方案遵循 skill 规范，可安装到任何支持 skill 的 agent（Claude Code、OpenClaw 等），**不做平台区分**。

---

## 整体架构

四个 skill 结构不变，改动集中在 `job-hunt-fetcher` 内部和 `job-hunt` 主 skill 的编排逻辑：

```
job-hunt              ← 主：编排（大幅简化）
├── job-hunt-fetcher  ← ⚡ 内部完全重写：截图解析
├── job-hunt-analyzer ← 不动
└── job-hunt-tailor   ← 不动
```

---

## 用户完整流程

```
1. 用户提供简历
2. 用户上传岗位截图（可分批）
3. fetcher 解析截图 → 写入 jd-pool
4. analyzer 对所有 JD 跑 STAR 匹配
5. tailor 为所有 JD 生成定制简历三件套
6. 输出 shortlist（文件 + 聊天同步展示）
```

**没有**：配置向导、硬过滤、top_n 截断、偏好权重。用户上传几个岗位就处理几个，全部走完整流程。

---

## 主 skill 变化

### 删除
- `batch_size` 询问
- `seen_ids` 构建与去重
- 分页采集逻辑
- 断点续传
- bb-browser 登录检测引导
- 硬过滤逻辑
- 首次运行向导（6 轮对话 + preferences.yaml 写入）

### 新增步骤（替换原抓取环节）

**Step 1：获取简历**

提示用户提供简历，支持三种方式（不做平台区分，均可用）：
- 发送简历文件（.md 或 .docx）
- 告知本地文件路径
- 直接将简历文本粘贴到消息框

收到后，`.docx` 用 `docx` skill 解析，统一转为 Markdown 供后续使用。

**Step 2：收集截图**

```
请上传你感兴趣的岗位截图（Boss 直聘详情页）。
可以一次发多张，也可以分批发送。
截图发完后告诉我「开始分析」。
```

每次收到截图，调用 `job-hunt-fetcher` 处理，处理完继续等待。
用户说「开始分析」后，进入 analyzer 流程。

### 保留
- 调 analyzer、tailor 的编排逻辑
- shortlist 生成与输出

---

## job-hunt-fetcher 新设计

### 职责
接收用户上传的截图 → 解析 JD 信息 → 写入 jd-pool。

### 输入
主 skill 传入：
- `work_dir`：工作根目录
- `run_id`：本次运行时间戳 ID（格式 YYYY-MM-DD-HHMM）
- `screenshots`：本批次截图（1 张或多张）

### Step 1：判断模式 + 完整性确认

收到截图后，识别截图涉及几个岗位：

**多个岗位（批量模式）**

逐张识别「职位名称 + 公司名称」，归组，展示分组结果请用户确认：

```
我识别出 3 个岗位，分组如下：
- 组1：字节跳动 · 产品经理（2张）
- 组2：美团 · 高级产品经理（1张）
- 组3：滴滴 · 产品经理（1张，截图疑似不完整，缺少任职要求）

分组有误或需要补截图吗？没问题直接说「继续」。
```

**单个岗位（流式模式）**

先确认完整性：

```
我看到了「字节跳动 · 产品经理」的截图，这些截图已经包含完整的 JD 信息了吗？
（岗位职责、任职要求都截到了？）
如果还有截图没发，继续发过来；都发完了告诉我「完整了」，我开始解析。
```

用户继续发截图 → 追加到当前组 → 重复询问。
用户说「完整了」→ 进入 Step 2。

**只有 1 张截图且内容完整明确时**，跳过确认直接处理。

### Step 2：解析并写入 jd-pool

对每组截图，合并阅读所有图片，提取以下字段：

```yaml
title: 职位名称
company:
  name: 公司名称
  size: 规模档位（A/B/C/D/E/F，见映射表）
  industry: 行业标签
  stage: 融资阶段（无则 null）
salary:
  range: 薪资文本（如"20-40K"）
  monthly_count: 月数（如"16薪"则 16，无则 null）
location:
  city: 城市
  district: 区域
requirements:
  experience: 经验要求
  education: 学历要求
tags: [技能标签列表]
benefits: [福利标签列表]
hr:
  name: HR 姓名
  title: HR 职称
  active_status: HR 活跃状态文本（如"今日活跃"）
posted_at: 发布时间
job_description: 岗位职责全文
job_requirements: 任职要求全文
company_intro: 公司介绍全文（无则 null）
```

规模文本 → 档位映射：
- 20人以下 → A，20-99人 → B，100-499人 → C
- 500-999人 → D，1000-9999人 → E，10000人以上 → F

**字段缺失处理**：截图截不全时，能提取的字段正常写，提取不到的置为 `null`，不中断写入。解析完成后汇报缺失情况。

**文件 ID 与路径**：

| 情况 | 文件名 |
|---|---|
| 能提取到公司名 + 职位名 | `公司名-职位名-YYYYMMDDTHHmm.md` |
| 提取不到名称 | `screenshot-YYYYMMDDTHHmm.md` |

写入路径：`<work_dir>/.work/jd-pool/<文件名>`

**写入格式**（frontmatter + 正文，与原 jd-pool 格式一致）：

```markdown
---
id: <文件名去掉 .md>
fetched_at: <当前 ISO 8601 时间>
run_id: <run_id>
source: screenshot

title: <title>
company:
  name: ...
  ...（同上字段）

status:
  detail_fetched: true
  analyzed: false
---

## 岗位职责

<job_description>

## 任职要求

<job_requirements>

## 公司介绍

<company_intro，若 null 则删除此节>
```

**解析完成后汇报**：

```
已解析完成：
- ✅ 字节跳动·产品经理（字段完整）
- ✅ 美团·高级产品经理（字段完整）
- ⚠️ 滴滴·产品经理（公司介绍未截到，已置空）
```

---

## 排序与 shortlist

### 排序规则

```
final_rank_score = match_score
```

`match_score` 由 analyzer 给出（简历 × JD 匹配度，0-100）。

HR 活跃状态**不参与计算**，在 shortlist 中作为辅助信息展示，用户自行判断。

### shortlist 输出

**双路输出**：
1. 写入文件：`<work_dir>/output/<run_id>/shortlist.md`
2. 在聊天中同步展示完整内容

shortlist 格式：

```markdown
# Shortlist · <run_id>

## 排名

| # | 公司 | 职位 | 匹配度 | HR 活跃 | 定制简历路径 |
|---|---|---|---|---|---|
| 1 | 字节跳动 | 产品经理 | 92 | 今日活跃 | output/.../bytedance-pm/ |
| 2 | 美团 | 高级产品经理 | 87 | 3天内活跃 | output/.../meituan-pm/ |
...
```

---

## 删除的模块与文件

| 删除项 | 原因 |
|---|---|
| `templates/preferences.yaml` | 无配置需求 |
| fetcher 中 bb-browser 所有操作 | 改为截图解析 |
| fetcher 中分页、seen_ids、防风控延迟 | 不再需要 |
| 主 skill 中首次运行向导 | 无配置需求 |
| 主 skill 中硬过滤逻辑 | 用户手动筛选替代 |
| 主 skill 中 batch_size / top_n_for_tailor | 全量处理，无需截断 |

---

## 不变的部分

- `job-hunt-analyzer/SKILL.md`：完全不动
- `job-hunt-tailor/SKILL.md`：完全不动
- jd-pool 文件格式：analyzer 和 tailor 读取的字段结构不变
- `output/<run_id>/` 目录结构：不变
- `docx` skill 依赖：保留（用于解析 .docx 简历）
