# VCPToolBox Upstream 更新清单（Stash → Pull → Pop → Config → PM2 → Push）

> 适用仓库：`D:\SoftwareDevelopCase\VCPToolBox`  
> Fork `origin`：`https://github.com/VincentHDLee/VCPToolBox.git`  
> Upstream：`https://github.com/lioensky/VCPToolBox.git`  
> 分支：`main`  
> 本文档目标：可重复执行的「有本地改动时从上游同步」完整流程，并在启动成功后推送到 fork。

---

## 0. 硬性规则（每次必读）

| 规则                | 说明                                                                                                                           |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| **不提交密钥**      | 永不 `git add config.env`、插件私有 `config.env`、API Key、证书                                                                |
| **config.env 编码** | 始终 **UTF-8 无 BOM**。禁止 PowerShell `Set-Content -Encoding utf8`（会写 BOM/乱码）                                           |
| **推荐写入**        | Node `fs.writeFileSync(p, Buffer.from(text,'utf8'))` 或 `[IO.File]::WriteAllText($p,$t,(New-Object Text.UTF8Encoding $false))` |
| **本机地址**        | 固定 LAN 改为 `127.0.0.1`（回调、API、Rerank 等）                                                                              |
| **PM2 内存**        | `ecosystem.config.js` **不要**加 `max_memory_restart`（冷启动 KB 峰值会死循环）                                                |
| **Git 回滚**        | 未征得用户同意不做 `reset --hard` / force-push                                                                                 |
| **网络**            | GitHub 443 不通时用镜像或本地 mirror clone（见 §3）                                                                            |
| **插件禁用**        | 禁用 = `Plugin/<Name>/plugin-manifest.json.block`；启用 = 去掉 `.block`                                                        |

### 常用路径

```text
仓库根：     D:\SoftwareDevelopCase\VCPToolBox
配置：       config.env              （gitignore，本地真源）
模板：       config.env.example
PM2：        ecosystem.config.js
插件：       Plugin/
预处理器序： preprocessor_order.json
日志：       %USERPROFILE%\.pm2\logs\
主服务：     http://127.0.0.1:6005
管理面板：   http://127.0.0.1:6006/AdminPanel
健康检查：   http://127.0.0.1:6005/health   （有鉴权时常 401，属预期）
```

---

## 1. 更新前快照（Checklist）

在 PowerShell 中于仓库根执行：

```powershell
cd D:\SoftwareDevelopCase\VCPToolBox

# 1.1 工作区与远端
git status -sb
git remote -v
git branch -vv
git log -5 --oneline
git stash list

# 1.2 记录当前 HEAD（写入运行日志时用）
git rev-parse HEAD

# 1.3 可选：整目录备份（大改动前强烈建议）
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$backup = "D:\SoftwareDevelopCase\vcp_local_backup_$ts"
# Robocopy 示例（排除 node_modules/venv/.git 可按需）：
# robocopy . $backup /E /XD node_modules venv .git VectorStore VectorStoreTDB tmp logs DebugLog /NFL /NDL /NJH /NJS

# 1.4 单独备份 config.env（永远先做）
Copy-Item config.env "config.env.bak_$ts" -Force
```

**检查项：**

- [ ] `config.env` 已备份
- [ ] 已知本地改动列表（`git status`）
- [ ] 已记录 `PRE_HEAD=<sha>`
- [ ] PM2 是否在跑：`npx pm2 status`（更新中可先 `npx pm2 stop all`，避免半更新进程）

---

## 2. Stash 本地改动

### 2.1 应纳入 stash 的内容

- 已跟踪文件的修改（如 `ecosystem.config.js`、本地补丁）
- 需要保留的 **未跟踪** 本地文件：插件私有配置、本地数据目录片段等
  - 使用 `git stash push -u` 可包含 untracked
  - **不要**把 `node_modules`、`venv`、巨型向量库塞进 stash（应已在 `.gitignore`）

### 2.2 命令

```powershell
$msg = "pre-upstream-sync-$(Get-Date -Format 'yyyyMMdd')"
# 含 untracked；若只需已跟踪：去掉 -u
git stash push -u -m $msg

git status -sb   # 期望干净或仅剩故意留下的文件
git stash list   # 确认 stash@{0} 为本次
```

**检查项：**

- [ ] `git status` 干净（或仅剩可忽略项）
- [ ] stash 信息可识别
- [ ] `config.env` **仍在磁盘**（gitignore，一般不会进 stash；若曾被 track 需特别处理）

> **注意：** `config.env` 被 gitignore 时不会进 stash。更新前后都靠 **文件备份** + **键差补全** 保护，而不是依赖 stash。

---

