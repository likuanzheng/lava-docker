#!/bin/sh
# 一步注入：按严格依赖顺序把 user-data/ 里的设备类型/设备/设备字典推到运行中的集群。
#   1) device-types（设备类型）——板级注册的前置
#   2) devices（板级定义）——dict set 的前置
#   3) device-dicts（连接/电源等 dict 内容）
# 三者数据源全部限定在 user-data/（device-types/ + devices/ → 渲染出 device-dicts/）。
# 全程对运行中的集群经 lavacli 操作，无需 rebuild，幂等可重复跑。
set -e
cd "$(dirname "$0")"

./scripts/reload-device-types.sh
./scripts/reload-devices.sh
./scripts/reload-device-dicts.sh

echo "reload-all 完成：device-types / devices / device-dicts 已注入集群。"
