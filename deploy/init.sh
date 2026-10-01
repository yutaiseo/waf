#!/usr/bin/env bash
# ============================================================
# 初始化脚本 — 下载 OWASP CRS v4 规则集
# 运行一次即可，之后 docker compose 会挂载进去
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CRS_DIR="$SCRIPT_DIR/../data-plane/rules/owasp-crs"

echo "=== WAF Phase 1 初始化 ==="
echo ""

# 1. 检查 Git
if ! command -v git &> /dev/null; then
    echo "❌ 请先安装 git: apt install git / yum install git"
    exit 1
fi

# 2. 创建目录
mkdir -p "$CRS_DIR"

# 3. 下载 OWASP CRS v4（浅克隆，省空间和时间）
if [ -d "$CRS_DIR/.git" ]; then
    echo "📥 OWASP CRS 已存在，检查更新..."
    cd "$CRS_DIR"
    git fetch --depth 1 origin
    git checkout v4.0.0 || git checkout master
    git pull --ff-only
else
    echo "📥 下载 OWASP CRS v4..."
    git clone --depth 1 --branch v4.0.0 \
        https://github.com/coreruleset/coreruleset.git \
        "$CRS_DIR"
fi

# 4. 检查目录结构
RULES_DIR="$CRS_DIR/rules"
if [ ! -d "$RULES_DIR" ]; then
    echo "❌ OWASP CRS rules/ 目录不存在"
    exit 1
fi

RULE_COUNT=$(ls "$RULES_DIR"/*.conf 2>/dev/null | wc -l)
echo ""
echo "✅ OWASP CRS 下载完成"
echo "   规则文件数量: $RULE_COUNT"
echo "   路径: $CRS_DIR"

# 5. 确认 Coraza 兼容配置存在
if [ ! -f "$CRS_DIR/crs-setup.conf.example" ]; then
    echo "⚠️  crs-setup.conf.example 不存在，请检查 CRS 版本"
fi

echo ""
echo "=== 下一步 ==="
echo "1. 编辑 data-plane/Caddyfile，改域名和 IDC IP"
echo "2. 编辑 deploy/docker-compose.yml（可选）"
echo "3. docker compose -f deploy/docker-compose.yml up -d --build"
