#!/usr/bin/env python3
"""模拟 jenkins pipeline 的 job 生成过程。

读取 job 设备字典 user-data/devices/devices.yaml，对每台设备声明的每个操作（op），
用 user-data/job-templates/<device_type>/<op>.yaml.j2 渲染出具体 job，
写到 user-data/jobs/<name>-<op>.yaml。

只写自己生成的文件（按名覆盖），不触碰 jobs/ 下的其它文件（如 mqtt-reset*.sh）。
"""
import sys
from pathlib import Path

import yaml
from jinja2 import Environment, FileSystemLoader, StrictUndefined

ROOT = Path(__file__).resolve().parent
DEVICES_FILE = ROOT / "user-data" / "devices" / "devices.yaml"
TEMPLATES_DIR = ROOT / "user-data" / "job-templates"
JOBS_DIR = ROOT / "user-data" / "jobs"


def main():
    if not DEVICES_FILE.exists():
        sys.exit(f"ERROR: 设备字典不存在: {DEVICES_FILE}")

    with DEVICES_FILE.open(encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    devices = data.get("devices") or []
    if not devices:
        sys.exit(f"ERROR: {DEVICES_FILE} 中没有 devices 条目")

    env = Environment(
        loader=FileSystemLoader(str(TEMPLATES_DIR)),
        undefined=StrictUndefined,   # 模板用到字典里没有的字段时立即报错
        keep_trailing_newline=True,
    )

    JOBS_DIR.mkdir(parents=True, exist_ok=True)
    written = []
    for dev in devices:
        try:
            name = dev["name"]
            device_type = dev["device_type"]
            jobs = dev["jobs"]
        except KeyError as e:
            sys.exit(f"ERROR: 设备条目缺少必填字段 {e}: {dev!r}")

        for op, timeouts in jobs.items():
            tpl_rel = f"{device_type}/{op}.yaml.j2"
            tpl_path = TEMPLATES_DIR / tpl_rel
            if not tpl_path.exists():
                sys.exit(f"ERROR: 缺少模板 {tpl_path}（设备 {name} 的 {op} 操作）")

            # 渲染上下文 = 设备全部字段 + 该操作的 timeouts（覆盖同名 jobs 字段）
            ctx = {k: v for k, v in dev.items() if k != "jobs"}
            ctx.setdefault("tags", None)   # 可选字段，模板用 `{% if tags %}` 判断
            ctx["op"] = op
            ctx["timeouts"] = timeouts

            rendered = env.get_template(tpl_rel).render(**ctx)
            out_path = JOBS_DIR / f"{name}-{op}.yaml"
            # 校验生成的 YAML 合法，避免写出坏文件
            try:
                yaml.safe_load(rendered)
            except yaml.YAMLError as e:
                sys.exit(f"ERROR: {out_path.name} 渲染结果不是合法 YAML: {e}")
            out_path.write_text(rendered, encoding="utf-8")
            written.append(out_path)

    print(f"已生成 {len(written)} 个 job 到 {JOBS_DIR}:")
    for p in written:
        print(f"  - {p.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
