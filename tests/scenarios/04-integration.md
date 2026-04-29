# 端到端验证场景

## 首次运行完整流程
- [ ] 工作目录下有 preferences.yaml 和 resume.md
- [ ] 运行 `/job-hunt`
- [ ] 被提示检查 Chrome 登录态（来自 fetcher skill）
- [ ] 开始抓取，有实时进度提示
- [ ] 若有验证码，被正确提示暂停并等待，用户确认后自动重试
- [ ] 抓取完成后自动进入分析阶段
- [ ] 分析完成后自动进入定制阶段（只为 Top N 生成）
- [ ] 最终生成 shortlist.md，结构含 Top 推荐 + 其余 JD 表格

## 断点续跑
- [ ] 中途中断（模拟 phase=fetched 时停止）
- [ ] 再次运行 `/job-hunt`
- [ ] 被询问「继续/重开/放弃」
- [ ] 选择继续后，从 analyze 阶段开始，已完成的 JD 不重复处理

## 缓存验证
- [ ] 24 小时内第二次运行，fetcher 应显著快于首次（大多数 JD 走缓存）
- [ ] 修改 resume.md 后运行，analysis 缓存被 invalidate，重新分析所有 JD

## 子命令验证
- [ ] `/job-hunt status` 输出当前 run_id、phase、各 stages 的 JD 数量
- [ ] `/job-hunt fetch` 只执行抓取，结束后不继续进入分析
- [ ] `/job-hunt clean` 清理缓存后确认 jd-pool 和 output 目录均已清空

## 伦理边界验证
- [ ] 找到一条 JD，运行完整流程
- [ ] 打开 tailored/<id>/changelog.md，每条改动能在主简历中找到原始依据
- [ ] resume.md 中没有出现主简历不存在的经历或数字
