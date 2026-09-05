# VCPToolBox 生产升级 SOP（客户 / 运维 / CLI Agent）

> **唯一生产真源。** 客户部署、本机服务升级、snow-cli / 自动化 Agent 只执行本文。  
> 开发者向上游提 PR：见 [`VCPToolbox更新与配置管理流程.txt`](./VCPToolbox更新与配置管理流程.txt)（rebase 流，禁止当生产手册）。  
> 本机历史 runbook 与踩坑台账：[`UPSTREAM_STASH_PULL_POP_CHECKLIST.md`](./UPSTREAM_STASH_PULL_POP_CHECKLIST.md)。

**适用：** 已配置 `origin`（fork）+ `upstream`（`lioensky/VCPToolBox`）、分支 `main`、PM2 双进程（`vcp-main` / `vcp-admin`）。  
**不适用：** 交互式 rebase、默认 commit/push、自动 `git reset --hard`。

---

## 0. 硬门禁（每次必读）

| 规则           | 说明                                                                                                                                                  |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| **无交互**     | 只用 `git fetch` + `git merge --ff-only`。不能快进则 **非零退出**，禁止 `rebase` / `stash pop` 在无 TTY 环境挂起。                                    |
| **物理备份**   | `config.env` 被 `.gitignore` 忽略。`git stash -u` **不会**收集它。必须拷到**仓库外**备份目录。                                                        |
| **先停机**     | 替换磁盘文件前 `npx pm2 stop vcp-main vcp-admin`，避免 `.node` 锁与 SQLite 半写。                                                                     |
| **配置补缺**   | 对照 `config.env.example` **只追加缺失键**，禁止用 example 整文件覆盖。Windows 写回必须 **UTF-8 无 BOM**。                                            |
| **AA 真源**    | `Plugin/AgentAssistant/config.json`（不是 `config.env`）。该文件已 gitignore，仍禁止 `git add`。                                                      |
| **PM2 名**     | `vcp-main` + `vcp-admin`。不存在名为 `VCPToolBox` 的实例。不要加 `max_memory_restart`。                                                               |
| **探针**       | `http://127.0.0.1:6005/health` 允许 **200 或 401**（全局 Key 鉴权时常 401）。`http://127.0.0.1:6006/AdminPanel` 期望 **200**。禁止把 401 当失败回滚。 |
| **失败策略**   | 失败只 **停机 + 保留备份 + 写报告**。**严禁** Agent 自动 `git reset --hard` / force-push / 未经用户同意回滚 Git 或向量库。                            |
| **默认不推送** | 生产升级成功 ≠ commit。禁止 `git add .`。                                                                                                             |
| **update.bat** | 已改为安全拦截，**不会**再执行裸 `git pull`。                                                                                                         |

### 常用路径

```text
仓库根：     <clone>/VCPToolBox          （本机示例 D:\SoftwareDevelopCase\VCPToolBox）
配置：       config.env                  （gitignore，本地真源）
模板：       config.env.example
AA 角色表：  Plugin/AgentAssistant/config.json
PM2：        ecosystem.config.js
外部备份：   仓库外目录，例如 D:\SoftwareDevelopCase\vcp_local_backup_<timestamp>
日志：       %USERPROFILE%\.pm2\logs\    （Linux: ~/.pm2/logs/）
主服务：     http://127.0.0.1:6005
管理面板：   http://127.0.0.1:6006/AdminPanel
健康检查：   http://127.0.0.1:6005/health   （401 属预期）
```

根 `package.json` **没有** `build` 脚本。不要跑 `npm run build` / `npm ci --production` 当升级默认动作。Rust 原生模块仅在 `rust-vexus-lite` 源码或绑定有 diff 时再构建。

---

## 1. 预检（失败即停）

在仓库根执行（PowerShell 示例，Linux 把盘符路径换成实际 clone）：

```powershell
cd D:\SoftwareDevelopCase\VCPToolBox

git status -sb
git remote -v
git branch -vv
git rev-parse HEAD          # 记为 PRE_HEAD
git stash list
npx pm2 status
```

**通过条件：** 能看到 `upstream` 指向 `lioensky/VCPToolBox`，当前在 `main`。  
工作区可以脏，但必须进入下一步备份 +（如有已跟踪改动）stash。

---

## 2. 仓库外物理备份

```powershell
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$backup = "D:\SoftwareDevelopCase\vcp_local_backup_$ts"
New-Item -ItemType Directory -Force -Path $backup | Out-Null

Copy-Item config.env (Join-Path $backup 'config.env') -Force
if (Test-Path 'Plugin\AgentAssistant\config.json') {
  Copy-Item 'Plugin\AgentAssistant\config.json' (Join-Path $backup 'AgentAssistant.config.json') -Force
}

# 可选整树（排除体积与可再生目录；不要把备份写进仓库 .backup/）
# robocopy . $backup /E /XD node_modules venv .git VectorStore VectorStoreTDB tmp logs DebugLog /NFL /NDL /NJH /NJS
```

Linux：

