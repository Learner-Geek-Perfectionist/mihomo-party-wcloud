# mihomo-party-wcloud

Wcloud 订阅的 mihomo party 配置备份，方便在其他 macOS 设备上快速部署。

## 文件说明

| 文件 | 说明 |
|------|------|
| `config.yaml` | mihomo party 应用设置（主题、语言、侧栏顺序、端口显示等） |
| `mihomo.yaml` | mihomo 核心配置（TUN、DNS、sniffer、geo 数据源等） |
| `override/claude-and-download-fix.yaml` | 复写规则：Claude 专用路由 + Google 下载修复 |

**不包含**：`profile.yaml`（含订阅 token）、`profiles/`（订阅缓存数据）。

## 自动刷新订阅流量

安装脚本会自动为 Wcloud 订阅开启定时刷新（每 6 小时），方便随时查看剩余流量：

- `autoUpdate: true` — 启用自动更新
- `interval: 360` — 每 360 分钟（6 小时）刷新一次

> 前提：需要先手动添加 Wcloud 订阅，再运行 `install.sh`。

## 配置层级关系

```
mihomo.yaml（引擎层：TUN/DNS/sniffer/geo）
    ↓
订阅 profile（节点 + 分流规则，需手动添加）
    ↓
override（补丁：在订阅基础上追加代理组和规则）
    ↓
config.yaml（UI 层：主题/语言/侧栏/端口显示）
```

## 复写规则详情

### Claude 专用路由（`✴️ Claude专用`）
- 将 `claude.ai`、`anthropic.com`、`cdn.usefathom.com` 路由到家宽节点
- 自动测速选择台湾、新加坡、马来、日本、美国、加拿大的家宽代理

### Google 下载修复（`🌐 通用代理`）
- 将 `dl.google.com`、`tools.google.com` 等路由到非家宽节点
- 修复家宽 IP 下载受限的问题

## 安装

### 快速安装

```bash
git clone git@github.com:Learner-Geek-Perfectionist/mihomo-party-wcloud.git
cd mihomo-party-wcloud
./install.sh
```

### 预览模式（不做任何修改）

```bash
./install.sh --dry-run
```

### 脚本执行内容

1. 备份已有配置到 `~/.mihomo-party-backup-<时间戳>/`
2. 复制 `config.yaml` 和 `mihomo.yaml` 到 mihomo party 数据目录
3. 生成随机 ID，注册并复制复写规则文件
4. 输出后续操作提示

### 安装后操作

1. **重启 mihomo party** 加载新配置
2. **添加 Wcloud 订阅**：配置 -> 导入 -> 粘贴订阅 URL
3. **启用复写规则**：覆写 -> 开启「Claude专用 & 下载修复」
4. **关联到订阅**：配置 -> 选择 Wcloud 配置 -> 覆写 -> 勾选该规则
