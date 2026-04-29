#!/bin/bash
# 将 job-hunt skill suite 安装到 Claude Code 插件目录

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Claude Code 插件安装路径
# 根据 installed_plugins.json 的结构，本地插件应该被安装到 ~/.claude/plugins/cache/local/
CLAUDE_PLUGINS_CACHE="$HOME/.claude/plugins/cache"
LOCAL_PLUGIN_DIR="$CLAUDE_PLUGINS_CACHE/local/job-hunt"
SKILL_INSTALL_DIR="$LOCAL_PLUGIN_DIR/1.0.0/skills"

# 允许用户通过环境变量覆盖路径
if [ -n "$SKILL_INSTALL_DIR_OVERRIDE" ]; then
  SKILL_INSTALL_DIR="$SKILL_INSTALL_DIR_OVERRIDE"
fi

# 检查 Claude Code 插件目录是否存在
if [ ! -d "$CLAUDE_PLUGINS_CACHE" ]; then
  echo "❌ 未找到 Claude Code 插件目录（~/.claude/plugins/cache/）"
  echo "   请确认 Claude Code 已安装，或手动指定安装路径："
  echo "   SKILL_INSTALL_DIR_OVERRIDE=/path/to/skills bash scripts/install.sh"
  exit 1
fi

echo "🔧 安装 job-hunt skill suite 到 $SKILL_INSTALL_DIR ..."
echo ""

# 创建必要的目录结构
mkdir -p "$SKILL_INSTALL_DIR/job-hunt"
mkdir -p "$SKILL_INSTALL_DIR/job-hunt-fetcher"
mkdir -p "$SKILL_INSTALL_DIR/job-hunt-analyzer"
mkdir -p "$SKILL_INSTALL_DIR/job-hunt-tailor"

echo "📁 创建目录结构..."

# 复制 skill index.md 文件
if [ ! -f "$REPO_ROOT/skills/job-hunt/index.md" ]; then
  echo "❌ 错误：未找到 $REPO_ROOT/skills/job-hunt/index.md"
  exit 1
fi

cp "$REPO_ROOT/skills/job-hunt/index.md"           "$SKILL_INSTALL_DIR/job-hunt/index.md"
echo "✅ 安装 job-hunt"

cp "$REPO_ROOT/skills/job-hunt-fetcher/index.md"   "$SKILL_INSTALL_DIR/job-hunt-fetcher/index.md"
echo "✅ 安装 job-hunt-fetcher"

cp "$REPO_ROOT/skills/job-hunt-analyzer/index.md"  "$SKILL_INSTALL_DIR/job-hunt-analyzer/index.md"
echo "✅ 安装 job-hunt-analyzer"

cp "$REPO_ROOT/skills/job-hunt-tailor/index.md"    "$SKILL_INSTALL_DIR/job-hunt-tailor/index.md"
echo "✅ 安装 job-hunt-tailor"

echo ""
echo "✅ 安装完成！"
echo ""
echo "📝 后续步骤："
echo "  1. 重启 Claude Code"
echo "  2. 准备配置文件："
echo "     mkdir -p ~/.job-hunt"
echo "     cp $REPO_ROOT/templates/preferences.yaml ~/.job-hunt/preferences.yaml"
echo "  3. 编辑 ~/.job-hunt/preferences.yaml，填入你的求职偏好"
echo "  4. 把简历放到 ~/.job-hunt/resume.md 或 ~/.job-hunt/resume.docx"
echo "  5. 确保 Chrome 已登录 Boss 直聘（zhipin.com）"
echo "  6. 在 Claude Code 中运行 /job-hunt"
echo ""
echo "已安装的 skill 位置：$SKILL_INSTALL_DIR"
