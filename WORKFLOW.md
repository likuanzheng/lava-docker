# lava-docker 工作流

唯一源：`user-data/devices/<name>.yaml`（一台一文件，文件名 == name）、
`user-data/device-types/*.jinja2`、`user-data/job-templates/`、`user-data/lab.yaml`。
其余（`boards.yaml`、`user-data/jobs/`、`user-data/device-dicts/`、`output/`）都是生成产物。

每件事一条命令（脚本已把生成步骤折叠进去）：

| # | 做什么 | 命令 | 重 build / compose up |
|---|---|---|---|
| 1 | 部署空集群（1 master + 1 slave） | `./deploy-cluster.sh` | 是 |
| 2 | 加/更新 device-types（设备类型） | `./reload-device-types.sh` | 否 |
| 3 | 加/更新 devices 板级定义 | `./reload-devices.sh` | 否 |
| 4 | 加/更新 设备字典（dict 内容） | `./reload-device-dicts.sh` | 否 |
| 5 | 提交 job | `./submit-job.sh <job.yaml>` | 否 |

> 第 2~5 步都对**运行中的集群**经 lavacli 操作，幂等可重复跑。
> 顺序依赖：3 在 2 之后（板级 add 需类型存在）；4 在 3 之后（dict set 需设备已注册）。

---

## 1. 部署空集群
```sh
./deploy-cluster.sh
```
= `gen-boards.py`（拼拓扑，无设备）→ `lavalab-gen.sh` → `compose build + up`。
起来后：slave 已连为 worker，**设备为空**。web UI http://localhost:10070（ywyh / ywyh@204）。

## 2. 添加/更新 device-types
```sh
# 改已有类型模板：软链实时生效，下个 job 渲染即用，无需跑任何命令。
# 新增类型：先建模板，再注册到 master：
$EDITOR user-data/device-types/<newtype>.jinja2
./reload-device-types.sh
```

## 3. 添加/更新 devices 板级定义
```sh
# 新增设备：建一台一文件（文件名 == name）
$EDITOR user-data/devices/<name>.yaml      # device_type / slave / connection_command / power / tags ...
./reload-devices.sh
```
= 渲染 `device-dicts/` → 容器内 `lavacli devices add/update`（类型/worker/tags/health）。

## 4. 添加/更新 设备字典
```sh
./reload-device-dicts.sh
```
= 渲染 `device-dicts/` → 容器内 `lavacli devices dict set`（连接/电源等 dict 内容）。

> 改了某设备的 `connection_command`/`power` 后只需此步；改了 worker/type/tags 用第 3 步。
> 拿不准就 3、4 都跑（幂等）。

## 5. 提交 job
```sh
python3 gen-jobs.py                                   # 改过 jobs:/模板才需要
./submit-job.sh user-data/jobs/xt-c100-001-boot.yaml  # 返回 job id
```
设备需已注册且 online（worker 连上 + 健康检查通过），否则 job 在队列等待。

---

### 设备文件最小字段
```yaml
name: <name>            # 必须 == 文件名
device_type: <type>
slave: lab-slave-0
connection_command: telnet <host> <port>
power:
  mqtt_topic: <topic>
  reset_script: <脚本名，位于 user-data/power/>
jobs:                   # 可选，要出 job 才写
  boot: { job: 10, action: 5, test: 2 }
# 可选：tags / aliases / user / group / 各 job 模板用到的字段
```

### 改了基础设施 / 加 slave 节点
改 `user-data/lab.yaml` 后重跑 `./deploy-cluster.sh`（这才需要 compose up）。
