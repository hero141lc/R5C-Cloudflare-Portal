#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# 始终在脚本所在目录执行，保证配置为相对路径
cd "$(dirname "$0")"

echo -e "${GREEN}>>> 开始部署 R5C Cloudflare 穿透服务...${NC}"

# 1. 输入 Token 和 UUID
read -p "请输入你的 Cloudflare Tunnel Token: " CF_TOKEN
read -p "请输入 Xray UUID (直接回车可自动生成): " USER_UUID
if [ -z "$USER_UUID" ]; then
    USER_UUID=$(cat /proc/sys/kernel/random/uuid)
fi

# 2. 创建 xray 配置文件（端口与路径选用非常用值，减少冲突与扫描）
cat > xray_config.json <<EOF
{
    "inbounds": [{
        "port": 38472,
        "listen": "0.0.0.0",
        "protocol": "vless",
        "settings": {
            "clients": [{"id": "$USER_UUID"}],
            "decryption": "none"
        },
        "streamSettings": {
            "network": "ws",
            "wsSettings": {"path": "/9k2m"}
        }
    }],
    "outbounds": [{"protocol": "freedom"}]
}
EOF

# 3. 创建 docker-compose.yml
cat > docker-compose.yml <<EOF
version: '3'
services:
  dashdot:
    image: mauricenino/dashdot:latest
    container_name: dashdot
    restart: always
    privileged: true
    volumes:
      - /:/mnt/host:ro
  xray:
    image: teddysun/xray:latest
    container_name: xray
    restart: always
    volumes:
      - ./xray_config.json:/etc/xray/config.json
  tunnel:
    image: cloudflare/cloudflared:latest
    container_name: cf-tunnel
    restart: always
    command: tunnel --no-autoupdate run --token $CF_TOKEN
EOF

# 4. 启动 Docker
docker compose up -d

echo -e "${GREEN}>>> 部署完成！${NC}"
echo -e "${RED}请保存你的 UUID: $USER_UUID${NC}"
echo -e "现在请前往 Cloudflare 网页端配置域名映射。"
