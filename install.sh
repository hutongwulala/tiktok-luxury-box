#!/bin/bash

# ============================================
# TikTok精装桶Pro - VPS专用一键脚本
# 多协议 + BBR加速 + 自动故障切换 + IP被墙通知
# 适用于：DMIT / RackNerd / 任何 9929/CN2 GIA VPS
# ============================================

set -e

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} 请使用 root 权限运行此脚本！"
    echo -e "${YELLOW}提示: ${NC}运行 'sudo su' 切换到 root 或使用 'sudo bash install.sh'"
    exit 1
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 随机生成安全端口（避开常用端口，兼容macOS和Linux）
random_port() {
    if command -v shuf &> /dev/null; then
        shuf -i 10000-60000 -n 1
    else
        # macOS fallback
        jot -r 1 10000 60000 2>/dev/null || awk -v min=10000 -v max=60000 'BEGIN{srand(); printf "%.0f\n", min+rand()*(max-min)}'
    fi
}

PORT_VLESS=$(random_port)
PORT_VMESS=$(random_port)
PORT_HYSTERIA=$(random_port)
PORT_TUIC=$(random_port)
PORT_ANYTLS=$(random_port)
PORT_MIXED=$(random_port)

echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════════════╗"
echo "║         TikTok精装桶Pro - 一键安装脚本          ║"
echo "║   多协议 + BBR + 自动切换 + IP被墙通知        ║"
echo "╚═══════════════════════════════════════════════════╝"
echo -e "${NC}"

# 获取服务器IP
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ip.sb 2>/dev/null || echo "YOUR_IP")
echo -e "${BLUE}[INFO]${NC} 服务器IP: ${GREEN}$SERVER_IP${NC}"

# 检测系统
echo -e "${BLUE}[INFO]${NC} 检测系统环境..."
if [[ -f /etc/debian_version ]]; then
    OS="debian"
    PKG_MANAGER="apt"
elif [[ -f /etc/redhat-release ]]; then
    OS="centos"
    PKG_MANAGER="yum"
elif [[ -f /etc/alpine-release ]]; then
    OS="alpine"
    PKG_MANAGER="apk"
else
    echo -e "${RED}[ERROR]${NC} 不支持的系统！"
    exit 1
fi
echo -e "${GREEN}[OK]${NC} 系统: $OS"

# ============================================
# 步骤1: 安装基础依赖
# ============================================
echo -e "${YELLOW}"
echo "╔═══════════════════════════════════════════════════╗"
echo "║   步骤1: 安装基础依赖                          ║"
echo "╚═══════════════════════════════════════════════════╝"
echo -e "${NC}"

if [[ "$PKG_MANAGER" == "apt" ]]; then
    apt update -y
    apt install -y curl wget unzip sudo ca-certificates lsb-release git jq net-tools
elif [[ "$PKG_MANAGER" == "yum" ]]; then
    yum install -y curl wget unzip sudo git jq net-tools
elif [[ "$PKG_MANAGER" == "apk" ]]; then
    apk add --no-cache curl wget unzip sudo git jq bash
fi

echo -e "${GREEN}[OK]${NC} 依赖安装完成"

# ============================================
# 步骤2: 开启 BBR 加速
# ============================================
echo -e "${YELLOW}"
echo "╔═══════════════════════════════════════════════════╗"
echo "║   步骤2: 开启 BBR 加速                        ║"
echo "╚═══════════════════════════════════════════════════╝"
echo -e "${NC}"

# 检查并启用 BBR
if grep -q "net.core.default_qdisc = fq" /etc/sysctl.conf 2>/dev/null; then
    echo -e "${GREEN}[OK]${NC} BBR 已配置"
else
    cat >> /etc/sysctl.conf << EOF

# BBR 加速
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    sysctl -p > /dev/null 2>&1
    echo -e "${GREEN}[OK]${NC} BBR 已启用"
fi

# 验证 BBR
if sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
    echo -e "${GREEN}[OK]${NC} BBR 状态: $(sysctl net.ipv4.tcp_congestion_control)"
else
    echo -e "${YELLOW}[WARN]${NC} BBR 可能需要重启生效"
fi

# ============================================
# 步骤3: 安装 sing-box
# ============================================
echo -e "${YELLOW}"
echo "╔═══════════════════════════════════════════════════╗"
echo "║   步骤3: 安装 sing-box 多协议                  ║"
echo "╚═══════════════════════════════════════════════════╝"
echo -e "${NC}"

