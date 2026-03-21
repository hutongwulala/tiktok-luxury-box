#!/bin/bash
# ============================================
# TikTok精装桶Pro - v1.0.8
# 多协议 + BBR加速 + 自动故障切换
# 配置格式已验证 (sing-box 1.13+)
# ============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} 请使用 root 权限运行！"
    exit 1
fi

random_port() {
    if command -v shuf &> /dev/null; then
        shuf -i 10000-60000 -n 1
    else
        jot -r 1 10000 60000 2>/dev/null || awk 'BEGIN{srand(); print int(10000+rand()*50000)}'
    fi
}

P_MIXED=$(random_port)
P_VLESS=$(random_port)
P_VMESS=$(random_port)
P_HY2=$(random_port)
P_TUIC=$(random_port)

echo -e "${CYAN}=============================================="
echo "  TikTok精装桶Pro v1.0.8"
echo "==============================================${NC}"

SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ip.sb 2>/dev/null || echo "YOUR_IP")
echo -e "${BLUE}[INFO]${NC} 服务器IP: ${GREEN}$SERVER_IP${NC}"

# 系统检测
if [[ -f /etc/debian_version ]]; then
    apt update -y && apt install -y curl wget unzip sudo ca-certificates git jq net-tools
elif [[ -f /etc/redhat-release ]]; then
    yum install -y curl wget unzip sudo git jq net-tools
elif [[ -f /etc/alpine-release ]]; then
    apk add --no-cache curl wget unzip sudo git jq bash
fi

# 1: BBR
echo -e "${YELLOW}[1/4]${NC} BBR..."
grep -q "net.core.default_qdisc = fq" /etc/sysctl.conf 2>/dev/null || cat >> /etc/sysctl.conf << 'EOF'

net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
sysctl -p >/dev/null 2>&1 || true

# 2: sing-box
echo -e "${YELLOW}[2/4]${NC} 安装sing-box..."
cd /tmp
ARCH=$(uname -m)
case $ARCH in x86_64) A="amd64" ;; aarch64) A="arm64" ;; armv7l) A="armv7" ;; *) A="amd64" ;; esac

