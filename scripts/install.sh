#!/bin/bash
# 将 job-hunt skill suite 安装到 Claude Code 插件目录

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Claude Code 插件安装路径
# 本地插件必须安装到 ~/.claude/plugins/cache/local/
CLAUDE_PLUGINS_CACHE="$HOME/.claude/plugins/cache"
LOCAL_PLUGIN_DIR="$CLAUDE_PLUGINS_CACHE/local/job-hunt/1.0.0"
SKILL_INSTALL_DIR="$LOCAL_PLUGIN_DIR/skills"
PLUGINS_JSON="$HOME/.claude/plugins/installed_plugins.json"

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
mkdir -p "$LOCAL_PLUGIN_DIR/.claude-plugin"

echo "📁 创建目录结构..."

# 检查源文件存在
if [ ! -f "$REPO_ROOT/skills/job-hunt/SKILL.md" ]; then
  echo "❌ 错误：未找到 $REPO_ROOT/skills/job-hunt/SKILL.md"
  exit 1
fi

# 复制 skill 文件（Claude Code 要求文件名为 SKILL.md）
cp "$REPO_ROOT/skills/job-hunt/SKILL.md"           "$SKILL_INSTALL_DIR/job-hunt/SKILL.md"
echo "✅ 安装 job-hunt"

cp "$REPO_ROOT/skills/job-hunt-fetcher/SKILL.md"   "$SKILL_INSTALL_DIR/job-hunt-fetcher/SKILL.md"
echo "✅ 安装 job-hunt-fetcher"

cp "$REPO_ROOT/skills/job-hunt-analyzer/SKILL.md"  "$SKILL_INSTALL_DIR/job-hunt-analyzer/SKILL.md"
echo "✅ 安装 job-hunt-analyzer"

cp "$REPO_ROOT/skills/job-hunt-tailor/SKILL.md"    "$SKILL_INSTALL_DIR/job-hunt-tailor/SKILL.md"
echo "✅ 安装 job-hunt-tailor"

# 创建 plugin.json 清单（Claude Code 识别插件所必需）
cat > "$LOCAL_PLUGIN_DIR/.claude-plugin/plugin.json" << 'PLUGIN_JSON'
{
  "name": "job-hunt",
  "description": "Boss 直聘 JD 抓取 + STAR 匹配分析 + 定制简历三件套",
  "version": "1.0.0",
  "author": {
    "name": "wuhaojie"
  }
}
PLUGIN_JSON
echo "✅ 创建 .claude-plugin/plugin.json"

# 注册到 installed_plugins.json（如果 python3 可用）
if command -v python3 &>/dev/null && [ -f "$PLUGINS_JSON" ]; then
  python3 - << PYEOF
import json, sys

with open('$PLUGINS_JSON', 'r') as f:
    data = json.load(f)

data['plugins']['job-hunt@local'] = [
    {
        "scope": "user",
        "installPath": "$LOCAL_PLUGIN_DIR",
        "version": "1.0.0",
        "installedAt": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
        "lastUpdated": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
        "gitCommitSha": "local"
    }
]

with open('$PLUGINS_JSON', 'w') as f:
    json.dump(data, f, indent=2)

print("✅ 已注册到 installed_plugins.json")
PYEOF
else
  echo "⚠️  跳过注册（python3 不可用 或 installed_plugins.json 不存在）"
  echo "   请手动将以下内容添加到 $PLUGINS_JSON 的 plugins 对象中："
  echo '   "job-hunt@local": [{"scope":"user","installPath":"'"$LOCAL_PLUGIN_DIR"'","version":"1.0.0","installedAt":"'"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"'","lastUpdated":"'"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"'","gitCommitSha":"local"}]'
fi

echo ""
echo "✅ 安装完成！"
echo ""
echo "📝 后续步骤："
echo "  1. 重启 Claude Code（必须，插件在启动时加载）"
echo "  2. 准备配置文件："
echo "     mkdir -p ~/.job-hunt"
echo "     cp $REPO_ROOT/templates/preferences.yaml ~/.job-hunt/preferences.yaml"
echo "  3. 编辑 ~/.job-hunt/preferences.yaml，填入你的求职偏好"
echo "  4. 把简历放到 ~/.job-hunt/resume.md 或 ~/.job-hunt/resume.docx"
echo "  5. 确保 Chrome 已登录 Boss 直聘（zhipin.com）"
echo "  6. 在 Claude Code 中运行 /job-hunt"
echo ""
echo "已安装的 skill 位置：$SKILL_INSTALL_DIR"
