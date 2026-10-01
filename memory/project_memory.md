# WAF 项目记忆（禁止存 C 盘！）

> 所有项目相关记忆、决策、上下文只保存在 `E:\code\domain\Waf\memory\` 下

---

## 项目概述

自托管 WAF（Web Application Firewall）系统，面向 **IDC 虚拟主机场景**（无 root 权限、仅开放 80/443），同时支持跨服务器、跨站点防护。

## 核心架构

- **控制平面 + 数据平面分离**
- 数据平面：**Caddy + coraza-caddy v2**（Coraza WAF 引擎嵌入 Caddy）+ OWASP CRS v4
- 控制平面：Go API + Vue 3 管理界面（Phase 2 实现）
- 分布式：多节点 + Redis 状态同步 + gRPC 配置下发（Phase 3）

## 关键技术决策

| 决策 | 选择 | 理由 |
|-----|------|------|
| **反向代理** | **Caddy 2.11** | coraza-caddy 官方支持，自动 HTTPS，配置简洁 |
| WAF 引擎 | coraza-caddy v2 + Coraza (Go) | OWASP 官方，ModSecurity 兼容，高性能 |
| 规则集 | OWASP CRS v4 | 社区维护，2000+ 规则，覆盖 OWASP Top 10 |
| GeoIP | MaxMind GeoLite2 (mmdb) | 业界标杆，本地零延迟 |
| 状态存储 | Redis | 频率限制、IP 黑白名单（Phase 2） |
| 日志存储 | coraza-caddy 审计日志 → PostgreSQL（Phase 2）|
| **部署模式** | **CNAME 接入（反向代理）** | 虚拟主机零修改，DNS 切换即可 |

## 重要架构发现（教训）

**Coraza 没有原生 OpenResty/Nginx 模块！** 
- Coraza 官方支持 Caddy（coraza-caddy v2）、Envoy、HAProxy
- 没有 OpenResty/Lua 集成方式
- 所以 Phase 1 从 OpenResty **改为 Caddy**，这是正确选择
- Caddy 本身就是反代 + TLS + HTTP 解析，加上 coraza-caddy 插件 = 完整 WAF

## 部署模式

### 主方案：CNAME 接入（虚拟主机）
```
浏览器 → DNS(CNAME) → Caddy+Coraza WAF VPS:80 → proxy_pass → IDC 虚拟主机:80
```
- IDC 虚拟主机零感知
- 只需 DNS 控制权 + 一台公网 VPS
- .htaccess IP 白名单可缓解真实 IP 泄露风险

## WAF 自身安全（Fail-Open 优先）

1. **故障保护**：Caddy 健康检查、coraza 超时 → 流量放行
2. **资源隔离**：Docker 2核/512M 硬限制
3. **管理平面隔离**：Phase 2 实现
4. **规则沙箱**：规则 Monitor 模式跑 7 天 + 正则超时
5. **高可用**：DNS 轮询多节点（Phase 3）

## Phase 1 已落地文件结构

```
E:\code\domain\Waf\
├── README.md                       ← 根项目说明
├── docs/
│   ├── README.md                   ← 完整架构设计（已更新为 Caddy）
│   └── deployment.md               ← 部署指南
├── memory/
│   └── project_memory.md           ← 本文件
├── .gitignore
│
├── data-plane/                     ← 数据平面（已完整落地）
│   ├── README.md                   ← Phase 1 快速开始
│   ├── Dockerfile                  ← caddy:2.11-builder + xcaddy + coraza-caddy/v2
│   ├── Caddyfile                    ← 站点 + coraza_waf + reverse_proxy 配置
│   ├── coraza.conf-recommended     ← Coraza 基础配置
│   ├── crs-setup.conf.example      ← OWASP CRS 全局设置
│   ├── blocked.html                 ← 403 拦截页面
│   └── rules/
│       ├── custom/
│       │   └── 01-protection.conf  ← 8 条自定义规则（扫描器/敏感文件/CC/WebShell等）
│       └── owasp-crs/               ← 需要 git clone --branch v4.0.0 下载
│
└── deploy/
    ├── docker-compose.yml          ← 一键启动（含 Redis 预留注释）
    ├── init.sh                     ← 下载 OWASP CRS（Linux）
    └── init.cmd                     ← 下载 OWASP CRS（Windows）
```

## Phase 1 启动步骤

```bash
# 1. 下载 OWASP CRS v4
bash deploy/init.sh

# 2. 编辑 Caddyfile — 改域名和 IDC IP
vim data-plane/Caddyfile

# 3. 启动
docker compose -f deploy/docker-compose.yml up -d --build

# 4. 测试
curl -H "Host: yourdomain.com" http://localhost/
curl -H "Host: yourdomain.com" "http://localhost/?id=1%20OR%201=1"  # 应返回 403
```

## 开发阶段

- **Phase 1**：✅ Caddy + coraza-caddy + OWASP CRS v4（文件已落地，待 Linux 服务器验证）
- Phase 2：多站点 + Redis 状态同步 + Web 管理界面
- Phase 3：分布式 + 控制平面 + gRPC 配置下发
- Phase 4：高级特性（Bot/网页防篡改/威胁情报）

## 注意事项

- coraza-caddy v2 是 Coraza 官方维护的 Caddy 插件，替代 coraza-nginx（不存在）
- 构建用 `caddy:2.11-builder` + `xcaddy build --with github.com/corazawaf/coraza-caddy/v2`
- OWASP CRS v4 推荐 git clone --branch v4.0.0，不用 master
- Caddy 的 coraza_waf 指令必须 `order coraza_waf first` 排在最前面
- SecRuleEngine 初始用 DetectionOnly（只记录），跑 7 天再切 On（拦截）
- ModSecurity v2 2024 年停止开发，Coraza 是官方替代
- 当前开发机 Windows 没有 Docker，Phase 1 需要在 Linux VPS 上验证
