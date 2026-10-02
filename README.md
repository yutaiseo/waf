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

## ⚠️ 关键前提：VPS 防火墙必须开放端口

**VPS 控制台（阿里云/腾讯云/AWS/搬瓦工）的安全组/防火墙必须放行以下端口，否则外部无法访问！**

### Coraza + Caddy（自研方案）

| 端口 | 协议 | 用途 | 必须开放 |
|------|------|------|---------|
| **80** | TCP | HTTP 流量入口（WAF 反代监听） | ✅ 是 |
| **443** | TCP | HTTPS 流量入口 | ⭕ 有 HTTPS 时开放 |
| 2019 | TCP | Caddy Admin API（管理 API，**不要对外开放**，用 SSH 隧道） | ❌ 否 |
| 8080 | TCP | 测试端口（可选） | ❌ 否 |

### SamWaf（GUI 方案）

| 端口 | 协议 | 用途 | 必须开放 |
|------|------|------|---------|
| **80** | TCP | HTTP 流量入口 | ✅ 是 |
| **443** | TCP | HTTPS 流量入口 | ⭕ 有 HTTPS 时开放 |
| **26666** | TCP | **Web 管理界面（浏览器访问 WAF）** | ✅ 是 |

### 宝塔面板自身也需要

| 端口 | 协议 | 用途 |
|------|------|------|
| 8888 | TCP | 宝塔 Web 管理面板（默认） |

### 防火墙配置方法

**云服务商控制台（阿里云示例）**：
```
阿里云控制台 → ECS → 安全组 → 入方向规则 → 添加：
  协议: TCP  端口: 80   授权对象: 0.0.0.0/0  (所有人可访问)
  协议: TCP  端口: 443  授权对象: 0.0.0.0/0
  协议: TCP  端口: 26666 授权对象: 0.0.0.0/0  (SamWaf GUI)
  协议: TCP  端口: 8888 授权对象: 0.0.0.0/0  (宝塔)
```

**Linux 本机防火墙（如果开了）**：
```bash
# Ubuntu UFW
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 26666/tcp
ufw allow 8888/tcp
ufw reload

# CentOS firewalld
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --permanent --add-port=443/tcp
firewall-cmd --permanent --add-port=26666/tcp
firewall-cmd --reload
```

**验证端口是否开放（在本地电脑上执行）**：
```bash
# PowerShell
Test-NetConnection -ComputerName VPS_IP -Port 80
Test-NetConnection -ComputerName VPS_IP -Port 26666

# 或浏览器直接访问
http://VPS_IP:26666   ← 能打开 SamWaf 登录页 = 端口通了
http://VPS_IP          ← 能看到 WAF 响应 = 80 端口通了
```

### 常见坑

| 问题 | 原因 | 解决 |
|------|------|------|
| 容器启动了但浏览器打不开 | 云安全组没放行 80 | 控制台添加规则 |
| `curl localhost` 通但外部 IP 不通 | 本机防火墙（ufw/iptables）拦了 | `ufw allow` |
| 80 端口被宝塔 Nginx 占了 | 两个服务抢同一个端口 | 宝塔面板里停 Nginx |
| 443 端口被占 | 宝塔面板自身的 SSL 监听 | SamWaf 可以改 HTTPS 端口或关掉宝塔 SSL |

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
