#!/bin/sh
# 第 4 步：向运行中的集群添加/更新「设备字典」（connection_command/power 等 dict 内容）。
# 渲染并把设备字典 docker cp 进 slave（设备字典不再 bind-mount）→ 容器内经 lavacli
# devices dict set 推到 master。设备需已注册（先跑第 3 步）。无需 rebuild，幂等。
set -e
cd "$(dirname "$0")"

./push-device-dicts.sh
cd ../output/local && docker compose exec -T lab-slave-0 /usr/local/bin/register-device-dicts.sh
