#!/bin/bash
# ============================================
# TikTok精装桶Pro - VPS专用一键脚本 v1.0.6
# 多协议 + BBR加速 + 自动故障切换
# 修复: 移除inbound中多余的protocol字段 (sing-box 1.13+)
# ============================================

set -e

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} 请使用 root 权限运行此脚本！"
    exit 1
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 随机生成安全端口
random_port() {
    if command -v shuf &> /dev/null; then
        shuf -i 10000-60000 -n 1
    else
        jot -r 1 10000 60000 2>/dev/null || awk 'BEGIN{srand(); print int(10000+rand()*50000)}'
    fi
}

PORT_VLESS=$(random_port)
PORT_VMESS=$(random_port)
PORT_HYSTERIA=$(random_port)
PORT_TUIC=$(random_port)
PORT_ANYTLS=$(random_port)
PORT_MIXED=$(random_port)

echo -e "${CYAN}"
echo "=============================================="
echo "  TikTok精装桶Pro - 一键安装脚本 v1.0.6"
echo "=============================================="
echo -e "${NC}"

# 获取服务器IP
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ip.sb 2>/dev/null || echo "YOUR_IP")
echo -e "${BLUE}[INFO]${NC} 服务器IP: ${GREEN}$SERVER_IP${NC}"

# 检测系统
echo -e "${BLUE}[INFO]${NC} 检测系统..."
if [[ -f /etc/debian_version ]]; then
    PKG_MANAGER="apt"
    apt update -y
    apt install -y curl wget unzip sudo ca-certificates git jq net-tools
elif [[ -f /etc/redhat-release ]]; then
    PKG_MANAGER="yum"
    yum install -y curl wget unzip sudo git jq net-tools
elif [[ -f /etc/alpine-release ]]; then
    PKG_MANAGER="apk"
    apk add --no-cache curl wget unzip sudo git jq bash
else
    echo -e "${RED}[ERROR]${NC} 不支持的系统！"
    exit 1
fi

# 步骤1: BBR
echo -e "${YELLOW}[1/5]${NC} 开启 BBR..."
if ! grep -q "net.core.default_qdisc = fq" /etc/sysctl.conf 2>/dev/null; then
    cat >> /etc/sysctl.conf << 'EOF'

net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    sysctl -p >/dev/null 2>&1 || true
fi
echo -e "${GREEN}[OK]${NC} BBR 完成"

# 步骤2: 安装 sing-box
echo -e "${YELLOW}[2/5]${NC} 安装 sing-box..."
cd /tmp

ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH_NAME="amd64" ;;
    aarch64) ARCH_NAME="arm64" ;;
    armv7l) ARCH_NAME="armv7" ;;
    *) ARCH_NAME="amd64" ;;
esac

if command -v sing-box &> /dev/null; then
    echo -e "${GREEN}[OK]${NC} sing-box 已安装"
