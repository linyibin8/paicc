#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import plistlib
import posixpath
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


DEFAULT_RELEASE_DIR = Path("/Users/macstar/projects/pai-cc")
DEFAULT_SHARED_ENV = Path("/Users/macstar/testflight-auto/ios-publish.env")
DEFAULT_PROJECT_ENV = Path("/Users/macstar/testflight-auto/ios-publish-paicc.env")
DEFAULT_SOURCE_SSH = "ydz@100.64.0.13:/home/ydz/projects/pai-cc"
DEFAULT_GROUP_NAME = "PAICC Internal"
DEFAULT_TESTERS = "269123786@qq.com,linyibin8@qq.com,3972104921@qq.com,643014114@qq.com"


class ReleaseError(RuntimeError):
    pass


def log(message: str) -> None:
    print(message, flush=True)


def run(
    command: list[str],
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    check: bool = True,
    input_stream: Any | None = None,
) -> subprocess.CompletedProcess[str]:
    log("+ " + " ".join(shlex.quote(part) for part in command))
    completed = subprocess.run(
        command,
        cwd=str(cwd) if cwd else None,
        env=env,
        text=True,
        stdin=input_stream,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if completed.stdout:
        print(completed.stdout, end="", flush=True)
    if check and completed.returncode != 0:
        raise ReleaseError(f"Command failed with exit {completed.returncode}: {' '.join(command)}")
    return completed


def parse_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for raw in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:].strip()
        match = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", line)
        if not match:
            continue
        key, value = match.groups()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        values[key] = value
    return values


def read_project_version(release_dir: Path) -> str | None:
    project_yml = release_dir / "project.yml"
    if not project_yml.exists():
        return None
    match = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', project_yml.read_text(encoding="utf-8", errors="ignore"))
    return match.group(1) if match else None


def merged_env(args: argparse.Namespace, *, build_number: str | None = None) -> dict[str, str]:
    env = os.environ.copy()
    shared = parse_env_file(Path(args.shared_env))
    project = parse_env_file(Path(args.project_env))
    loaded: dict[str, str] = {}
    loaded.update(shared)
    loaded.update(project)
    loaded.update(env)

    release_dir = Path(args.release_dir)
    project_version = read_project_version(release_dir)
    chosen_version = args.version or project_version or loaded.get("APP_VERSION") or "1.0.0"
    chosen_build = args.build_number or build_number or time.strftime("%Y%m%d%H%M%S")

    defaults = {
        "APP_NAME": "PAI-CC",
        "APP_BUNDLE_ID": "com.evowit.paicc",
        "APP_VERSION": chosen_version,
        "APP_BUILD_NUMBER": chosen_build,
        "APP_SKU": "paicc001",
        "APPLE_TEAM_ID": "N3G45G5H74",
        "PROFILE_NAME": "paicc_appstore_profile",
        "TESTFLIGHT_GROUP_NAME": DEFAULT_GROUP_NAME,
        "TESTFLIGHT_INTERNAL": "1",
        "TESTER_EMAILS": DEFAULT_TESTERS,
        "WHAT_TO_TEST": "PAI-CC iOS update.",
        "BUILD_WAIT_SECONDS": "1800",
        "P12_DIR": "/Users/macstar/Desktop/p12",
        "RCODESIGN": "/Users/macstar/Tools/apple-codesign/apple-codesign-0.29.0-macos-universal/rcodesign",
    }

    final = env.copy()
    final.update(defaults)
    final.update(shared)
    final.update(project)
    final.update(env)

    # Version and build should follow the checked-out project and this run, not stale env files.
    final["APP_VERSION"] = chosen_version
    final["APP_BUILD_NUMBER"] = chosen_build
    final["APP_SKU"] = project.get("APP_SKU") or shared.get("APP_SKU") or "paicc001"
    final["PROFILE_NAME"] = project.get("PROFILE_NAME") or shared.get("PROFILE_NAME") or "paicc_appstore_profile"
    final["TESTFLIGHT_GROUP_NAME"] = (
        project.get("PAICC_TESTFLIGHT_GROUP_NAME")
        or project.get("TESTFLIGHT_GROUP_NAME")
        or DEFAULT_GROUP_NAME
    )
    final["TESTFLIGHT_INTERNAL"] = (
        project.get("PAICC_TESTFLIGHT_INTERNAL")
        or project.get("TESTFLIGHT_INTERNAL")
        or shared.get("TESTFLIGHT_INTERNAL")
        or "1"
    )
    final["TESTER_EMAILS"] = (
        project.get("PAICC_TESTER_EMAILS")
        or project.get("TESTER_EMAILS")
        or shared.get("TESTER_EMAILS")
        or DEFAULT_TESTERS
    )
    final["WHAT_TO_TEST"] = project.get("PAICC_WHAT_TO_TEST") or project.get("WHAT_TO_TEST") or defaults["WHAT_TO_TEST"]
    final["BUILD_WAIT_SECONDS"] = (
        project.get("PAICC_BUILD_WAIT_SECONDS")
        or project.get("BUILD_WAIT_SECONDS")
        or shared.get("BUILD_WAIT_SECONDS")
        or "1800"
    )
    final["PATH"] = f"/Users/macstar/bin:/opt/homebrew/bin:/usr/local/bin:{final.get('PATH', '')}"

    for key in ("ASC_KEY_PATH", "SIGNING_KEYCHAIN", "P12_DIR", "RCODESIGN"):
        if key in final:
            final[key] = os.path.expandvars(os.path.expanduser(final[key]))
    return final


