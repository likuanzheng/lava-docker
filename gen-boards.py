#!/usr/bin/env python3
"""拼装 boards.yaml（lavalab-gen 的输入，生成产物）。

读取 user-data/lab.yaml（masters/slaves + power_defaults）和 user-data/devices/ 下
每台一个的设备文件，组装成 {masters, slaves, boards} 写到根目录 boards.yaml。

每台设备：
  - type            ← device_type（lavalab 用 type）
  - pdu_generic     ← 由 power.{mqtt_topic, reset_script} + lab.power_defaults 展开
  - 其余 lavalab board 字段（slave/tags/connection_command/uart…）原样透传，
    job 专用字段（boot_ipaddr/jobs/partitions…）不写入（lavalab 会忽略未知键，
    但这里只挑相关键，让生成的 boards.yaml 保持精简）。
"""
import sys
from pathlib import Path

import yaml

from assemble_devices import ROOT, load_devices

LAB_FILE = ROOT / "user-data" / "lab.yaml"
BOARDS_FILE = ROOT / "boards.yaml"

# lavalab-gen.py 认得的 board 级字段（name/type/pdu_generic 单独处理，不在此列）
LAVALAB_BOARD_KEYS = (
    "slave", "tags", "connection_command", "kvm", "uart", "aliases",
    "uboot_ipaddr", "uboot_macaddr", "fastboot_serial_number",
    "user", "group", "custom_option", "raw_custom_option", "lava",
)

POWER_ON_FMT = (
    "mosquitto_pub -h {host} -u {user} -P '{pwd}' "
    "-t {topic}-set -m '{{\"key\":1,\"messageId\":\"\",\"type\":\"event\"}}'"
)


def expand_power(power, pd):
    topic = power["mqtt_topic"]
    return {
        "power_on_command": POWER_ON_FMT.format(
            host=pd["mqtt_host"], user=pd["mqtt_user"], pwd=pd["mqtt_pass"], topic=topic
        ),
        "hard_reset_command": f"bash {pd['reset_script_dir']}/{power['reset_script']}",
    }


def main():
    if not LAB_FILE.exists():
        sys.exit(f"ERROR: 缺少实验室基础设施文件: {LAB_FILE}")
    with LAB_FILE.open(encoding="utf-8") as f:
        lab = yaml.safe_load(f) or {}

    power_defaults = lab.get("power_defaults") or {}
    out = {"masters": lab.get("masters") or [], "slaves": lab.get("slaves") or []}

    boards = []
    for dev in load_devices():
        src = dev.get("__src", dev.get("name"))
        try:
            board = {"name": dev["name"], "type": dev["device_type"]}
        except KeyError as e:
            sys.exit(f"ERROR: {src} 缺少必填字段 {e}")

        for k in LAVALAB_BOARD_KEYS:
            if k in dev:
                board[k] = dev[k]

        if "power" in dev:
            if not power_defaults:
                sys.exit(f"ERROR: {src} 用了 power 但 lab.yaml 缺 power_defaults")
            board["pdu_generic"] = expand_power(dev["power"], power_defaults)

        boards.append(board)

    out["boards"] = boards

    header = (
        "# !!! 生成产物，请勿手改 !!!\n"
        "# 由 gen-boards.py 从 user-data/lab.yaml + user-data/devices/*.yaml 拼装。\n"
        "# 改设备/基础设施请改那些源文件后重跑：python3 gen-boards.py\n"
    )
    with BOARDS_FILE.open("w", encoding="utf-8") as f:
        f.write(header)
        yaml.safe_dump(out, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

    print(f"已生成 {BOARDS_FILE.name}：{len(boards)} 台设备")
    for b in boards:
        print(f"  - {b['name']} ({b['type']})")


if __name__ == "__main__":
    main()
