#!/usr/bin/env python3
"""模拟 jenkins pipeline 的 job 生成过程。

读取 job 设备字典 user-data/devices/devices.yaml，对每台设备声明的每个操作（op），
用 user-data/job-templates/<device_type>/<op>.yaml.j2 渲染出具体 job，
写到 user-data/jobs/<name>-<op>.yaml。

另外把每个用到的 device_type 下的「配套脚本」物化进 tftp 服务树：
job-templates/<dt>/*.sh.j2 渲染、*.sh 原样拷贝 → user-data/tftp/<dt>/*.sh，
供 job 运行时经 HTTP curl 下来执行（见 WORKFLOW「tftp 目录约定」/ 构建法则·法则6）。
tftp 是可删的运行时数据，这些脚本是产物——删掉 tftp 后重跑本脚本即恢复。

只写自己生成的文件（按名覆盖），不触碰 jobs/ 下的其它文件（如 mqtt-reset*.sh）。
"""
import shutil
import sys
from pathlib import Path

import yaml
from jinja2 import Environment, FileSystemLoader, StrictUndefined

from assemble_devices import ROOT, load_devices

TEMPLATES_DIR = ROOT / "user-data" / "job-templates"
JOBS_DIR = ROOT / "user-data" / "jobs"
LAB_FILE = ROOT / "user-data" / "lab.yaml"
TFTP_DIR = ROOT / "user-data" / "tftp"


def materialize_scripts(env, device_types):
    """把 job-templates/<dt>/ 下的配套脚本物化进 tftp/<dt>/。

    *.sh.j2 → 用 lab 级上下文（serverip / ssh_user / device_type）渲染；
    *.sh    → 原样拷贝。device_types 只含实际有设备的类型。
    """
    with LAB_FILE.open(encoding="utf-8") as f:
        slave = yaml.safe_load(f)["slaves"][0]
    base_ctx = {"serverip": slave["dispatcher_ip"], "ssh_user": slave["remote_user"]}

    written = []
    for dt in sorted(device_types):
        tdir = TEMPLATES_DIR / dt
        scripts = sorted(
            p for p in tdir.iterdir()
            if p.suffix == ".sh" or p.name.endswith(".sh.j2")
        ) if tdir.is_dir() else []
        if not scripts:
            continue
        out_dir = TFTP_DIR / dt
        out_dir.mkdir(parents=True, exist_ok=True)
        for sp in scripts:
            if sp.name.endswith(".j2"):
                ctx = dict(base_ctx, device_type=dt)
                text = env.get_template(f"{dt}/{sp.name}").render(**ctx)
                out_path = out_dir / sp.name[:-3]   # 去掉 .j2
                out_path.write_text(text, encoding="utf-8")
            else:
                out_path = out_dir / sp.name
                shutil.copyfile(sp, out_path)
            out_path.chmod(0o755)
            written.append(out_path)
    return written


def main():
    devices = load_devices()

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

            # 渲染上下文 = 设备字段（去掉非模板字段）+ 该操作的 timeouts
            ctx = {k: v for k, v in dev.items() if k not in ("jobs", "power", "__src")}
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

    # 配套脚本物化进 tftp 服务树（只处理实际有设备的类型）
    scripts = materialize_scripts(env, {dev["device_type"] for dev in devices})
    if scripts:
        print(f"已物化 {len(scripts)} 个配套脚本到 tftp/<device_type>/:")
        for p in scripts:
            print(f"  - {p.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