## 3. 从 Upstream 拉取并合并

### 3.A 直连可用时

```powershell
git fetch upstream main
git log --oneline HEAD..upstream/main | Select-Object -First 80
git merge --ff-only upstream/main
# 若不能 ff-only，再评估 merge 提交（需用户同意非快进策略时）
```

### 3.B GitHub 不通：镜像 fetch

```powershell
# 方式 1：临时 remote + 镜像 URL（按当前可用镜像替换）
git remote remove upstream-mirror 2>$null
git remote add upstream-mirror "https://ghfast.top/https://github.com/lioensky/VCPToolBox.git"
git fetch upstream-mirror main
git merge --ff-only upstream-mirror/main
git remote remove upstream-mirror
```

### 3.C 镜像仍失败：本地 mirror 目录

```powershell
$mirrorRoot = "D:\SoftwareDevelopCase\_vcp_upstream_full"
# 若目录不存在或过旧：用浏览器/其他可访问通道重新 clone 官方 main 到该路径
# git clone --depth 1 https://.../lioensky/VCPToolBox.git $mirrorRoot

git remote remove upstream-local 2>$null
git remote add upstream-local $mirrorRoot
git -c protocol.file.allow=always fetch upstream-local main
git merge --ff-only upstream-local/main
git remote remove upstream-local
```

### 3.D 拉取后记录

```powershell
git rev-parse HEAD          # POST_HEAD
git log --oneline PRE_HEAD..HEAD
git diff --stat PRE_HEAD..HEAD
```

**检查项：**

- [ ] merge 成功，无冲突（ff-only 最干净）
- [ ] 已保存 `POST_HEAD`
- [ ] 已浏览提交范围与文件 diff

---

## 4. 分析更新内容（核对清单）

对 `PRE_HEAD..POST_HEAD` 做结构化审阅：

### 4.1 代码与依赖

```powershell
git log --oneline PRE_HEAD..POST_HEAD
git diff --stat PRE_HEAD..POST_HEAD
git diff PRE_HEAD..POST_HEAD -- package.json requirements.txt pyproject.toml
git diff PRE_HEAD..POST_HEAD -- config.env.example ecosystem.config.js preprocessor_order.json
```

### 4.2 插件与 Manifest

```powershell
# 新增/变更的插件目录
git diff --name-status PRE_HEAD..POST_HEAD -- Plugin/

# 列出所有 manifest
Get-ChildItem Plugin -Recurse -Filter plugin-manifest.json | Select-Object FullName
Get-ChildItem Plugin -Recurse -Filter plugin-manifest.json.block | Select-Object FullName
```

关注：

| 类型                        | 动作                                                            |
| --------------------------- | --------------------------------------------------------------- |
| **新插件**                  | 读 README / manifest；默认是否启用；是否需要插件级 `config.env` |
| **manifest 变更**           | 新 env 键、入口脚本、权限、回调                                 |
| **已启用插件更新**          | 对比插件目录 `config.env.example` ↔ 本地 `config.env`           |
| **preprocessor_order.json** | 新 preprocessor 是否需插入顺序（通常跟 upstream）               |
| **Admin / 路由**            | `adminServer.js`、`routes/`、`AdminPanel-Vue`                   |

### 4.3 输出「更新摘要」模板

```markdown
## 本次 Upstream 摘要 (PRE..POST)

- 提交数：
- 主题标签：（性能 / 插件 / 安全 / 记忆 / 管理面板 …）
- 破坏性变更：
- 新配置键（根 config.env.example）：
- 新/改插件：
- 依赖变化（npm / pip）：
- 启动注意：
```

**检查项：**

- [ ] 摘要已写入本次运行记录（本文档 §11 或独立 runlog）
- [ ] 已知需要手工配置的键列表

---

## 5. 配置与 Manifest 同步

### 5.1 根 `config.env`：只追加缺失键，不覆盖已有值

原则：**以本地现有值为准**，从 `config.env.example` **补缺**；强制本机策略键可覆盖。

```powershell
# 概念步骤（实际用 Node 脚本更安全，见仓库内既有做法）：
# 1. 解析 config.env 与 config.env.example 的 KEY=VALUE
# 2. example 有、本地无 → 追加（可加注释块 # --- Auto-appended YYYY-MM-DD ---）
# 3. 强制：
#    CALLBACK_BASE_URL=http://127.0.0.1:6005/plugin-callback
#    全局 192.168.x.x → 127.0.0.1（按需）
#    VCP_BROWSER_RUNTIME_ENABLED 按本机策略
# 4. UTF-8 无 BOM 写回
```

**禁止：**

- 用 example 整文件覆盖 `config.env`
- 把密钥打印到聊天/日志全文

