# TikTok精装桶Pro

> 一键安装，多协议自动切换，IP固定，被墙自动通知

---

## 一键安装

```bash
bash <(curl -Ls https://raw.githubusercontent.com/hutongwulala/tiktok-luxury-box/main/install.sh)
```

---

## 功能特性

| 功能 | 说明 |
|------|------|
| 5协议共存 | VLESS Reality + VMess WS + Hysteria2 + TUIC + Naive |
| BBR加速 | 自动开启 TCP BBR 优化 |
| 随机端口 | 避开默认端口，更安全 |
| 自动切换 | Tolerance=0，IP固定，只有挂了才切换 |
| IP被墙通知 | Telegram Bot 实时推送 |
| 二维码生成 | 支持 Shadowrocket/Stash 等 |
| 订阅地址 | V2Ray / Clash 格式 |

---

## 协议优先级

| 优先级 | 协议 | 特点 |
|--------|------|------|
| 1 | VLESS Reality | 抗检测最强，主协议 |
| 2 | VMess WebSocket | 兼容性好 |
| 3 | Hysteria2 | 高带宽 |
| 4 | TUIC | 速度快 |
| 5 | Naive | 备用 |

---

## 自动切换逻辑

```
正常状态: VLESS Reality（IP固定不变）
    ↓ TikTok检测/封锁
自动切换: VMess WS（IP不变）
    ↓ 也挂了
自动切换: Hysteria2（IP不变）
    ↓ ...以此类推
全部恢复: 自动切回 VLESS Reality
```

**核心：只有彻底挂了才切换，IP始终固定**

---

## 安装前提

### 系统要求

- Debian / Ubuntu ✅
- CentOS / AlmaLinux / RockyLinux ✅
- Alpine Linux ✅

### 推荐VPS

| 服务商 | 线路 | 价格 |
|--------|------|------|
| DMIT | CN2 GIA / 9929 | ¥30/月起 |
| RackNerd | 9929 / 4837 | ¥6/月起 |

---

## 安装步骤

### 1. 连接VPS

```bash
ssh root@你的VPS_IP
```

### 2. 一键安装

复制以下命令，粘贴到终端：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/hutongwulala/tiktok-luxury-box/main/install.sh)
```

### 3. 配置通知（可选）

安装过程中会询问是否开启 Telegram 通知：

1. 在 Telegram 搜索 `@BotFather`，发送 `/newbot`
2. 按提示创建 Bot，获取 **Bot Token**（格式：`123456789:ABCdef...`）
3. 在 Telegram 搜索 `@userinfobot`，发送 `/start`，获取 **Chat ID**
4. 安装时填入即可

### 4. 完成后

安装成功后会显示：
- 订阅地址
- 二维码（终端显示 + PNG文件）
- 各协议端口和配置信息

---

## 客户端使用

### 方法1：订阅地址

| 客户端 | 订阅格式 |
|--------|----------|
| PassWall2 / OpenClash | http://IP:端口/config.json |
| V2RayN / Nekoray | http://IP:端口/config.json |
| Clash Meta | http://IP:端口/clash.yaml |

### 方法2：二维码

安装完成后终端会显示二维码，也可以下载 PNG：

```bash
scp root@你的VPS:/etc/sing-box/qrcodes/*.png ./
```

支持的客户端：
- Shadowrocket ✅
- Stash ✅
- Quantumult X ✅
- Surge ✅

---

## 常用命令

```bash
# 查看服务状态
systemctl status sing-box

# 查看运行日志
journalctl -u sing-box -f

# 重启服务
systemctl restart sing-box

# 查看配置
cat /etc/sing-box/config.json

# IP被墙通知日志
journalctl -u tiktok-monitor -f
```

---

## 目录结构

```
/etc/sing-box/
├── config.json           # 主配置文件
├── config.json.bak.*     # 备份文件
├── clash.yaml           # Clash配置
├── subscription.json     # 订阅配置
└── qrcodes/           # 二维码图片
    ├── 01-vless-reality.png
    ├── 02-vmess-ws.png
    └── 03-shadowsocks.png

/usr/local/bin/
├── sing-box             # 主程序
└── tiktok-ip-monitor.sh # IP监控脚本
```

---

## 故障排查

### 问题1：安装失败

```
请确保：
1. 使用 root 权限运行: sudo su
2. 网络正常
3. 系统是 Debian/Ubuntu/CentOS/Alpine
```

### 问题2：服务启动失败

```bash
# 查看详细日志
journalctl -u sing-box -n 50

# 检查端口是否冲突
netstat -tlnp | grep sing-box
```

### 问题3：二维码不显示

```bash
# 安装 qrencode
apt install qrencode  # Debian/Ubuntu
yum install qrencode   # CentOS

# 查看已生成的二维码
ls /etc/sing-box/qrcodes/
```

### 问题4：Telegram 通知不生效

```bash
# 检查 Token 配置
cat /usr/local/bin/tiktok-ip-monitor.sh | grep TOKEN

# 手动测试发送
curl -X POST "https://api.telegram.org/bot你的TOKEN/sendMessage" \
  -d "chat_id=你的ChatID" \
  -d "text=测试消息"
```

---

## 卸载

```bash
# 停止服务
systemctl stop sing-box tiktok-monitor

# 禁用开机自启
systemctl disable sing-box tiktok-monitor

# 删除文件
rm -rf /etc/sing-box
rm -f /etc/systemd/system/sing-box.service
rm -f /etc/systemd/system/tiktok-monitor.service
rm -f /usr/local/bin/sing-box
rm -f /usr/local/bin/tiktok-ip-monitor.sh
```

---

## 常见问题

**Q: IP会被TikTok检测吗？**
A: 使用 VLESS Reality 协议，抗检测能力很强。

**Q: 多协议切换会改变IP吗？**
A: 不会，所有协议都在同一台服务器，IP始终固定。

**Q: 服务器挂了怎么办？**
A: IP被墙后 Telegram 会通知你，备用方案是再买一台VPS。

**Q: 可以同时用几台设备？**
A: 可以，订阅地址可以多人共享。

---

## 对比同类项目

| 功能 | 本项目 | yonggekkk/sing-box-yg |
|------|--------|------------------------|
| BBR自动开启 | ✅ | ❌ |
| 随机端口 | ✅ | ✅ |
| 自动协议切换 | ✅ | ❌ |
| IP被墙通知 | ✅ | ❌ |
| 二维码生成 | ✅ | ✅ |
| TikTok专属优化 | ✅ | ❌ |

---

## 免责声明

本工具仅供技术研究和学习使用，请遵守当地法律法规。

---

## 更新日志

### v1.0.0
- 初始版本发布
- 支持5协议共存
- BBR自动加速
- 自动故障切换
- IP被墙Telegram通知
- 二维码生成