# 下载 sing-box
cd /tmp
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH_NAME="amd64" ;;
    aarch64) ARCH_NAME="arm64" ;;
    armv7l) ARCH_NAME="armv7" ;;
    *) ARCH_NAME="amd64" ;;
esac

# 尝试多个源
DOWNLOAD_SUCCESS=false
for version in "v1.9.12" "v1.9.11" "v1.9.10" "v1.9.9"; do
    echo -e "${BLUE}[INFO]${NC} 尝试下载 sing-box $version..."
    URL1="https://github.com/SagerNet/sing-box/releases/download/${version}/sing-box-${version#v}-linux-${ARCH_NAME}.tar.gz"
    URL2="https://cdn.jsdelivr.net/gh/SagerNet/sing-box@${version}/download/sing-box-${version#v}-linux-${ARCH_NAME}.tar.gz"
    
    if curl -kL -o sing-box.tar.gz "$URL1" 2>/dev/null && [[ -s sing-box.tar.gz ]]; then
        DOWNLOAD_SUCCESS=true
        break
    fi
    if curl -kL -o sing-box.tar.gz "$URL2" 2>/dev/null && [[ -s sing-box.tar.gz ]]; then
        DOWNLOAD_SUCCESS=true
        break
    fi
done

if ! $DOWNLOAD_SUCCESS; then
    echo -e "${RED}[ERROR]${NC} 下载失败，请检查网络"
    exit 1
fi

tar -xzf sing-box.tar.gz
mv sing-box-*/sing-box /usr/local/bin/sing-box
chmod +x /usr/local/bin/sing-box
rm -rf sing-box*

# 验证安装
sing-box version | head -1
echo -e "${GREEN}[OK]${NC} sing-box 安装完成"

# ============================================
# 步骤4: 生成配置
# ============================================
echo -e "${YELLOW}"
echo "╔═══════════════════════════════════════════════════╗"
echo "║   步骤4: 生成多协议配置                         ║"
echo "╚═══════════════════════════════════════════════════╝"
echo -e "${NC}"

# 生成随机值
UUID=$(cat /proc/sys/kernel/random/uuid)
PSK=$(openssl rand -base64 32)
HYSTERIA_PWD=$(openssl rand -base64 32)
TUIC_UUID=$(cat /proc/sys/kernel/random/uuid)
TUIC_PASSWORD=$(openssl rand -base64 32)

mkdir -p /etc/sing-box /var/log/sing-box

#Reality 配置
REALITY_PUB=$(openssl ecparam -name prime256v1 -genkey -noout 2>/dev/null | openssl ec -pubout 2>/dev/null | base64 -w 0)
REALITY_PRIV=$(openssl ecparam -name prime256v1 -genkey -noout 2>/dev/null | base64 -w 0)
[[ -z "$REALITY_PUB" ]] && REALITY_PUB="REPLACE_WITH_YOUR_PUBKEY"
[[ -z "$REALITY_PRIV" ]] && REALITY_PRIV="REPLACE_WITH_YOUR_PRIVKEY"

# 生成配置（先备份旧的）
if [[ -f /etc/sing-box/config.json ]]; then
    cp /etc/sing-box/config.json /etc/sing-box/config.json.bak.$(date +%Y%m%d%H%M%S)
    echo -e "${YELLOW}[BACKUP]${NC} 旧配置已备份"
fi

mkdir -p /etc/sing-box

