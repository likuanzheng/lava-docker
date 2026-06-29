#!/bin/sh
# 以 user-data/device-types 为 device-type 定义的唯一来源，构建前同步进
# lava-master/device-types/（master 镜像构建目录）。
#
# 数据流：user-data/device-types/*.jinja2
#          └─(本脚本拷贝)→ lava-master/device-types/*.jinja2   [生成产物，已 .gitignore]
#              └─(lavalab-gen.sh 复制)→ output/local/master1/device-types/
#                  └─(Dockerfile COPY)→ master 镜像
#
# 运行顺序：./sync-device-types.sh → python3 gen-jobs.py → ./lavalab-gen.sh boards.yaml
#           → cd output/local && ./deploy.sh
set -e

cd "$(dirname "$0")"
cp user-data/device-types/*.jinja2 lava-master/device-types/
echo "已同步 device-types → lava-master/device-types/:"
ls -1 lava-master/device-types/*.jinja2
