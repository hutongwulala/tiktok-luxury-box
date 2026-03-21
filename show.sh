#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

if [[ ! -f /etc/sing-box/config.json ]]; then
    echo -e "${RED}[错误]${NC} 配置文件不存在，请先运行安装脚本"
    exit 1
fi

if ! command -v qrencode &>/dev/null; then
    apt update && apt install -y qrencode 2>/dev/null
fi

echo -e "${CYAN}=============================================="
echo "  TikTok精装桶Pro - 节点信息"
echo "==============================================${NC}"
echo ""

SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "未知IP")
UUID=$(jq -r '.inbounds[] | select(.type=="vless") | .users[0].uuid' /etc/sing-box/config.json 2>/dev/null)
REALITY_PUB=$(jq -r '.inbounds[] | select(.type=="vless") | .tls.reality.short_id[0]' /etc/sing-box/config.json 2>/dev/null)

P_MIXED=$(jq -r '.inbounds[] | select(.type=="mixed") | .listen_port' /etc/sing-box/config.json 2>/dev/null)
P_VLESS=$(jq -r '.inbounds[] | select(.type=="vless") | .listen_port' /etc/sing-box/config.json 2>/dev/null)
P_VMESS=$(jq -r '.inbounds[] | select(.type=="vmess") | .listen_port' /etc/sing-box/config.json 2>/dev/null)
P_HY2=$(jq -r '.inbounds[] | select(.type=="hysteria2") | .listen_port' /etc/sing-box/config.json 2>/dev/null)
P_TUIC=$(jq -r '.inbounds[] | select(.type=="tuic") | .listen_port' /etc/sing-box/config.json 2>/dev/null)

HY2_PASS=$(jq -r '.inbounds[] | select(.type=="hysteria2") | .users[0].password' /etc/sing-box/config.json 2>/dev/null)
TUIC_PASS=$(jq -r '.inbounds[] | select(.type=="tuic") | .users[0].password' /etc/sing-box/config.json 2>/dev/null)

echo -e "${YELLOW}服务器IP:${NC} $SERVER_IP"
echo -e "${YELLOW}UUID:${NC} $UUID"
echo ""
echo -e "${CYAN}端口信息:${NC}"
echo "  Mixed:     $P_MIXED"
echo "  VLESS:     $P_VLESS"
echo "  VMess:     $P_VMESS"
echo "  Hysteria2: $P_HY2"
echo "  TUIC:      $P_TUIC"
echo ""

echo -e "${CYAN}==============================================${NC}"
echo -e "${CYAN}        分享链接 & 二维码${NC}"
echo -e "${CYAN}==============================================${NC}"
echo ""

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}🔗 VLESS Reality (推荐)${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
VLESS_URL="vless://$UUID@$SERVER_IP:$P_VLESS?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pb=$REALITY_PUB&sid=a1b2c3d4&type=tcp&headless=tls#TikTok-VLESS"
echo "$VLESS_URL"
echo ""
echo "$VLESS_URL" | qrencode -t UTF8
echo ""

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}🔗 VMess WebSocket${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
VMESS_JSON="{\"v\":\"2\",\"ps\":\"TikTok-VMess\",\"add\":\"$SERVER_IP\",\"port\":\"$P_VMESS\",\"id\":\"$UUID\",\"net\":\"ws\",\"path\":\"/vmess-ws\",\"tls\":\"tls\"}"
VMESS_LINK="vmess://$(echo -n "$VMESS_JSON" | base64 -w0)"
echo "$VMESS_LINK"
echo ""
echo "$VMESS_LINK" | qrencode -t UTF8
echo ""

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}🔗 Hysteria2${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
HY2_URL="hysteria2://${HY2_PASS}@${SERVER_IP}:${P_HY2}#TikTok-HY2"
echo "$HY2_URL"
echo ""
echo "$HY2_URL" | qrencode -t UTF8
echo ""

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}🔗 TUIC${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
TUIC_URL="tuic://$UUID:${TUIC_PASS}@$SERVER_IP:$P_TUIC?congestion_control=bbr#TikTok-TUIC"
echo "$TUIC_URL"
echo ""
echo "$TUIC_URL" | qrencode -t UTF8
echo ""

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}🔗 Mixed (HTTP/SOCKS5)${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "$SERVER_IP:$P_MIXED"
echo "用户: tiktok"
echo "密码: mixed-password"
echo ""
MIXED_URL="http://tiktok:mixed-password@$SERVER_IP:$P_MIXED"
echo "$MIXED_URL"
echo ""
echo "$MIXED_URL" | qrencode -t UTF8
echo ""