def require_file(path: Path, label: str) -> None:
    if not path.exists():
        raise ReleaseError(f"Missing {label}: {path}")


def preflight(args: argparse.Namespace) -> dict[str, Any]:
    release_dir = Path(args.release_dir)
    env = merged_env(args)
    required_commands = ["xcodebuild", "xcrun", "security", "zip", "ditto", "tar", "rsync", "python3"]
    command_status = {name: shutil.which(name, path=env.get("PATH")) for name in required_commands}
    xcodegen = shutil.which("xcodegen", path=env.get("PATH")) or "/Users/macstar/bin/xcodegen"
    command_status["xcodegen"] = xcodegen if Path(xcodegen).exists() else None

    p12_dir = Path(env["P12_DIR"])
    files = {
        "release_dir": release_dir,
        "project_yml": release_dir / "project.yml",
        "source_dir": release_dir / "PAICC" / "Sources",
        "app_icon": release_dir / "PAICC" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset",
        "info_plist": release_dir / "PAICC" / "Sources" / "App" / "Info.plist",
        "ensure_asc_app": release_dir / "scripts" / "ensure_asc_app.py",
        "configure_testflight": release_dir / "scripts" / "configure_testflight.py",
        "asc_key_path": Path(env.get("ASC_KEY_PATH", "")),
        "rcodesign": Path(env["RCODESIGN"]),
        "signing_private_key_pem": Path(env.get("SIGNING_PRIVATE_KEY_PEM", p12_dir / "dist_cert_private_key.pem")),
        "signing_certificate_pem": Path(env.get("SIGNING_CERTIFICATE_PEM", p12_dir / "distribution-cert.pem")),
    }
    file_status = {name: path.exists() for name, path in files.items()}

    missing_commands = [name for name, path in command_status.items() if not path]
    missing_files = [name for name, ok in file_status.items() if not ok]
    result = {
        "ok": not missing_commands and not missing_files,
        "missing_commands": missing_commands,
        "missing_files": missing_files,
        "app_version": env["APP_VERSION"],
        "next_build_number": env["APP_BUILD_NUMBER"],
        "bundle_id": env.get("APP_BUNDLE_ID"),
        "release_dir": str(release_dir),
    }
    log(json.dumps(result, indent=2, sort_keys=True))
    return result


