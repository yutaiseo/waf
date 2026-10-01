# WAF Phase 1 — Caddy + Coraza + OWASP CRS

这是 WAF 系统的数据平面（反代 + WAF 检测引擎），作为 Docker 容器运行。

## 架构

```
客户端
  │
  ▼
┌─────────────────────────┐
│ Caddy + coraza-caddy v2  │  ← 本容器
│ (反向代理 + WAF 引擎)     │
│                          │
│ coraza_waf {             │
│   load_owasp_crs         │  ← OWASP CRS v4 规则集
│   directives `...`       │  ← 包含自定义规则
│ }                        │
│                          │
│ reverse_proxy            │  ← 回源到 IDC 虚拟主机
└──────────┬──────────────┘
           │ proxy_pass http://IDC_IP:80
           ▼
┌─────────────────────────┐
│ IDC 虚拟主机              │
│ (你无法修改的那个服务器)    │
└─────────────────────────┘
```

## 快速开始（3 步）

### 1. 准备环境

需要：Linux x86_64 VPS（1核 1G 最低）、Docker 24+、Docker Compose v2

```bash
# 克隆项目
git clone https://github.com/your-org/waf.git /opt/waf
cd /opt/waf

# 下载 OWASP CRS v4 规则集
git clone --depth 1 --branch v4.0.0 https://github.com/coreruleset/coreruleset.git rules/owasp-crs
```

### 2. 修改配置

编辑 `Caddyfile`：

```caddy
# 把 yourdomain.com 改成你的真实域名
# 把 123.45.67.89 改成 IDC 虚拟主机的真实 IP

yourdomain.com, www.yourdomain.com {
    coraza_waf {
        load_owasp_crs
        directives `
            Include @coraza.conf-recommended
            Include @crs-setup.conf.example
            Include @owasp_crs/*.conf
            SecRuleEngine On
        `
    }

    reverse_proxy 123.45.67.89:80 {
        header_up X-Real-IP {remote.host}
        header_up X-Forwarded-For {remote.host}
        header_up X-Forwarded-Proto {scheme}
    }
}
```

### 3. 启动 + 测试

```bash
# 构建并启动
docker compose up -d --build

# 正常访问应该能看到 IDC 网站内容
curl -H "Host: yourdomain.com" http://localhost/

# SQL 注入测试 — 应该返回 403
curl -H "Host: yourdomain.com" "http://localhost/?id=1%20OR%201=1"
# 或 PowerShell:
# curl.exe -H "Host: yourdomain.com" "http://localhost/?id=1%20OR%201=1"

# XSS 测试 — 应该返回 403
curl -H "Host: yourdomain.com" "http://localhost/?q=<script>alert(1)</script>"

# 查看拦截日志
docker compose logs -f caddy | grep -i "coraza\|denied"
```

### 4. 改 DNS（最后一步！）

确认本地测试通过后：
1. 登录域名 DNS 管理面板
2. 把 `yourdomain.com` 的 A 记录从 IDC IP 改成 WAF VPS 的公网 IP
3. DNS 生效后（几分钟到几小时），浏览器直接访问你的域名

## 配置模式

WAF 有三种运行模式，通过 Caddyfile 中的 `SecRuleEngine` 控制：

| 模式 | 指令 | 效果 | 推荐场景 |
|-----|------|------|---------|
| **拦截**（生产） | `SecRuleEngine On` | 匹配规则 → 403 | 确认规则稳定后 |
| **监控**（试运行） | `SecRuleEngine DetectionOnly` | 只记录不拦截 | 首次部署，避免误伤 |
| **绕过**（紧急） | `SecRuleEngine Off` | 完全关闭检测 | 规则异常导致业务不可用时 |

建议：**先 DetectionOnly 跑 7 天**，看日志里有没有误报，确认没问题再切 On。

## 自定义规则

在 `rules/custom/` 目录下创建 `.conf` 文件，Caddyfile 的 directives 里会自动 Include。

示例 `rules/custom/sql-protect.conf`：
```
# 自定义规则 ID 从 900000 开始，避免和 CRS 冲突

# 强制某些路径走严格模式
SecRule REQUEST_URI "@streq /api/v1/user/login" \
    "id:900001,\
    phase:1,\
    pass,\
    setvar:'tx.paranoia_level=4',\
    msg:'API Login path — strict mode enabled'"

# 封禁特定 User-Agent
SecRule REQUEST_HEADERS:User-Agent "@rx (sqlmap|nikto|nmap|masscan)" \
    "id:900002,\
    phase:1,\
    block,\
    t:lowercase,\
    msg:'Scanner User-Agent Blocked',\
    severity:2"
```

## IDC 虚拟主机 IP 白名单（重要！）

攻击者可能通过历史 DNS 记录查到 IDC 真实 IP，然后直接访问绕过 WAF。如果是 Apache 虚拟主机，用 FTP 上传 `.htaccess`：

```apache
# .htaccess — 放在网站根目录
# 把 98.76.54.32 改成你的 WAF VPS IP

Order Deny,Allow
Deny from all
Allow from 98.76.54.32
Allow from 127.0.0.1

# Wordpress 后台只允许你的 IP 访问（额外保护）
<FilesMatch "wp-login.php">
    Order Allow,Deny
    Allow from 98.76.54.32
    Allow from 你的公网IP
    Deny from all
</FilesMatch>
```

## 文件说明

```
data-plane/
├── Dockerfile              ← 多阶段构建 Caddy + coraza-caddy
├── Caddyfile               ← 站点 + WAF 配置（你要改的）
├── coraza.conf-recommended ← Coraza 基础配置（一般不改）
├── crs-setup.conf.example  ← OWASP CRS 全局设置（可调 paranoia_level）
├── rules/
│   ├── owasp-crs/          ← git clone 下来的 OWASP CRS v4
│   └── custom/             ← 你写的自定义规则
└── logs/                   ← 运行时日志（docker volume）

deploy/
└── docker-compose.yml      ← 一键启动编排
```

## 常见问题

### Q: 回源超时？
在 Caddyfile 的 `reverse_proxy` 块里加：
```
transport http {
    read_timeout 60s
    dial_timeout 10s
}
```

### Q: 误报太多（正常请求被拦）？
1. 先切 `DetectionOnly` 模式
2. 看日志里哪些规则在拦 → 加白名单
3. 提高 `crs-setup.conf.example` 里的 `tx.paranoia_level`（默认 2，越低越宽松）

### Q: HTTPS 怎么处理？
Caddy 自动处理 HTTPS！只要域名 DNS 已经指向 WAF VPS，Caddy 会自动申请 Let's Encrypt 证书。
IDC 那边：
- 如果 IDC 有 SSL → Caddy 可以 HTTPS 回源：`reverse_proxy https://IDC_IP:443`
- 如果 IDC 只有 HTTP → 正常 HTTP 回源即可（客户端到 WAF 是加密的）

### Q: 真实访客 IP IDC 看不到？
Caddy 会自动设置 `X-Forwarded-For` 头，大部分现代 CMS（WordPress/Typecho/Drupal）会自动读取。
