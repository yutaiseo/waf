# WAF — 自托管 Web 应用防火墙

面向 IDC 虚拟主机场景（无 root 权限、仅开放 80/443）的自托管 WAF 系统。

**架构**：Caddy + coraza-caddy v2 + OWASP CRS v4  
**部署**：CNAME 接入（反向代理模式），IDC 零修改  
**语言**：配置层 Caddyfile + SecLang 规则

---

## 目录结构

```
Waf/
├── docs/                           ← 设计文档
│   ├── README.md                   ← 完整架构设计（必读）
│   └── deployment.md               ← 部署指南
│
├── memory/
│   └── project_memory.md           ← 项目记忆（只存 E 盘！）
│
├── data-plane/                     ← 数据平面（反代 + WAF 引擎）
│   ├── Dockerfile                  ← Caddy + coraza-caddy 构建
│   ├── Caddyfile                    ← 站点 + WAF 配置 ★ 你要改的
│   ├── coraza.conf-recommended     ← Coraza 基础配置
│   ├── crs-setup.conf.example      ← OWASP CRS 全局设置
│   ├── blocked.html                 ← WAF 拦截页面
│   ├── README.md                    ← Phase 1 快速开始
│   └── rules/
│       ├── custom/                  ← 自定义规则 ★
│       │   └── 01-protection.conf
│       └── owasp-crs/               ← OWASP CRS v4（git clone 下载）
│
├── deploy/
│   ├── docker-compose.yml           ← 一键启动
│   ├── init.sh                      ← 初始化脚本（Linux）
│   └── init.cmd                      ← 初始化脚本（Windows）
│
└── .gitignore
```

## 快速开始

```bash
# 1. 克隆项目
git clone <this-repo> /opt/waf && cd /opt/waf

# 2. 下载 OWASP CRS v4
bash deploy/init.sh

# 3. 改配置（Caddyfile 里改域名和 IDC IP）
vim data-plane/Caddyfile

# 4. 启动
docker compose -f deploy/docker-compose.yml up -d --build

# 5. 测试
curl -H "Host: yourdomain.com" http://localhost/  # 正常
curl -H "Host: yourdomain.com" "http://localhost/?id=1%20OR%201=1"  # 403

# 6. 改 DNS（最后一步！）
# yourdomain.com A 记录 → WAF VPS 公网 IP
```

详见 [data-plane/README.md](data-plane/README.md)

## 工作原理

```
浏览器 → DNS(CNAME) → WAF VPS:80 → Caddy+Coraza WAF 检测 → 放行 → proxy_pass → IDC 虚拟主机:80
                                      ↓
                                  拦截 → 403 自定义页面
```

## 安全承诺：Fail-Open

WAF 挂了 → 流量放行，不阻塞业务。宁可漏拦，不可拒接。

## 开发阶段

| Phase | 内容 | 状态 |
|-------|------|------|
| **1** | 单机 MVP（Caddy+Coraza+CRS） | ✅ 开发中 |
| 2 | 多站点 + Web 管理界面 | 📋 计划中 |
| 3 | 分布式 + 控制平面 + Redis 状态同步 | 📋 计划中 |
| 4 | 高级特性（Bot/网页防篡改/威胁情报） | 📋 计划中 |

## 参考资料

- [Coraza 官方仓库](https://github.com/corazawaf/coraza)
- [OWASP Core Rule Set](https://coreruleset.org/)
- [Caddy 官方文档](https://caddyserver.com/docs)
- [完整设计文档](docs/README.md)
