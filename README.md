# OpenList Termux

Termux 环境下的 [OpenList](https://github.com/OpenListTeam/OpenList) 一站式管理工具，集成 aria2 高速下载与 Cloudflare Tunnel 外网访问。

## 功能一览

| 类别 | 功能 |
|------|------|
| OpenList | 一键安装/更新、启动/停止、密码重置、配置编辑、日志查看、卸载 |
| aria2 | 自动配置、启动/停止、BT Tracker 更新、配置编辑、日志查看、卸载 |
| Cloudflare Tunnel | 一键配置隧道、启动/停止外网访问、日志查看、卸载 |
| 运维 | 开机自启、版本检测、数据备份/还原/残留清理、全局快捷命令 `oplist` |

## 前置要求

- **Termux** (Android)
- **curl**：`pkg install -y curl`（脚本会自动检测并尝试安装）
- **Termux Boot** (可选，开机自启)：[下载 v0.8.1](https://github.com/termux/termux-boot/releases/download/v0.8.1/termux-boot-app_v0.8.1+github.debug.apk)
- **Cloudflare 账号及域名** (可选，外网访问)

## 快速开始

```bash
# 克隆仓库
git clone https://github.com/fii6/openlist_termux.git
cd openlist_termux

# 创建配置文件并填写
cp .env.example .env
vi .env    # 至少填写 ARIA2_SECRET

# 运行
chmod +x *.sh
./main.sh
```

首次运行自动安装全局命令，之后直接输入 `oplist` 即可打开管理菜单。

## 配置说明

复制 `.env.example` 为 `.env`，按需填写：

| 变量 | 必填 | 说明 |
|------|:----:|------|
| `ARIA2_SECRET` | 是 | aria2 RPC 认证密钥 |
| `GITHUB_TOKEN` | 否 | GitHub Token，提升版本检测与下载稳定性（[获取方法](https://github.com/settings/tokens)） |
| `TUNNEL_NAME` | 否 | Cloudflare Tunnel 名称 |
| `DOMAIN` | 否 | 外网访问域名 |
| `LOCAL_PORT` | 否 | OpenList 本地端口，默认 `5244` |

> `.env` 优先从脚本同目录读取，也兼容 `~/.env`。

## 菜单结构

```
主菜单
 1. 安装 OpenList
 2. 更新 OpenList
 3. 启动 OpenList 和 aria2
 4. 停止 OpenList 和 aria2
 5. 查看 OpenList 启动日志
 6. 查看 aria2 启动日志
 7. 更多功能
     1. 修改 OpenList 密码
     2. 编辑 OpenList 配置文件
     3. 编辑 aria2 配置文件
     4. 更新 aria2 BT Tracker
     5. 备份/还原 OpenList 配置
         1. 备份
         2. 还原
         3. 清理还原残留目录
     6. 开启 OpenList 外网访问
     7. 停止 OpenList 外网访问
     8. 查看 Cloudflare Tunnel 日志
     9. 一键卸载（OpenList + aria2 + Tunnel）
 0. 退出
```

## 项目结构

```
openlist_termux/
├── main.sh          # 入口脚本，主菜单与流程控制
├── common.sh        # 公共定义（颜色、日志轮转、进程管理等）
├── openlist.sh      # OpenList 安装/启动/更新/停止/卸载
├── aria2.sh         # aria2 配置/启动/停止/Tracker 更新/卸载
├── backup.sh        # 数据备份/还原/残留清理
├── tunnel.sh        # Cloudflare Tunnel 配置/启动/停止/卸载
├── .env.example     # 配置模板
└── .gitignore
```

## 数据目录

| 路径 | 用途 |
|------|------|
| `~/Openlist/` | OpenList 工作目录 |
| `~/Openlist/data/` | OpenList 数据与配置 |
| `~/aria2/` | aria2 配置、会话、DHT |
| `~/.cloudflared/` | Cloudflare Tunnel 凭证与配置 |
| `/sdcard/Download/` | 默认备份与下载目录 |

## 注意事项

- 安装/更新时请确保网络连接稳定
- `.env` 包含敏感信息，切勿提交到仓库
- 开机自启依赖 [Termux Boot](https://github.com/termux/termux-boot) 插件
- Cloudflare Tunnel 需提前将域名托管到 Cloudflare

## 问题反馈

请在 GitHub 仓库提交 [issue](https://github.com/fii6/openlist_termux/issues)。
