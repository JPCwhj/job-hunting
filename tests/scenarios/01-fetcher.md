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
