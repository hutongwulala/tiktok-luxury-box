#!/bin/bash
# ============================================
# TikTok精装桶Pro - 交互式安装脚本 v2.1
# 按回车继续，自动继续安装
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 按回车继续
press_enter() {
    echo -e "${YELLOW}按回车继续...${NC}"
    read
}

# 检查root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[错误]${NC} 需要root权限！"
    exit 1
fi

echo -e "${CYAN}=============================================="
echo "  TikTok精装桶Pro - 交互式安装"
echo "==============================================${NC}"

press_enter

# 步骤1: 安装依赖
echo -e "${YELLOW}[步骤1/5]${NC} 安装依赖..."

if [[ -f /etc/debian_version ]]; then
    apt update && apt install -y curl wget unzip sudo git jq net-tools
elif [[ -f /etc/redhat-release ]]; then
    yum install -y curl wget unzip sudo git jq net-tools
elif [[ -f /etc/alpine-release ]]; then
    apk add --no-cache curl wget unzip sudo git jq bash
fi
echo -e "${GREEN}[OK]${NC} 依赖安装完成"

press_enter

# 步骤2: BBR
echo -e "${YELLOW}[步骤2/5]${NC} 开启BBR..."

if ! grep -q "net.core.default_qdisc = fq" /etc/sysctl.conf; then
    cat >> /etc/sysctl.conf << 'EOF'

net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    sysctl -p 2>/dev/null || true
fi
echo -e "${GREEN}[OK]${NC} BBR完成"

press_enter

# 步骤3: 安装sing-box
echo -e "${YELLOW}[步骤3/5]${NC} 安装sing-box..."

if command -v sing-box &>/dev/null; then
    echo -e "${GREEN}[OK]${NC} sing-box已安装: $(sing-box version | head -1)"
else
    cd /tmp
    ARCH=$(uname -m)
    case $ARCH in x86_64) A="amd64" ;; aarch64) A="arm64" ;; armv7l) A="armv7" ;; *) A="amd64" ;; esac
    
    VER=$(curl -kLs https://api.github.com/repos/SagerNet/sing-box/releases/latest 2>/dev/null | grep tag_name | head -n1 | cut -d'"' -f4)
    [[ -z "$VER" ]] && VER="v1.13.3"
    FILE="sing-box-${VER#v}-linux-${A}.tar.gz"
    
    echo "下载: $FILE"
    for url in "https://github.com/SagerNet/sing-box/releases/download/${VER}/${FILE}" "https://ghproxy.com/https://github.com/SagerNet/sing-box/releases/download/${VER}/${FILE}"; do
        echo "尝试: ${url##*//}"
        wget -q --timeout=60 -O sing-box.tar.gz "$url" 2>/dev/null && break
    done
    
    if [[ -f sing-box.tar.gz ]] && file sing-box.tar.gz | grep -qE "gzip|archive"; then
        tar -xzf sing-box.tar.gz
        mv sing-box-*/sing-box /usr/local/bin/sing-box
        chmod +x /usr/local/bin/sing-box
        rm -rf sing-box*
        echo -e "${GREEN}[OK]${NC} sing-box安装完成"
    else
        echo -e "${RED}[错误]${NC} 下载失败"
        exit 1
    fi
fi

press_enter

# 步骤4: 生成配置
echo -e "${YELLOW}[步骤4/5]${NC} 生成配置..."

SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ip.sb 2>/dev/null || echo "未知IP")
echo "服务器IP: $SERVER_IP"

UUID=$(cat /proc/sys/kernel/random/uuid)
echo "UUID: $UUID"

echo "生成Reality密钥..."
KEYS=$(sing-box generate reality-keypair 2>/dev/null || echo "PRIVATE_KEY:xxx\nPUBLIC_KEY:xxx")
REALITY_PRIV=$(echo "$KEYS" | grep PrivateKey: | cut -d: -f2 | tr -d ' ')
REALITY_PUB=$(echo "$KEYS" | grep PublicKey: | cut -d: -f2 | tr -d ' ')
[[ -z "$REALITY_PRIV" ]] && REALITY_PRIV="xxx" && REALITY_PUB="xxx"
echo "Reality公钥: $REALITY_PUB"