def backup_and_sync(release_dir: Path, payload_dir: Path) -> Path:
    require_file(payload_dir / "project.yml", "source project.yml")
    if not (payload_dir / "PAICC").is_dir():
        raise ReleaseError(f"Missing source PAICC directory: {payload_dir / 'PAICC'}")
    backup = release_dir.with_name(f"{release_dir.name}.backup-{time.strftime('%Y%m%d-%H%M%S')}")
    run(["ditto", str(release_dir), str(backup)])
    run(["rsync", "-a", "--delete", str(payload_dir / "PAICC") + "/", str(release_dir / "PAICC") + "/"])
    shutil.copy2(payload_dir / "project.yml", release_dir / "project.yml")
    log(f"SYNCED_RELEASE={release_dir}")
    log(f"BACKUP={backup}")
    return backup


def sync_ssh(args: argparse.Namespace) -> None:
    spec = args.source_ssh or DEFAULT_SOURCE_SSH
    if ":" not in spec:
        raise ReleaseError("source ssh must look like user@host:/path/to/project")
    host, project_path = spec.split(":", 1)
    release_dir = Path(args.release_dir)
    with tempfile.TemporaryDirectory(prefix="pai-cc-ios-sync-") as temp_root:
        temp_dir = Path(temp_root)
        remote_ios = posixpath.join(project_path.rstrip("/"), "ios")
        remote_command = f"cd {shlex.quote(remote_ios)} && tar -czf - project.yml PAICC"
        log(f"SYNC_SOURCE={host}:{remote_ios}")
        producer = subprocess.Popen(["ssh", "-o", "BatchMode=yes", host, remote_command], stdout=subprocess.PIPE)
        try:
            run(["tar", "-xzf", "-", "-C", str(temp_dir)], input_stream=producer.stdout)
        finally:
            if producer.stdout:
                producer.stdout.close()
            rc = producer.wait()
        if rc != 0:
            raise ReleaseError(f"ssh sync failed with exit {rc}")
        backup_and_sync(release_dir, temp_dir)


def sync_archive(args: argparse.Namespace) -> None:
    release_dir = Path(args.release_dir)
    archive = Path(args.archive)
    require_file(archive, "source archive")
    with tempfile.TemporaryDirectory(prefix="pai-cc-ios-archive-") as temp_root:
        temp_dir = Path(temp_root)
        run(["tar", "-xzf", str(archive), "-C", str(temp_dir)])
        backup_and_sync(release_dir, temp_dir)


