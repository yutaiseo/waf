# ============================================================
# WAF 数据平面 — Caddy + coraza-caddy + OWASP CRS
# 多阶段构建：builder 阶段用 xcaddy 编译带 Coraza 插件的 Caddy
# 生产阶段复制到干净的 alpine 镜像
# ============================================================

# --- Stage 1: Build ---
FROM caddy:2.11-builder AS builder

# 用 xcaddy 编译 Caddy，嵌入 coraza-caddy v2 插件
# pin 版本确保可复现构建
RUN xcaddy build \
    --with github.com/corazawaf/coraza-caddy/v2

# --- Stage 2: Runtime ---
FROM caddy:2.11

# 从 builder 复制编译好的 caddy 二进制
COPY --from=builder /usr/bin/caddy /usr/bin/caddy

# 设置基础目录权限
RUN mkdir -p /var/log/coraza && \
    touch /var/log/coraza/audit.log && \
    chown -R caddy:caddy /var/log/coraza

# 暴露 80/443
EXPOSE 80 443

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost:2019/health || exit 1

# 默认命令
CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
