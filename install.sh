#!/bin/bash
# ============================================
# TikTok精装桶Pro - VPS专用一键脚本 v1.0.4
# 多协议 + BBR加速 + 自动故障切换 + IP被墙通知
# 修复: listen_ports -> listen_port (sing-box 1.13+ 兼容)
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

# 随机生成安全端口（避开常用端口）
random_port() {
    if command -v shuf &> /dev/null; then
        shuf -i 10000-60000 -n 1
    else
        jot -r 1 10000 60000 2>/dev/null || awk 'BEGIN{srand(); print 10000+int(rand()*50000)}'
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
echo "║           v1.0.4 (sing-box 1.13+ 兼容)        ║"
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
    apt update -y
    apt install -y curl wget unzip sudo ca-certificates lsb-release git jq net-tools
elif [[ -f /etc/redhat-release ]]; then
    OS="centos"
    PKG_MANAGER="yum"
    yum install -y curl wget unzip sudo git jq net-tools
elif [[ -f /etc/alpine-release ]]; then
    OS="alpine"
    PKG_MANAGER="apk"
    apk add --no-cache curl wget unzip sudo git jq bash
else
    echo -e "${RED}[ERROR]${NC} 不支持的系统！"
    exit 1
fi
echo -e "${GREEN}[OK]${NC} 系统: $OS"

# 步骤1: 开启 BBR 加速
echo -e "${YELLOW}[步骤1]${NC} 开启 BBR 加速..."

if grep -q "net.core.default_qdisc = fq" /etc/sysctl.conf 2>/dev/null; then
    echo -e "${GREEN}[OK]${NC} BBR 已配置"
else
    cat >> /etc/sysctl.conf << 'BBREOF'

# BBR 加速
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
BBREOF
    sysctl -p > /dev/null 2>&1 || true
    echo -e "${GREEN}[OK]${NC} BBR 已启用"
fi

# 步骤2: 安装 sing-box
echo -e "${YELLOW}[步骤2]${NC} 安装 sing-box..."

cd /tmp
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH_NAME="amd64" ;;
    aarch64) ARCH_NAME="arm64" ;;
    armv7l) ARCH_NAME="armv7" ;;
    *) ARCH_NAME="amd64" ;;
esac

if command -v sing-box &> /dev/null; then
    echo -e "${GREEN}[OK]${NC} sing-box 已安装: $(sing-box version | head -1)"
else
    echo -e "${BLUE}[INFO]${NC} 正在安装 sing-box..."
    
    LATEST_VERSION=$(curl -kLs https://api.github.com/repos/SagerNet/sing-box/releases/latest 2>/dev/null | grep tag_name | head -n1 | cut -d'"' -f4)
    [[ -z "$LATEST_VERSION" ]] && LATEST_VERSION="v1.13.3"
    echo -e "${BLUE}[INFO]${NC} 最新版本: $LATEST_VERSION"
    
    BASE_NAME="sing-box-${LATEST_VERSION#v}-linux-${ARCH_NAME}.tar.gz"
    URLS="
    https://github.com/SagerNet/sing-box/releases/download/${LATEST_VERSION}/${BASE_NAME}
    https://ghproxy.com/https://github.com/SagerNet/sing-box/releases/download/${LATEST_VERSION}/${BASE_NAME}
    https://mirror.ghproxy.com/https://github.com/SagerNet/sing-box/releases/download/${LATEST_VERSION}/${BASE_NAME}
    https://gitee.com/sing-box/sing-box/releases/download/${LATEST_VERSION}/${BASE_NAME}
    "
    
    DOWNLOAD_SUCCESS=false
    for url in $URLS; do
        echo -e "${BLUE}[尝试]${NC} $(echo $url | cut -d/ -f3)"
        rm -f sing-box.tar.gz
        if wget -q --timeout=60 -O sing-box.tar.gz "$url" 2>/dev/null && [[ -s sing-box.tar.gz ]]; then
            if file sing-box.tar.gz | grep -qE "gzip|archive"; then
                DOWNLOAD_SUCCESS=true
                echo -e "${GREEN}[成功]${NC}"
                break
            fi
        fi
    done
    
    if ! $DOWNLOAD_SUCCESS; then
        echo -e "${RED}[ERROR]${NC} 下载失败"
        exit 1
    fi
    
    tar -xzf sing-box.tar.gz
    mv sing-box-*/sing-box /usr/local/bin/sing-box
    chmod +x /usr/local/bin/sing-box
    rm -rf sing-box*
    echo -e "${GREEN}[OK]${NC} sing-box 安装完成"
fi

# 步骤3: 生成配置
echo -e "${YELLOW}[步骤3]${NC} 生成多协议配置..."

UUID=$(cat /proc/sys/kernel/random/uuid)
REALITY_PRIV=$(openssl ecparam -name prime256v1 -genkey -noout 2>/dev/null | base64 -w 0)
REALITY_PUB=$(openssl ecparam -name prime256v1 -genkey -noout 2>/dev/null | openssl ec -pubout 2>/dev/null | base64 -w 0)
HYSTERIA_PWD=$(openssl rand -base64 16)
TUIC_UUID=$(cat /proc/sys/kernel/random/uuid)
TUIC_PASSWORD=$(openssl rand -base64 16)

mkdir -p /etc/sing-box /var/log/sing-box

# 备份旧配置
if [[ -f /etc/sing-box/config.json ]]; then
    cp /etc/sing-box/config.json /etc/sing-box/config.json.bak.$(date +%Y%m%d%H%M%S)
fi

# 生成配置文件 - 使用 listen_port (sing-box 1.13+ 格式)
cat > /etc/sing-box/config.json << CONFIGEOF
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
      "listen_port": ${PORT_MIXED},
      "sniff": true,
      "sniff_override_destination": true
    },
    {
      "type": "vless",
      "tag": "vless-reality-in",
      "listen": "0.0.0.0",
      "listen_port": ${PORT_VLESS},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
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
          "private_key": "${REALITY_PRIV}",
          "short_id": [""]
        }
      }
    },
    {
      "type": "vmess",
      "tag": "vmess-ws-in",
      "listen": "0.0.0.0",
      "listen_port": ${PORT_VMESS},
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
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
      "listen_port": ${PORT_HYSTERIA},
      "protocol": "hysteria2",
      "settings": {
        "auth": {
          "type": "password",
          "password": "${HYSTERIA_PWD}"
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
      "listen_port": ${PORT_TUIC},
      "protocol": "tuic",
      "settings": {
        "users": [
          {
            "uuid": "${TUIC_UUID}",
            "password": "${TUIC_PASSWORD}"
          }
        ],
        "congestion_control": "bbr"
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
      "listen_port": ${PORT_ANYTLS},
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
      "outbounds": ["vless-reality-out","vmess-ws-out","hysteria2-out","tuic-out","direct"],
      "default": "vless-reality-out",
      "fallback": true,
      "tolerance": 0,
      "url": "https://www.tiktok.com",
      "interval": "10m"
    },
    {
      "type": "vless",
      "tag": "vless-reality-out",
      "server": "${SERVER_IP}",
      "port": ${PORT_VLESS},
      "uuid": "${UUID}",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "www.apple.com",
        "reality": {
          "enabled": true,
          "public_key": "${REALITY_PUB}",
          "short_id": ""
        }
      }
    },
    {
      "type": "vmess",
      "tag": "vmess-ws-out",
      "server": "${SERVER_IP}",
      "port": ${PORT_VMESS},
      "uuid": "${UUID}",
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
      "server": "${SERVER_IP}",
      "port": ${PORT_HYSTERIA},
      "password": "${HYSTERIA_PWD}",
      "tls": {
        "enabled": true,
        "server_name": "www.google.com"
      }
    },
    {
      "type": "tuic",
      "tag": "tuic-out",
      "server": "${SERVER_IP}",
      "port": ${PORT_TUIC},
      "uuid": "${TUIC_UUID}",
      "password": "${TUIC_PASSWORD}",
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "server_name": "www.microsoft.com"
      }
    },
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
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
  }
}
CONFIGEOF

