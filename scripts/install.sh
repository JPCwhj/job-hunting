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
echo "📝 使用方式："
echo "  1. 在 Claude Code（或其他支持 skill 的 agent）中运行 /job-hunt"
echo "  2. 按提示提供简历（发文件、告知路径，或直接粘贴文本）"
echo "  3. 上传 Boss 直聘岗位详情页截图"
echo "  4. 等待分析完成，查看 shortlist"