### 5.2 插件级配置

对每个 **已启用**（存在 `plugin-manifest.json` 且无 `.block`）且本次有 diff 的插件：

1. 读 `plugin-manifest.json` 的 `configSchema` / env 声明
2. 若有 `config.env.example`：对本地 `Plugin/<Name>/config.env` 补缺
3. 路径类键（Linux 绝对路径、GPU 工具）：**Windows 上勿盲填**，记入「待用户确认」
4. 新插件默认：可先 `.block` 禁用，确认依赖后再启用

### 5.2.1 AgentAssistant（AA）配置格式变更 — 必读

> **Breaking change（上游 `8311f03c`，2026-04-10）：** AA 运行时配置从 **`config.env` 改为 `config.json` 为唯一真源**。
> 这是用户最容易踩坑、同步摘要里**必须写明**的插件级变更。README 仍可能写 `config.env`，以代码为准。

| 项           | 说明                                                                                              |
| ------------ | ------------------------------------------------------------------------------------------------- |
| **真源**     | `Plugin/AgentAssistant/config.json`（`agents[]` + 委托/历史等字段）                               |
| **加载**     | `loadAgentsFromLocalConfig()` **只读 json**                                                       |
| **迁移**     | 启动时 `migrateEnvToJson()`：**仅当 json 不存在且 env 存在**时，把 env 一次性写成 json            |
| **之后**     | 再改 `config.env` **不会生效**；日志甚至提示 env 可删除                                           |
| **仓库**     | upstream **不提交**本地 `config.json` / `config.env`（私有角色表）；树内仅有 `config.env.example` |
| **本机镜像** | 可保留 gitignore 的 `config.env` 作人工对照，但必须以 json 为准                                   |
| **改完生效** | `npx pm2 restart vcp-main`，日志应出现 `Config reloaded: N agents loaded.`                        |

**同步时检查清单：**

- [ ] 是否存在 `config.json`？有则 diff 体积/agent 数，勿被「短 json + 长 env」误导
- [ ] 若只有 env：让服务启动一次完成迁移，或手工把长配置迁入 json
- [ ] 名称字段无引号/行尾注释污染（错误迁移常见）
- [ ] 摘要中明确写出「AA 配置真源 = config.json」

**近期 AA 功能变更（与配置格式分开）：**

| 日期       | Commit     | 内容                                                              |
| ---------- | ---------- | ----------------------------------------------------------------- |
| 2026-08-15 | `6c24fa4b` | 委托任务直接调用 **Flowlock 心流锁**内核（`flowlockProtocol.js`） |
| 2026-08-06 | `2b00d0d2` | 接入 reasoning→content 适配，清理思维链避免污染 AA 历史           |
| 更早       | 多笔       | inject_tools、异步委托、积分、总线重试等（V2 起）                 |

### 5.3 Manifest 健康

```powershell
# 启用集与 block 集不应同时指向同一逻辑名混乱
# preprocessor_order.json 中的名字应能在 Plugin 下解析到
```

**检查项：**

- [ ] 根 config 键集合 ≥ example 必要项（或明确跳过项有记录）
- [ ] 无 BOM；抽查中文注释/值未乱码
- [ ] 回调与端口仍为 `127.0.0.1:6005` / admin `6006`
- [ ] 高风险插件配置未误写 Linux 路径

---

## 6. Pop / 恢复本地改动

```powershell
# 先看 stash 内容
git stash show -p "stash@{0}" --stat

# 应用并移除 stash（冲突时用 apply 更稳）
git stash pop
# 或：git stash apply "stash@{0}"  → 解决后再 drop
```

### 6.1 冲突处理原则

| 文件                    | 策略                                             |
| ----------------------- | ------------------------------------------------ |
| `ecosystem.config.js`   | 保留「无 max_memory_restart」+ upstream 有用字段 |
| 业务补丁                | 手工 merge，跑语法检查                           |
| 插件 `config.json` 本地 | 保留本地密钥/端口，吸收 upstream 新字段          |
| 二进制 `code.bin` 等    | 确认是否仍需要本地版；否则用 upstream            |

```powershell
# 冲突标记清理后
git status
# 勿把 config.env 加入提交
```

**检查项：**

- [ ] 无 `UU` 未解决冲突
- [ ] 本地必要文件已恢复
- [ ] stash 是否 drop 已确认

---

## 7. 依赖安装

```powershell
# Node（可用国内镜像）
npm install --registry=https://registry.npmmirror.com

# Python：清代理后装（本机若 7897 劫持失败时）
$env:HTTP_PROXY=''; $env:HTTPS_PROXY=''; $env:http_proxy=''; $env:https_proxy=''
python -m pip install -r requirements.txt
# win10toast 在 Python 3.14 可能需要 setuptools==80.9.0（pkg_resources）
```

