# ============================================================
# WAF — 宝塔面板一键部署
# ============================================================
# 3 步搞定，全部在宝塔面板里点
# ============================================================

## 前置条件（做一次就行）

### 步骤 1：停掉宝塔 Nginx（释放 80/443 端口）

宝塔面板 → 软件商店 → 已安装 → 找到 Nginx → 点 **停止** 或 **卸载**

### 步骤 2：装 Docker 管理器

宝塔面板 → 软件商店 → 搜索 **Docker** → 安装 Docker 管理器

---

## 一键部署（3 步）

### 步骤 A：上传 WAF 文件

宝塔面板 → 文件 → 进入 `/www/wwwroot/` → 新建文件夹 `waf`

**把以下文件全部放到 `/www/wwwroot/waf/` 下：**

```
/www/wwwroot/waf/
├── Dockerfile
├── Caddyfile
├── coraza.conf-recommended
├── crs-setup.conf.example
├── blocked.html
├── rules/
│   ├── custom/
│   │   └── 01-protection.conf
│   └── owasp-crs/            ← 需要 git clone
│       └── rules/
│           ├── 941100-sqli.conf
│           ├── 941200-sqli.conf
│           └── ...（v4 全部规则文件）
└── docker-compose.yml
```

**OWASP CRS 规则下载**（在 VPS 终端执行）：
```bash
cd /www/wwwroot/waf
git clone --depth 1 --branch v4.0.0 https://github.com/coreruleset/coreruleset.git rules/owasp-crs
```

### 步骤 B：粘贴 Docker 编排

宝塔面板 → Docker → 编排 → 新建编排

**名称填**：`waf`

**粘贴以下内容**：

```yaml
version: '3.8'

services:
  waf:
    build:
      context: /www/wwwroot/waf
      dockerfile: Dockerfile
    container_name: waf-node
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /www/wwwroot/waf/Caddyfile:/etc/caddy/Caddyfile:ro
      - /www/wwwroot/waf/coraza.conf-recommended:/etc/caddy/coraza.conf-recommended:ro
      - /www/wwwroot/waf/crs-setup.conf.example:/etc/caddy/crs-setup.conf.example:ro
      - /www/wwwroot/waf/blocked.html:/etc/caddy/blocked.html:ro
      - /www/wwwroot/waf/rules/custom:/etc/caddy/custom:ro
      - /www/wwwroot/waf/rules/owasp-crs/rules:/etc/coraza/owasp_crs:ro
      - /www/wwwroot/waf/logs/coraza:/var/log/coraza
      - /www/wwwroot/waf/logs/caddy:/var/log/caddy
      - /www/wwwroot/waf/data:/data
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 512M
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:2019/health"]
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 15s
    restart: unless-stopped

  fake-backend:
    image: nginx:alpine
    container_name: waf-fake-backend
    command: >
      bash -c 'echo "<h1>✅ Fake Backend OK - WAF 测试通过</h1>" > /usr/share/nginx/html/index.html && nginx -g "daemon off;"'
    restart: unless-stopped

networks:
  default:
    name: waf-net
```

点 **保存**，然后点 **构建并启动**

### 步骤 C：验证

宝塔面板 → Docker → 容器 → 看到 `waf-node` 和 `waf-fake-backend` 都是 **运行中**

VPS 终端测试：
```bash
# 正常请求 → 200
curl -s http://localhost/

# SQL 注入 → 应该 403
curl -s -o /dev/null -w "%{http_code}" "http://localhost/?id=1%20OR%201=1"

# XSS → 应该 403
curl -s -o /dev/null -w "%{http_code}" "http://localhost/?q=<script>alert(1)</script>"
```

---

## 改回源（上线用）

测试通过后，改 `/www/wwwroot/waf/Caddyfile`，把 `fake-backend:80` 改成你的 IDC 虚拟主机真实 IP：

```nginx
# 改之前
reverse_proxy fake-backend:80

# 改之后（假设 IDC IP 是 1.2.3.4）
reverse_proxy 1.2.3.4:80 {
    header_up Host {host}
    header_up X-Real-IP {remote.host}
    header_up X-Forwarded-For {remote.host}
}
```

然后：宝塔 → Docker → 容器 → `waf-node` → 点 **重启**

最后改 DNS：域名解析 A 记录指向这台 VPS 的公网 IP。

---

## 常用操作

| 操作 | 在哪里做 |
|-----|---------|
| 看 WAF 拦截日志 | 宝塔 → Docker → 容器 → waf-node → 日志 |
| 改规则 | 宝塔 → 文件 → `/www/wwwroot/waf/rules/custom/` |
| 改 Caddyfile | 宝塔 → 文件 → `/www/wwwroot/waf/Caddyfile` |
| 重启 WAF | 宝塔 → Docker → 容器 → waf-node → 重启 |
| 停止所有 | 宝塔 → Docker → 编排 → waf → 停止 |