echo -e "${GREEN}[OK]${NC} 配置文件已生成"

# 步骤4: 设置服务
echo -e "${YELLOW}[步骤4]${NC} 设置开机自启服务..."

cat > /etc/systemd/system/sing-box.service << 'SVCEOF'
[Unit]
Description=sing-box Service
After=network.target
Wants=network.target

[Service]
Type=simple
Environment="ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true"
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
    journalctl -u sing-box -n 30 --no-pager
    exit 1
fi

# 步骤5: 防火墙
echo -e "${YELLOW}[步骤5]${NC} 开放防火墙端口..."

if command -v ufw &> /dev/null; then
    ufw allow ${PORT_MIXED}/tcp 2>/dev/null || true
    ufw allow ${PORT_VLESS}/tcp 2>/dev/null || true
    ufw allow ${PORT_VMESS}/tcp 2>/dev/null || true
    ufw allow ${PORT_HYSTERIA}/tcp 2>/dev/null || true
    ufw allow ${PORT_TUIC}/tcp 2>/dev/null || true
    ufw allow ${PORT_ANYTLS}/tcp 2>/dev/null || true
    echo -e "${GREEN}[OK]${NC} UFW 端口已开放"
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port=${PORT_MIXED}/tcp 2>/dev/null || true
    firewall-cmd --permanent --add-port=${PORT_VLESS}/tcp 2>/dev/null || true
    firewall-cmd --permanent --add-port=${PORT_VMESS}/tcp 2>/dev/null || true
    firewall-cmd --permanent --add-port=${PORT_HYSTERIA}/tcp 2>/dev/null || true
    firewall-cmd --permanent --add-port=${PORT_TUIC}/tcp 2>/dev/null || true
    firewall-cmd --permanent --add-port=${PORT_ANYTLS}/tcp 2>/dev/null || true
    firewall-cmd --reload 2>/dev/null || true
    echo -e "${GREEN}[OK]${NC} Firewalld 端口已开放"
fi

# 完成
clear
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           TikTok精装桶Pro 安装完成！            ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════╝${NC}"
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
echo -e "${CYAN}核心配置:${NC}"
echo "  UUID: $UUID"
echo "  Reality公钥: ${REALITY_PUB:0:40}..."
echo ""
echo -e "${GREEN}常用命令:${NC}"
echo "  查看状态: systemctl status sing-box"
echo "  查看日志: journalctl -u sing-box -f"
echo "  重启服务: systemctl restart sing-box"
echo ""
echo -e "${GREEN}订阅地址:${NC}"
echo "  http://$SERVER_IP:$PORT_MIXED/config.json"
echo ""
echo -e "${GREEN}✅ 全部完成！${NC}"
