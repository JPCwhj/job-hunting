# Analyzer 验证场景

## 前置条件
- `<work_dir>/.work/jd-pool/` 中至少有 2 条 JD（来自 fetcher 测试）
- `<work_dir>/.work/resume.md` 是一份真实简历

## 验证检查点
- [ ] resume.star.md 被生成，每段工作经历都有 STAR 四要素（S/T/A/R）
- [ ] 4 维子分（hard_skills/experience_depth/domain_fit/soft_fit）各在 0-100 范围内
- [ ] total_match 等于 4 维均值（可手算验证）
- [ ] final_rank_score 公式正确：`round((total_match × match_weight + preference_score × pref_weight) × hr_factor, 2)`
- [ ] analysis.md 中没有出现「请增加 [从未提到的] 经历」之类的建议
- [ ] Result 段若简历缺数字，建议中使用了 `[请填写：xxx]` 而非编造数字
- [ ] HR 活跃度系数被正确应用（刚刚活跃的 JD final_rank_score 不低于本周活跃的同分 JD）
- [ ] 分析缓存生效：第二次运行同一简历+同一 JD，直接复用 analysis.md，不重新分析