**检查项：**

- [ ] `npm install` 成功
- [ ] 关键 Python 包 import 抽查
- [ ] `package.json` / `requirements.txt` 若有新原生模块，Windows 构建工具是否具备

---

## 8. PM2 启动与验证

### 8.1 启动

```powershell
npx pm2 stop all 2>$null
npx pm2 delete all 2>$null
npx pm2 start ecosystem.config.js
npx pm2 save
npx pm2 status
```

### 8.2 验证

```powershell
npx pm2 logs vcp-main --lines 80 --nostream
npx pm2 logs vcp-admin --lines 40 --nostream

# HTTP
try { Invoke-WebRequest -Uri "http://127.0.0.1:6005/health" -UseBasicParsing -TimeoutSec 10 | Select StatusCode } catch { $_.Exception.Response.StatusCode.value__ }
try { Invoke-WebRequest -Uri "http://127.0.0.1:6006/AdminPanel" -UseBasicParsing -TimeoutSec 10 | Select StatusCode } catch { $_ }
```

**成功标准：**

- [ ] `vcp-main` / `vcp-admin` 均为 `online`，无疯狂 restart
- [ ] 主服务端口监听；`/health` 为 200 或 **401（鉴权）**
- [ ] AdminPanel **200**
- [ ] **本轮启动**错误日志无「立刻退出」级致命错误（缺可选依赖的 warn 可记录但不阻断）
- [ ] 若要推 fork：双进程日志门禁通过（见 §8.4）

### 8.3 失败时修复循环

1. 读 `vcp-main-error.log` / `vcp-admin-error.log`（路径见 §0 常用路径）
2. 分类：配置键缺失 / 依赖缺失 / 端口占用 / 编码乱码 / 插件 fatal
3. 修 → `npx pm2 restart ecosystem.config.js` 或整表重拉 → 再验证
4. 仍失败：`npx pm2 stop all`，保留日志路径，升级排查（勿强推 fork）

常见：

| 现象         | 处理                                                                                               |
| ------------ | -------------------------------------------------------------------------------------------------- |
| 端口占用     | `netstat -ano \| findstr :6005` 后结束占用或改 PORT                                                |
| admin 起不来 | 查 `ADMIN_PORT`、是否误解析多 PORT                                                                 |
| 插件缺模块   | 按需 `npm i <pkg>` 或暂时 `.block`                                                                 |
| 中文配置乱码 | 从 `.bak_*` 按 UTF-8 无 BOM 重建                                                                   |
| RSS 被杀循环 | 确认没有 `max_memory_restart`                                                                      |
| 天气城市 400 | 查根 `config.env` 的 `VarCity` 是否 mojibake；UTF-8 无 BOM 写回合法城市名后 `pm2 restart vcp-main` |
| 日志混历史   | **先 `npx pm2 flush` 再 delete/start**，只审本轮启动                                               |

### 8.4 推 fork 前：双进程日志门禁（HARD / SOFT）

> 用户策略（2026-08-19）：**PM2 调试通过且两进程日志无硬错误，才考虑 push fork。**

**务必先清空历史再启，否则会把旧 EADDRINUSE / 崩溃混进结论：**

```powershell
npx pm2 flush
npx pm2 delete all
npx pm2 start ecosystem.config.js
Start-Sleep -Seconds 20
npx pm2 status
npx pm2 save
# 再读 %USERPROFILE%\.pm2\logs\vcp-{main,admin}-{error,out}.log
```

| 级别                          | 判定（示例）                                                                                                                                                              | 是否挡 push                     |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------- |
| **HARD（进程级）**            | `UnhandledPromiseRejection` / `UncaughtException` / `EADDRINUSE` / `Error: listen` / `heap out of memory` / `SyntaxError` 导致起不来 / `Failed to start` / DB `malformed` | **挡** — 先修                   |
| **功能降级（常被误标 HARD）** | 可选插件 `Cannot find module 'ssh2'`、缺邮件 SDK 等；主进程仍 online                                                                                                      | **不挡主服务**；记入 §14 待商议 |
| **SOFT**                      | `ENOENT` 缺可选 json、外网 `ETIMEDOUT`、天气子接口失败、WARN                                                                                                              | **不挡**；按需修                |
| **噪声**                      | PM2 控制台中文乱码、宿主 RAM 高但进程未 OOM                                                                                                                               | **不挡**                        |

**本轮还应出现的正向信号：**

