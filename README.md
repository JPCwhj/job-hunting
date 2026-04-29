# job-hunt · Claude Code Skill Suite

用 AI 帮你从 Boss 直聘批量抓取 JD、匹配简历、生成定制简历和开场白，最后按匹配度排序输出 shortlist。

> **定位**：效率工具，不是自动投递机器人。最终点击「立即沟通」由你来决定。

---

## 它能做什么

1. **抓取 JD**：用你已登录的 Chrome，从 Boss 直聘按城市 × 关键词组合搜索，自动抓取详情页
2. **匹配分析**：把每条 JD 和你的简历做 STAR 对齐，输出 4 个维度的匹配分（硬技能 / 经验深度 / 行业契合 / 软性匹配）
3. **生成三件套**：对匹配度最高的 Top N 岗位，各生成一份定制简历 + 开场白 + 改动说明
4. **输出 shortlist**：按综合评分（匹配度 × HR 活跃度）排序，一眼看清哪些值得优先投

---

## 安装

```bash
git clone https://github.com/JPCwhj/job-hunting.git
cd job-hunting
bash scripts/install.sh
```

安装完成后，**无需重启 Claude Code**，skill 立即可用。

---

## 使用

在任意目录启动 Claude Code，运行：

```
/job-hunt
```

**首次运行**会自动引导完成配置：
1. 通过对话收集求职偏好（城市、岗位、薪资、规模等）→ 自动生成 `preferences.yaml`
2. 提示你把简历文件（`.md` 或 `.docx`，文件名随意）放到当前目录 → 自动识别

之后每次运行直接开始抓取，数据保存在 Claude 启动时所在的目录下。

### 子命令

| 命令 | 作用 |
|---|---|
| `/job-hunt` | 完整流程（抓取 → 分析 → 生成 → shortlist） |
| `/job-hunt fetch` | 只抓取 JD |
| `/job-hunt analyze` | 只做匹配分析（基于已有 jd-pool） |
| `/job-hunt tailor` | 只生成定制简历（基于已有分析结果） |
| `/job-hunt status` | 查看当前进度 |
| `/job-hunt clean` | 清理所有缓存和输出 |

---

## 前置条件

- [Claude Code](https://claude.ai/code) 已安装
- [bb-browser](https://github.com/epiral/bb-browser/blob/main/README.zh-CN.md) MCP 已配置（用于控制 Chrome）
- Chrome 浏览器已登录 [Boss 直聘](https://www.zhipin.com)

---

## 输出文件结构

```
<当前目录>/
├── preferences.yaml              ← 求职偏好配置（首次运行自动生成）
├── .work/
│   └── jd-pool/                  ← JD 缓存（7 天有效）
└── output/
    └── 2026-04-29-1430/          ← 每次运行一个目录
        ├── shortlist.md          ← 最终排序结果
        ├── search.summary.md     ← 抓取统计
        └── tailored/
            └── boss-<id>/
                ├── resume.md     ← 定制简历
                ├── opener.md     ← 开场白
                └── changelog.md  ← AI 改了什么（透明度保险）
```

---

## 设计边界

- **仅支持 Boss 直聘**（v1）
- **不做自动投递**，避免封号风险
- **简历改写有伦理约束**：只改措辞和结构，不凭空增加经历，编造数字必须用 `[请填写：xxx]` 占位，`changelog.md` 记录每一处改动供你审查

---

## License

MIT
