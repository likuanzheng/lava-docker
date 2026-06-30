#!/bin/bash
# 板级注册：把设备「板级定义」经 lavacli upsert 到 master（devices add/update：
# 类型/worker/tags/health/user/group）。**不含设备字典**——字典由 register-device-dicts.sh
# 单独 dict set（对应工作流第 3、4 步分离）。
#
# 由 user-data/reload-devices.sh 在 slave 容器内调用。读 bind-mount 进来的
# /root/{devices,tags,aliases,deviceinfo}（= user-data/device-dicts/，gen-device-dicts.py 渲染）。
# worker 由 setup.sh 在启动时注册，本脚本不碰 worker、不 retire，幂等可重复跑。

. /root/setupenv

if [ -z "$LAVA_MASTER_URI" ];then
	echo "ERROR: Missing LAVA_MASTER_URI"
	exit 11
fi

lavacli identities add --uri $LAVA_MASTER_BASEURI --token $LAVA_MASTER_TOKEN --username $LAVA_MASTER_USER default
LAVACLIOPTS="--uri $LAVA_MASTER_URI"

# 设备字典由 reload 时 docker cp 注入；防御性建目录，空类目也不会让 ls 报错
mkdir -p /root/devices /root/tags /root/aliases /root/deviceinfo
# This directory is used for storing device-types already added
mkdir -p /root/.lavadocker/

lavacli $LAVACLIOPTS device-types list > /tmp/device-types.list
if [ $? -ne 0 ];then
	echo "ERROR: fail to list device-types (master up?)"
	exit 1
fi
lavacli $LAVACLIOPTS devices list -a > /tmp/devices.list
if [ $? -ne 0 ];then
	echo "ERROR: fail to list devices"
	exit 1
fi

for worker in $(ls /root/devices/)
do
	for device in $(ls /root/devices/$worker/)
	do
		devicename=$(echo $device | sed 's,.jinja2,,')
		devicetype=$(grep -h extends /root/devices/$worker/$device| grep -o '[a-zA-Z0-9_-]*.jinja2' | sed 's,.jinja2,,')
		if [ -e /root/.lavadocker/devicetype-$devicetype ];then
			echo "Skip devicetype $devicetype"
		else
			echo "Add devicetype $devicetype"
			grep -q "$devicetype[[:space:]]" /tmp/device-types.list
			if [ $? -eq 0 ];then
				echo "Skip devicetype $devicetype"
			else
				lavacli $LAVACLIOPTS device-types add $devicetype || exit $?
			fi
			touch /root/.lavadocker/devicetype-$devicetype
		fi
		DEVICE_OPTS=""
		if [ -e /root/deviceinfo/$devicename ];then
			echo "Found customization for $devicename"
			. /root/deviceinfo/$devicename
			if [ ! -z "$DEVICE_USER" ];then
				echo "DEBUG: give $devicename to $DEVICE_USER"
				DEVICE_OPTS="$DEVICE_OPTS --user $DEVICE_USER"
			fi
			if [ ! -z "$DEVICE_GROUP" ];then
				echo "DEBUG: give $devicename to group $DEVICE_GROUP"
				DEVICE_OPTS="$DEVICE_OPTS --group $DEVICE_GROUP"
			fi
		fi
		echo "Add device $devicename on $worker"
		grep -q "$devicename[[:space:]]" /tmp/devices.list
		if [ $? -eq 0 ];then
			echo "$devicename already present"
			#verify if present on another worker
			lavacli $LAVACLIOPTS devices show $devicename |grep ^worker > /tmp/current-worker
			if [ $? -ne 0 ]; then
				CURR_WORKER=""
			else
				CURR_WORKER=$(cat /tmp/current-worker | sed 's,^.* ,,')
			fi
			if [ ! -z "$CURR_WORKER" -a "$CURR_WORKER" != "$worker" ];then
				echo "ERROR: $devicename already present on another worker $CURR_WORKER"
				exit 1
			fi
			DEVICE_HEALTH=$(grep "$devicename[[:space:]]" /tmp/devices.list | sed 's/.*,//')
			case "$DEVICE_HEALTH" in
			Retired)
				echo "DEBUG: Keep $devicename state: $DEVICE_HEALTH"
				DEVICE_HEALTH='RETIRED'
			;;
			Maintenance)
				echo "DEBUG: Keep $devicename state: $DEVICE_HEALTH"
				DEVICE_HEALTH='MAINTENANCE'
			;;
			*)
				echo "DEBUG: Set $devicename state to UNKNOWN (from $DEVICE_HEALTH)"
				DEVICE_HEALTH='UNKNOWN'
			;;
			esac
			lavacli $LAVACLIOPTS devices update --worker $worker --health $DEVICE_HEALTH $DEVICE_OPTS $devicename || exit $?
		else
			lavacli $LAVACLIOPTS devices add --type $devicetype --worker $worker $DEVICE_OPTS $devicename || exit $?
		fi
		if [ -e /root/tags/$devicename ];then
			while read tag
			do
				echo "DEBUG: Add tag $tag to $devicename"
				lavacli $LAVACLIOPTS devices tags add $devicename $tag || exit $?
			done < /root/tags/$devicename
		fi
	done
done

for devicetype in $(ls /root/aliases/)
do
	lavacli $LAVACLIOPTS device-types aliases list $devicetype > /tmp/device-types-aliases-$devicetype.list
	while read alias
	do
		grep -q " $alias$" /tmp/device-types-aliases-$devicetype.list
		if [ $? -eq 0 ];then
			echo "DEBUG: $alias for $devicetype already present"
			continue
		fi
		echo "DEBUG: Add alias $alias to $devicetype"
		lavacli $LAVACLIOPTS device-types aliases add $devicetype $alias || exit $?
		echo " $alias" >> /tmp/device-types-aliases-$devicetype.list
	done < /root/aliases/$devicetype
done

exit 0