- `[AgentAssistant Service] Config reloaded: N agents loaded.`（N 与本地 json 一致）
- `[KnowledgeBase] ✅ System Ready` / Admin「管理面板地址」
- 天气：城市查询 **无 400**（预警成功即可；空气质量超时另记）

### 8.5 AA 生效自检

```powershell
# 改 Plugin/AgentAssistant/config.json 后：
npx pm2 restart vcp-main
npx pm2 logs vcp-main --lines 100 --nostream | Select-String -Pattern "agents loaded|AgentAssistant"
```

- 只改 `config.env` **不会**生效（见 §5.2.1）。
- 名称字段禁止「引号 + 行尾注释」污染（错误迁移常见）。

---

## 9. 推送到 Fork

**仅在启动验证 + §8.4 日志门禁通过后：**

```powershell
git status -sb
git log origin/main..HEAD --oneline
git diff --stat HEAD

# 只 add 明确要共享的路径；禁止盲 git add .
# 只推送已提交内容；本地脏文件不要 commit
git push origin main
```

### 9.1 默认 **不要** commit / push 的路径

| 路径                                               | 原因                                                                          |
| -------------------------------------------------- | ----------------------------------------------------------------------------- |
| `config.env`、`**/config.env`、各类 `.bak_*`       | 密钥 / 本机环境（gitignore）                                                  |
| `Plugin/AgentAssistant/config.json`                | **私有角色表**；注意：当前 **未必** 被 `.gitignore` 忽略，必须 **刻意不 add** |
| `Plugin/AgentAssistant/config.env` 及 `*.bak_aa_*` | 镜像/备份；env 已 ignore，bak 也可能 untracked                                |
| `Plugin/UserAuth/code.bin`                         | 本机认证产物                                                                  |
| `Plugin/VCPBridgeServer/bridge-config.json`        | 本地桥接                                                                      |
| `sarprompt.json` 等私货                            | 非上游共享                                                                    |
| `Plugin/1PanelInfoProvider/`                       | 本地插件目录，推送前需用户确认                                                |

### 9.2 默认可推 / 需确认

| 路径                                             | 建议                                  |
| ------------------------------------------------ | ------------------------------------- |
| `docs/**`（清单、§5.2.1、问题台账、runlog）      | ✅ 默认可推                           |
| 已 ff-merge 的 upstream 提交                     | ✅ 随 `main` 推                       |
| `ecosystem.config.js`（无 `max_memory_restart`） | ⚠️ **待商议** — 是否共享本机 PM2 策略 |
| `Plugin/PowerShellExecutor/config.env`           | ❌ 本地；仅 example 在仓内            |

**检查项：**

- [ ] §8.4 HARD 门禁通过
- [ ] `git status` 中无密钥 / 私有 AA 角色表被 staged
- [ ] `origin/main` 与本地 `HEAD` 一致（push 后）
- [ ] 推送成功

若有需要保留的 **非密钥** 本地提交，单独 commit 后再 push，message 写清原因；**先问用户**再推 ecosystem / 本地插件。

---

## 10. 收尾

```powershell
# 可选：确认 stash 是否还要保留
git stash list

# 可选：删除过期 config.env.bak_*（至少留一份最近成功）
# 运行记录追加到 docs/runlogs/ 或本文档 §11
```

- [ ] 用户已知本次摘要与遗留项（FFmpeg、可选插件、AICodeWorker 路径等）
- [ ] PM2 保持 online 或按用户要求 stop

---

## 11. 本次运行记录（2026-08-19）

| 项            | 值                                                                                                                                                                                    |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 日期          | 2026-08-19                                                                                                                                                                            |
| 操作者        | Snow AI CLI                                                                                                                                                                           |
| PRE_HEAD      | `6c24fa4b610a5eeb9f5bd40b96b5576b75cae112`                                                                                                                                            |
| POST_HEAD     | `31c3a3713da048d3e2030e730e96b1ef1ed5e0e0`                                                                                                                                            |
| Stash 名      | `pre-upstream-sync-20260819`（已 pop）                                                                                                                                                |
| config 备份   | `config.env.bak_20260819_152453` / `_152732`                                                                                                                                          |
| 拉取方式      | `ghfast.top` 镜像：`git fetch upstream-mirror main` + `merge --ff-only`（直连 GitHub git/API 失败；curl 可下 zip）                                                                    |
| 提交数        | **13** commits，`6c24fa4b..31c3a371`                                                                                                                                                  |
| 提交范围摘要  | 见 §11.3                                                                                                                                                                              |
| 根 config.env | **无变更必要**：`config.env.example` / `package.json` / `requirements.txt` 本窗口无 diff；UTF-8 无 BOM；`CALLBACK_BASE_URL=http://127.0.0.1:6005/plugin-callback`；无 `192.168.1.100` |
| Config 追加键 | 插件级：`Plugin/PowerShellExecutor/config.env` 追加 `POWERSHELL_RETURN_MODE=delta`、`VERBOSE_ERROR=true`                                                                              |
| Manifest      | `PowerShellExecutor` → v1.1.0（上游已带）；其余无新根 manifest 要求                                                                                                                   |
| 依赖安装      | 跳过（根 package/requirements 无 diff；预编译 `vexus-lite.win32-x64-msvc.node` 与 `paperreader-cli.exe` 已随仓库更新）                                                                |
| PM2 结果      | **成功**：`vcp-main`/`vcp-admin` online；`/health` **401**；AdminPanel **200**；监听 **6005**                                                                                         |
| Push 结果     | （见下方执行后更新）                                                                                                                                                                  |
| 遗留问题      | WeatherReporter 城市查询 400（沿用缓存）；主机 RAM ~87%；本地代理 7897 未开时 git 直连 GitHub 不稳定                                                                                  |