cat > /etc/sing-box/config.json << 'EOF'
{
  "log": {
    "level": "info",
    "output": "/var/log/sing-box/sing-box.log"
  },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "0.0.0.0",
      "listen_ports": {
        "min": MIXED_PORT,
        "max": MIXED_PORT
      },
      "sniff": true,
      "sniff_override_destination": true
    },
    {
      "type": "vless",
      "tag": "vless-reality-in",
      "listen": "0.0.0.0",
      "listen_ports": {
        "min": VLESS_PORT,
        "max": VLESS_PORT
      },
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "UUID_PLACEHOLDER",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "tls": {
        "enabled": true,
        "server_name": "www.apple.com",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "www.apple.com",
            "server_port": 443
          },
          "dest": "www.apple.com:443",
          "private_key": "REALITY_PRIV_PLACEHOLDER",
          "short_id": [
            ""
          ]
        }
      },
      "transport": {
        "type": "tcp"
      }
    },
    {
      "type": "vmess",
      "tag": "vmess-ws-in",
      "listen": "0.0.0.0",
      "listen_ports": {
        "min": VMESS_PORT,
        "max": VMESS_PORT
      },
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "UUID_PLACEHOLDER",
            "alterId": 0
          }
        ]
      },
      "transport": {
        "type": "ws",
        "ws": {
          "path": "/vmess-ws"
        }
      },
      "tls": {
        "enabled": true,
        "server_name": "cloudflare.com"
      }
    },
    {
      "type": "hysteria2",
      "tag": "hysteria2-in",
      "listen": "0.0.0.0",
      "listen_ports": {
        "min": HYSTERIA_PORT,
        "max": HYSTERIA_PORT
      },
      "protocol": "hysteria2",
      "settings": {
        "auth": {
          "type": "password",
          "password": "HYSTERIA_PWD_PLACEHOLDER"
        },
        "bandwidth": {
          "up": 100,
          "down": 100
        }
      },
      "tls": {
        "enabled": true,
        "server_name": "www.google.com"
      }
    },
    {
      "type": "tuic",
      "tag": "tuic-in",
      "listen": "0.0.0.0",
      "listen_ports": {
        "min": TUIC_PORT,
        "max": TUIC_PORT
      },
      "protocol": "tuic",
      "settings": {
        "users": [
          {
            "uuid": "TUIC_UUID_PLACEHOLDER",
            "password": "TUIC_PWD_PLACEHOLDER"
          }
        ],
        "congestion_control": "bbr",
        "udp_relay_mode": "native"
      },
      "tls": {
        "enabled": true,
        "server_name": "www.microsoft.com"
      }
    },
    {
      "type": "naive",
      "tag": "naive-in",
      "listen": "0.0.0.0",
      "listen_ports": {
        "min": ANYTLS_PORT,
        "max": ANYTLS_PORT
      },
      "protocol": "naive",
      "settings": {
        "users": [
          {
            "username": "tiktok",
            "password": "tiktok123"
          }
        ]
      },
      "tls": {
        "enabled": true,
        "server_name": "www.amazon.com"
      }
    }
  ],
  "outbounds": [
    {
      "type": "urltest",
      "tag": "auto-fallback",
      "outbounds": [
        "vless-reality-out",
        "vmess-ws-out",
        "hysteria2-out",
        "tuic-out",
        "direct"
      ],
      "default": "vless-reality-out",
      "fallback": true,
      "tolerance": 0,
      "max_allow_delay": 1500,
      "url": "https://www.tiktok.com",
      "interval": "10m"
    },
    {
      "type": "vless",
      "tag": "vless-reality-out",
      "server": "SERVER_IP_PLACEHOLDER",
      "port": VLESS_PORT,
      "uuid": "UUID_PLACEHOLDER",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "www.apple.com",
        "reality": {
          "enabled": true,
          "public_key": "REALITY_PUB_PLACEHOLDER",
          "short_id": ""
        }
      }
    },
    {
      "type": "vmess",
      "tag": "vmess-ws-out",
      "server": "SERVER_IP_PLACEHOLDER",
      "port": VMESS_PORT,
      "uuid": "UUID_PLACEHOLDER",
      "alterId": 0,
      "security": "auto",
      "transport": {
        "type": "ws",
        "ws": {
          "path": "/vmess-ws"
        }
      },
      "tls": {
        "enabled": true,
        "server_name": "cloudflare.com"
      }
    },
    {
      "type": "hysteria2",
      "tag": "hysteria2-out",
      "server": "SERVER_IP_PLACEHOLDER",
      "port": HYSTERIA_PORT,
      "up_mbps": 100,
      "down_mbps": 100,
      "password": "HYSTERIA_PWD_PLACEHOLDER",
      "tls": {
        "enabled": true,
        "server_name": "www.google.com",
        "insecure": false
      }
    },
    {
      "type": "tuic",
      "tag": "tuic-out",
      "server": "SERVER_IP_PLACEHOLDER",
      "port": TUIC_PORT,
      "uuid": "TUIC_UUID_PLACEHOLDER",
      "password": "TUIC_PWD_PLACEHOLDER",
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "server_name": "www.microsoft.com",
        "insecure": false
      }
    },
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    },
    {
      "type": "dns",
      "tag": "dns-out"
    }
  ],
  "route": {
    "auto_detect_interface": true,
    "rules": [
      {
        "type": "default",
        "outbound": "auto-fallback"
      }
    ]
  },
  "dns": {
    "servers": [
      {
        "tag": "google",
        "address": "tls://8.8.8.8"
      },
      {
        "tag": "cloudflare",
        "address": "https://1.1.1.1/dns-query",
        "detour": "auto-fallback"
      }
    ]
  }
}
EOF

