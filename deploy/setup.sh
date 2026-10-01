#!/bin/bash
# ============================================================
# WAF Phase 1 — 一键部署脚本
# 作者：自动生成
# 用法：curl -sL https://你的脚本地址/setup.sh | bash
# 或者在 VPS 上：bash setup.sh
#
# 做的事：
#   1. 检查依赖（docker, git）
#   2. 下载 OWASP CRS v4
#   3. 创建所有配置文件（Dockerfile, Caddyfile, Coraza 规则...）
#   4. docker compose build + up
#   5. 自动跑测试：正常请求 200，SQL 注入 403
# ============================================================

set -e
export DEBIAN_FRONTEND=noninteractive

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo ""
echo "╔═══════════════════════════════════════════════════════╗"
echo "║        WAF Phase 1 — 一键部署脚本                      ║"
echo "║        Caddy + coraza-caddy + OWASP CRS v4             ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""

WORKDIR=~/waf-phase1
rm -rf "$WORKDIR" && mkdir -p "$WORKDIR"
cd "$WORKDIR"
info "工作目录: $WORKDIR"

# ============================================================
# 1. 检查/安装 Docker
# ============================================================
if ! command -v docker &>/dev/null; then
    info "Docker 未安装，正在安装..."
    curl -fsSL https://get.docker.com | bash
    systemctl enable docker && systemctl start docker
fi

if ! command -v docker &>/dev/null; then
    error "Docker 安装失败"
fi
info "Docker 就绪: $(docker --version)"

# ============================================================
# 2. 创建 Dockerfile
# ============================================================
info "创建 Dockerfile..."

cat > Dockerfile << 'DOCKERFILE'
FROM caddy:2.11-builder AS builder
RUN xcaddy build --with github.com/corazawaf/coraza-caddy/v2
FROM caddy:2.11
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
RUN mkdir -p /var/log/coraza /var/log/caddy /tmp/coraza
EXPOSE 80 443 2019
CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
DOCKERFILE

# ============================================================
# 3. 创建 Caddyfile
# ============================================================
info "创建 Caddyfile..."

cat > Caddyfile << 'CADDYFILE'
{
    order coraza_waf first
    log { level INFO }
}

:80 {
    coraza_waf {
        load_owasp_crs
        directives `
            Include @coraza.conf-recommended
            Include @crs-setup.conf.example
            Include @owasp_crs/*.conf
            Include /etc/caddy/custom/*.conf
            SecRuleEngine On
        `
    }

    reverse_proxy fake-backend:80 {
        header_up Host {host}
        transport http { dial_timeout 10s; read_timeout 30s }
    }
}
CADDYFILE

# ============================================================
# 4. 创建 Coraza 基础配置
# ============================================================
info "创建 Coraza 配置..."

cat > coraza.conf-recommended << 'CORAZACONF'
SecRuleEngine DetectionOnly
SecRequestBodyAccess On
SecRequestBodyLimit 13107200
SecRequestBodyNoFilesLimit 131072
SecResponseBodyAccess On
SecResponseBodyMimeType text/plain text/html text/xml application/json
SecResponseBodyLimit 524288
SecTmpDir /tmp/coraza/tmp/
SecDataDir /tmp/coraza/data/
SecAuditEngine RelevantOnly
SecAuditLogRelevantStatus "^(?:5|4(?!04))"
SecAuditLogParts ABIJDEFHZ
SecAuditLogType Serial
SecAuditLog /var/log/coraza/audit.log
SecStatusEngine Off
CORAZACONF

# ============================================================
# 5. 创建 OWASP CRS setup
# ============================================================
info "创建 CRS setup..."

cat > crs-setup.conf.example << 'CRSSETUP'
tx.paranoia_level=2
tx.executing_mode=1
tx.blocking_mode=1
tx.allowed_methods=GET|HEAD|POST|OPTIONS|PUT|DELETE|PATCH
tx.max_num_args=255
tx.arg_name_length=100
tx.arg_length=400
tx.inbound_anomaly_score_threshold=5
tx.outbound_anomaly_score_threshold=4
tx.xss_anomaly_score_threshold=3
tx.sql_injection_anomaly_score_threshold=4
tx.inbound_anomaly_score_pl1=3
tx.inbound_anomaly_score_pl2=4
tx.inbound_anomaly_score_pl3=5
tx.inbound_anomaly_score_pl4=6
CRSSETUP