### 11.1 更新前本地脏文件（快照）

```text
 M Plugin/UserAuth/code.bin
 M ecosystem.config.js
?? Plugin/1PanelInfoProvider/
?? Plugin/AgentAssistant/config.json
?? Plugin/VCPBridgeServer/bridge-config.json
?? sarprompt.json
```

### 11.2 执行日志（时间线）

```text
15:22  创建 docs/UPSTREAM_STASH_PULL_POP_CHECKLIST.md
15:27  备份 config.env；确认 local mirror 仍停在 6c24fa4
15:30  stash push -u → pre-upstream-sync-20260819
15:30  直连/多镜像 git ls-remote 失败；本地 7897/7890 代理端口关闭
15:31  curl+ghfast 下载 main.zip 成功（~176MB，备用）
15:34  git remote add upstream-mirror ghfast；fetch+ff-only → 31c3a371
15:34  stash pop 无冲突；恢复本地 ecosystem / 插件私有文件
15:35  PSE config.env 补缺 2 键；根 config 抽查 OK
15:35  pm2 start ecosystem；health 401 / admin 200
15:3x  pm2 save；commit 清单文档；push origin main
```

### 11.3 本次 Upstream 摘要（6c24fa4..31c3a371）

**主题：** PaperReader 大 PDF/MinerU 布局、PowerShellExecutor 1.1.0、RAG 占位符跨块修复、流式 RAG 刷新、SQLite 生命周期加固、rust-vexus-lite 更新、MiniMax music helper。

| 区域                      | 变更要点                                                                                                                      |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| **PaperReader**           | MinerU layout JSON；超页 PDF split；`paperreader-cli.exe` 更新；smoke 脚本增强                                                |
| **PowerShellExecutor**    | v1.1.0：PS7 优先、智能安全检查（路径不误判 rm）、BOM、VERBOSE_ERROR；新增 `config.env.example`                                |
| **RAGDiaryPlugin**        | 正则占位符禁止跨 block 匹配；DirectDiary/TDB 小修                                                                             |
| **chatCompletionHandler** | 流式 RAG 刷新 / 围栏增强（PR#449 相关）                                                                                       |
| **sqliteHealthManager**   | SQL/连接生命周期加固；`docs/OPERATIONS.md` 增加在线直连知识库红线                                                             |
| **rust-vexus-lite**       | 原生 node 二进制更新 + memo artifact 小改                                                                                     |
| **SKILL/frontend-dev**    | MiniMax music 模型/区域 endpoint 刷新                                                                                         |
| **根配置/依赖**           | `config.env.example`、`package.json`、`requirements.txt`、`ecosystem.config.js`、`preprocessor_order.json`：**本窗口无 diff** |

**破坏性/运维注意：**

- 主服务在线时 **禁止** 外部进程直接打开 `VectorStore/knowledge_base.sqlite`（见 OPERATIONS §8.0）。
- PowerShell 插件安全策略更严且更智能；若本地有自定义 `FORBIDDEN_COMMANDS`，保留本地值并只补缺新键。

### 11.4 未提交（有意保留在工作区）

```text
 M ecosystem.config.js          # 本地无 max_memory_restart 策略
 M Plugin/UserAuth/code.bin
 M Plugin/PowerShellExecutor/config.env   # 本地补键，勿推
?? Plugin/AgentAssistant/config.json      # 私有 44 agents — 勿推（未必 gitignore）
?? Plugin/AgentAssistant/*.bak_aa_*
?? Plugin/1PanelInfoProvider/
?? Plugin/VCPBridgeServer/bridge-config.json
?? config.env.bak_*
?? sarprompt.json
# config.env 永不提交
```

