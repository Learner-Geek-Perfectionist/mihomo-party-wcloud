# mihomo-party-wcloud

一套给 macOS / Linux 上 `Clash Party` / `mihomo-party` 使用的配置仓库，用来把 Wcloud 订阅相关配置快速同步到新机器。

仓库提供：

- 一键安装 `config.yaml`、`mihomo.yaml` 和本地 override
- 自动为名为 `Wcloud` 的订阅挂载覆写规则
- 自动把 `Wcloud` 订阅设置为每 1 小时刷新一次
- 安装前后按需停启 `Clash Party`，避免运行中的旧状态把新配置覆盖回去
- 基于 [MetaCubeX](https://github.com/MetaCubeX) `geosite.dat` 的白名单分流规则，并单独给 Claude 预留代理组

## 适用场景

- 你已经在 `Clash Party` 里使用 Wcloud
- 你想把一套稳定的 mihomo / UI / 覆写规则复制到另一台 macOS 设备
- 你不想把带订阅 token 的 `profile.yaml`、缓存数据、运行态文件直接提交到仓库

## 仓库内容

| 文件 | 作用 |
| --- | --- |
| `install.sh` | 安装入口，负责 staging、原子写入、应用停启和日志输出 |
| `sync_install_state.rb` | 同步 `override.yaml` / `profile.yaml` 的状态，生成或复用 override ID |
| `config.yaml` | `Clash Party` 应用层配置 |
| `mihomo.yaml` | mihomo 核心层配置，包含端口、TUN、DNS、sniffer、geo 数据源等 |
| `override/geosite-whitelist-claude.yaml` | 覆写规则，完整替换订阅规则体系 |
| `tests/install.sh` | 安装流程回归测试 |

未包含的内容：

- `profile.yaml`
- `profiles/`
- 任何订阅 URL、token、缓存节点数据

## 前置条件

- macOS 或 Linux
- 已安装并至少启动过一次 `Clash Party` / `mihomo-party`
- 本地存在数据目录：
  macOS: `~/Library/Application Support/mihomo-party`
  Linux: `${XDG_CONFIG_HOME:-~/.config}/mihomo-party`
- 系统可用 `ruby`，并带有 `yaml` / `securerandom`
- 如果希望自动把 override 挂到订阅上，需先在应用里手动添加一个名为 `Wcloud` 的订阅

## 快速开始

```bash
git clone git@github.com:Learner-Geek-Perfectionist/mihomo-party-wcloud.git
cd mihomo-party-wcloud
./install.sh
```

默认会安装到：

```text
macOS: ~/Library/Application Support/mihomo-party
Linux: ${XDG_CONFIG_HOME:-~/.config}/mihomo-party
```

如果你想写入别的目录：

```bash
TARGET_DIR="/path/to/mihomo-party" ./install.sh
```

## 安装脚本会做什么

1. 校验 `ruby` 运行时和仓库内必需文件是否存在。
2. 把 `config.yaml`、`mihomo.yaml` 和 override 文件先复制到临时 staging 目录。
3. 读取目标目录里的 `override.yaml` / `profile.yaml`，生成或复用 override ID。
4. 向 `override.yaml` 注册 `MetaCubeX GEOSITE + Claude专用` 这条本地覆写。
5. 如果找到了名为 `Wcloud` 的订阅，就把它的 `override`、`autoUpdate` 和 `interval` 自动补齐。
6. 在允许应用控制时，安装前停止正在运行的 `Clash Party`，安装后再拉起。
7. 用原子写入方式覆盖目标目录，避免半写入状态。

## 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `TARGET_DIR` | macOS: `~/Library/Application Support/mihomo-party`；Linux: `${XDG_CONFIG_HOME:-~/.config}/mihomo-party` | 目标数据目录 |
| `APP_CONTROL_MODE` | `auto` | `auto` 仅在默认目录安装时停启应用；`always` 总是停启；`never` 从不控制应用 |
| `DEFAULT_TARGET_DIR` | 跟随当前平台默认目录 | 给 `auto` 模式判断“默认目录”用，通常只在测试或高级场景下改 |
| `NO_COLOR` | 未设置 | 设置后关闭彩色日志输出 |

示例：

```bash
APP_CONTROL_MODE=never ./install.sh
NO_COLOR=1 ./install.sh
```

## 覆写规则说明

`override/geosite-whitelist-claude.yaml` 使用 [MetaCubeX](https://github.com/MetaCubeX) 的 `geosite.dat` 做白名单模式分流，思路是：

- 明确的国内流量走 `DIRECT`
- 明确的国际服务走代理
- 未命中的流量默认走 `🚀 节点选择`

当前规则重点包括：

- `claude.ai`、`anthropic.com`、`cdn.usefathom.com` 走 `Claude专用`
- `Claude专用` 代理组会从全部节点中筛选 `美国家宽`
- `www.bing.com` / `www2.bing.com` 和 `bing@cn` 走直连
- Copilot 显式入口和其余 `geosite:bing` 流量走 `💬 人工智能`
- `mojie.app` / `mojie.co` / `mojie.kim` / `mojieai.com` 强制走代理，避免被国内 IP 误判直连
- `private`、`cn`、中国区子集服务走直连，其他国际流量继续按 geosite / geoip 兜底

geo 数据下载地址定义在 `mihomo.yaml` 的 `geox-url` 中，并启用了自动更新。

## 安全提示

这套配置默认更偏向“受信任局域网共享代理”，不是保守封闭配置。当前仓库里：

- `mihomo.yaml` 开启了 `allow-lan: true`
- `mihomo.yaml` 使用 `bind-address: "*"`
- `mihomo.yaml` 的 `authentication` 为空
- `config.yaml` 仍把 `SubStore` 绑定在 `127.0.0.1`

如果你的网络环境不可信，至少应自行收紧：

- `allow-lan`
- `bind-address`
- `lan-allowed-ips`
- `authentication`

## 测试

运行安装流程回归测试：

```bash
bash tests/install.sh
```

当前测试覆盖：

- 覆写注册和 ID 复用
- `Wcloud` 订阅字段自动补齐
- 重复安装幂等性
- 非法 YAML 时不落盘
- Ruby 运行时异常时提前失败
- 应用运行时的停启流程

## 常见问题

### 1. 安装后没有自动挂到订阅上

脚本只会修改名称严格等于 `Wcloud` 的订阅。先在 `Clash Party` 里导入该订阅，再重新执行 `./install.sh`。

### 2. 为什么脚本会尝试关闭应用

因为 `Clash Party` 运行中可能在退出时把旧状态重新写回配置文件。脚本默认优先保证落盘后的配置不被覆盖。

### 3. 可以在 Linux 上直接用吗

可以。`install.sh` 现在已支持 Linux 默认目录和应用停启流程；默认目标目录是 `${XDG_CONFIG_HOME:-~/.config}/mihomo-party`，进程名使用 `mihomo-party`。如果你的安装方式不是标准桌面启动器，也可以继续显式传 `TARGET_DIR`。
