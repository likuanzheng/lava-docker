# lava-docker 工作流

唯一源：`user-data/devices/<name>.yaml`（一台一文件，文件名 == name）、
`user-data/device-types/*.jinja2`、`user-data/job-templates/`、`user-data/lab.yaml`。
其余（`boards.yaml`、`user-data/jobs/`、`user-data/device-dicts/`、`output/`）都是生成产物。

每件事一条命令（脚本已把生成步骤折叠进去）：

| # | 做什么 | 命令 | 重 build / compose up |
|---|---|---|---|
| 1 | 部署空集群（1 master + 1 slave） | `./deploy-cluster.sh` | 是 |
| 2 | 注入设备（类型→板级→字典，一步到位） | `./user-data/reload-all.sh` | 否 |
| 3 | 提交 job | `./user-data/submit-job.sh <job.yaml>` | 否 |

> 第 2~3 步都对**运行中的集群**经 lavacli 操作，幂等可重复跑。
> 第 2 步 `reload-all.sh` 按严格依赖顺序串起 device-types → devices → device-dicts
> （板级 add 需类型存在；dict set 需设备已注册）；数据源全部来自 `user-data/`。
> 入口脚本（`reload-all.sh` / `submit-job.sh` / `gen-jobs.py`）在 `user-data/` 顶层；
> 被它们调用的内部脚本收在 `user-data/scripts/`。如需单独跑某一环，分别调用
> `scripts/reload-device-types.sh` / `scripts/reload-devices.sh` / `scripts/reload-device-dicts.sh`。

---

## 1. 部署空集群
```sh
./deploy-cluster.sh
```
= `gen-boards.py`（拼拓扑，无设备）→ `lavalab-gen.sh` → `compose build + up`。
起来后：slave 已连为 worker，**设备为空**。web UI http://localhost:10070（ywyh / ywyh@204）。

## 2. 注入设备（类型 → 板级 → 字典，一步到位）
```sh
# 改/加 设备类型、设备：只改 user-data/ 下的源文件
$EDITOR user-data/device-types/<type>.jinja2     # 设备类型模板
$EDITOR user-data/devices/<name>.yaml            # 一台一文件，文件名 == name
                                                 # device_type / slave / connection_command / power / tags ...
# 一步注入到运行中的集群（严格依赖顺序，全程幂等）：
./user-data/reload-all.sh
```
`reload-all.sh`（顶层入口）依次执行 `scripts/` 下三个内部脚本：
1. `scripts/reload-device-types.sh` —— 软链类型模板并注册（`device-types add`）
2. `scripts/reload-devices.sh` —— 渲染 `device-dicts/` → `lavacli devices add/update`（类型/worker/tags/health）
3. `scripts/reload-device-dicts.sh` —— `lavacli devices dict set`（连接/电源等 dict 内容）

> 数据源全部来自 `user-data/`。需要单独跑某一环（如只改了 `connection_command`/`power`，
> 只需第 3 环）时，可分别调用上面三个 `scripts/` 脚本；拿不准就跑 `reload-all.sh`（幂等）。

## 3. 提交 job
```sh
python3 user-data/gen-jobs.py                                   # 改过 jobs:/模板才需要
./user-data/submit-job.sh user-data/jobs/xt-c100-001-boot.yaml  # 返回 job id
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
  mqtt_topic: <topic>          # 开机/硬复位命令由 gen-device-dicts 内联生成，无需脚本文件
jobs:                   # 可选，要出 job 才写
  boot: { job: 10, action: 5, test: 2 }
# 可选：tags / aliases / user / group / 各 job 模板用到的字段
```

### 改了基础设施 / 加 slave 节点
改 `user-data/lab.yaml` 后重跑 `./deploy-cluster.sh`（这才需要 compose up）。

---

## tftp 目录约定

`user-data/tftp/` 经 `lab.yaml` bind-mount 进 slave 的 `/var/lib/lava/dispatcher/tmp/tftp`，
由 TFTP + HTTP（`http://<serverip>/tmp/tftp/...`）同时对外服务。**整体是可删的运行时数据、不入库**
（`.gitignore`，仅留 `.gitkeep` 固化骨架）；里面的东西要么运行时灌入、要么由生成器物化。两类用途分目录：

```
user-data/tftp/
├── <device_type>/            ① 下行·易失：发给设备的产物（image.ub / rootfs.* / Image / dtb / BOOT.BIN …）
│   └── flash.sh / backup.sh    job 配套脚本，由 gen-jobs.py 物化（源在 job-templates/<dt>/，目前仅 xz-a100）
├── _backup/<device_type>/    ② 上行·缓存：job 写回的备份（xt-c100 经 tftpput、xz-a100 经 ssh+dd）
└── .gitkeep                    过渡用本地缓存，后续交 Nexus 管理
```

约定：
- **下行产物随用随放、用完可清**；job 按固定路径 `tftp/<device_type>/<artifact>` 下载（模板用 `{{ device_type }}` 参数化）。
- **备份一律落 `tftp/_backup/<device_type>/`**；`_backup/<device_type>/` 必须 `chmod 0777`（tftpput 由容器内 tftp 守护进程写入，需可写；`deploy-cluster.sh` 已自动建目录赋权）。
- **job 配套脚本是 job 源、不是 tftp 数据**：源放 `job-templates/<dt>/*.sh`（要按设备/lab 取值用 `*.sh.j2`，可用 `serverip`/`ssh_user`/`device_type`），`gen-jobs.py` 渲染/拷贝进 `tftp/<dt>/`。改脚本改源后跑 `python3 user-data/gen-jobs.py`；**别改 tftp 里的产物副本**（会被下次生成覆盖）。
- **host 侧工具不放服务树**：如 `inject-ssh-key.sh`（在 host 改 uInitrd）放 `user-data/tools/`，不经 TFTP/HTTP 暴露。
- 改备份**落点路径**还须同步 `job-templates/xt-c100/backup.yaml.j2`（tftpput 落点）与上述 `*.sh.j2`，再 `gen-jobs.py` 重生成。
