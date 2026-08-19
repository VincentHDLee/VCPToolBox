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
- [ ] 错误日志无「立刻退出」级致命错误（缺可选依赖的 warn 可记录但不阻断）

### 8.3 失败时修复循环

1. 读 `vcp-main-error.log` / `vcp-admin-error.log`
2. 分类：配置键缺失 / 依赖缺失 / 端口占用 / 编码乱码 / 插件 fatal
3. 修 → `npx pm2 restart ecosystem.config.js` → 再验证
4. 仍失败：`npx pm2 stop all`，保留日志路径，升级排查（勿强推 fork）

常见：

| 现象         | 处理                                                |
| ------------ | --------------------------------------------------- |
| 端口占用     | `netstat -ano \| findstr :6005` 后结束占用或改 PORT |
| admin 起不来 | 查 `ADMIN_PORT`、是否误解析多 PORT                  |
| 插件缺模块   | 按需 `npm i <pkg>` 或暂时 `.block`                  |
| 中文配置乱码 | 从 `.bak_*` 按 UTF-8 无 BOM 重建                    |
| RSS 被杀循环 | 确认没有 `max_memory_restart`                       |

---

## 9. 推送到 Fork

**仅在启动验证通过后：**

```powershell
git status -sb
git log origin/main..HEAD --oneline

# 只推送已提交的上游同步结果；本地脏文件（config.env、私有 json）不要 commit
git push origin main
# 若使用 vcp-fork 同 URL，二者等价
```

**检查项：**

- [ ] 无密钥进入即将 push 的 commit
- [ ] `origin/main` 与本地 `HEAD` 一致
- [ ] 推送成功

若有需要保留的 **非密钥** 本地提交（如 ecosystem 注释强化），单独 commit 后再 push，commit message 写清原因。

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
?? Plugin/* 私有 config / 1Panel
?? config.env.bak_*
?? sarprompt.json
# config.env 永不提交
```

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
npx pm2 start ecosystem.config.js
npx pm2 status
# 验证 HTTP 后：
git push origin main
```

---

## 13. 与 VCPChat 的边界（勿混）

| 项目           | 更新方式                     | 记忆相关                                                                          |
| -------------- | ---------------------------- | --------------------------------------------------------------------------------- |
| **VCPToolBox** | 本文流程 + PM2               | 服务端插件/日记/向量                                                              |
| **VCPChat**    | 另仓 stash-pull；`npm start` | 客户端 CDS/DeepMemo；`npm run build` 仅编 Rust CDS，有预编译 exe 时本地可不 build |

VCPChat 不在本清单默认范围内，除非用户明确要求同步前端。
