#!/usr/bin/env python3
"""Build a clean Windows distribution from pinned upstream and character assets."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct
import zipfile

VERSION = "1.0.0"
UPSTREAM_VERSION = "4.4.0"
UPSTREAM_URL = "https://github.com/MerZlin/dsh-pet-indesktop/releases/download/v4.4.0/dsh-pet-standalone-webm-chat-portable.zip"
UPSTREAM_SHA256 = "3f31b8c9454702d114e539324137347ad3a0c7c264d8071e29b250becdc59ea6"

def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

def create_zip(folder, target):
    if target.exists():
        raise FileExistsError(target)
    with zipfile.ZipFile(target, "x", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(folder.rglob("*")):
            if path.is_file():
                archive.write(path, (Path(folder.name) / path.relative_to(folder)).as_posix())
    with zipfile.ZipFile(target) as archive:
        assert archive.testzip() is None

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=Path, required=True)
    parser.add_argument("--character", type=Path, required=True)
    parser.add_argument("--preview", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent
    if sha256(args.upstream) != UPSTREAM_SHA256:
        raise ValueError("Upstream archive differs from the author's pinned release digest")
    manifest = json.loads((args.character / "manifest.json").read_text(encoding="utf-8"))
    videos = sorted((args.character / "videos").rglob("*.webm"))
    assert len(videos) == 12
    args.output.mkdir(parents=True, exist_ok=True)
    target = args.output / ("BeretGirl-Windows-v" + VERSION)
    if target.exists():
        raise FileExistsError(target)
    target.mkdir()
    app = target / "app"
    app.mkdir()
    with zipfile.ZipFile(args.upstream) as archive:
        for info in archive.infolist():
            name = info.filename.replace("\\", "/")
            if name.startswith("/") or ".." in Path(name).parts or ":" in name:
                raise ValueError("Unsafe upstream ZIP path")
            if (info.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError("Unexpected symlink in Windows archive")
        archive.extractall(app)
    executables = list(app.rglob("dsh-pet-standalone-webm-chat.exe"))
    if len(executables) != 1:
        raise ValueError("Expected exactly one main Windows executable")
    exe = executables[0]
    with exe.open("rb") as handle:
        assert handle.read(2) == b"MZ"
        handle.seek(0x3c)
        offset = struct.unpack("<I", handle.read(4))[0]
        handle.seek(offset)
        assert handle.read(4) == b"PE\0\0"
        machine = struct.unpack("<H", handle.read(2))[0]
    assert machine == 0x8664, "The official executable must be Windows x86-64"
    if not any(p.name.lower() in {"license", "license.txt", "license.md"} for p in app.rglob("*") if p.is_file()):
        raise ValueError("Upstream license files were not found")
    (target / "app-relative-path.txt").write_text(exe.relative_to(target).as_posix() + "\n", encoding="utf-8")
    clean = target / "character" / "beret-girl"
    clean.mkdir(parents=True)
    (clean / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for video in videos:
        dst = clean / video.relative_to(args.character)
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(video, dst)
    (clean / "安装说明.md").write_text((repo / "README.md").read_text(encoding="utf-8"), encoding="utf-8")
    checks = [f"{sha256(p)}  {p.relative_to(clean).as_posix()}" for p in sorted(clean.rglob("*")) if p.is_file()]
    (clean / "SHA256SUMS.txt").write_text("\n".join(checks) + "\n", encoding="utf-8")
    (target / "scripts").mkdir()
    ps = (repo / "scripts" / "Install-And-Run.ps1").read_text(encoding="utf-8-sig")
    (target / "scripts" / "Install-And-Run.ps1").write_text(ps.replace("\r\n", "\n").replace("\n", "\r\n"), encoding="utf-8-sig")
    cmd = (repo / "启动贝雷帽女孩.cmd").read_text(encoding="utf-8")
    (target / "启动贝雷帽女孩.cmd").write_bytes(cmd.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8"))
    (target / "使用说明.md").write_text((repo / "README.md").read_text(encoding="utf-8"), encoding="utf-8-sig")
    shutil.copytree(args.preview, target / "动作预览")
    (target / "动作预览" / "安装说明.md").write_text((repo / "README.md").read_text(encoding="utf-8"), encoding="utf-8")
    info = {
        "name": "贝雷帽女孩", "version": VERSION, "platform": "Windows x86-64",
        "upstream": {"repository": "https://github.com/MerZlin/dsh-pet-indesktop", "version": UPSTREAM_VERSION,
                     "download": UPSTREAM_URL, "sha256": UPSTREAM_SHA256},
        "character_id": "beret-girl", "animation_count": len(videos),
        "includes_personal_configuration": False,
        "main_executable": exe.relative_to(target).as_posix(), "launcher": "启动贝雷帽女孩.cmd",
        "verification": {"upstream_sha256": True, "windows_pe_machine": hex(machine),
                         "character_assets_prevalidated": True, "windows_gui_smoke_test": False}
    }
    (target / "distribution-info.json").write_text(json.dumps(info, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (target / "第三方说明.md").write_text(
        "# 第三方软件\n\n本包保留 dsh-pet-indesktop v4.4.0 原版 Windows Chat 运行时及其随附许可证。"
        "\n\n上游：https://github.com/MerZlin/dsh-pet-indesktop\n\n"
        "原始程序未修改；其许可证、依赖及第三方素材声明位于 app/ 原版目录中。"
        "自定义角色素材与启动配置脚本为本发布增加的内容。\n", encoding="utf-8")
    full_zip = args.output / (target.name + ".zip")
    create_zip(target, full_zip)
    role_zip = args.output / "beret-girl-character.zip"
    create_zip(clean, role_zip)
    release_files = [full_zip, role_zip]
    (args.output / "SHA256SUMS.txt").write_text("\n".join(f"{sha256(p)}  {p.name}" for p in release_files) + "\n", encoding="ascii")
    report = {
        "status": "COMPLETE", "full_package": str(full_zip), "full_package_bytes": full_zip.stat().st_size,
        "full_package_sha256": sha256(full_zip), "character_package": str(role_zip), "animation_count": 12,
        "windows_executable_verified": True, "upstream_digest_verified": True
    }
    (args.output / "build-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False, indent=2))
if __name__ == "__main__":
    main()

