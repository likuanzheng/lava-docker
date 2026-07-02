#!/usr/bin/env python3
"""渲染 LAVA 设备字典（dict）到稳定的 bind-mount 源目录。

读同一份 user-data/devices/*.yaml（经 assemble_devices.load_devices()），把每台设备
渲染成 LAVA device dict 及 tags/aliases/deviceinfo，写到 user-data/device-dicts/。
该目录经 bind-mount 进 slave 的 /root/{devices,tags,aliases,deviceinfo}，由
reload-devices.sh 经 lavacli 注入 master（部署后运行，无需 rebuild）。

dict 文本与 lavalab-gen.py 的 template_device* 完全一致，保证等价：
    {% extends '<type>.jinja2' %}
    <空行>
    {% set hard_reset_command = "<hard>" %}
    {% set power_on_command = "<on>" %}
    #
    {% set connection_command = '<cc>' %}

放在 output/ 之外（lavalab-gen.sh 会 rm -rf output），故 bind-mount 稳定。
"""
import shutil
import sys
from pathlib import Path

import yaml

from assemble_devices import ROOT, load_devices

LAB_FILE = ROOT / "user-data" / "lab.yaml"
OUT_DIR = ROOT / "user-data" / "device-dicts"

MQTT_PUB_FMT = (
    "mosquitto_pub -h {host} -u {user} -P '{pwd}' "
    "-t {topic}-set -m '{{\"key\":{key},\"messageId\":\"\",\"type\":\"event\"}}'"
)


def expand_power(power, pd):
    """power.mqtt_topic + lab.power_defaults → pdu_generic 命令（全内联，无脚本文件）。

    hard_reset = 关(key:0) → sleep 5 → 开(key:1)。

    ⚠ LAVA 执行电源命令时逐条 shlex 拆分、**不经 shell**（见 slave 的
    lava_dispatcher/power.py::PDUReboot：`for cmd in command` 直接调 argv）。
    所以 `;`/`sleep` 不能裸拼进一条命令（会被当成 mosquitto_pub 的参数，报
    "Unknown option 'sleep'"）——必须整条 compound 包进 `sh -c "…"` 交给 shell。
    内部 " 转义供 shlex 在 sh 的双引号参数里还原（shlex: \" → "、' 原样）。
    power_on 是单条命令、shlex 直接可跑，不包。
    """
    def pub(key):
        return MQTT_PUB_FMT.format(
            host=pd["mqtt_host"], user=pd["mqtt_user"], pwd=pd["mqtt_pass"],
            topic=power["mqtt_topic"], key=key,
        )

    compound = f"{pub(0)}; sleep 5; {pub(1)}"
    hard = 'sh -c "%s"' % compound.replace("\\", "\\\\").replace('"', '\\"')
    return {
        "power_on_command": pub(1),
        "hard_reset_command": hard,
    }


def render_dict(dev, power_defaults):
    """组装 LAVA device dict 文本（与 lavalab-gen.py 字节级一致）。"""
    text = "{%% extends '%s.jinja2' %%}\n" % dev["device_type"]

    if "power" in dev:
        if not power_defaults:
            sys.exit(f"ERROR: {dev['name']} 用了 power 但 lab.yaml 缺 power_defaults")
        pdu = expand_power(dev["power"], power_defaults)
        # 嵌入 jinja 双引号字符串：先转义 \ 再转义 "（hard_reset 含 sh -c 的 \" 转义，必须先处理 \）
        hard = pdu["hard_reset_command"].replace("\\", "\\\\").replace('"', '\\"')
        on = pdu["power_on_command"].replace("\\", "\\\\").replace('"', '\\"')
        text += (
            "\n"
            '{%% set hard_reset_command = "%s" %%}\n' % hard
            + '{%% set power_on_command = "%s" %%}\n' % on
        )

    if "connection_command" in dev:
        text += "#\n{%% set connection_command = '%s' %%}\n" % dev["connection_command"]

    if "uboot_ipaddr" in dev:
        text += "{%% set uboot_ipaddr_cmd = 'setenv ipaddr %s' %%}\n" % dev["uboot_ipaddr"]

    return text


def main():
    if not LAB_FILE.exists():
        sys.exit(f"ERROR: 缺少 {LAB_FILE}")
    with LAB_FILE.open(encoding="utf-8") as f:
        lab = yaml.safe_load(f) or {}
    power_defaults = lab.get("power_defaults") or {}

    devices = load_devices()

    # 清掉自己上轮产物（删设备后不残留），只动 device-dicts/ 子树
    if OUT_DIR.exists():
        shutil.rmtree(OUT_DIR)
    devices_dir = OUT_DIR / "devices"
    tags_dir = OUT_DIR / "tags"
    aliases_dir = OUT_DIR / "aliases"
    deviceinfo_dir = OUT_DIR / "deviceinfo"
    for d in (devices_dir, tags_dir, aliases_dir, deviceinfo_dir):
        d.mkdir(parents=True, exist_ok=True)

    aliases_by_type = {}   # device_type -> set(alias)
    written = []
    for dev in devices:
        name = dev["name"]
        if "device_type" not in dev:
            sys.exit(f"ERROR: {dev.get('__src', name)} 缺少 device_type")
        worker = dev.get("slave")
        if not worker:
            sys.exit(f"ERROR: {name} 缺少 slave（设备挂在哪个 worker 上）")

        # dict
        worker_dir = devices_dir / worker
        worker_dir.mkdir(parents=True, exist_ok=True)
        (worker_dir / f"{name}.jinja2").write_text(render_dict(dev, power_defaults),
                                                   encoding="utf-8")
        written.append(name)

        # tags：每行一个（setup.sh 按行读 /root/tags/<name>）
        tags = dev.get("tags")
        if tags:
            (tags_dir / name).write_text("".join(f"{t}\n" for t in tags), encoding="utf-8")

        # aliases：按 device_type 聚合去重（setup.sh 读 /root/aliases/<type>）
        for a in dev.get("aliases") or []:
            aliases_by_type.setdefault(dev["device_type"], set()).add(a)

        # deviceinfo：user/group → shell 变量（setup.sh `. /root/deviceinfo/<name>`）
        info = []
        if dev.get("user"):
            info.append(f'DEVICE_USER={dev["user"]}\n')
        if dev.get("group"):
            info.append(f'DEVICE_GROUP={dev["group"]}\n')
        if info:
            (deviceinfo_dir / name).write_text("".join(info), encoding="utf-8")

    for dtype, aliases in aliases_by_type.items():
        (aliases_dir / dtype).write_text("".join(f"{a}\n" for a in sorted(aliases)),
                                         encoding="utf-8")

    print(f"已生成 {len(written)} 台设备字典到 {OUT_DIR.relative_to(ROOT)}/:")
    for name in written:
        print(f"  - {name}")


if __name__ == "__main__":
    main()
