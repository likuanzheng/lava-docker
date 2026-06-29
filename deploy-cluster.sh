#!/bin/sh
# 第 1 步：部署「空」集群（1 master + 1 slave）。
# 拼装拓扑 boards.yaml（无设备）→ 重建 output/ → docker compose build + up。
# 起来后 slave 只注册 worker，设备为空；device-types/devices 由后续步骤经 lavacli 注入。
set -e
cd "$(dirname "$0")"

python3 gen-boards.py
./lavalab-gen.sh boards.yaml
cd output/local && ./deploy.sh