### 11.5 本轮日志门禁结论（flush 后）

| 文件                  | HARD 进程级        | 备注                                                           |
| --------------------- | ------------------ | -------------------------------------------------------------- |
| `vcp-main-error.log`  | 无崩溃/端口/未捕获 | 有功能降级：`ssh2`；SOFT：LightMemo ENOENT、空气质量 ETIMEDOUT |
| `vcp-main-out.log`    | 0                  | System Ready / AA Initialized / 多服务 listening               |
| `vcp-admin-error.log` | 0（空文件）        | 历史 EADDRINUSE 仅出现在 flush **前**，勿采信                  |
| `vcp-admin-out.log`   | 0                  | AdminPanel 地址正常                                            |
| HTTP                  | —                  | 6005/health **401**；6006/AdminPanel **200**                   |
| AA                    | —                  | `Config reloaded: 44 agents loaded.`                           |
| 天气                  | —                  | 城市 400 **已消失**；预警成功；AQI 超时另记                    |

**门禁：通过 → 已允许 docs-only push。**

---

## 12. 一页纸命令序（熟手用）

```powershell
cd D:\SoftwareDevelopCase\VCPToolBox
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
Copy-Item config.env "config.env.bak_$ts" -Force
git rev-parse HEAD | Tee-Object -Variable pre
git stash push -u -m "pre-upstream-sync-$ts"
# fetch+merge upstream（直连或镜像，见 §3）
git rev-parse HEAD
# 审 diff、补 config、处理插件
git stash pop
npm install --registry=https://registry.npmmirror.com
# pip 按需
# 建议：npx pm2 flush → delete all → start（§8.4 门禁）
npx pm2 start ecosystem.config.js
npx pm2 status
# 验证 HTTP + 双进程本轮日志无 HARD 后：
# 只 add docs/等安全路径；勿 add AA config.json
git push origin main
```

---

## 13. 与 VCPChat 的边界（勿混）

| 项目           | 更新方式                     | 记忆相关                                                                          |
| -------------- | ---------------------------- | --------------------------------------------------------------------------------- |
| **VCPToolBox** | 本文流程 + PM2               | 服务端插件/日记/向量                                                              |
| **VCPChat**    | 另仓 stash-pull；`npm start` | 客户端 CDS/DeepMemo；`npm run build` 仅编 Rust CDS，有预编译 exe 时本地可不 build |

VCPChat 不在本清单默认范围内，除非用户明确要求同步前端。

---

## 14. 问题台账（已处理 / 待商议）

> 同步与启动过程中踩过的坑。**已处理**可复用；**待商议**需用户拍板后再动。  
> 更新日期：2026-08-19。

### 14.1 已处理（Resolved）

| ID  | 问题                                 | 根因 / 现象                                                            | 处理                                                                                            | 文档锚点          |
| --- | ------------------------------------ | ---------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- | ----------------- |
| R1  | 同步摘要漏报 AA 配置格式变更         | 上游 `8311f03c` 起 runtime 只读 `config.json`；README 仍写 env         | 写清 §5.2.1；摘要强制点名；本机迁入 44 agents                                                   | §5.2.1、§8.5      |
| R2  | AA 短 json（~12）盖住长 env          | `migrateEnvToJson` **仅当 json 不存在**时跑；已有短 json 后改 env 无效 | 以长备份+HUAIJIN 重写 `config.json`；env 仅作镜像；`pm2 restart vcp-main` 见 `44 agents loaded` | §5.2.1            |
| R3  | AA 名称字段污染                      | 迁移把行尾注释/多余引号写进 name                                       | 清洗后再写入 json                                                                               | §8.5              |
| R4  | 模型策略                             | 旧 Pro / `gemini-3.1-pro` 不可用                                       | **全员** `gemini-3.7-flash`；ATHENA/JIYUXIN/MORPHEUS 留 `modelNote` 待新 Pro                    | 本地 json（勿推） |
| R5  | 根 `VarCity` 乱码 → 天气城市 **400** | UTF-8 被错误写入/BOM 导致 mojibake                                     | UTF-8 **无 BOM** 写回 `VarCity=防城港`；`pm2 restart vcp-main`；城市 400 消失                   | §0、§8.3          |
| R6  | PM2 日志误判                         | error 日志混入数月前 EADDRINUSE 等                                     | 门禁前 **`pm2 flush` → delete all → start**，只审本轮                                           | §8.4、§11.5       |
| R7  | 推 fork 带私钥风险                   | AA `config.json` **未**在 gitignore                                    | §9.1 明确禁止 add；本次仅 push docs                                                             | §9.1              |
| R8  | PSE 缺新键                           | 上游 v1.1.0 example 新增                                               | 本地 `config.env` 追加 `POWERSHELL_RETURN_MODE` / `VERBOSE_ERROR`（不提交）                     | §11               |
| R9  | GitHub 直连失败                      | 代理端口关闭 / 443 不稳                                                | `ghfast.top` upstream-mirror fetch + ff-only                                                    | §3、§11           |
| R10 | 编码 BOM                             | PS `Set-Content -Encoding utf8`                                        | 禁止；用 Node Buffer 或 `UTF8Encoding $false`                                                   | §0                |
| R11 | LAN IP                               | 历史 `192.168.1.100`                                                   | 统一 `127.0.0.1` 回调/本地 API                                                                  | §0                |
| R12 | PM2 冷启动死循环                     | `max_memory_restart` 误杀                                              | ecosystem **不写**该字段（本地保留）                                                            | §0、§9.2          |
| R13 | docs 推送                            | 清单 + §5.2.1                                                          | `8e464072`、`e3a5bfb6` → origin main                                                            | §11               |

