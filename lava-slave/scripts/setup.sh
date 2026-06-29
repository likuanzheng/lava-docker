#!/bin/bash

# 启动脚本：只注册 worker（add + token + dispatcher_ip），不注册任何 device-type/设备。
# 设备由部署后运行的 reload-devices.sh → register-devices.sh 经 lavacli 注入。
# 这样 `docker compose up` 后 LAVA 设备为空，部署与设备配置解耦。

# /root/devices 不再 bind-mount（设备字典改为 reload 时 docker cp 临时注入）。
# 这里用运行时 hostname 建出 worker 目录，让下面的 worker 注册照常进行；
# 设备本身由 reload-devices.sh / reload-device-dicts.sh 部署后经 lavacli 注入。
mkdir -p "/root/devices/$(hostname)"

. /root/setupenv

if [ -z "$LAVA_MASTER_URI" ];then
	echo "ERROR: Missing LAVA_MASTER_URI"
	exit 11
fi

# Install PXE
OPWD=$(pwd)
cd /var/lib/lava/dispatcher/tmp && grub-mknetdir --net-directory=.
cp /root/grub.cfg /var/lib/lava/dispatcher/tmp/boot/grub/
cd $OPWD

lavacli identities add --uri $LAVA_MASTER_BASEURI --token $LAVA_MASTER_TOKEN --username $LAVA_MASTER_USER default

echo "Dynamic slave for $LAVA_MASTER ($LAVA_MASTER_URI)"
LAVACLIOPTS="--uri $LAVA_MASTER_URI"

# do a sort of ping for letting master to be up
TIMEOUT=1200
while [ $TIMEOUT -ge 1 ];
do
	STEP=2
	lavacli $LAVACLIOPTS device-types list >/dev/null
	if [ $? -eq 0 ];then
		TIMEOUT=0
	else
		echo "Wait for master.... (${TIMEOUT}s remains)"
		sleep $STEP
	fi
	TIMEOUT=$(($TIMEOUT-$STEP))
done

for worker in $(ls /root/devices/)
do
	lavacli $LAVACLIOPTS workers list |grep -q $worker
	if [ $? -eq 0 ];then
		# worker 已存在（持久化 DB 重启）：保留，不 retire（避免把设备打成 RETIRED，
		# 设备状态由 register-devices.sh 管理）。
		echo "Worker $worker already present, keep it"
	else
		echo "Adding worker $worker"
		lavacli $LAVACLIOPTS workers add --description "LAVA dispatcher on $(cat /root/phyhostname)" $worker || exit $?
		# does we ran 2020.09+ and worker need a token
	fi

	lavacli $LAVACLIOPTS workers update --job-limit $LAVA_JOBLIMIT $worker || exit $?

	grep -q "TOKEN" /root/entrypoint.sh
	if [ $? -eq 0 ];then
		# This is 2020.09+
		echo "DEBUG: Worker need a TOKEN"
		if [ -z "$LAVA_WORKER_TOKEN" ];then
			echo "DEBUG: get token dynamicly"
			# Does not work on 2020.09, since token was not added yet in RPC2
			WTOKEN=$(getworkertoken.py $LAVA_MASTER_URI $worker)
			if [ $? -ne 0 ];then
				echo "ERROR: cannot get WORKER TOKEN"
				exit 1
			fi
			if [ -z "$WTOKEN" ];then
				echo "ERROR: got an empty token"
				exit 1
			fi
		else
			echo "DEBUG: got token from env"
			WTOKEN=$LAVA_WORKER_TOKEN
		fi
		echo "DEBUG: write token in /var/lib/lava/dispatcher/worker/"
		mkdir -p /var/lib/lava/dispatcher/worker/
		echo "$WTOKEN" > /var/lib/lava/dispatcher/worker/token
		# lava worker ran under root
		chown root:root /var/lib/lava/dispatcher/worker/token
		chmod 640 /var/lib/lava/dispatcher/worker/token
		sed -i "s,.*TOKEN.*,TOKEN=\"--token-file /var/lib/lava/dispatcher/worker/token\"," /etc/lava-dispatcher/lava-worker || exit $?

		echo "DEBUG: set master URL to $LAVA_MASTER_URL"
		sed -i "s,^# URL.*,URL=\"$LAVA_MASTER_URL\"," /etc/lava-dispatcher/lava-worker || exit $?
		cat /etc/lava-dispatcher/lava-worker
	else
		echo "DEBUG: Worker does not need a TOKEN"
	fi
	if [ ! -z "$LAVA_DISPATCHER_IP" ];then
		echo "Add dispatcher_ip $LAVA_DISPATCHER_IP to $worker"
		/usr/local/bin/setdispatcherip.py $LAVA_MASTER_URI $worker $LAVA_DISPATCHER_IP || exit $?
	fi
done

exit 0
