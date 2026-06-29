#!/bin/sh
# 运行时刷新 device-types，无需 rebuild、无需重启容器。
#
# 用法：改完 user-data/device-types/*.jinja2 后跑本脚本。
#  - 改已有类型：其实软链已实时生效，本脚本主要用于「新增类型」时把新模板软链进
#    LAVA 运行时目录并注册（lava-server manage device-types add）。
#  - 模板源经 bind mount 已在容器内 /root/device-types/ 可见。
set -e
cd "$(dirname "$0")/output/local"

docker compose exec -T master1 sh -c '
  for i in /root/device-types/*.jinja2; do
    [ -e "$i" ] || continue
    ln -sf "$i" /etc/lava-server/dispatcher-config/device-types/$(basename "$i")
    chown -h lavaserver:lavaserver /etc/lava-server/dispatcher-config/device-types/$(basename "$i")
    dt=$(basename "$i" .jinja2)
    if lava-server manage device-types --no-color list | grep -qw "$dt"; then
      echo "已有 $dt（模板已刷新）"
    else
      echo "注册新 device-type $dt"
      lava-server manage device-types add "$dt"
    fi
  done'