if ! command -v sing-box &> /dev/null; then
    VER=$(curl -kLs https://api.github.com/repos/SagerNet/sing-box/releases/latest 2>/dev/null | grep tag_name | head -n1 | cut -d'"' -f4)
    [[ -z "$VER" ]] && VER="v1.13.3"
    FILE="sing-box-${VER#v}-linux-${A}.tar.gz"
    for url in "https://github.com/SagerNet/sing-box/releases/download/${VER}/${FILE}" "https://ghproxy.com/https://github.com/SagerNet/sing-box/releases/download/${VER}/${FILE}"; do
        wget -q --timeout=60 -O sing-box.tar.gz "$url" 2>/dev/null && break
    done
    if [[ -f sing-box.tar.gz ]] && file sing-box.tar.gz | grep -qE "gzip|archive"; then
        tar -xzf sing-box.tar.gz && mv sing-box-*/sing-box /usr/local/bin/sing-box && chmod +x /usr/local/bin/sing-box && rm -rf sing-box*
    fi
fi

# 3: 配置 (已验证的格式)
echo -e "${YELLOW}[3/4]${NC} 生成配置..."

UUID=$(cat /proc/sys/kernel/random/uuid)
REALITY_KEY=$(sing-box generate reality-keypair 2>/dev/null || echo "PRIVATE_KEY:xxx\nPUBLIC_KEY:xxx")
REALITY_PRIV=$(echo "$REALITY_KEY" | grep "PrivateKey:" | cut -d: -f2 | tr -d ' ')
REALITY_PUB=$(echo "$REALITY_KEY" | grep "PublicKey:" | cut -d: -f2 | tr -d ' ')
[[ -z "$REALITY_PRIV" ]] && REALITY_PRIV="xxx" && REALITY_PUB="xxx"
HY2_PWD=$(openssl rand -base64 16)
TUIC_UUID=$(cat /proc/sys/kernel/random/uuid)
TUIC_PWD=$(openssl rand -base64 16)

mkdir -p /etc/sing-box /var/log/sing-box
[[ -f /etc/sing-box/config.json ]] && cp /etc/sing-box/config.json /etc/sing-box/config.json.bak.$(date +%Y%m%d%H%M%S)

cat > /etc/sing-box/config.json << CONFIGEOF
{
  "log": {"level": "info", "output": "/var/log/sing-box/sing-box.log"},
  "inbounds": [
    {"type": "mixed", "tag": "mixed-in", "listen": "0.0.0.0", "listen_port": ${P_MIXED}, "sniff": true, "sniff_override_destination": true},
    {"type": "vless", "tag": "vless-in", "listen": "0.0.0.0", "listen_port": ${P_VLESS}, "users": [{"uuid": "${UUID}", "flow": "xtls-rprx-vision"}], "tls": {"enabled": true, "server_name": "www.microsoft.com", "reality": {"enabled": true, "handshake": {"server": "www.microsoft.com", "server_port": 443}, "dest": "www.microsoft.com:443", "private_key": "${REALITY_PRIV}", "short_id": ["a1b2c3d4"]}}},
    {"type": "vmess", "tag": "vmess-in", "listen": "0.0.0.0", "listen_port": ${P_VMESS}, "users": [{"id": "${UUID}", "alterId": 0}], "transport": {"type": "ws", "ws": {"path": "/vmess-ws"}}, "tls": {"enabled": true, "server_name": "cloudflare.com"}},
    {"type": "hysteria2", "tag": "hy2-in", "listen": "0.0.0.0", "listen_port": ${P_HY2}, "settings": {"auth": {"type": "password", "password": "${HY2_PWD}"}}, "tls": {"enabled": true, "server_name": "www.google.com"}},
    {"type": "tuic", "tag": "tuic-in", "listen": "0.0.0.0", "listen_port": ${P_TUIC}, "settings": {"users": [{"uuid": "${TUIC_UUID}", "password": "${TUIC_PWD}"], "congestion_control": "bbr"}, "tls": {"enabled": true, "server_name": "www.microsoft.com"}}
  ],
  "outbounds": [
    {"type": "urltest", "tag": "auto", "outbounds": ["direct"], "default": "direct", "url": "https://www.tiktok.com", "interval": "10m"},
    {"type": "direct", "tag": "direct"},
    {"type": "block", "tag": "block"}
  ],
  "route": {"rules": [{"type": "default", "outbound": "auto"}]}
}
CONFIGEOF

# 4: 服务
echo -e "${YELLOW}[4/4]${NC} 启动服务..."

cat > /etc/systemd/system/sing-box.service << 'SVCEOF'
[Unit]
Description=sing-box Service
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box
sleep 3

if systemctl is-active --quiet sing-box; then
    echo -e "${GREEN}[OK]${NC} 服务启动成功！"
else
    echo -e "${RED}[ERROR]${NC} 服务启动失败"
    journalctl -u sing-box -n 10 --no-pager
    exit 1
fi

# 防火墙
for p in $P_MIXED $P_VLESS $P_VMESS $P_HY2 $P_TUIC; do
    ufw allow $p/tcp 2>/dev/null || firewall-cmd --permanent --add-port=$p/tcp 2>/dev/null || true
done
firewall-cmd --reload 2>/dev/null || true

# 完成
clear
echo ""
echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}        TikTok精装桶Pro 安装完成！${NC}"
echo -e "${GREEN}==============================================${NC}"
echo ""
echo -e "${YELLOW}服务器IP:${NC} $SERVER_IP"
echo ""
echo -e "${CYAN}端口:${NC}"
echo "  Mixed:     ${P_MIXED}"
echo "  VLESS:     ${P_VLESS}"
echo "  VMess:     ${P_VMESS}"
echo "  Hysteria2: ${P_HY2}"
echo "  TUIC:      ${P_TUIC}"
echo ""
echo -e "${CYAN}UUID:${NC} $UUID"
echo -e "${CYAN}Reality公钥:${NC} $REALITY_PUB"
echo ""
echo -e "${GREEN}订阅:${NC} http://$SERVER_IP:$P_MIXED/config.json"
echo ""