# ============================================================
# 6. 创建 403 拦截页
# ============================================================
info "创建拦截页..."

cat > blocked.html << 'BLOCKEDHTML'
<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="UTF-8"><title>403 - Access Denied</title>
<style>body{font-family:system-ui,sans-serif;background:#f5f5f5;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0}
.c{text-align:center;padding:40px 60px;background:#fff;border-radius:12px;box-shadow:0 2px 20px rgba(0,0,0,.1)}
.h{font-size:72px;font-weight:bold;color:#e74c3c;margin:0}.t{font-size:20px;color:#333;margin:16px 0 8px}
.d{font-size:14px;color:#666;line-height:1.6}.w{display:inline-block;margin-top:20px;padding:4px 12px;background:#fff3cd;color:#856404;border-radius:4px;font-size:12px}</style>
</head><body><div class="c"><p class="h">403</p><h1 class="t">访问被拒绝</h1>
<p class="d">您的请求被 WAF 识别为恶意攻击并已被拦截。<br>如果这是正常访问，请联系网站管理员。</p>
<p class="w">🛡️ Protected by Coraza + Caddy</p></div></body></html>
BLOCKEDHTML

# ============================================================
# 7. 创建自定义规则
# ============================================================
info "创建自定义规则..."
mkdir -p rules/custom

cat > rules/custom/01-protection.conf << 'CUSTOMPROT'
SecRule REQUEST_HEADERS:User-Agent "@rx (?i)(sqlmap|nikto|nmap|masscan|nessus|acunetix|burpsuite|zap|havij|commix)" \
    "id:900001,phase:1,block,t:lowercase,msg:'Scanner UA Blocked',severity:2,tag:scanner"

SecRule REQUEST_URI "@rx (?i)(\.env|\.git/|\.htaccess|\.svn/|web\.config)" \
    "id:900002,phase:1,block,t:lowercase,msg:'Sensitive File Access',severity:2,tag:info_leak"

SecRule REQUEST_URI "@rx (?i)(/phpmyadmin|/administrator|/setup\.php|/install\.php)" \
    "id:900003,phase:1,block,msg:'Admin Path Scan',severity:3,tag:path_traversal"

SecRule ARGS "@rx (?i)(eval\s*\(|assert\s*\(|base64_decode|shell_exec|passthru)" \
    "id:900004,phase:2,block,msg:'Potential WebShell',severity:4,tag:webshell"
CUSTOMPROT

# ============================================================
# 8. 下载 OWASP CRS v4
# ============================================================
info "下载 OWASP CRS v4..."
if [ ! -d rules/owasp-crs/.git ]; then
    git clone --depth 1 --branch v4.0.0 \
        https://github.com/coreruleset/coreruleset.git \
        rules/owasp-crs 2>/dev/null || \
    git clone --depth 1 https://github.com/coreruleset/coreruleset.git \
        rules/owasp-crs
fi

CRS_COUNT=$(ls rules/owasp-crs/rules/*.conf 2>/dev/null | wc -l)
info "OWASP CRS 下载完成，共 $CRS_COUNT 条规则"

# ============================================================
# 9. 创建 docker-compose.yml
# ============================================================
info "创建 docker-compose.yml..."

cat > docker-compose.yml << 'COMPOSEYAML'
version: '3.8'
services:
  fake-backend:
    image: nginx:alpine
    container_name: waf-fake-backend
    command: >
      bash -c 'echo "<h1>✅ IDC Fake Backend - WAF 测试 OK</h1><p>正常请求通过了 WAF</p>" > /usr/share/nginx/html/index.html && nginx -g "daemon off;"'
    networks: [waf-net]

  waf:
    build: .
    container_name: waf-node
    ports: ["80:80"]
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./coraza.conf-recommended:/etc/caddy/coraza.conf-recommended:ro
      - ./crs-setup.conf.example:/etc/caddy/crs-setup.conf.example:ro
      - ./blocked.html:/etc/caddy/blocked.html:ro
      - ./rules/custom:/etc/caddy/custom:ro
      - ./rules/owasp-crs/rules:/etc/coraza/owasp_crs:ro
      - coraza_logs:/var/log/coraza
      - coraza_tmp:/tmp/coraza
      - caddy_data:/data
    depends_on: [fake-backend]
    networks: [waf-net]
    deploy:
      resources:
        limits: {cpus: '2.0', memory: 512M}
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:2019/health"]
      interval: 30s; timeout: 3s; retries: 3; start_period: 10s

volumes: {coraza_logs: {}, coraza_tmp: {}, caddy_data: {}}
networks: {waf-net: {}}
COMPOSEYAML

# ============================================================
# 10. 清理可能占用 80 端口的服务
# ============================================================
if ss -tlnp 2>/dev/null | grep -q ':80'; then
    warn "80 端口被占用，尝试释放..."
    fuser -k 80/tcp 2>/dev/null || true
fi

# ============================================================
# 11. 构建并启动
# ============================================================
info "构建 Docker 镜像（首次需要几分钟下载依赖）..."
docker compose build

info "启动 WAF..."
docker compose up -d --force-recreate

# 等容器就绪
sleep 5
for i in $(seq 1 20); do
    if curl -s -o /dev/null http://localhost/ 2>/dev/null; then
        info "WAF 已就绪"
        break
    fi
    sleep 2
done

# ============================================================
# 12. 跑测试
# ============================================================
echo ""
echo "════════════════════════════════════════════════════════"
echo "                       自动测试"
echo "════════════════════════════════════════════════════════"
echo ""

PASS=0; FAIL=0

echo -n "测试 1 - 正常请求（应该返回 200）: "
STATUS1=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/)
if [ "$STATUS1" = "200" ]; then
    echo -e "${GREEN}✅ PASS${NC} (HTTP $STATUS1)"; PASS=$((PASS+1))
else
    echo -e "${RED}❌ FAIL${NC} (HTTP $STATUS1)"; FAIL=$((FAIL+1))
fi

echo -n "测试 2 - SQL 注入（应该返回 403）: "
STATUS2=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/?id=1%20OR%201=1")
if [ "$STATUS2" = "403" ]; then
    echo -e "${GREEN}✅ PASS${NC} (HTTP $STATUS2)"; PASS=$((PASS+1))
else
    echo -e "${RED}❌ FAIL${NC} (HTTP $STATUS2)"; FAIL=$((FAIL+1))
fi

echo -n "测试 3 - XSS（应该返回 403）: "
STATUS3=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/?q=<script>alert(1)</script>")
if [ "$STATUS3" = "403" ]; then
    echo -e "${GREEN}✅ PASS${NC} (HTTP $STATUS3)"; PASS=$((PASS+1))
else
    echo -e "${RED}❌ FAIL${NC} (HTTP $STATUS3)"; FAIL=$((FAIL+1))
fi

echo -n "测试 4 - 扫描器 UA（应该返回 403）: "
STATUS4=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "User-Agent: sqlmap/1.5" \
    http://localhost/)
if [ "$STATUS4" = "403" ]; then
    echo -e "${GREEN}✅ PASS${NC} (HTTP $STATUS4)"; PASS=$((PASS+1))
else
    echo -e "${RED}❌ FAIL${NC} (HTTP $STATUS4)"; FAIL=$((FAIL+1))
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo -e "结果: ${GREEN}$PASS 通过${NC} / ${RED}$FAIL 失败${NC}"
echo "════════════════════════════════════════════════════════"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}🎉 全部测试通过！WAF 引擎工作正常！${NC}"
    echo ""
    echo "下一步："
    echo "  1. 确认后把 Caddyfile 里的 fake-backend:80 改成你的 IDC 真实 IP"
    echo "  2. 改 DNS，把域名解析到这台 VPS 的公网 IP"
    echo "  3. Caddy 会自动申请 Let's Encrypt 证书"
else
    echo -e "${RED}有测试失败，请检查日志：${NC}"
    echo "  docker compose logs waf"
fi

echo ""
echo "常用命令:"
echo "  cd $WORKDIR"
echo "  docker compose logs -f waf    # 看 WAF 日志"
echo "  docker compose down           # 停止"
echo "  docker compose up -d          # 启动"