```bash
ts=$(date +%Y%m%d_%H%M%S)
backup="${BACKUP_ROOT:-/var/backups}/vcp_local_backup_$ts"
mkdir -p "$backup"
cp -p config.env "$backup/config.env"
[ -f Plugin/AgentAssistant/config.json ] && cp -p Plugin/AgentAssistant/config.json "$backup/AgentAssistant.config.json"
```

**不要**备份进仓库内 `.backup/` 再 `git add`。

---

## 3. 优雅停机

```powershell
npx pm2 stop vcp-main vcp-admin
```

主服务在线时 **禁止** 外部进程打开 `VectorStore/knowledge_base.sqlite`。

---

## 4. 已跟踪本地补丁：stash（可选，不含 ignore 文件）

```powershell
git status -sb
# 仅当有已跟踪修改时：
git stash push -m "pre-upstream-sync-$ts"
# 需要未跟踪且未被 ignore 的文件时才加 -u。
# -u 仍然不会带走 config.env / **/config.env / AA config.json。
```

`git stash show -p` **看不到** untracked。预览用：`git stash show -u --stat`。

---

## 5. 确定性拉取（禁止交互挂起）

```powershell
git fetch upstream main
if ($LASTEXITCODE -ne 0) { Write-Error 'fetch failed'; exit 1 }

git log --oneline HEAD..upstream/main | Select-Object -First 80
git merge --ff-only upstream/main
if ($LASTEXITCODE -ne 0) {
  Write-Error 'cannot fast-forward; local commits or dirty history — stop for human audit'
  git status -sb
  exit 1
}

git rev-parse HEAD   # POST_HEAD
```

GitHub 443 失败时用镜像或本地 mirror（详见 checklist §3.B / §3.C），**不要**把网络失败当成配置冲突去改文件。

不能 `--ff-only`：立刻退出。不要 rebase，不要 merge 出额外提交，除非人明确改策略。

---

## 6. 配置增量对齐（Diff-Fill）

原则：**本地已有值为准**；example 有、本地无 → 追加；禁止覆盖密钥。

核对 `PRE_HEAD..HEAD`：

```powershell
git log --oneline PRE_HEAD..HEAD
git diff --stat PRE_HEAD..HEAD
git diff PRE_HEAD..HEAD -- config.env.example ecosystem.config.js preprocessor_order.json package.json requirements.txt
git diff --name-status PRE_HEAD..HEAD -- Plugin/
```

必查：

| 对象                                                                     | 动作                                                  |
| ------------------------------------------------------------------------ | ----------------------------------------------------- |
| 根 `config.env` vs `config.env.example`                                  | 补缺键；`CALLBACK_BASE_URL` 等本机策略保留            |
| 已启用插件 `config.env.example`                                          | 对本地 `Plugin/<Name>/config.env` 补缺                |
| **AgentAssistant**                                                       | 只维护 `config.json`；改 env **不会生效**             |
| `preprocessor_order.json`                                                | 新 preprocessor 是否要插入（文件可能被 gitignore）    |
| `agent_map.json` / `SemanticModelRouter.json` / `multimodal-config.json` | 有 example 则对照补缺                                 |
| 新插件                                                                   | 默认可先 `plugin-manifest.json.block`，依赖就绪再启用 |

Windows：**禁止** `Set-Content -Encoding utf8`（会写 BOM，`VarCity` 乱码 → 天气 400）。用 Node `fs.writeFileSync(p, Buffer.from(text,'utf8'))` 或 `[IO.File]::WriteAllText($p,$t,(New-Object Text.UTF8Encoding $false))`。

配置优先级（代码）：**插件目录 config.env > 根 config.env > manifest 默认值**。天气 Key、Tavily、B 站 cookie 等在**根**配置，不是只改插件目录。

然后恢复 stash（若有）：

```powershell
git stash pop
# 冲突则改用 apply，解决后再 drop；Agent 遇冲突非零退出，不交互 rebase
```

---

## 7. 依赖（按 diff，不要每次全量）

```powershell
git diff PRE_HEAD HEAD -- package.json package-lock.json requirements.txt pyproject.toml
```

- 根 lock/package 有变：`npm install`（可用 `https://registry.npmmirror.com`）。不要默认 `npm ci --production`。
- `requirements.txt` 有变：`python -m pip install -r requirements.txt`
- `Plugin/` 新增或变更子 `package.json` / `requirements.txt` 才进该目录安装
- `rust-vexus-lite` 源码或 `.node` 绑定有变才考虑 `cd rust-vexus-lite; npm run build`
- `AdminPanel-Vue`：仓内通常已带 `dist/`；仅源码变且 dist 未更新时才 `npm run build:admin`

---

## 8. 拉起与分层探针

冷启动知识库可能到**分钟级**。禁止 `sleep 5` + 失败就 Git 回滚。

```powershell
npx pm2 flush
npx pm2 delete all
npx pm2 start ecosystem.config.js
Start-Sleep -Seconds 20
npx pm2 status
npx pm2 save
```

