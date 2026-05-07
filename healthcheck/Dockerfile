FROM debian:trixie

RUN find /etc/apt -name "*.list" -o -name "*.sources" | xargs sed -i \
    -e 's|deb\.debian\.org|mirrors.tuna.tsinghua.edu.cn|g' \
    -e 's|security\.debian\.org|mirrors.tuna.tsinghua.edu.cn|g' 2>/dev/null || true
RUN apt-get update && apt-get -y install git
RUN git clone https://github.com/BayLibre/lava-healthchecks-binary.git

FROM nginx:mainline-alpine

COPY port.conf /etc/nginx/conf.d/

COPY --from=0 /lava-healthchecks-binary/mainline /usr/share/nginx/html/mainline/
COPY --from=0 lava-healthchecks-binary/images /usr/share/nginx/html/images/
COPY --from=0 lava-healthchecks-binary/next /usr/share/nginx/html/next/
COPY --from=0 lava-healthchecks-binary/stable /usr/share/nginx/html/stable/
COPY --from=0 lava-healthchecks-binary/rootfs /usr/share/nginx/html/rootfs/
