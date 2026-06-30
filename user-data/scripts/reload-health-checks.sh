#!/bin/sh
# 向运行中的 master 注入 device-type 级健康检查 job。
# 源：job-templates/<dt>/healthcheck.yaml（设备无关的自检 job，按 device-type 关联）。
# 落点：master:/etc/lava-server/dispatcher-config/health-checks/<dt>.yaml，
#   LAVA 调度器按设备类型的健康检查频率（默认约 24h）自动在该类型设备上跑：过=Good、挂=Bad。
# 设备类型须已注册（先跑 reload-device-types.sh）。运行时注入，无需 rebuild，幂等可重复跑。
set -e
cd "$(dirname "$0")"
HC_DIR=/etc/lava-server/dispatcher-config/health-checks

cd ../../output/local
found=0
for hc in ../../user-data/job-templates/*/healthcheck.yaml; do
	[ -e "$hc" ] || continue
	dt=$(basename "$(dirname "$hc")")
	echo "注入 health-check: $dt"
	docker compose cp "$hc" "master1:$HC_DIR/$dt.yaml"
	found=1
done

if [ "$found" = 1 ]; then
	docker compose exec -T master1 chown -R lavaserver:lavaserver "$HC_DIR"
	echo "health-checks 注入完成（LAVA 按频率自动跑；频率在 admin / lava-server manage device-types 可调）。"
else
	echo "无 job-templates/*/healthcheck.yaml，跳过。"
fi
