#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

CHECK_INSTALL() {
    if [[ ! -f /etc/sing-box/config.json ]] || ! systemctl is-active --quiet sing-box 2>/dev/null; then
        return 1
    fi
    return 0
}

INSTALL() {
    echo -e "${CYAN}=============================================="
    echo "  跨境专线盒Pro - 一键安装"
    echo "==============================================${NC}"
    
    echo -e "${YELLOW}[1/5]${NC} 安装依赖..."
    apt update && apt install -y curl wget unzip sudo git jq net-tools openssl qrencode 2>/dev/null
    echo -e "${GREEN}[OK]${NC}"
    
    echo -e "${YELLOW}[2/5]${NC} 开启BBR..."
    if ! grep -q "net.core.default_qdisc = fq" /etc/sysctl.conf; then
        cat >> /etc/sysctl.conf << 'EOFBBR'

net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOFBBR
        sysctl -p 2>/dev/null || true
    fi
    echo -e "${GREEN}[OK]${NC}"
    
    echo -e "${YELLOW}[3/5]${NC} 安装sing-box..."
    if ! command -v sing-box &>/dev/null; then
        cd /tmp
        ARCH=$(uname -m)
        case $ARCH in x86_64) A="amd64" ;; aarch64) A="arm64" ;; *) A="amd64" ;; esac
        
        VER=$(curl -kLs https://api.github.com/repos/SagerNet/sing-box/releases/latest 2>/dev/null | grep tag_name | head -n1 | cut -d'"' -f4)
        [[ -z "$VER" ]] && VER="v1.13.3"
        FILE="sing-box-${VER#v}-linux-${A}.tar.gz"
        
        for url in "https://github.com/SagerNet/sing-box/releases/download/${VER}/${FILE}" "https://ghproxy.com/https://github.com/SagerNet/sing-box/releases/download/${VER}/${FILE}"; do
            wget -q --timeout=60 -O sing-box.tar.gz "$url" 2>/dev/null && break
        done
        
        tar -xzf sing-box.tar.gz && mv sing-box-*/sing-box /usr/local/bin/sing-box && chmod +x /usr/local/bin/sing-box && rm -rf sing-box*
    fi
    echo -e "${GREEN}[OK]${NC} $(sing-box version | head -1)"
    
    echo -e "${YELLOW}[4/5]${NC} 生成配置..."
    
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "未知IP")
    UUID=$(cat /proc/sys/kernel/random/uuid)
    
    KEYS=$(sing-box generate reality-keypair 2>/dev/null || echo "PRIVATE_KEY:xxx PUBLIC_KEY:xxx")
    REALITY_PRIV=$(echo "$KEYS" | grep PrivateKey: | cut -d: -f2 | tr -d ' ')
    REALITY_PUB=$(echo "$KEYS" | grep PublicKey: | cut -d: -f2 | tr -d ' ')
    [[ -z "$REALITY_PRIV" ]] && REALITY_PRIV="xxx" && REALITY_PUB="xxx"
    
    P_MIXED=$((10000 + RANDOM % 50000))
    P_VLESS=$((10000 + RANDOM % 50000))
    P_VMESS=$((10000 + RANDOM % 50000))
    P_HY2=$((10000 + RANDOM % 50000))
    P_TUIC=$((10000 + RANDOM % 50000))
    
    mkdir -p /etc/sing-box /var/log/sing-box /etc/sing-box/certs
    
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout /etc/sing-box/certs/key.pem \
        -out /etc/sing-box/certs/cert.pem \
        -subj "/CN=tiktok-proxy" -days 365 2>/dev/null
    
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
        {"type": "mixed", "tag": "mixed-in", "listen": "0.0.0.0", "listen_port": ($mixed | tonumber), "sniff": true},
        {"type": "vless", "tag": "vless-in", "listen": "0.0.0.0", "listen_port": ($vless | tonumber), "users": [{"uuid": $uuid, "flow": "xtls-rprx-vision"}], "tls": {"enabled": true, "server_name": "www.microsoft.com", "reality": {"enabled": true, "handshake": {"server": "www.microsoft.com", "server_port": 443}, "private_key": $rpriv, "short_id": ["a1b2c3d4"]}}},
        {"type": "vmess", "tag": "vmess-in", "listen": "0.0.0.0", "listen_port": ($vmess | tonumber), "users": [{"uuid": $uuid}], "transport": {"type": "ws", "path": "/vmess-ws"}, "tls": {"enabled": true, "certificate_path": "/etc/sing-box/certs/cert.pem", "key_path": "/etc/sing-box/certs/key.pem"}},
        {"type": "hysteria2", "tag": "hy2-in", "listen": "0.0.0.0", "listen_port": ($hy2 | tonumber), "users": [{"password": "hy2-password"}], "tls": {"enabled": true, "certificate_path": "/etc/sing-box/certs/cert.pem", "key_path": "/etc/sing-box/certs/key.pem"}},
        {"type": "tuic", "tag": "tuic-in", "listen": "0.0.0.0", "listen_port": ($tuic | tonumber), "users": [{"uuid": $uuid, "password": "tuic-password"}], "congestion_control": "bbr", "tls": {"enabled": true, "certificate_path": "/etc/sing-box/certs/cert.pem", "key_path": "/etc/sing-box/certs/key.pem"}}
      ],
      "outbounds": [{"type": "direct", "tag": "direct"}, {"type": "block", "tag": "block"}],
      "route": {"rules": []}
    }' > /etc/sing-box/config.json
    
    echo -e "${GREEN}[OK]${NC} 配置已保存"
    
    echo ""
    echo -e "${YELLOW}按回车启动服务...${NC}"
    read
    
    echo -e "${YELLOW}[5/5]${NC} 启动服务..."
    
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
        curl -sL https://raw.githubusercontent.com/hutongwulala/tiktok-luxury-box/main/show.sh -o /usr/local/bin/tiktok-show && chmod +x /usr/local/bin/tiktok-show
        return 0
    else
        echo -e "${RED}[错误]${NC} 服务启动失败"
        return 1
    fi
}

