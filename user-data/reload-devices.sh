#!/bin/sh
# 第 3 步：向运行中的集群添加/更新 devices「板级定义」（名字/类型/worker/tags/health）。
# 渲染并把设备字典 docker cp 进 slave（设备字典不再 bind-mount）→ 容器内经 lavacli
# upsert 板级定义到 master。不含 dict 内容（见 reload-device-dicts.sh）。无需 rebuild，幂等。
set -e
cd "$(dirname "$0")"

./push-device-dicts.sh
cd ../output/local && docker compose exec -T lab-slave-0 /usr/local/bin/register-devices.sh
