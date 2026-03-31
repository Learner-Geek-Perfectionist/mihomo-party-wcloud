# mihomo-party-wcloud

Wcloud 订阅的 mihomo party 配置备份，方便在其他 macOS 设备上快速部署。

默认安全策略：

- 代理端口默认对局域网开放，方便局域网设备共用代理
- `SubStore` 仍仅绑定 `127.0.0.1`
- 如果网络环境不可信，请手动收紧 `mihomo.yaml` 的监听范围并启用认证

## 文件说明

| 文件 | 说明 |
|------|------|
| `config.yaml` | mihomo party 应用设置（主题、语言、侧栏顺序、端口显示等） |
| `mihomo.yaml` | mihomo 核心配置（TUN、DNS、sniffer、geo 数据源等） |
| `override/geosite-whitelist-claude.yaml` | 覆写规则：MetaCubeX GEOSITE 白名单模式 + Claude 专用路由 |

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

覆写文件使用 [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) 提供的 `geosite.dat` 做**白名单模式**分流，完整替换 Wcloud 订阅自带的规则体系。

与旧版 `rule-providers` 方案相比，这一版的核心变化是：

- 覆写内直接使用 `GEOSITE` / `GEOIP`，不再依赖额外的外部规则文件下载
- 不再混用 `proxy` 与 `direct` 两套域名列表，避免 `bing.com` 一类域名出现重叠命中和优先级冲突

`geosite.dat` 的更新由 mihomo 自己负责，来源配置见 `mihomo.yaml` 中的 `geox-url.geosite` 与 `geo-auto-update`。

### 白名单模式

白名单模式 = 明确匹配到的国内流量、中国区子集、私有网络走直连，**其余默认走代理**。相比 Wcloud 原有的黑名单模式（只代理明确列出的域名），不会出现国外网站因 GEOIP 误判而走直连的问题。

### 规则匹配链

```text
Claude 专用路由（最高优先级）
    ↓
Copilot 显式入口（api.msn.com / gateway.bingviz.* → 💬 人工智能）
    ↓
机场面板走代理（mojie.app 等域名解析到国内 IP，不能走直连）
    ↓
Bing 搜索直连（bing@cn + www.bing.com / www2.bing.com）
    ↓
其余 Bing / Copilot 走 💬 人工智能
    ↓
中国区子集直连（apple-cn / icloud@cn / google@cn / microsoft@cn / steam@cn / category-games@cn）
    ↓
国际服务代理（youtube / google / github / telegram / twitter / scholar）
    ↓
GEOSITE 兜底（geolocation-!cn → 代理，cn → 直连）
    ↓
GEOIP 兜底（private / telegram / CN）
    ↓
MATCH → 🚀 节点选择（未匹配的全走代理）
```

### Claude 专用路由

- 将 `claude.ai`、`anthropic.com`、`cdn.usefathom.com` 路由到美国家宽节点
- 通过 `Claude专用` 代理组选择节点

### Bing / Copilot 分流

- `www.bing.com`、`www2.bing.com` 和 `bing@cn` 中国区子集走 `DIRECT`
- 其余 `geosite:bing` 流量走 `💬 人工智能`
- `api.msn.com`、`assets.msn.com`、`gateway.bingviz.microsoft.net`、`gateway.bingviz.microsoftapp.net` 作为 Copilot 显式入口，直接送入 `💬 人工智能`

这样可以同时满足两件事：

- Safari / 浏览器访问 Bing 搜索页保持直连，避免被慢节点拖累
- `copilot.microsoft.com` 及其相关依赖仍保留代理能力，不会被“一刀切”到直连

### 中国区子集直连

- 使用 `apple-cn`、`icloud@cn`、`google@cn`、`microsoft@cn`、`steam@cn`、`category-games@cn`
- 这比旧版 `DOMAIN-KEYWORD,microsoft`、`officecdn` 一类的粗粒度规则更稳，避免把 OneDrive、Azure、Office 国际域名整体误放行到 `DIRECT`

### 机场面板代理

- `mojie.app`、`mojie.co`、`mojie.kim`、`mojieai.com` 强制走 `🚀 节点选择`
- 这些域名解析到中国 IP，会被 `GEOSITE,cn` / `GEOIP,CN,DIRECT` 误判为直连导致无法访问

## 安装

### 快速安装

```bash
git clone git@github.com:Learner-Geek-Perfectionist/mihomo-party-wcloud.git
cd mihomo-party-wcloud
./install.sh
```

如需对测试目录或非默认数据目录执行安装，可显式指定：

```bash
TARGET_DIR="/path/to/mihomo-party" ./install.sh
```

脚本默认使用 ANSI 彩色输出，便于区分步骤、成功状态和跳过项。如需关闭颜色，可使用：

```bash
NO_COLOR=1 ./install.sh
```

示例输出：

```text
[01] Staging config files
     staged       config.yaml, mihomo.yaml

[02] Installing override rule
     override     MetaCubeX GEOSITE + Claude专用
     file         aae3735c27.yaml

[03] Installing to target
     installed    config.yaml, mihomo.yaml
     override     aae3735c27.yaml

[04] Configuring Wcloud subscription
     skipped      Wcloud subscription not found (add it first, then re-run)

[done] Restart Clash Party to apply changes immediately.
```

### 脚本执行内容

1. 如果 `Clash Party` 正在运行，脚本会按“先停应用，再写配置”的顺序执行，避免退出时把旧内存状态写回配置文件
2. 复制 `config.yaml` 和 `mihomo.yaml` 到 mihomo party 数据目录
3. 生成随机 ID（或复用已有 ID），注册并复制覆写规则文件
4. 将覆写关联到 Wcloud 订阅，并开启自动刷新（每 6 小时）
5. 如果安装前应用正在运行，脚本会自动重启它

默认情况下，脚本会在发现默认数据目录上的 `Clash Party` 正在运行时自动停启。你可以：

- 直接运行 `./install.sh`，让脚本自动停启应用
- 或显式关闭应用控制：`APP_CONTROL_MODE=never ./install.sh`

### 安装后操作

1. **首次使用**需先手动添加 Wcloud 订阅：配置 -> 导入 -> 粘贴订阅 URL，然后重新运行 `./install.sh`
2. **重启 mihomo party** 加载新配置