### 14.2 待商议（Open / Decide）

| ID  | 事项                                  | 现状                                             | 选项 / 建议                                                                                            | 优先级     |
| --- | ------------------------------------- | ------------------------------------------------ | ------------------------------------------------------------------------------------------------------ | ---------- |
| O1  | **`ecosystem.config.js` 是否推 fork** | 本地无 `max_memory_restart`，与上游可能 diff     | A) 保持仅本地 B) commit 共享策略                                                                       | 中         |
| O2  | **AA `config.json` 是否 gitignore**   | 未忽略，易误 add                                 | 建议在 `.gitignore` 增加 `Plugin/AgentAssistant/config.json`（及 bak）；需确认是否有人要共享公开角色表 | 高         |
| O3  | **LinuxShellExecutor / `ssh2`**       | 缺模块，长待机/SSH 监控受限                      | `npm i ssh2` 或保持降级 / `.block`                                                                     | 低         |
| O4  | **LightMemo `semantic_groups.json`**  | ENOENT，无查询扩展                               | 按 RAG 文档补文件或忽略                                                                                | 低         |
| O5  | **天气空气质量 ETIMEDOUT**            | 打到 `198.18.1.1:443`（常见于代理/虚拟网卡路由） | 查系统代理/TUN；城市与预警已 OK 可暂缓                                                                 | 中         |
| O6  | **VCPClawMail 等可选 SDK**            | 历史/按需缺邮件 SDK                              | 不用则 block；要用再装                                                                                 | 低         |
| O7  | **PaperReader 仍 `.block`**           | 上游大更新但未启用                               | 需要 PDF 工作流时再启并测 CLI                                                                          | 低         |
| O8  | **`Plugin/1PanelInfoProvider/`**      | untracked 本地插件                               | 推 fork？保留本地？删除？                                                                              | 中         |
| O9  | **主机 RAM ~90%+**                    | 双进程+向量后偏高                                | 关不用插件 / 加内存 / 观察；**不要**用 max_memory_restart 硬杀                                         | 中         |
| O10 | **代理 7897/7890**                    | 常关导致 git/部分 API 不稳                       | 固定「开发时开代理」或继续 ghfast                                                                      | 中         |
| O11 | **FFmpeg PATH / AICodeWorker 路径**   | Windows 勿盲填 Linux 路径                        | 用到再配                                                                                               | 低         |
| O12 | **旧 stash**                          | 如 `pre-upstream-sync-20260816`                  | `stash list` 审后 drop 或保留                                                                          | 低         |
| O13 | **模型切回 Pro**                      | 三 agent 已 modelNote                            | 等官方可用新 Pro 后再改 `modelId`                                                                      | 低         |
| O14 | **VCPChat**                           | 已另仓同步过；默认不推                           | 用户点名再动                                                                                           | —          |
| O15 | **同步摘要质量**                      | 曾漏 AA 格式                                     | 每次摘要必须：新插件 + **破坏性配置** + 已启用插件 config diff                                         | 高（流程） |

### 14.3 建议下次同步时多做的 30 秒检查

```text
1. git log PRE..POST --oneline + 扫 Plugin/*/ 新目录
2. 对已启用插件：config.env.example / config.json 模板是否有新键
3. 点名 AgentAssistant：config.json 是否存在、agents 数量是否符合预期
4. 根 config.env：UTF-8 无 BOM；VarCity/回调 URL 抽查
5. pm2 flush 后干净启动 → §8.4 门禁 → 再谈 push
6. git status：AA json、code.bin、bridge、bak 永不 add
```
