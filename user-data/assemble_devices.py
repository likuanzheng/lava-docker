#!/usr/bin/env python3
"""设备字典共享加载器。

唯一设备源是 user-data/devices/ 下「每台一个」的 YAML 文件（顶层即设备字段）。
gen-jobs.py 与 gen-device-dicts.py 都通过本模块加载，保证两边看到的是同一份设备清单。
本模块与上述生成器同处 user-data/，故 ROOT 取本文件上两级（= 仓库根）。

约定：
  - 文件名（去扩展名）必须等于设备的 name 字段，文件名即权威 id。
  - 以 `_` 开头的文件被忽略（模板/示例/说明，如 _README.yaml）。
"""
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
DEVICES_DIR = ROOT / "user-data" / "devices"


def load_devices():
    """返回设备 dict 列表，按文件名排序。每个 dict 带一个 `__src`（来源文件名）。"""
    if not DEVICES_DIR.is_dir():
        raise SystemExit(f"ERROR: 设备目录不存在: {DEVICES_DIR}")

    devices = []
    for p in sorted(DEVICES_DIR.glob("*.yaml")):
        if p.name.startswith("_"):
            continue
        with p.open(encoding="utf-8") as f:
            dev = yaml.safe_load(f) or {}
        if not isinstance(dev, dict):
            raise SystemExit(f"ERROR: {p.name} 顶层必须是单个设备映射（dict）")
        name = dev.get("name")
        if not name:
            raise SystemExit(f"ERROR: {p.name} 缺少 name 字段")
        if name != p.stem:
            raise SystemExit(
                f"ERROR: {p.name} 的 name='{name}' 与文件名不一致（应为 {name}.yaml）"
            )
        dev["__src"] = p.name
        devices.append(dev)

    if not devices:
        raise SystemExit(f"ERROR: {DEVICES_DIR} 下没有设备文件（*.yaml）")
    return devices