def ensure_app_icon_manifest(release_dir: Path) -> None:
    icon_dir = release_dir / "PAICC" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
    icon_dir.mkdir(parents=True, exist_ok=True)
    entries = [
        ("universal", "20x20", "2x", "AppIcon-40x40.png"),
        ("universal", "20x20", "3x", "AppIcon-60x60.png"),
        ("universal", "29x29", "2x", "AppIcon-58x58.png"),
        ("universal", "29x29", "3x", "AppIcon-87x87.png"),
        ("universal", "40x40", "2x", "AppIcon-80x80.png"),
        ("universal", "40x40", "3x", "AppIcon-120x120.png"),
        ("iphone", "60x60", "2x", "AppIcon-120x120.png"),
        ("iphone", "60x60", "3x", "AppIcon-180x180.png"),
        ("ipad", "20x20", "1x", "AppIcon-20x20.png"),
        ("ipad", "20x20", "2x", "AppIcon-40x40.png"),
        ("ipad", "29x29", "1x", "AppIcon-29x29.png"),
        ("ipad", "29x29", "2x", "AppIcon-58x58.png"),
        ("ipad", "40x40", "1x", "AppIcon-40x40.png"),
        ("ipad", "40x40", "2x", "AppIcon-80x80.png"),
        ("ipad", "76x76", "1x", "AppIcon-76x76.png"),
        ("ipad", "76x76", "2x", "AppIcon-152x152.png"),
        ("ipad", "83.5x83.5", "2x", "AppIcon-167x167.png"),
        ("ios-marketing", "1024x1024", "1x", "AppIcon-1024x1024.png"),
    ]
    missing = [filename for _, _, _, filename in entries if not (icon_dir / filename).exists()]
    if missing:
        raise ReleaseError("Missing app icon files: " + ", ".join(sorted(set(missing))))
    contents = {
        "images": [
            {"idiom": idiom, "size": size, "scale": scale, "filename": filename}
            if idiom != "ios-marketing"
            else {"idiom": idiom, "size": size, "scale": scale, "filename": filename}
            for idiom, size, scale, filename in entries
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (icon_dir / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")
    log("APP_ICON_MANIFEST_OK=true")


def ensure_info_plist(release_dir: Path) -> None:
    plist = release_dir / "PAICC" / "Sources" / "App" / "Info.plist"
    require_file(plist, "Info.plist")

    def plistbuddy(command: str, check: bool = False) -> subprocess.CompletedProcess[str]:
        return run(["/usr/libexec/PlistBuddy", "-c", command, str(plist)], check=check)

    if plistbuddy("Print :CFBundleIconName").returncode != 0:
        plistbuddy("Add :CFBundleIconName string AppIcon", check=True)
    else:
        plistbuddy("Set :CFBundleIconName AppIcon", check=True)

    if plistbuddy("Print :ITSAppUsesNonExemptEncryption").returncode != 0:
        plistbuddy("Add :ITSAppUsesNonExemptEncryption bool false", check=True)
    else:
        plistbuddy("Set :ITSAppUsesNonExemptEncryption false", check=True)
    log("INFO_PLIST_OK=true")


def parse_key_values(output: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in output.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            if re.match(r"^[A-Z0-9_]+$", key):
                values[key] = value.strip()
    return values


def prepare_asc(release_dir: Path, env: dict[str, str]) -> tuple[Path, str]:
    completed = run([sys.executable, "scripts/ensure_asc_app.py"], cwd=release_dir, env=env)
    values = parse_key_values(completed.stdout or "")
    profile_path = values.get("PROFILE_PATH")
    app_id = values.get("ASC_APP_ID")
    if not profile_path or not app_id:
        raise ReleaseError("ensure_asc_app.py did not emit PROFILE_PATH and ASC_APP_ID")
    return Path(profile_path), app_id


def maybe_unlock_keychain(env: dict[str, str]) -> None:
    keychain = env.get("SIGNING_KEYCHAIN")
    password = env.get("SIGNING_KEYCHAIN_PASSWORD")
    if not keychain or not password:
        log("KEYCHAIN_UNLOCK_SKIPPED=missing_config")
        return
    keychain_path = Path(keychain)
    if not keychain_path.exists():
        log(f"KEYCHAIN_UNLOCK_SKIPPED=missing:{keychain_path}")
        return
    result = run(["security", "unlock-keychain", "-p", password, str(keychain_path)], check=False)
    if result.returncode == 0:
        run(["security", "list-keychains", "-d", "user", "-s", str(keychain_path), str(Path.home() / "Library/Keychains/login.keychain-db")], check=False)
        run(["security", "default-keychain", "-s", str(keychain_path)], check=False)
        run(["security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", password, str(keychain_path)], check=False)
        log("KEYCHAIN_UNLOCKED=true")
    else:
        log("KEYCHAIN_UNLOCKED=false")
        log("KEYCHAIN_UNLOCK_FAILURE_IS_OK_WHEN_RCODESIGN_IS_AVAILABLE=true")


def generate_project(release_dir: Path, env: dict[str, str]) -> None:
    xcodegen = shutil.which("xcodegen", path=env.get("PATH")) or "/Users/macstar/bin/xcodegen"
    require_file(Path(xcodegen), "xcodegen")
    run([xcodegen, "generate"], cwd=release_dir, env=env)


def archive_app(release_dir: Path, env: dict[str, str]) -> Path:
    build_dir = release_dir / "build"
    if build_dir.exists():
        shutil.rmtree(build_dir)
    build_dir.mkdir(parents=True)
    archive_path = build_dir / "PAICC.xcarchive"
    run(
        [
            "xcodebuild",
            "-project",
            "PAICC.xcodeproj",
            "-scheme",
            "PAICC",
            "-configuration",
            "Release",
            "-destination",
            "generic/platform=iOS",
            "-archivePath",
            str(archive_path),
            f"APPLE_TEAM_ID={env['APPLE_TEAM_ID']}",
            f"PRODUCT_BUNDLE_IDENTIFIER={env['APP_BUNDLE_ID']}",
            f"MARKETING_VERSION={env['APP_VERSION']}",
            f"CURRENT_PROJECT_VERSION={env['APP_BUILD_NUMBER']}",
            "CODE_SIGNING_ALLOWED=NO",
            "clean",
            "archive",
        ],
        cwd=release_dir,
        env=env,
    )
    app_path = archive_path / "Products" / "Applications" / "PAICC.app"
    require_file(app_path, "archived app")
    return app_path


def sign_path_with_rcodesign(target: Path, env: dict[str, str], entitlements: Path | None = None) -> None:
    p12_dir = Path(env["P12_DIR"])
    rcodesign = Path(env["RCODESIGN"])
    private_key = Path(env.get("SIGNING_PRIVATE_KEY_PEM", str(p12_dir / "dist_cert_private_key.pem")))
    certificate = Path(env.get("SIGNING_CERTIFICATE_PEM", str(p12_dir / "distribution-cert.pem")))
    require_file(rcodesign, "rcodesign")
    require_file(private_key, "signing private key pem")
    require_file(certificate, "signing certificate pem")
    command = [
        str(rcodesign),
        "sign",
        "--pem-file",
        str(private_key),
        "--pem-file",
        str(certificate),
        "--timestamp-url",
        "none",
    ]
    if entitlements:
        command += ["--entitlements-xml-file", str(entitlements)]
    command.append(str(target))
    run(command)


def write_distribution_entitlements(profile_xml: str, output: Path, env: dict[str, str]) -> None:
    profile = plistlib.loads(profile_xml.encode("utf-8"))
    source = profile.get("Entitlements", {})
    team_id = env["APPLE_TEAM_ID"]
    bundle_id = env["APP_BUNDLE_ID"]
    app_identifier = f"{team_id}.{bundle_id}"
    keychain_group = f"{team_id}.{bundle_id}"

    entitlements: dict[str, Any] = {
        "application-identifier": app_identifier,
        "com.apple.developer.team-identifier": team_id,
        "get-task-allow": False,
        "keychain-access-groups": [keychain_group],
    }
    if source.get("beta-reports-active", True):
        entitlements["beta-reports-active"] = True

    allowed_extra = {
        item.strip()
        for item in env.get("IOS_ALLOWED_EXTRA_ENTITLEMENTS", "").split(",")
        if item.strip()
    }
    for key in sorted(allowed_extra):
        if key in source:
            entitlements[key] = source[key]

    output.write_bytes(plistlib.dumps(entitlements, fmt=plistlib.FMT_XML, sort_keys=True))
    removed = sorted(set(source) - set(entitlements))
    log("ENTITLEMENTS_WRITTEN=true")
    if removed:
        log("ENTITLEMENTS_REMOVED=" + ",".join(removed))


def sign_app(release_dir: Path, app_path: Path, profile_path: Path, env: dict[str, str]) -> None:
    build_dir = release_dir / "build"
    shutil.copy2(profile_path, app_path / "embedded.mobileprovision")
    profile_plist = build_dir / "profile.plist"
    entitlements = build_dir / "entitlements.plist"
    decoded = subprocess.run(["security", "cms", "-D", "-i", str(profile_path)], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=True)
    profile_plist.write_text(decoded.stdout, encoding="utf-8")
    write_distribution_entitlements(decoded.stdout, entitlements, env)

    frameworks = app_path / "Frameworks"
    if frameworks.exists():
        for item in sorted(frameworks.rglob("*")):
            if item.suffix in {".framework", ".dylib"}:
                sign_path_with_rcodesign(item, env)
        log("FRAMEWORKS_SIGNED=true")

    sign_path_with_rcodesign(app_path, env, entitlements)
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app_path)])
    log("SIGNING_VERIFIED=true")


def package_ipa(release_dir: Path, app_path: Path) -> Path:
    package_dir = release_dir / "build" / "package"
    export_dir = release_dir / "build" / "export"
    if package_dir.exists():
        shutil.rmtree(package_dir)
    if export_dir.exists():
        shutil.rmtree(export_dir)
    payload_dir = package_dir / "Payload"
    payload_dir.mkdir(parents=True)
    export_dir.mkdir(parents=True)
    run(["ditto", str(app_path), str(payload_dir / "PAICC.app")])
    swift_support = release_dir / "build" / "PAICC.xcarchive" / "SwiftSupport"
    zip_items = ["Payload"]
    if swift_support.exists():
        run(["ditto", str(swift_support), str(package_dir / "SwiftSupport")])
        zip_items.append("SwiftSupport")
    ipa = export_dir / "PAICC.ipa"
    run(["zip", "-qry", str(ipa), *zip_items], cwd=package_dir)
    require_file(ipa, "IPA")
    log(f"IPA_PATH={ipa}")
    return ipa


def upload_ipa(ipa: Path, env: dict[str, str]) -> None:
    run(
        [
            "xcrun",
            "altool",
            "--upload-app",
            "--type",
            "ios",
            "-f",
            str(ipa),
            "--apiKey",
            env["ASC_KEY_ID"],
            "--apiIssuer",
            env["ASC_ISSUER_ID"],
            "--verbose",
        ],
        env=env,
    )
    log("UPLOAD_SUBMITTED=true")


def configure_testflight(release_dir: Path, env: dict[str, str], app_id: str) -> None:
    env = env.copy()
    env["ASC_APP_ID"] = app_id
    run([sys.executable, "scripts/configure_testflight.py"], cwd=release_dir, env=env)


def status(args: argparse.Namespace) -> None:
    release_dir = Path(args.release_dir)
    env = merged_env(args, build_number=args.build_number or "")
    env["APP_BUILD_NUMBER"] = args.build_number or ""
    run([sys.executable, "scripts/check_status.py"], cwd=release_dir, env=env, check=False)


def publish(args: argparse.Namespace) -> None:
    release_dir = Path(args.release_dir)
    build_number = args.build_number or time.strftime("%Y%m%d%H%M%S")
    env = merged_env(args, build_number=build_number)
    log(f"PUBLISH_STARTED={time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}")
    log(f"APP_VERSION={env['APP_VERSION']}")
    log(f"APP_BUILD_NUMBER={env['APP_BUILD_NUMBER']}")
    if args.sync_ssh:
        args.source_ssh = args.sync_ssh
        sync_ssh(args)
        env = merged_env(args, build_number=build_number)
    preflight_result = preflight(argparse.Namespace(**{**vars(args), "build_number": build_number}))
    if not preflight_result["ok"]:
        raise ReleaseError("Preflight failed")
    maybe_unlock_keychain(env)
    ensure_app_icon_manifest(release_dir)
    ensure_info_plist(release_dir)
    profile_path, app_id = prepare_asc(release_dir, env)
    generate_project(release_dir, env)
    app_path = archive_app(release_dir, env)
    sign_app(release_dir, app_path, profile_path, env)
    ipa = package_ipa(release_dir, app_path)
    upload_ipa(ipa, env)
    configure_testflight(release_dir, env, app_id)
    log("FULL_PIPELINE_COMPLETED=true")
    log(f"APP_VERSION={env['APP_VERSION']}")
    log(f"APP_BUILD_NUMBER={env['APP_BUILD_NUMBER']}")


def serve(args: argparse.Namespace) -> None:
    script = Path(__file__).resolve()
    token = args.token or os.getenv("IOS_PUBLISH_TOKEN", "")

    class Handler(BaseHTTPRequestHandler):
        def send_json(self, status_code: int, payload: dict[str, Any]) -> None:
            data = json.dumps(payload).encode("utf-8")
            self.send_response(status_code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def authorized(self) -> bool:
            if not token:
                return self.client_address[0] in {"127.0.0.1", "::1"}
            return self.headers.get("Authorization") == f"Bearer {token}"

        def do_GET(self) -> None:
            if self.path == "/health":
                self.send_json(200, {"ok": True})
                return
            if self.path == "/status":
                if not self.authorized():
                    self.send_json(401, {"ok": False, "error": "unauthorized"})
                    return
                completed = subprocess.run([sys.executable, str(script), "status"], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                self.send_json(200, {"ok": completed.returncode == 0, "output": completed.stdout})
                return
            self.send_json(404, {"ok": False, "error": "not found"})

        def do_POST(self) -> None:
            if self.path != "/publish":
                self.send_json(404, {"ok": False, "error": "not found"})
                return
            if not self.authorized():
                self.send_json(401, {"ok": False, "error": "unauthorized"})
                return
            length = int(self.headers.get("Content-Length", "0"))
            body = json.loads(self.rfile.read(length).decode("utf-8") or "{}")
            log_dir = Path(args.release_dir) / "publish-api-logs"
            log_dir.mkdir(parents=True, exist_ok=True)
            build = body.get("build_number") or time.strftime("%Y%m%d%H%M%S")
            log_path = log_dir / f"publish-{build}.log"
            command = [sys.executable, str(script), "--release-dir", args.release_dir, "--build-number", build]
            if body.get("version"):
                command += ["--version", str(body["version"])]
            command.append("publish")
            if body.get("sync_ssh"):
                command += ["--sync-ssh", str(body["sync_ssh"])]
            with log_path.open("w", encoding="utf-8") as log_file:
                process = subprocess.Popen(command, stdout=log_file, stderr=subprocess.STDOUT)
            self.send_json(202, {"ok": True, "pid": process.pid, "build_number": build, "log": str(log_path)})

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    log(f"LISTENING=http://{args.host}:{args.port}")
    server.serve_forever()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="One-click PAI-CC iOS TestFlight release manager.")
    parser.add_argument("--release-dir", default=str(DEFAULT_RELEASE_DIR))
    parser.add_argument("--shared-env", default=str(DEFAULT_SHARED_ENV))
    parser.add_argument("--project-env", default=str(DEFAULT_PROJECT_ENV))
    parser.add_argument("--version", default="")
    parser.add_argument("--build-number", default="")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("preflight")
    status_parser = sub.add_parser("status")
    status_parser.add_argument("--build-number", default="")

    sync_parser = sub.add_parser("sync-ssh")
    sync_parser.add_argument("--source-ssh", default=DEFAULT_SOURCE_SSH)

    archive_parser = sub.add_parser("sync-archive")
    archive_parser.add_argument("archive")

    publish_parser = sub.add_parser("publish")
    publish_parser.add_argument("--sync-ssh", default="")

    serve_parser = sub.add_parser("serve")
    serve_parser.add_argument("--host", default="127.0.0.1")
    serve_parser.add_argument("--port", type=int, default=8765)
    serve_parser.add_argument("--token", default="")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.command == "preflight":
            return 0 if preflight(args)["ok"] else 2
        if args.command == "status":
            status(args)
            return 0
        if args.command == "sync-ssh":
            sync_ssh(args)
            return 0
        if args.command == "sync-archive":
            sync_archive(args)
            return 0
        if args.command == "publish":
            publish(args)
            return 0
        if args.command == "serve":
            serve(args)
            return 0
    except ReleaseError as error:
        log(f"ERROR={error}")
        return 1
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
