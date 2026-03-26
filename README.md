
# Termux 下的 OpenList 管理脚本

这是一个用于在 Android Termux 环境中便捷安装、更新和管理 [OpenList](https://github.com/OpenListTeam/OpenList) 的脚本，简化操作流程并提供丰富功能。

## 功能
- **一键安装与更新**：在 Termux 中快速安装或更新 OpenList。
- **高效下载**：集成 aria2，支持高速下载。
- **快捷命令**：通过 `oplist` 命令快速打开管理菜单。
- **版本检测**：支持非实时检测 OpenList 新版本。
- **开机自启**：支持 OpenList 和 aria2 开机自动启动。
- **数据备份与恢复**：支持本地备份与本地还原。
- **外网访问**：通过 Cloudflare Tunnel 实现外网访问。

## 前置要求
1. **安装必要工具**：
   在 Termux 中运行以下命令安装 `curl` 和 `wget`：
   ```bash
   pkg install -y wget curl
   ```

2. **GitHub 个人访问令牌（Token，可选）**：
   - 用途：用于提升 GitHub API 访问稳定性，避免速率限制。
   - 当前脚本部分功能依赖该字段；如果留空，版本检查和 OpenList 下载可能受限。
   - 获取方法：
     1. 访问 [GitHub 设置 > 开发者设置 > 个人访问令牌 > 经典令牌](https://github.com/settings/tokens)。
     2. 点击 **生成新令牌（经典）**。
     3. 权限选择：公开仓库场景通常无需额外权限；如需访问私有仓库，再按需勾选权限。
     4. 生成后复制令牌，并保存至 `.env` 文件的 `GITHUB_TOKEN` 字段。
     - **注意**：令牌仅显示一次，务必妥善保存。

3. **aria2 RPC 密钥**：
   - 设置一个由字母、数字和符号组成的密钥，用于 aria2 RPC 认证。
   - 保存至 `.env` 文件的 `ARIA2_SECRET` 字段。

4. **Termux Boot 插件**：
   - 下载地址：[Termux Boot v0.8.1](https://github.com/termux/termux-boot/releases/download/v0.8.1/termux-boot-app_v0.8.1+github.debug.apk)
   - 用途：实现 OpenList 和 aria2 的开机自启。

5. **Cloudflare 账号及托管于其上的域名**：
   - 用于通过 Cloudflare Tunnel 实现 OpenList 的外网访问。
   - 建议提前登录 Cloudflare 账号。

## 安装与使用
1. **配置 `.env` 文件**：
   - 先复制模板：`cp .env.example .env`
   - 推荐将 `.env` 放在**脚本同目录**；当前脚本也兼容读取 `~/.env`。
   - 至少建议填写：`ARIA2_SECRET`；如需稳定下载与版本检测，再填写 `GITHUB_TOKEN`。

2. **运行脚本**：
   在 Termux 中执行以下命令：
   ```bash
   git clone https://github.com/fii6/openlist_termux.git
   cd openlist_termux
   chmod +x main.sh *.sh
   ./main.sh
   ```

   首次运行后，脚本会自动安装全局命令 `oplist`，之后可直接输入：
   ```bash
   oplist
   ```

3. **执行流程**：
   - 输入标号 1 安装OpenList。
   - 输入标号 3 启动 openlist 和 aria2。
   - 更多功能 打开 二级菜单功能。

4. **开机自启设置**：
   - 安装 Termux Boot 插件后，脚本会在 OpenList 和 aria2 启动成功后询问是否启用开机自启：
     - 输入 `y` 启用。
     - 输入 `n` 取消。

6. **数据备份与恢复**：
   - 当前版本已支持**本地备份**与**本地还原**。
   - 默认备份目录：`/sdcard/Download`
   - 备份内容：`$HOME/Openlist/data`

## 快捷使用
安装完成后，可通过以下命令快速打开管理菜单：
```bash
oplist
```
无需记忆复杂路径或参数，即可管理所有功能。

## 注意事项
- **网络稳定性**：安装或更新时请确保网络连接稳定。
- **敏感信息**：请勿将填写好的 `.env` 提交到仓库；仓库只保留 `.env.example` 模板。
- **Cloudflare Tunnel**：确保正确配置 Cloudflare 账号和域名以实现外网访问。

## 常见问题
- **无法下载文件**：
  - 可能原因：网络问题，或未正确配置 `.env` 中的必要字段。
  - 解决方案：检查网络、确认 `ARIA2_SECRET` 已填写；如需要更稳定的 GitHub 访问，再补 `GITHUB_TOKEN`。

## 支持与反馈
如有问题或建议，请在当前 GitHub 仓库提交 issue。
