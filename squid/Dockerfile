FROM debian:9

RUN find /etc/apt -name "*.list" -o -name "*.sources" | xargs sed -i \
    -e 's|deb\.debian\.org|mirrors.tuna.tsinghua.edu.cn|g' \
    -e 's|security\.debian\.org|mirrors.tuna.tsinghua.edu.cn|g' 2>/dev/null || true
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y squid3

COPY entrypoint.sh /sbin/entrypoint.sh
COPY squid.conf /etc/squid/squid.conf
RUN chmod 755 /sbin/entrypoint.sh

EXPOSE 3128/tcp
CMD "/sbin/entrypoint.sh"
