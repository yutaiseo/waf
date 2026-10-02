# WAF — 自托管 Web 应用防火墙

面向 IDC 虚拟主机场景（无 root 权限、仅开放 80/443）的自托管 WAF 系统。

---

## 当前状态（2026-10-02）

| Phase | 内容 | 状态 |
|-------|------|------|
| **1** | 单机 MVP（Coraza+Caddy+CRS 引擎验证） | ✅ **技术验证完成** |
| **1.5** | 接入真实 IDC 虚拟主机反代 | 🚧 待执行 |
| **2** | Web 管理界面 + 多站点管理 | 📋 开发中 |
| **3** | 分布式 + 控制平面 + Redis 状态同步 | 📋 计划中 |
| **4** | 高级特性（Bot/网页防篡改/威胁情报） | 📋 计划中 |

### 已验证的核心能力

- ✅ Docker 镜像构建（`caddy:2.11-builder` + xcaddy + coraza-caddy/v2）
- ✅ Caddy + Coraza 启动正常
- ✅ OWASP CRS v4 加载成功（2000+ 规则）
- ✅ SQL 注入 → 403 拦截
- ✅ XSS → 403 拦截
- ✅ 扫描器探测（`.env`） → 403 拦截
- ✅ 正常请求 → 200 放行

### 发现的限制（Coraza + coraza-caddy v2）

- ⚠️ `custom_redirect` 不是 coraza-caddy v2 的有效指令（拦截页面需用 Caddy 层 `handle_errors` 处理）
- ⚠️ 无 GUI，所有配置靠改 Caddyfile
- ⚠️ 生产部署遇到 80/443 端口冲突问题（宝塔 Nginx、SamWaf 共存）

### GUI 方案：SamWaf（临时使用）

在 Phase 2 自研 GUI 完成前，使用 **SamWaf** 提供完整的 Web 管理界面：

```bash
docker run -d --name samwaf --restart=always \
  -p 80:80 -p 26666:26666 \
  -v /www/wwwroot/samwaf/conf:/app/conf \
  -v /www/wwwroot/samwaf/data:/app/data \
  -v /www/wwwroot/samwaf/logs:/app/logs \
  -v /www/wwwroot/samwaf/ssl:/app/ssl \
  samwaf/samwaf:latest

# 初始密码（新版随机生成）：
docker exec samwaf cat /app/data/initial_password.txt
# 或试老版固定密码 admin / admin868
```

SamWaf 访问：`http://VPS_IP:26666`

---

## 目录结构

```
Waf/
├── docs/                           ← 设计文档
│   ├── README.md                   ← 完整架构设计
│   └── deployment.md               ← 部署指南
│
├── memory/
│   └── project_memory.md           ← 项目记忆（只存 E 盘！）
│
├── data-plane/                     ← Coraza 数据平面引擎
│   ├── Dockerfile                  ← Caddy + coraza-caddy 构建
│   ├── Caddyfile                    ← 站点 + WAF 配置
│   ├── coraza.conf-recommended     ← Coraza 基础配置
│   ├── crs-setup.conf.example      ← OWASP CRS 全局设置
│   ├── blocked.html                 ← WAF 拦截页面
│   ├── README.md
│   └── rules/
│       ├── custom/                  ← 自定义规则
│       └── owasp-crs/               ← OWASP CRS v4（git clone）
│
├── deploy/
│   ├── docker-compose.yml
│   ├── baota-compose.yml            ← 宝塔面板专用
│   ├── baota-README.md
│   ├── setup.sh                     ← 一键部署脚本
│   ├── init.sh / init.cmd
│
└── README.md
```

## 快速开始（Coraza 引擎验证）

```bash
# 1. 克隆 + 下载 OWASP CRS
git clone <this-repo> /www/wwwroot/waf && cd /www/wwwroot/waf
mkdir -p rules/owasp-crs
git clone --depth 1 --branch v4.0.0 https://github.com/coreruleset/coreruleset.git rules/owasp-crs

# 2. 构建镜像 + 启动
docker build -t waf-node:latest -f data-plane/Dockerfile .
docker run -d --name waf-node \
  -p 8080:80 \
  -v /www/wwwroot/waf/data-plane/Caddyfile:/etc/caddy/Caddyfile:ro \
  -v /www/wwwroot/waf/data-plane/coraza.conf-recommended:/etc/caddy/coraza.conf-recommended:ro \
  -v /www/wwwroot/waf/data-plane/crs-setup.conf.example:/etc/caddy/crs-setup.conf.example:ro \
  -v /www/wwwroot/waf/rules/owasp-crs/rules:/etc/coraza/owasp_crs:ro \
  --restart=unless-stopped \
  waf-node:latest

# 3. 验证
curl -s http://localhost:8080/                                          # 200 OK
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:8080/?id=1%20OR%201=1"  # 403
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:8080/.env"   # 403
```

## 工作原理

```
浏览器 → DNS → WAF VPS:80 → Caddy + Coraza WAF 检测 → 放行 → 回源到 IDC 虚拟主机:80
                               ↓
                           拦截 → 403
```

## 安全承诺：Fail-Open

WAF 挂了 → 流量放行，不阻塞业务。宁可漏拦，不可拒接。

## 参考资料

- [Coraza 官方仓库](https://github.com/corazawaf/coraza)
- [OWASP Core Rule Set](https://coreruleset.org/)
- [Caddy 官方文档](https://caddyserver.com/docs)
- [SamWaf 官方文档](https://doc.samwaf.com/)
- [完整设计文档](docs/README.md)
