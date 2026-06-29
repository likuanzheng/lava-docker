FROM lavasoftware/lava-dispatcher:2026.01

RUN find /etc/apt -name "*.list" -o -name "*.sources" | xargs sed -i \
    -e 's|deb\.debian\.org|mirrors.tuna.tsinghua.edu.cn|g' \
    -e 's|security\.debian\.org|mirrors.tuna.tsinghua.edu.cn|g' 2>/dev/null || true
RUN if [ -e /etc/apt/sources.list.d/debian.sources ] ;then sed -i 's,.*bullseye-backports,#,' /etc/apt/sources.list.d/debian.sources ; fi
RUN if [ -e /etc/apt/sources.list.d/backports.list ] ;then sed -i 's,.*bullseye-backports,#,' /etc/apt/sources.list.d/backports.list ; fi

RUN apt-get update

# telnet is for using ser2net
# git is necessary for checkout tests
RUN DEBIAN_FRONTEND=noninteractive apt-get -y install telnet git ser2net patch lavacli
RUN if [ $(uname -m) = amd64 -o $(uname -m) = x86_64 ];then apt-get -y install linux-image-amd64 ; fi

COPY configs/lava-slave /etc/lava-dispatcher/lava-slave

COPY configs/tftpd-hpa /etc/default/tftpd-hpa
COPY lava-coordinator/ /etc/lava-coordinator/

COPY scripts/ /usr/local/bin/
RUN chmod a+x /usr/local/bin/*

# Caution to not use any port between the Linux dynamic port range: 32768-60999
RUN find /usr/lib/python3/dist-packages/ -iname constants.py | xargs sed -i 's,XNBD_PORT_RANGE_MIN.*,XNBD_PORT_RANGE_MIN=61950,'
RUN find /usr/lib/python3/dist-packages/ -iname constants.py | xargs sed -i 's,XNBD_PORT_RANGE_MAX.*,XNBD_PORT_RANGE_MAX=62000,'

COPY ser2net.yaml /etc

# PXE stuff
RUN if [ $(uname -m) != amd64 -a $(uname -m) != x86_64 ]; then dpkg --add-architecture amd64 && apt-get update; fi
RUN apt-get -y install grub-efi-amd64-bin:amd64
RUN if [ $(uname -m) != amd64 -a $(uname -m) != x86_64 ]; then dpkg --remove architecture amd64 && apt-get update; fi
COPY grub.cfg /root/

COPY default/* /etc/default/

COPY phyhostname /root/
COPY setupenv /root/
COPY scripts/setup.sh .

COPY lava-patch/ /root/lava-patch
RUN cd /usr/lib/python3/dist-packages && for patch in $(ls /root/lava-patch/*patch) ; do echo "APPLY $patch"; patch -p1 < $patch || exit $?;done

# needed for lavacli identities
RUN mkdir -p /root/.config

# devices/tags/aliases/deviceinfo 改为运行时 bind-mount（见 boards.yaml slaves custom_volumes），
# 不再烘进镜像：编辑 user-data/devices + gen-device-dicts.py + reload-devices.sh 即时生效。
COPY entrypoint.d/* /root/entrypoint.d/
RUN chmod +x /root/entrypoint.d/*

RUN if [ -x /usr/local/bin/extra_actions ] ; then /usr/local/bin/extra_actions ; fi

EXPOSE 69/udp 80

CMD /usr/local/bin/start.sh
