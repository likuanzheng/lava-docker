#!/usr/bin/env python3
"""拼装 boards.yaml（lavalab-gen 的输入，生成产物）。

只读 user-data/lab.yaml，把 masters / slaves 拓扑原样写到根目录 boards.yaml。

**不再包含 boards: 字段**：设备不再烘进镜像、也不在部署时注册。设备字典由
gen-device-dicts.py 渲染到 user-data/device-dicts/（bind-mount 进 slave），部署后
由 reload-devices.sh 经 lavacli 注入。lavalab-gen 因此不渲染任何设备 dict，
`docker compose up` 后 LAVA 设备为空。

power_defaults 仅 gen-device-dicts.py 使用，不写进 boards.yaml。
"""
import sys
from pathlib import Path

import yaml

from assemble_devices import ROOT

LAB_FILE = ROOT / "user-data" / "lab.yaml"
BOARDS_FILE = ROOT / "boards.yaml"


def main():
    if not LAB_FILE.exists():
        sys.exit(f"ERROR: 缺少实验室基础设施文件: {LAB_FILE}")
    with LAB_FILE.open(encoding="utf-8") as f:
        lab = yaml.safe_load(f) or {}

    out = {"masters": lab.get("masters") or [], "slaves": lab.get("slaves") or []}

    header = (
        "# !!! 生成产物，请勿手改 !!!\n"
        "# 由 gen-boards.py 从 user-data/lab.yaml 拼装（只含 masters/slaves 拓扑，无 boards）。\n"
        "# 改基础设施请改 lab.yaml 后重跑：python3 gen-boards.py\n"
        "# 设备由 gen-device-dicts.py + reload-devices.sh 经 lavacli 注入，不在此。\n"
    )
    with BOARDS_FILE.open("w", encoding="utf-8") as f:
        f.write(header)
        yaml.safe_dump(out, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

    print(f"已生成 {BOARDS_FILE.name}："
          f"{len(out['masters'])} master / {len(out['slaves'])} slave（无 boards 段）")


if __name__ == "__main__":
    main()
