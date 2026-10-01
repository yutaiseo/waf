# 部署指南

## Phase 1：单机 MVP 快速部署

### 前置条件

- 一台公网 VPS（1核 1G 最低要求，Linux x86_64）
- VPS 公网 IP（记为 `YOUR_WAF_IP`）
- 域名 DNS 控制权
- Docker 24+ 和 Docker Compose v2

### 步骤

```bash
# 1. 克隆项目
git clone https://github.com/your-org/waf.git /opt/waf
cd /opt/waf

# 2. 下载 OWASP CRS 规则集
git submodule update --init --recursive

# 3. 配置站点
# 编辑 data-plane/openresty/conf/sites/default.conf
# 修改 proxy_pass 为 IDC 虚拟主机的真实 IP:80
# 修改 server_name 为你的域名

# 4. 下载 GeoLite2 数据库
mkdir -p data-plane/openresty/geoip
cd data-plane/openresty/geoip
wget https://git.io/GeoLite2-Country.mmdb
cd -

# 5. 启动
docker compose up -d --build

# 6. 验证
curl -H "Host: yourdomain.com" http://YOUR_WAF_IP/
# → 应该看到 IDC 网站内容

# 7. 攻击测试
curl -H "Host: yourdomain.com" "http://YOUR_WAF_IP/?id=1%20OR%201=1"
# → 应该返回 403 Forbidden

# 8. 改 DNS（最后一步！确认没问题再改）
# 把 yourdomain.com 的 A 记录从 IDC IP 改成 YOUR_WAF_IP
# DNS 生效后（几分钟到几小时），直接浏览器访问 yourdomain.com
```

### 生产环境检查清单

- [ ] 配置 HTTPS 证书（Let's Encrypt 或商业证书）
- [ ] 关闭 ModSecurity 的 `SecStatusEngine`（性能）
- [ ] 规则引擎初始用 Monitor 模式跑一周，再切 Block
- [ ] 配置 .htaccess IP 白名单（IDC 虚拟主机只允许 WAF IP）
- [ ] 设置 crontab 自动更新 GeoLite2
- [ ] 配置 syslog 或 ELK 收集攻击日志
- [ ] 设置 Fail-Open 环境变量（WAF 崩溃时流量放行）

## 常见问题

### Q: OpenResty 回源 IDC 虚拟主机超时？
A: 调大 `proxy_read_timeout` 和 `proxy_connect_timeout`，很多 IDC 响应慢

### Q: 攻击日志里看不到 IDC 真实响应？
A: ModSecurity 默认只检测请求，开启响应检测需要配置 `SecResponseBodyAccess`

### Q: Coraza 规则匹配太慢？
A: 检查 Redis 连接状态，Lua Redis 客户端如果用 TCP 而不是 Unix Socket 会慢
