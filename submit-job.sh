#!/bin/sh
# 第 5 步：向集群提交一个 job。
# 用法：./submit-job.sh user-data/jobs/xt-c100-001-boot.yaml
# 经 slave 容器内的 lavacli 提交到 master（无需本机装 lavacli）。设备需已注册且 online。
set -e

JOB="$1"
if [ -z "$JOB" ] || [ ! -f "$JOB" ]; then
	echo "用法: $0 <job.yaml>   （如 user-data/jobs/xt-c100-001-boot.yaml）"
	exit 1
fi
JOB_ABS=$(cd "$(dirname "$JOB")" && pwd)/$(basename "$JOB")

cd "$(dirname "$0")/output/local"
MURI='http://ywyh:longrandomtokenadmin@master1:80/RPC2'

docker compose cp "$JOB_ABS" lab-slave-0:/tmp/job.yaml
docker compose exec -T lab-slave-0 lavacli --uri "$MURI" jobs submit /tmp/job.yaml
