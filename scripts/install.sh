#!/bin/bash
# 将 job-hunt skill suite 安装到 Claude Code skills 目录

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Claude Code 直接读取 ~/.claude/skills/ 下的 skill 目录
SKILL_DIR="$HOME/.claude/skills"

# 检查目录是否存在
if [ ! -d "$SKILL_DIR" ]; then
  echo "❌ 未找到 ~/.claude/skills/ 目录，请确认 Claude Code 已安装"
  exit 1
fi

echo "🔧 安装 job-hunt skill suite 到 $SKILL_DIR ..."
echo ""

for skill in job-hunt job-hunt-fetcher job-hunt-analyzer job-hunt-tailor; do
  mkdir -p "$SKILL_DIR/$skill"
  cp "$REPO_ROOT/skills/$skill/SKILL.md" "$SKILL_DIR/$skill/SKILL.md"
  echo "✅ 安装 $skill"
done

echo ""
echo "✅ 安装完成！无需重启 Claude Code，skill 立即生效。"
echo ""
echo "📝 后续步骤："
echo "  1. 准备配置文件："
echo "     mkdir -p ~/.job-hunt"
echo "     cp $REPO_ROOT/templates/preferences.yaml ~/.job-hunt/preferences.yaml"
echo "  2. 编辑 ~/.job-hunt/preferences.yaml，填入你的求职偏好"
echo "  3. 把简历放到 ~/.job-hunt/resume.md 或 ~/.job-hunt/resume.docx"
echo "  4. 确保 Chrome 已登录 Boss 直聘（zhipin.com）"
echo "  5. 在 Claude Code 中运行 /job-hunt"