### Gate A — 进程（约 20s）

`vcp-main`、`vcp-admin` 均为 `online`，无疯狂 restart。失败：保持 **stop**，读 `%USERPROFILE%\.pm2\logs\vcp-*-error.log`，**不要** reset Git。

### Gate B — HTTP

| URL                                | 通过           |
| ---------------------------------- | -------------- |
| `http://127.0.0.1:6005/health`     | **200 或 401** |
| `http://127.0.0.1:6006/AdminPanel` | **200**        |

没有 `/api/health`。不要用 `curl -f` 把 401 判死。

PowerShell：

```powershell
function Probe($url) {
  try {
    $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15
    return [int]$r.StatusCode
  } catch {
    if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode.value__ }
    throw
  }
}
$code5 = Probe 'http://127.0.0.1:6005/health'
$code6 = Probe 'http://127.0.0.1:6006/AdminPanel'
if ($code5 -notin 200,401) { Write-Error "6005 unexpected $code5"; exit 1 }
if ($code6 -ne 200) { Write-Error "6006 unexpected $code6"; exit 1 }
```

### Gate C — 日志 HARD / SOFT（观察，默认不回滚 Git）

先 `pm2 flush` 再启，只审**本轮**日志。

| 级别           | 例                                                                                 | 是否挡主服务                                |
| -------------- | ---------------------------------------------------------------------------------- | ------------------------------------------- |
| **HARD**       | UnhandledRejection / listen 失败 / EADDRINUSE / heap OOM / DB malformed / 立刻退出 | 停机报修                                    |
| **SOFT**       | 可选插件缺 `ssh2`、外网超时、WARN                                                  | 不挡；记入报告                              |
| **Ready 观察** | `[KnowledgeBase] System Ready`、`Config reloaded: N agents loaded`                 | 可等数分钟；超时记报告，默认不自动 rollback |

---

## 9. 失败处理（Rollback 边界）

允许自动做：

1. `npx pm2 stop vcp-main vcp-admin`（或保持已停止）
2. 指出备份目录与 `PRE_HEAD`
3. 打印 `git status`、本轮 error log 路径

**禁止**自动做：`git reset --hard`、`git checkout --force`、force-push、删除 `VectorStore`、用备份覆盖正在写的 sqlite。

配置回滚（仅人确认后）：从外部备份拷回 `config.env` / AA `config.json`（UTF-8 无 BOM）。

代码回滚（仅人确认后）：`git merge --ff-only` 失败本就不会改 HEAD；若已快进且必须退回：由用户批准后再 `git reset --hard PRE_HEAD`（会丢未提交工作区）。

---

## 10. 成功收尾

生产客户：**到此结束**。不要默认 `git commit` / `git push`。

Fork 维护者若要推共享文档/补丁：只 `git add` 白名单路径；黑名单：`config.env`、`Plugin/AgentAssistant/config.json`、`code.bin`、`*.bak_*`、本地私有插件目录。推送前再跑一遍 Gate A/B。详见 checklist §8.4 / §9。

清理：审 `git stash list`；过期 stash 人工 drop。至少留一份最近成功的 `config.env` 外部备份。

---

## 11. 一页纸命令序（熟手 / Agent）

```powershell
cd D:\SoftwareDevelopCase\VCPToolBox
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pre = git rev-parse HEAD
$backup = "D:\SoftwareDevelopCase\vcp_local_backup_$ts"
New-Item -ItemType Directory -Force -Path $backup | Out-Null
Copy-Item config.env "$backup\config.env" -Force
npx pm2 stop vcp-main vcp-admin
git stash push -m "pre-upstream-sync-$ts"   # 无已跟踪改动可跳过
git fetch upstream main
git merge --ff-only upstream/main           # 失败则 exit 1
# 审 diff、补 config.env 缺失键、检查 AA config.json
git stash pop                               # 若做过 stash；冲突则 exit 1
# npm install / pip 仅当 package.json 或 requirements 有 diff
npx pm2 flush
npx pm2 delete all
npx pm2 start ecosystem.config.js
Start-Sleep -Seconds 20
# Probe 6005 in (200,401) and 6006 -eq 200
# HARD log 失败：停机报告，禁止 git reset
```

---

## 12. 文档关系

| 文档                                                                             | 角色                                                  |
| -------------------------------------------------------------------------------- | ----------------------------------------------------- |
| **本文**                                                                         | 生产 / 客户 / CLI Agent 升级                          |
| [`UPSTREAM_STASH_PULL_POP_CHECKLIST.md`](./UPSTREAM_STASH_PULL_POP_CHECKLIST.md) | 本机详细 runbook、镜像 fetch、AA 破坏性变更、问题台账 |
| `Docs/VCPToolbox更新与配置管理流程.txt`                                          | **仅**开发者 PR（rebase）；不得用于生产               |
| `update.bat`                                                                     | 安全拦截；指向本文                                    |
| [`OPERATIONS.md`](./OPERATIONS.md) §9                                            | 升级入口，转发到本文                                  |