SHOW_MENU() {
    echo -e "${CYAN}=============================================="
    echo "  跨境专线盒Pro"
    echo "==============================================${NC}"
    echo ""
    echo -e "${YELLOW}  1)${NC} 查看节点链接和二维码"
    echo -e "${YELLOW}  2)${NC} 重启服务"
    echo -e "${YELLOW}  3)${NC} 停止服务"
    echo -e "${YELLOW}  4)${NC} 查看服务状态"
    echo -e "${YELLOW}  5)${NC} 卸载"
    echo -e "${YELLOW}  0)${NC} 退出"
    echo ""
    echo -n "请选择 [0-5]: "
    read choice
    
    case $choice in
        1) SHOW_QR ;;
        2) systemctl restart sing-box && echo -e "${GREEN}[OK]${NC} 服务已重启" ;;
        3) systemctl stop sing-box && echo -e "${GREEN}[OK]${NC} 服务已停止" ;;
        4) systemctl status sing-box | head -10 ;;
        5) UNINSTALL ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效选择${NC}" ;;
    esac
}

SHOW_QR() {
    if ! command -v qrencode &>/dev/null; then
        apt update && apt install -y qrencode 2>/dev/null
    fi
    
    echo -e "${CYAN}=============================================="
    echo "  节点信息"
    echo "==============================================${NC}"
    echo ""
    
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || jq -r '.inbounds[0].listen' /etc/sing-box/config.json 2>/dev/null)
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
    
    echo -n "按回车返回菜单..."
    read
}

UNINSTALL() {
    echo -e "${RED}确定要卸载吗？${NC} (输入 yes 确认)"
    read confirm
    if [[ "$confirm" == "yes" ]]; then
        systemctl stop sing-box
        systemctl disable sing-box
        rm -f /etc/systemd/system/sing-box.service
        rm -rf /etc/sing-box
        rm -f /usr/local/bin/sing-box
        rm -f /usr/local/bin/tiktok-show
        echo -e "${GREEN}卸载完成${NC}"
    fi
}

if CHECK_INSTALL; then
    SHOW_MENU
else
    echo -e "${YELLOW}检测到未安装，是否现在安装？${NC}"
    echo -e "  ${YELLOW}1)${NC} 是，立即安装"
    echo -e "  ${YELLOW}2)${NC} 否，退出"
    echo -n "请选择 [1-2]: "
    read choice
    if [[ "$choice" == "1" ]]; then
        if INSTALL; then
            echo ""
            SHOW_QR
        fi
    else
        exit 0
    fi
fi
