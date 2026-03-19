# mihomo-party-wcloud

Wcloud 订阅的 mihomo party 配置备份，方便在其他 macOS 设备上快速部署。

## 文件说明

| 文件 | 说明 |
|------|------|
| `config.yaml` | mihomo party 应用设置（主题、语言、侧栏顺序、端口显示等） |
| `mihomo.yaml` | mihomo 核心配置（TUN、DNS、sniffer、geo 数据源等） |
| `override/loyalsoldier-whitelist-claude.yaml` | 覆写规则：Loyalsoldier 白名单模式 + Claude 专用路由 |

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
override（覆写：完整替换订阅的分流规则体系）
    ↓
config.yaml（UI 层：主题/语言/侧栏/端口显示）
```

## 覆写规则详情

覆写文件使用 [Loyalsoldier/clash-rules](https://github.com/Loyalsoldier/clash-rules)（25k+ stars）的**白名单模式**完整替换 Wcloud 订阅自带的分流规则。规则数据每天自动构建，来源于 v2fly/domain-list-community、GFWList、dnsmasq-china-list 等社区项目。

### 白名单模式

白名单模式 = 明确匹配到的国内流量走直连，**其余全部走代理**。相比 Wcloud 原有的黑名单模式（只代理明确列出的域名），不会出现国外网站因 GEOIP 误判而走直连的问题。

### 规则匹配链

```
Claude 专用路由（最高优先级）
    ↓
Loyalsoldier 规则集（applications → private → reject → icloud → apple → google → proxy → direct → lancidr → cncidr → telegramcidr）
    ↓
GEOIP 兜底（LAN/CN → DIRECT）
    ↓
MATCH → 🚀 节点选择（未匹配的全走代理）
```

### Claude 专用路由

- 将 `claude.ai`、`anthropic.com`、`cdn.usefathom.com` 路由到美国家宽节点
- 通过 `Claude专用` 代理组选择节点

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
3. 生成随机 ID，注册并复制覆写规则文件
4. 输出后续操作提示

### 安装后操作

1. **重启 mihomo party** 加载新配置
2. **添加 Wcloud 订阅**：配置 -> 导入 -> 粘贴订阅 URL
3. **启用覆写规则**：覆写 -> 开启「Loyalsoldier白名单 + Claude专用」
4. **关联到订阅**：配置 -> 选择 Wcloud 配置 -> 覆写 -> 勾选该规则
