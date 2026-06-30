#!/bin/sh
# 第 1 步：部署「空」集群（1 master + 1 slave）。
# 拼装拓扑 boards.yaml（无设备）→ 重建 output/ → docker compose build + up。
# 起来后 slave 只注册 worker，设备为空；device-types/devices 由后续步骤经 lavacli 注入。
set -e
cd "$(dirname "$0")"

# tftp 备份落点：git 不保存目录权限，部署时确保 _backup/<device_type>/ 存在且 0777
# （tftpput 由容器内 tftp 守护进程写入，需可写；见 WORKFLOW「tftp 目录约定」）。
mkdir -p user-data/tftp/_backup
for t in user-data/device-types/*.jinja2; do
	[ -e "$t" ] || continue
	mkdir -p "user-data/tftp/_backup/$(basename "$t" .jinja2)"
done
chmod -R 0777 user-data/tftp/_backup

python3 gen-boards.py
./lavalab-gen.sh boards.yaml
cd output/local && ./deploy.sh
