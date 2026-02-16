# R5C-Cloudflare-Portal

基于 Cloudflare Tunnel + Xray VLESS 的穿透与状态面板方案，适合在 R5C 等设备上一键部署：Dashdot 状态页 + 代理隧道，全部通过 Cloudflare 域名对外提供。

---

## 项目结构

| 文件 | 说明 |
|------|------|
| `deploy.sh` | 一键安装脚本：交互输入 Token/UUID、生成配置并启动 Docker |
| `docker-compose.yml` | 容器编排（nginx + dashdot + xray + cloudflared） |
| `nginx/default.conf` | Nginx 配置：`/` → dashdot，`/9k2m` → xray（可由 deploy.sh 生成） |
| `xray_config.example.json` | Xray 配置示例，实际使用的 `xray_config.json` 由 `deploy.sh` 生成 |
| `README.md` | 本说明文档 |

---

## 快速开始

### 1. 环境要求

- Linux 环境（如 R5C 的 OpenWrt/常见发行版）
- 已安装 Docker 与 Docker Compose（`deploy.sh` 可提示安装，但不会自动装 Docker）

### 2. 一键部署

```bash
git clone https://github.com/你的用户名/R5C-Cloudflare-Portal.git
cd R5C-Cloudflare-Portal
chmod +x deploy.sh
./deploy.sh
```

按提示输入：

- **Cloudflare Tunnel Token**：在 [Cloudflare Zero Trust](https://one.dash.cloudflare.com/) → Networks → Tunnels 中创建隧道后复制
- **Xray UUID**：直接回车可自动生成，请务必保存脚本输出的 UUID
- **镜像仓库地址**（可选）：直接回车使用默认源；若填写一个仓库地址（如 `hub.docker.bluepio.com`），则三个镜像（dashdot / xray / cloudflared）均从该仓库拉取，便于使用同一镜像加速或自建仓库

### 3. Cloudflare 网页端配置（单域名）

部署完成后，在 Cloudflare 里用**一个域名**指向 Nginx，由 Nginx 按路径分流：

- **`xxx.com/`** → Dashdot 状态页  
- **`xxx.com/9k2m`** → Xray 代理（WebSocket）

1. 登录 [Cloudflare Zero Trust](https://one.dash.cloudflare.com/)。
2. 进入 **Networks → Tunnels**，找到刚创建、且已在运行的隧道，点击 **Edit**。
3. 打开 **Public Hostname**，添加**一条**映射即可：

| 项 | 值 |
|----|-----|
| Subdomain | 留空或填 `@`（表示根域名） |
| Domain | 选择你的域名（如 `yourdomain.com`） |
| Service | `HTTP://127.0.0.1:19880` |

Tunnel 使用 **host 网络**（使用宿主机 DNS/网络，避免容器内 DNS 无法解析 Cloudflare），Nginx 映射到宿主机 `127.0.0.1:19880`，故此处填 `127.0.0.1:19880`。

**TLS：** 在 **Additional application settings → TLS** 中，内网为 HTTP 时可开启 **No TLS Verify**（按需）。

保存后，访问 `https://你的域名/` 为状态页，同一域名路径 `/9k2m` 为代理入口。

---

## 单域名与 Nginx 分流

本方案用 **Nginx** 做反向代理，实现**一个域名、按路径区分**：

- **Nginx**：对 Cloudflare Tunnel 暴露 80，收到请求后按路径转发。
- **`/`** → 转发到 **dashdot:3001**（状态页）。
- **`/9k2m`** → 转发到 **xray:38472**（VLESS WebSocket），并带上 WebSocket 升级头。

因此 Cloudflare 只需配置**一条** Public Hostname：域名 → `HTTP://127.0.0.1:19880`。Tunnel 使用 host 网络、Nginx 仅监听 127.0.0.1:19880，宿主机 80/443 可不占用。

---

## 朋友连接指南

把下面信息发给使用代理的人（将 `yourdomain.com` 换成你的实际域名，与状态页同域名）：

| 项目 | 值 |
|------|-----|
| **地址 (Address)** | `yourdomain.com` |
| **端口 (Port)** | `443` |
| **传输协议 (Network)** | `ws` |
| **路径 (Path)** | `/9k2m` |
| **TLS** | 开启 |
| **UUID** | 部署时脚本生成并输出的那个（或你自行填写的） |

客户端协议选择 **VLESS**，按上表填写即可。状态页与代理共用同一域名，仅路径不同（`/` 与 `/9k2m`）。

---

## 手动部署（不用 deploy.sh）

若已持有 Token 和 UUID，可手动操作：

1. 复制 `xray_config.example.json` 为 `xray_config.json`，将 `"id"` 改为你的 UUID。
2. 设置环境变量并启动：
   ```bash
   export CF_TOKEN=你的Cloudflare_Tunnel_Token
   docker compose up -d
   ```

---

## 镜像拉取失败（超时 / 国内网络）

若出现 `request canceled`、`Client.Timeout exceeded` 或 `dial tcp ... i/o timeout`，多为 Docker 无法直连 Docker Hub。

**重要**：你在终端里配置的代理（如 `export http_proxy=...`）只对当前 shell 生效，**Docker 守护进程不会使用**。拉取镜像的是 Docker daemon，需要单独为 Docker 配置代理。

### 让 Docker 使用本机代理（FriendlyWrt / systemd）

1. 创建目录并写入代理配置（把 `http://代理IP:端口` 换成你本机可用的代理，例如 `http://127.0.0.1:7890`）：
   ```bash
   mkdir -p /etc/systemd/system/docker.service.d
   cat > /etc/systemd/system/docker.service.d/http-proxy.conf << 'PROXY'
   [Service]
   Environment="HTTP_PROXY=http://代理IP:端口"
   Environment="HTTPS_PROXY=http://代理IP:端口"
   Environment="NO_PROXY=localhost,127.0.0.1"
   PROXY
   ```
2. 重载并重启 Docker：
   ```bash
   systemctl daemon-reload
   systemctl restart docker
   ```
3. 在项目目录重试：
   ```bash
   cd /root/R5C-Cloudflare-Portal
   docker compose up -d
   ```

若本机代理是 HTTP 且需认证，可写为：`http://用户名:密码@代理IP:端口`（注意特殊字符需 URL 编码）。

### 镜像来源说明

- **cloudflared**：已改为 `ghcr.io/cloudflare/cloudflared`，走 GitHub 镜像，一般无需 Docker Hub。
- **xray**：`teddysun/xray` 在 Docker Hub，部分环境或镜像加速会缓存。
- **dashdot**：仅 Docker Hub（`mauricenino/dashdot`），若超时需配置 Docker 代理或镜像加速后拉取。

### 其他方式

- **镜像加速**：编辑 `/etc/docker/daemon.json`，增加 `"registry-mirrors": ["https://镜像地址"]`，重启 Docker（适合无代理、用国内镜像站）。
- **分步拉取**：先 `docker pull ghcr.io/cloudflare/cloudflared:latest`、`docker pull teddysun/xray:latest`，再配置代理后 `docker pull mauricenino/dashdot:latest`，最后 `docker compose up -d`。

配置和 UUID 已写入当前目录，重试时无需再跑 `deploy.sh`，直接在同一目录执行 `docker compose up -d` 即可。

---

## 安全提醒

- **不要**将 `xray_config.json` 或内含 Token 的 `docker-compose.yml` 提交到公开仓库。
- UUID 相当于代理密码，请妥善保存并只分享给可信任的人。

---

## 许可证

可按需自行选择开源协议（如 MIT）。
