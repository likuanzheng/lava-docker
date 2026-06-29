#!/bin/bash
# 设备字典：把每台设备的 dict 内容（connection_command/power 等 jinja2）经 lavacli
# dict set 推到 master（对应工作流第 4 步）。
#
# 由根目录 reload-device-dicts.sh 在 slave 容器内调用。读 bind-mount 进来的
# /root/devices/<worker>/<name>.jinja2（= user-data/device-dicts/，gen-device-dicts.py 渲染）。
# 设备需已注册（先跑板级注册 reload-devices.sh）；未注册的设备会跳过并告警。幂等可重复跑。

. /root/setupenv

if [ -z "$LAVA_MASTER_URI" ];then
	echo "ERROR: Missing LAVA_MASTER_URI"
	exit 11
fi

lavacli identities add --uri $LAVA_MASTER_BASEURI --token $LAVA_MASTER_TOKEN --username $LAVA_MASTER_USER default
LAVACLIOPTS="--uri $LAVA_MASTER_URI"

# 设备字典由 reload 时 docker cp 注入；防御性建目录
mkdir -p /root/devices

lavacli $LAVACLIOPTS devices list -a > /tmp/devices.list
if [ $? -ne 0 ];then
	echo "ERROR: fail to list devices (master up?)"
	exit 1
fi

for worker in $(ls /root/devices/)
do
	for device in $(ls /root/devices/$worker/)
	do
		devicename=$(echo $device | sed 's,.jinja2,,')
		grep -q "$devicename[[:space:]]" /tmp/devices.list
		if [ $? -ne 0 ];then
			echo "WARN: $devicename 尚未注册，跳过 dict set（先跑 reload-devices.sh）"
			continue
		fi
		echo "Set dict for $devicename"
		lavacli $LAVACLIOPTS devices dict set $devicename /root/devices/$worker/$device || exit $?
	done
done

exit 0