# 替换占位符
sed -i "s/UUID_PLACEHOLDER/$UUID/g" /etc/sing-box/config.json
sed -i "s/SERVER_IP_PLACEHOLDER/$SERVER_IP/g" /etc/sing-box/config.json
sed -i "s/REALITY_PRIV_PLACEHOLDER/$REALITY_PRIV/g" /etc/sing-box/config.json
sed -i "s/REALITY_PUB_PLACEHOLDER/$REALITY_PUB/g" /etc/sing-box/config.json
sed -i "s/HYSTERIA_PWD_PLACEHOLDER/$HYSTERIA_PWD/g" /etc/sing-box/config.json
sed -i "s/TUIC_UUID_PLACEHOLDER/$TUIC_UUID/g" /etc/sing-box/config.json
sed -i "s/TUIC_PWD_PLACEHOLDER/$TUIC_PASSWORD/g" /etc/sing-box/config.json
sed -i "s/MIXED_PORT/$PORT_MIXED/g" /etc/sing-box/config.json
sed -i "s/VLESS_PORT/$PORT_VLESS/g" /etc/sing-box/config.json
sed -i "s/VMESS_PORT/$PORT_VMESS/g" /etc/sing-box/config.json
sed -i "s/HYSTERIA_PORT/$PORT_HYSTERIA/g" /etc/sing-box/config.json
sed -i "s/TUIC_PORT/$PORT_TUIC/g" /etc/sing-box/config.json
sed -i "s/ANYTLS_PORT/$PORT_ANYTLS/g" /etc/sing-box/config.json

echo -e "${GREEN}[OK]${NC} 配置文件已生成"

# ============================================
# 步骤5: 设置系统服务
# ============================================
echo -e "${YELLOW}"
echo "╔═══════════════════════════════════════════════════╗"
echo "║   步骤5: 设置开机自启服务                        ║"
echo "╚═══════════════════════════════════════════════════╝"
echo -e "${NC}"

cat > /etc/systemd/system/sing-box.service << 'SVCEOF'
[Unit]
Description=sing-box Service
After=network.target
Wants=network.target

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

sleep 2

if systemctl is-active --quiet sing-box; then
    echo -e "${GREEN}[OK]${NC} 服务启动成功"
else
    echo -e "${RED}[ERROR]${NC} 服务启动失败，请检查日志"
    journalctl -u sing-box -n 20
    exit 1
fi

# ============================================
# 步骤6: 开放防火墙
# ============================================
echo -e "${YELLOW}"
echo "╔═══════════════════════════════════════════════════╗"
echo "║   步骤6: 开放防火墙端口                         ║"
echo "╚═══════════════════════════════════════════════════╝"
echo -e "${NC}"

# 检查防火墙
if command -v ufw &> /dev/null; then
    ufw allow $PORT_MIXED/tcp
    ufw allow $PORT_VLESS/tcp
    ufw allow $PORT_VMESS/tcp
    ufw allow $PORT_HYSTERIA/tcp
    ufw allow $PORT_TUIC/tcp
    ufw allow $PORT_ANYTLS/tcp
    echo -e "${GREEN}[OK]${NC} UFW 端口已开放"
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port=$PORT_MIXED/tcp
    firewall-cmd --permanent --add-port=$PORT_VLESS/tcp
    firewall-cmd --permanent --add-port=$PORT_VMESS/tcp
    firewall-cmd --permanent --add-port=$PORT_HYSTERIA/tcp
    firewall-cmd --permanent --add-port=$PORT_TUIC/tcp
    firewall-cmd --permanent --add-port=$PORT_ANYTLS/tcp
    firewall-cmd --reload
    echo -e "${GREEN}[OK]${NC} Firewalld 端口已开放"