echo ""
echo "使用随机端口:"
P_MIXED=$((10000 + RANDOM % 50000))
P_VLESS=$((10000 + RANDOM % 50000))
P_VMESS=$((10000 + RANDOM % 50000))
P_HY2=$((10000 + RANDOM % 50000))
P_TUIC=$((10000 + RANDOM % 50000))

echo "  Mixed:     $P_MIXED"
echo "  VLESS:     $P_VLESS"
echo "  VMess:     $P_VMESS"
echo "  Hysteria2: $P_HY2"
echo "  TUIC:      $P_TUIC"

mkdir -p /etc/sing-box /var/log/sing-box

echo ""
echo "生成配置文件..."

jq -n \
  --arg ip "$SERVER_IP" \
  --arg mixed "$P_MIXED" \
  --arg vless "$P_VLESS" \
  --arg vmess "$P_VMESS" \
  --arg hy2 "$P_HY2" \
  --arg tuic "$P_TUIC" \
  --arg uuid "$UUID" \
  --arg rpriv "$REALITY_PRIV" \
  --arg rpub "$REALITY_PUB" \
  '{
  "log": {"level": "info", "output": "/var/log/sing-box/sing-box.log"},
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "0.0.0.0",
      "listen_port": ($mixed | tonumber),
      "sniff": true,
      "sniff_override_destination": true
    },
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "0.0.0.0",
      "listen_port": ($vless | tonumber),
      "users": [{"uuid": $uuid, "flow": "xtls-rprx-vision"}],
      "tls": {
        "enabled": true,
        "server_name": "www.microsoft.com",
        "reality": {
          "enabled": true,
          "handshake": {"server": "www.microsoft.com", "server_port": 443},
          "private_key": $rpriv,
          "short_id": ["a1b2c3d4"]
        }
      }
    },
    {
      "type": "vmess",
      "tag": "vmess-in",
      "listen": "0.0.0.0",
      "listen_port": ($vmess | tonumber),
      "users": [{"uuid": $uuid}],
      "transport": {"type": "ws", "path": "/vmess-ws"},
      "tls": {"enabled": true, "server_name": "cloudflare.com"}
    },
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "0.0.0.0",
      "listen_port": ($hy2 | tonumber),
      "password": "hy2-password",
      "tls": {"enabled": true, "server_name": "www.google.com"}
    },
    {
      "type": "tuic",
      "tag": "tuic-in",
      "listen": "0.0.0.0",
      "listen_port": ($tuic | tonumber),
      "uuid": $uuid,
      "password": "tuic-password",
      "congestion_control": "bbr",
      "tls": {"enabled": true, "server_name": "www.microsoft.com"}
    }
  ],
  "outbounds": [
    {"type": "direct", "tag": "direct"},
    {"type": "block", "tag": "block"}
  ],
  "route": {"rules": []}
}' > /etc/sing-box/config.json

echo -e "${GREEN}[OK]${NC} 配置已保存"

echo ""
echo "配置文件内容:"
cat /etc/sing-box/config.json

press_enter

# 步骤5: 启动服务
echo -e "${YELLOW}[步骤5/5]${NC} 启动服务..."

cat > /etc/systemd/system/sing-box.service << 'SVCEOF'
[Unit]
Description=sing-box Service
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=10
[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box
sleep 2

if systemctl is-active --quiet sing-box; then
    echo -e "${GREEN}[OK]${NC} 服务启动成功！"
else
    echo -e "${RED}[错误]${NC} 服务启动失败"
    journalctl -u sing-box -n 20 --no-pager
    exit 1
fi

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
echo "  Mixed:     $P_MIXED"
echo "  VLESS:     $P_VLESS"
echo "  VMess:     $P_VMESS"
echo "  Hysteria2: $P_HY2"
echo "  TUIC:      $P_TUIC"
echo ""
echo -e "${CYAN}UUID:${NC} $UUID"
echo -e "${CYAN}Reality公钥:${NC} $REALITY_PUB"
echo ""
echo -e "${GREEN}命令:${NC}"
echo "  状态: systemctl status sing-box"
echo "  日志: journalctl -u sing-box -f"
echo "  重启: systemctl restart sing-box"
echo ""
