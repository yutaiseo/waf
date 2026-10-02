# ============================================================
# WAF Dockerfile — 多阶段构建
# 阶段1：xcaddy 编译带 coraza 模块的 caddy
# 阶段2：用 caddy:2.11 运行
# ============================================================

# ---------- 阶段 1：编译 ----------
FROM caddy:2.11-builder AS builder

# 编译 Caddy + coraza-caddy v2 模块
# coraza-caddy/v2 对应 Caddy v2 的集成
RUN xcaddy build \
    --with github.com/corazawaf/coraza-caddy/v2 \
    --with github.com/corazawaf/coraza/v3 \
    --with github.com/caddyserver/xcaddy

# ---------- 阶段 2：运行 ----------
FROM caddy:2.11

# 复制编译好的 caddy 二进制
COPY --from=builder /usr/bin/caddy /usr/bin/caddy

# 创建必要目录
RUN mkdir -p /var/log/coraza /var/log/caddy /tmp/coraza /tmp/coraza/tmp /tmp/coraza/data

# 暴露端口
EXPOSE 80 443 2019

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=15s --retries=3 \
    CMD wget -qO- http://localhost:2019/health || exit 1

# 启动
CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