else
    echo -e "${YELLOW}[SKIP]${NC} 未检测到防火墙，跳过"
fi

# ============================================
# 生成订阅和连接信息
# ============================================
echo -e "${YELLOW}"
echo "╔═══════════════════════════════════════════════════╗"
echo "║   步骤7: 生成连接信息                           ║"
echo "╚═══════════════════════════════════════════════════╝"
echo -e "${NC}"

# 生成 V2Ray/Nekoray 订阅
cat > /etc/sing-box/subscription.json << EOF
[
  {
    "protocol": "vless",
    "tag": "VLESS Reality",
    "server": "$SERVER_IP",
    "port": $PORT_VLESS,
    "uuid": "$UUID",
    "flow": "xtls-rprx-vision",
    "tls": {
      "enabled": true,
      "server_name": "www.apple.com",
      "reality": {
        "enabled": true,
        "public_key": "$REALITY_PUB",
        "short_id": ""
      }
    }
  },
  {
    "protocol": "vmess",
    "tag": "VMess WebSocket",
    "server": "$SERVER_IP",
    "port": $PORT_VMESS,
    "uuid": "$UUID",
    "alterId": 0,
    "transport": {
      "type": "ws",
      "path": "/vmess-ws"
    }
  },
  {
    "protocol": "hysteria2",
    "tag": "Hysteria2",
    "server": "$SERVER_IP",
    "port": $PORT_HYSTERIA,
    "password": "$HYSTERIA_PWD"
  },
  {
    "protocol": "tuic",
    "tag": "TUIC",
    "server": "$SERVER_IP",
    "port": $PORT_TUIC,
    "uuid": "$TUIC_UUID",
    "password": "$TUIC_PASSWORD"
  }
]
EOF

# 生成 Clash Meta 订阅格式
cat > /etc/sing-box/clash.yaml << EOF
port: 7890
socks-port: 7891
allow-lan: true
mode: rule
external-controller: 0.0.0.0:9090

proxies:
  - name: "VLESS-Reality"
    type: vless
    server: $SERVER_IP
    port: $PORT_VLESS
    uuid: $UUID
    flow: xtls-rprx-vision
    tls: true
    servername: www.apple.com
    reality-opts:
      public-key: $REALITY_PUB
      short-id: ""

  - name: "VMess-WS"
    type: vmess
    server: $SERVER_IP
    port: $PORT_VMESS
    uuid: $UUID
    alterId: 0
    cipher: auto
    network: ws
    ws-path: /vmess-ws
    tls: true
    servername: cloudflare.com

  - name: "Hysteria2"
    type: hysteria2
    server: $SERVER_IP
    port: $PORT_HYSTERIA
    password: $HYSTERIA_PWD
    alpn:
      - h3

  - name: "TUIC"
    type: tuic
    server: $SERVER_IP
    port: $PORT_TUIC
    uuid: $TUIC_UUID
    password: $TUIC_PASSWORD
    alpn:
      - h3

proxy-groups:
  - name: "TikTok"
    type: url-test
    proxies:
      - VLESS-Reality
      - VMess-WS
      - Hysteria2
      - TUIC
    url: https://www.tiktok.com
    interval: 300
    tolerance: 0

rules:
  - DOMAIN-SUFFIX,tiktok.com,TikTok
  - DOMAIN-SUFFIX,tik-tokapi.com,TikTok
  - DOMAIN-KEYWORD,tiktok,TikTok
  - MATCH,direct
EOF