else
    LATEST_VERSION=$(curl -kLs https://api.github.com/repos/SagerNet/sing-box/releases/latest 2>/dev/null | grep tag_name | head -n1 | cut -d'"' -f4)
    [[ -z "$LATEST_VERSION" ]] && LATEST_VERSION="v1.13.3"
    BASE_NAME="sing-box-${LATEST_VERSION#v}-linux-${ARCH_NAME}.tar.gz"
    
    for url in \
        "https://github.com/SagerNet/sing-box/releases/download/${LATEST_VERSION}/${BASE_NAME}" \
        "https://ghproxy.com/https://github.com/SagerNet/sing-box/releases/download/${LATEST_VERSION}/${BASE_NAME}"; do
        echo -e "${BLUE}[下载]${NC} ${url##*//}"
        wget -q --timeout=60 -O sing-box.tar.gz "$url" 2>/dev/null && break
    done
    
    if [[ -f sing-box.tar.gz ]] && file sing-box.tar.gz | grep -qE "gzip|archive"; then
        tar -xzf sing-box.tar.gz
        mv sing-box-*/sing-box /usr/local/bin/sing-box
        chmod +x /usr/local/bin/sing-box
        rm -rf sing-box*
        echo -e "${GREEN}[OK]${NC} sing-box 安装完成"
    else
        echo -e "${RED}[ERROR]${NC} 下载失败"
        exit 1
    fi
fi

# 步骤3: 生成配置
echo -e "${YELLOW}[3/5]${NC} 生成配置..."

UUID=$(cat /proc/sys/kernel/random/uuid)
REALITY_PRIV=$(openssl ecparam -name prime256v1 -genkey -noout 2>/dev/null | base64 -w 0)
REALITY_PUB=$(openssl ecparam -name prime256v1 -genkey -noout 2>/dev/null | openssl ec -pubout 2>/dev/null | base64 -w 0)
HYSTERIA_PWD=$(openssl rand -base64 16)
TUIC_UUID=$(cat /proc/sys/kernel/random/uuid)
TUIC_PASSWORD=$(openssl rand -base64 16)

mkdir -p /etc/sing-box /var/log/sing-box

# 备份旧配置
[[ -f /etc/sing-box/config.json ]] && cp /etc/sing-box/config.json /etc/sing-box/config.json.bak.$(date +%Y%m%d%H%M%S)

# 生成配置文件 - 注意: inbound中不要protocol字段,协议类型由type决定
cat > /etc/sing-box/config.json << CONFIGEOF
{
  "log": {"level": "info", "output": "/var/log/sing-box/sing-box.log"},
  "inbounds": [
    {"type": "mixed", "tag": "mixed-in", "listen": "0.0.0.0", "listen_port": ${PORT_MIXED}, "sniff": true, "sniff_override_destination": true},
    {"type": "vless", "tag": "vless-reality-in", "listen": "0.0.0.0", "listen_port": ${PORT_VLESS}, "settings": {"clients": [{"id": "${UUID}", "flow": "xtls-rprx-vision"}], "decryption": "none"}, "tls": {"enabled": true, "server_name": "www.apple.com", "reality": {"enabled": true, "handshake": {"server": "www.apple.com", "server_port": 443}, "dest": "www.apple.com:443", "private_key": "${REALITY_PRIV}", "short_id": [""]}}},
    {"type": "vmess", "tag": "vmess-ws-in", "listen": "0.0.0.0", "listen_port": ${PORT_VMESS}, "settings": {"clients": [{"id": "${UUID}", "alterId": 0}]}, "transport": {"type": "ws", "ws": {"path": "/vmess-ws"}}, "tls": {"enabled": true, "server_name": "cloudflare.com"}},
    {"type": "hysteria2", "tag": "hysteria2-in", "listen": "0.0.0.0", "listen_port": ${PORT_HYSTERIA}, "settings": {"auth": {"type": "password", "password": "${HYSTERIA_PWD}"}}, "tls": {"enabled": true, "server_name": "www.google.com"}},
    {"type": "tuic", "tag": "tuic-in", "listen": "0.0.0.0", "listen_port": ${PORT_TUIC}, "settings": {"users": [{"uuid": "${TUIC_UUID}", "password": "${TUIC_PASSWORD}"}], "congestion_control": "bbr"}, "tls": {"enabled": true, "server_name": "www.microsoft.com"}},
    {"type": "naive", "tag": "naive-in", "listen": "0.0.0.0", "listen_port": ${PORT_ANYTLS}, "settings": {"users": [{"username": "tiktok", "password": "tiktok123"}]}, "tls": {"enabled": true, "server_name": "www.amazon.com"}}
  ],
  "outbounds": [
    {"type": "urltest", "tag": "auto", "outbounds": ["direct"], "default": "direct", "url": "https://www.tiktok.com", "interval": "10m"},
    {"type": "direct", "tag": "direct"},
    {"type": "block", "tag": "block"}
  ],
  "route": {"auto_detect_interface": true, "rules": [{"type": "default", "outbound": "auto"}]}
}
CONFIGEOF

echo -e "${GREEN}[OK]${NC} 配置已生成"

# 步骤4: 设置服务
echo -e "${YELLOW}[4/5]${NC} 设置服务..."

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
    echo -e "${GREEN}[OK]${NC} 服务启动成功"
else
    echo -e "${RED}[ERROR]${NC} 服务启动失败"
    journalctl -u sing-box -n 20 --no-pager
    exit 1
fi

# 步骤5: 防火墙
echo -e "${YELLOW}[5/5]${NC} 开放端口..."

for port in $PORT_MIXED $PORT_VLESS $PORT_VMESS $PORT_HYSTERIA $PORT_TUIC $PORT_ANYTLS; do
    ufw allow $port/tcp 2>/dev/null || firewall-cmd --permanent --add-port=$port/tcp 2>/dev/null || true
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
echo -e "${CYAN}协议端口:${NC}"
echo "  VLESS Reality: ${PORT_VLESS}"
echo "  VMess WS:     ${PORT_VMESS}"
echo "  Hysteria2:    ${PORT_HYSTERIA}"
echo "  TUIC:         ${PORT_TUIC}"
echo "  Naive:        ${PORT_ANYTLS}"
echo "  Mixed:        ${PORT_MIXED}"
echo ""
echo -e "${CYAN}UUID:${NC} $UUID"
echo ""
echo -e "${GREEN}订阅地址:${NC} http://$SERVER_IP:$PORT_MIXED/config.json"
echo ""
echo -e "${GREEN}查看日志:${NC} journalctl -u sing-box -f"
echo ""
