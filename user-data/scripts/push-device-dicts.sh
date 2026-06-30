#!/bin/sh
# 内部 helper（被 reload-devices.sh / reload-device-dicts.sh 调用，一般不单独跑）。
# 渲染设备字典（host，中间产物）→ 清掉 slave 容器里的旧目录 → docker cp 注入最新的
# devices/tags/aliases/deviceinfo → 清掉 host 端中间产物。设备字典不再 bind-mount，
# 注册后内容已进 master DB；先清后拷保证删掉的设备不残留。
set -e
cd "$(dirname "$0")"

python3 gen-device-dicts.py

cd ../../output/local
docker compose exec -T lab-slave-0 rm -rf /root/devices /root/tags /root/aliases /root/deviceinfo
for d in devices tags aliases deviceinfo; do
	docker compose cp "../../user-data/device-dicts/$d" "lab-slave-0:/root/$d"
done

# 中间产物用完即清：device-dicts 已 docker cp 进 slave，host 端不再保留（构建法则·法则5）。
# 注意：后续 register-devices.sh / register-device-dicts.sh 读的是容器内 /root/* 副本，不依赖此目录。
rm -rf ../../user-data/device-dicts