# ============================================
# 最终信息输出
# ============================================
clear
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                           ║${NC}"
echo -e "${CYAN}║           ${GREEN}✅ 安装完成！${CYAN}                                    ║${NC}"
echo -e "${CYAN}║                                                           ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}                        连接信息                            ${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}服务器IP:${NC} $SERVER_IP"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}                        协议端口                            ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}协议          端口       优先级   说明${NC}"
echo -e "──────────────────────────────────────────────"
echo -e "VLESS Reality  $PORT_VLESS    ⭐⭐⭐⭐⭐  抗检测最强，主协议"
echo -e "VMess WS      $PORT_VMESS    ⭐⭐⭐⭐   兼容性好"
echo -e "Hysteria2     $PORT_HYSTERIA   ⭐⭐⭐     带宽大"
echo -e "TUIC          $PORT_TUIC    ⭐⭐⭐     速度快"
echo -e "Naive         $PORT_ANYTLS    ⭐⭐       备用"
echo -e "Mixed         $PORT_MIXED   -         全协议代理"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}                        核心配置                            ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}UUID:${NC} $UUID"
echo -e "${CYAN}Reality公钥:${NC} $REALITY_PUB"
echo -e "${CYAN}Reality私钥:${NC} $REALITY_PRIV"
echo -e "${CYAN}Hysteria2密码:${NC} $HYSTERIA_PWD"
echo -e "${CYAN}TUIC UUID:${NC} $TUIC_UUID"
echo -e "${CYAN}TUIC密码:${NC} $TUIC_PASSWORD"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}                        订阅地址                            ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "Nekoray/V2RayN 订阅:"
echo -e "${YELLOW}http://$SERVER_IP:$PORT_MIXED/config.json${NC}"
echo ""
echo -e "Clash Meta 订阅:"
echo -e "${YELLOW}http://$SERVER_IP:$PORT_MIXED/clash.yaml${NC}"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}                        自动切换说明                        ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "• 默认使用 VLESS Reality，IP固定不变"
echo -e "• 每10分钟自动检测 TikTok 可访问性"
echo -e "• Tolerance=0: 只有完全挂了才切换"
echo -e "• 全恢复后自动切回 VLESS"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}                        常用命令                            ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "查看状态:   ${YELLOW}systemctl status sing-box${NC}"
echo -e "查看日志:   ${YELLOW}journalctl -u sing-box -f${NC}"
echo -e "重启服务:   ${YELLOW}systemctl restart sing-box${NC}"
echo -e "停止服务:   ${YELLOW}systemctl stop sing-box${NC}"
echo -e "查看配置:   ${YELLOW}cat /etc/sing-box/config.json${NC}"
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                           ║${NC}"
echo -e "${CYAN}║  ${YELLOW}配置文件已保存: /etc/sing-box/config.json         ${CYAN}       ║${NC}"
echo -e "${CYAN}║  ${YELLOW}Clash配置已保存: /etc/sing-box/clash.yaml        ${CYAN}       ║${NC}"
echo -e "${CYAN}║                                                           ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}提示: 将订阅地址复制到 PassWall2/OpenClash 即可使用${NC}"

# ============================================
# 生成各协议二维码（需要 qrencode）
# ============================================
echo -e "${BLUE}[INFO]${NC} 生成各协议二维码..."

# 安装 qrencode
if command -v qrencode &> /dev/null; then
    QR_INSTALLED=true
else
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        apt install -y qrencode 2>/dev/null && QR_INSTALLED=true || QR_INSTALLED=false
    elif [[ "$PKG_MANAGER" == "yum" ]]; then
        yum install -y qrencode 2>/dev/null && QR_INSTALLED=true || QR_INSTALLED=false
    elif [[ "$PKG_MANAGER" == "apk" ]]; then
        apk add --no-cache qrencode 2>/dev/null && QR_INSTALLED=true || QR_INSTALLED=false
    fi
fi

if $QR_INSTALLED; then
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}                        二维码订阅                        ${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # VLESS Reality QR
    VLESS_URI="vless://$UUID@$SERVER_IP:$PORT_VLESS?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.apple.com&fp=chrome&pb=$REALITY_PUB&sid=&type=tcp&headerType=none#VLESS-Reality-TikTok"
    echo -e "${CYAN}[VLESS Reality]${NC}"
    echo "$VLESS_URI" | qrencode -t UTF8
    echo ""
    
    # VMess QR
    VMESS_JSON="{\"v\":\"2\",\"ps\":\"VMess-WS-TikTok\",\"add\":\"$SERVER_IP\",\"port\":\"$PORT_VMESS\",\"id\":\"$UUID\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"\",\"path\":\"/vmess-ws\",\"tls\":\"tls\"}"
    VMESS_LINK="vmess://$(echo -n "$VMESS_JSON" | base64)"
    echo -e "${CYAN}[VMess WebSocket]${NC}"
    echo "$VMESS_LINK" | qrencode -t UTF8
    echo ""
    
    # Shadowsocks QR (基于 Naive 账号生成)
    SS_LINK="ss://YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXo=$SERVER_IP:$PORT_ANYTLS#SS-TikTok"
    echo -e "${CYAN}[Shadowsocks (Naive)]${NC}"
    echo "$SS_LINK" | qrencode -t UTF8
    echo ""
    
    echo -e "${YELLOW}提示: 用 Shadowrocket/Stash/Quantumult 等扫描上方二维码添加节点${NC}"
    
    # 保存二维码为PNG图片
    mkdir -p /etc/sing-box/qrcodes
    echo "$VLESS_URI" | qrencode -o /etc/sing-box/qrcodes/01-vless-reality.png -s 10
    echo "$VMESS_LINK" | qrencode -o /etc/sing-box/qrcodes/02-vmess-ws.png -s 10
    echo "$SS_LINK" | qrencode -o /etc/sing-box/qrcodes/03-shadowsocks.png -s 10
    
    echo -e "${CYAN}二维码图片已保存到: /etc/sing-box/qrcodes/${NC}"
    ls -la /etc/sing-box/qrcodes/
    echo ""
    echo -e "${YELLOW}下载二维码: scp root@$SERVER_IP:/etc/sing-box/qrcodes/*.png ./${NC}"
else
    echo -e "${YELLOW}[SKIP]${NC} qrencode 未安装，跳过二维码生成"
    echo -e "${YELLOW}提示: 安装 qrencode 后可生成二维码: apt install qrencode${NC}"
fi

echo ""
echo -e "${GREEN}✅ 全部安装完成！${NC}"
echo ""

# ============================================
# IP被墙检测 + Telegram通知
# ============================================
setup_ip_monitor() {
    echo -e "${BLUE}[INFO]${NC} 设置IP被墙监控..."
    
    # 创建监控脚本
    cat > /usr/local/bin/tiktok-ip-monitor.sh << 'MONITOR'
#!/bin/bash
# TikTok IP 被墙检测 + Telegram 通知

BOT_TOKEN="BOT_TOKEN_PLACEHOLDER"
CHAT_ID="CHAT_ID_PLACEHOLDER"
CHECK_URL="https://www.tiktok.com"
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null)

send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=HTML"
}

check_ip() {
    local response=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$CHECK_URL" 2>/dev/null)
    if [[ "$response" != "200" && "$response" != "301" && "$response" != "302" ]]; then
        local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
        send_telegram "🚨 <b>IP被墙警告</b>%0A%0A📍 服务器IP: <code>${SERVER_IP}</code>%0A⏰ 时间: ${timestamp}%0A%0A⚠️ TikTok 无法访问，IP可能被墙！%0A请及时更换IP或备用节点。"
        return 1
    fi
    return 0
}

# 主循环
while true; do
    check_ip
    sleep 300  # 每5分钟检测一次
done
MONITOR

    chmod +x /usr/local/bin/tiktok-ip-monitor.sh
    
    # 创建 systemd 服务
    cat > /etc/systemd/system/tiktok-monitor.service << 'SVCMON'
[Unit]
Description=TikTok IP Monitor Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/tiktok-ip-monitor.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SVCMON

    systemctl daemon-reload
    systemctl enable tiktok-monitor
    systemctl start tiktok-monitor
    
    echo -e "${GREEN}[OK]${NC} IP被墙监控服务已设置"
    echo -e "${YELLOW}[提示]${NC} 请配置 Telegram Bot Token 和 Chat ID"
    echo -e "${YELLOW}[提示]${NC} 编辑文件: /usr/local/bin/tiktok-ip-monitor.sh"
}

# 询问是否开启通知
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}是否开启 IP 被墙 Telegram 通知？${NC}"
echo -e "${YELLOW}(需要先创建 Telegram Bot 获取 Token)${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
read -p "请输入 Telegram Bot Token (直接回车跳过): " bot_token
if [[ -n "$bot_token" ]]; then
    read -p "请输入 Telegram Chat ID: " chat_id
    if [[ -n "$chat_id" ]]; then
        sed -i "s/BOT_TOKEN_PLACEHOLDER/$bot_token/" /usr/local/bin/tiktok-ip-monitor.sh
        sed -i "s/CHAT_ID_PLACEHOLDER/$chat_id/" /usr/local/bin/tiktok-ip-monitor.sh
        setup_ip_monitor
    else
        echo -e "${YELLOW}[SKIP]${NC} 跳过通知配置"
    fi
else
    echo -e "${YELLOW}[SKIP]${NC} 跳过通知配置"
fi
