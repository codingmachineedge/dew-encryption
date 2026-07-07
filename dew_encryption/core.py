from __future__ import annotations

import argparse
import datetime as dt
import getpass
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile
import urllib.error
import urllib.request
from dataclasses import dataclass
from dataclasses import asdict
from pathlib import Path


APP_NAME = "Dew Encryption"
REPO_DIR_NAME = ".dew-encryption-repo"
ARCHIVE_DIR_NAME = "Dew Encryption Archives"
VERACRYPT_EXT = ".dew.hc"


def app_base_dir() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent.parent


def config_file() -> Path:
    explicit = os.environ.get("DEW_ENCRYPTION_CONFIG")
    if explicit:
        return Path(explicit).expanduser().resolve()
    base = app_base_dir()
    if os.environ.get("DEW_ENCRYPTION_PORTABLE") == "1" or (base / "portable.flag").exists():
        return base / "settings.json"
    return Path(os.environ.get("APPDATA") or Path.home() / ".config") / "DewEncryption" / "settings.json"


class DewError(RuntimeError):
    pass


@dataclass(frozen=True)
class DewResult:
    source: Path
    repo: Path
    archive: Path
    commit: str


@dataclass(frozen=True)
class HistoryEntry:
    commit: str
    author_date: str
    subject: str


@dataclass(frozen=True)
class FileChange:
    status: str
    path: str




@dataclass
class DewDriveProfile:
    registry_ref: str

@dataclass
class VeraCryptSettings:
    encryption: str = "AES"
    hash: str = "SHA-512"
    filesystem: str = "exFAT"
    pim: str = "0"
    size_padding_mb: int = 64
    size_multiplier: float = 1.25
    minimum_size_mb: int = 32
    keep_source_after_encrypt: bool = False
    keep_container_after_decrypt: bool = True
    veracrypt_path: str = ""


@dataclass
class ThemeSettings:
    background: str = "#0f172a"
    foreground: str = "#e5e7eb"
    accent: str = "#38bdf8"
    font_family: str = "Segoe UI"
    font_size: int = 10


@dataclass
class HookAction:
    name: str = "New action"
    event: str = "open"
    kind: str = "script"
    target: str = ""
    payload: str = ""
    enabled: bool = True


@dataclass
class ContainerProfile:
    name: str = "Default"
    path: str = ""
    mount_path: str = ""
    theme: ThemeSettings | None = None
    hooks: list[HookAction] | None = None


@dataclass
class AppSettings:
    veracrypt: VeraCryptSettings
    containers: list[ContainerProfile] | None = None


def default_settings() -> AppSettings:
    return AppSettings(veracrypt=VeraCryptSettings(), containers=[])


def load_settings() -> AppSettings:
    path = config_file()
    if not path.exists():
        return default_settings()
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return default_settings()
    vc_raw = raw.get("veracrypt", {}) if isinstance(raw, dict) else {}
    defaults = VeraCryptSettings()
    values = asdict(defaults)
    values.update({key: value for key, value in vc_raw.items() if key in values})
    profiles: list[ContainerProfile] = []
    for profile_raw in raw.get("containers", []) if isinstance(raw, dict) else []:
        if not isinstance(profile_raw, dict):
            continue
        theme_raw = profile_raw.get("theme") if isinstance(profile_raw.get("theme"), dict) else {}
        theme_values = asdict(ThemeSettings())
        theme_values.update({key: value for key, value in theme_raw.items() if key in theme_values})
        hooks: list[HookAction] = []
        for hook_raw in profile_raw.get("hooks", []):
            if isinstance(hook_raw, dict):
                hook_values = asdict(HookAction())
                hook_values.update({key: value for key, value in hook_raw.items() if key in hook_values})
                hooks.append(HookAction(**hook_values))
        profiles.append(ContainerProfile(
            name=str(profile_raw.get("name") or "Default"),
            path=str(profile_raw.get("path") or ""),
            mount_path=str(profile_raw.get("mount_path") or ""),
            theme=ThemeSettings(**theme_values),
            hooks=hooks,
        ))
    return AppSettings(veracrypt=VeraCryptSettings(**values), containers=profiles)


def save_settings(settings: AppSettings) -> None:
    path = config_file()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(asdict(settings), indent=2), encoding="utf-8")


def find_executable(name: str, fallbacks: list[Path] | None = None) -> Path:
    found = shutil.which(name)
    if found:
        return Path(found)
    for candidate in fallbacks or []:
        if candidate.exists():
            return candidate
    raise DewError(f"Required executable not found: {name}")


def find_veracrypt() -> Path:
    configured = load_settings().veracrypt.veracrypt_path
    if configured and Path(configured).exists():
        return Path(configured)
    names = ["VeraCrypt.exe", "veracrypt.exe"] if os.name == "nt" else ["veracrypt"]
    for name in names:
        found = shutil.which(name)
        if found:
            return Path(found)
    fallbacks = [
        Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "VeraCrypt" / "VeraCrypt.exe",
        Path(os.environ.get("ProgramFiles(x86)", "C:/Program Files (x86)")) / "VeraCrypt" / "VeraCrypt.exe",
        Path("/usr/bin/veracrypt"),
        Path("/usr/local/bin/veracrypt"),
    ]
    for candidate in fallbacks:
        if candidate.exists():
            return candidate
    raise DewError("VeraCrypt was not found. Install VeraCrypt and make sure its CLI is available.")




def find_docker() -> Path:
    docker = shutil.which("docker")
    if docker:
        return Path(docker)
    fallbacks = [
        Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "Docker" / "Docker" / "resources" / "bin" / "docker.exe",
        Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "Docker" / "Docker" / "resources" / "docker.exe",
        Path("/usr/bin/docker"),
        Path("/usr/local/bin/docker"),
    ]
    for candidate in fallbacks:
        if candidate.exists():
            return candidate
    raise DewError("Docker was not found. Install Docker and make sure its CLI is available.")


def run_docker(args: list[str]) -> str:
    return run([str(find_docker()), *args])


def dew_drive_image_ref(profile: DewDriveProfile) -> str:
    registry_ref = profile.registry_ref.strip()
    if not registry_ref:
        raise DewError("Dew Drive registry reference is empty.")
    return registry_ref


def build_dew_drive_image(profile: DewDriveProfile, encrypted_payload: Path, metadata: dict[str, object]) -> str:
    registry_ref = dew_drive_image_ref(profile)
    encrypted_payload = Path(encrypted_payload).expanduser().resolve()
    if not encrypted_payload.exists():
        raise DewError(f"Encrypted payload does not exist: {encrypted_payload}")
    with tempfile.TemporaryDirectory(prefix="dew-drive-build-") as temp_dir:
        context = Path(temp_dir)
        dew_drive = context / "dew-drive"
        dew_drive.mkdir(parents=True, exist_ok=True)
        payload_target = dew_drive / encrypted_payload.name
        if encrypted_payload.is_dir():
            shutil.copytree(encrypted_payload, payload_target)
        else:
            shutil.copy2(encrypted_payload, payload_target)
        (dew_drive / "metadata.json").write_text(json.dumps(metadata, indent=2, sort_keys=True), encoding="utf-8")
        (context / "Dockerfile").write_text("FROM scratch\nCOPY dew-drive /dew-drive\n", encoding="utf-8")
        return run_docker(["build", "-t", registry_ref, str(context)])


def push_dew_drive(profile: DewDriveProfile) -> str:
    return run_docker(["push", dew_drive_image_ref(profile)])


def pull_dew_drive(registry_ref: str, output_dir: Path) -> Path:
    registry_ref = registry_ref.strip()
    if not registry_ref:
        raise DewError("Dew Drive registry reference is empty.")
    output_dir = Path(output_dir).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    run_docker(["pull", registry_ref])
    container = run_docker(["create", registry_ref])
    try:
        run_docker(["cp", f"{container}:/dew-drive", str(output_dir)])
    finally:
        run_docker(["rm", container])
    return output_dir / "dew-drive"


def run(cmd: list[str], cwd: Path | None = None) -> str:
    proc = subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if proc.returncode != 0:
        raise DewError(f"Command failed ({proc.returncode}): {' '.join(cmd)}\n{proc.stdout}")
    return proc.stdout.strip()


def run_bytes(cmd: list[str], cwd: Path | None = None) -> bytes:
    proc = subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if proc.returncode != 0:
        output = proc.stderr.decode(errors="replace")
        raise DewError(f"Command failed ({proc.returncode}): {' '.join(cmd)}\n{output}")
    return proc.stdout


def selected_root(paths: list[Path]) -> Path:
    resolved = [p.resolve() for p in paths if p.exists()]
    if not resolved:
        raise DewError("No existing files or folders were selected.")
    if len(resolved) == 1:
        return resolved[0]
    common = Path(os.path.commonpath([str(p.parent if p.is_file() else p) for p in resolved]))
    return common.resolve()


def unique_paths(paths: list[str]) -> list[Path]:
    seen: set[str] = set()
    result: list[Path] = []
    for item in paths:
        path = Path(item).resolve()
        key = str(path).casefold() if os.name == "nt" else str(path)
        if key in seen:
            continue
        seen.add(key)
        result.append(path)
    return result


def archive_output_dir(source: Path) -> Path:
    if source.is_file():
        base = source.parent
    else:
        base = source
    out = base / ARCHIVE_DIR_NAME
    out.mkdir(parents=True, exist_ok=True)
    return out


def repo_for_source(source: Path) -> Path:
    return archive_output_dir(source.resolve()) / REPO_DIR_NAME


def ensure_repo(repo: Path, git: Path) -> None:
    repo.mkdir(parents=True, exist_ok=True)
    if not (repo / ".git").exists():
        run([str(git), "init"], cwd=repo)
        run([str(git), "config", "user.name", "Dew Encryption"], cwd=repo)
        run([str(git), "config", "user.email", "dew-encryption@local"], cwd=repo)


def copy_selection(paths: list[Path], repo: Path) -> None:
    work = repo / "files"
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True, exist_ok=True)
    for source in paths:
        source = source.resolve()
        if not source.exists():
            continue
        destination = work / source.name
        if source.is_dir():
            ignore = shutil.ignore_patterns(".git", REPO_DIR_NAME, ARCHIVE_DIR_NAME)
            shutil.copytree(source, destination, ignore=ignore)
        else:
            shutil.copy2(source, destination)


def commit_repo(repo: Path, git: Path, label: str) -> str:
    run([str(git), "add", "-A"], cwd=repo)
    status = run([str(git), "status", "--porcelain"], cwd=repo)
    if status:
        run([str(git), "commit", "-m", label], cwd=repo)
    return current_commit(repo, git)


def current_commit(repo: Path, git: Path | None = None) -> str:
    git = git or find_executable("git")
    try:
        return run([str(git), "rev-parse", "--short", "HEAD"], cwd=repo)
    except DewError:
        return ""


def compress_repo(repo: Path, output_dir: Path, seven_zip: Path, password: str | None = None) -> Path:
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    archive = output_dir / f"dew-encryption-{stamp}.7z"
    cmd = [str(seven_zip), "a", "-t7z", "-mx=9", str(archive), str(repo)]
    if password:
        cmd.insert(4, "-mhe=on")
        cmd.insert(4, f"-p{password}")
    run(cmd)
    return archive


def process(paths: list[Path], password: str | None = None) -> DewResult:
    git = find_executable("git")
    seven_zip = find_executable(
        "7z",
        [
            Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "7-Zip" / "7z.exe",
            Path(os.environ.get("ProgramFiles(x86)", "C:/Program Files (x86)")) / "7-Zip" / "7z.exe",
        ],
    )
    root = selected_root(paths)
    repo = repo_for_source(root)
    ensure_repo(repo, git)
    copy_selection(paths, repo)
    commit = commit_repo(repo, git, f"dew snapshot {dt.datetime.now().isoformat(timespec='seconds')}")
    archive = compress_repo(repo, archive_output_dir(root), seven_zip, password=password)
    return DewResult(source=root, repo=repo, archive=archive, commit=commit)


def snapshot(paths: list[Path], label: str | None = None) -> DewResult:
    git = find_executable("git")
    root = selected_root(paths)
    repo = repo_for_source(root)
    ensure_repo(repo, git)
    copy_selection(paths, repo)
    commit = commit_repo(repo, git, label or f"dew history {dt.datetime.now().isoformat(timespec='seconds')}")
    return DewResult(source=root, repo=repo, archive=Path(), commit=commit)


def history(repo: Path, limit: int = 100) -> list[HistoryEntry]:
    git = find_executable("git")
    if not (repo / ".git").exists():
        return []
    raw = run(
        [str(git), "log", f"--max-count={limit}", "--date=iso-local", "--pretty=format:%h%x09%ad%x09%s"],
        cwd=repo,
    )
    entries: list[HistoryEntry] = []
    for line in raw.splitlines():
        parts = line.split("\t", 2)
        if len(parts) == 3:
            entries.append(HistoryEntry(parts[0], parts[1], parts[2]))
    return entries


def commit_details(repo: Path, commit: str) -> tuple[str, list[FileChange]]:
    git = find_executable("git")
    message = run([str(git), "show", "--no-patch", "--date=iso-local", "--pretty=fuller", commit], cwd=repo)
    raw_changes = run([str(git), "show", "--name-status", "--format=", commit], cwd=repo)
    changes: list[FileChange] = []
    for line in raw_changes.splitlines():
        parts = line.split("\t", 1)
        if len(parts) == 2:
            changes.append(FileChange(parts[0], parts[1]))
    return message, changes


def create_archive_for_repo(repo: Path, password: str | None = None) -> Path:
    seven_zip = find_executable(
        "7z",
        [
            Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "7-Zip" / "7z.exe",
            Path(os.environ.get("ProgramFiles(x86)", "C:/Program Files (x86)")) / "7-Zip" / "7z.exe",
        ],
    )
    return compress_repo(repo, repo.parent, seven_zip, password=password)


def restore_commit(repo: Path, commit: str, source: Path) -> None:
    git = find_executable("git")
    source = source.resolve()
    repo_member = f"files/{source.name}"
    archive = run_bytes([str(git), "archive", "--format=zip", commit, repo_member], cwd=repo)
    with tempfile.TemporaryDirectory(prefix="dew-restore-") as temp_dir:
        temp = Path(temp_dir)
        zip_path = temp / "restore.zip"
        zip_path.write_bytes(archive)
        with zipfile.ZipFile(zip_path) as zf:
            zf.extractall(temp)
        restored = temp / repo_member
        if not restored.exists():
            raise DewError(f"Commit does not contain {repo_member}")
        if restored.is_dir():
            if source.exists() and source.is_file():
                source.unlink()
            source.mkdir(parents=True, exist_ok=True)
            for child in source.iterdir():
                if child.name == ARCHIVE_DIR_NAME:
                    continue
                if child.is_dir():
                    shutil.rmtree(child)
                else:
                    child.unlink()
            for child in restored.iterdir():
                target = source / child.name
                if child.is_dir():
                    shutil.copytree(child, target)
                else:
                    shutil.copy2(child, target)
        else:
            source.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(restored, source)


def container_path_for_source(source: Path) -> Path:
    source = source.resolve()
    return source.with_name(source.name + VERACRYPT_EXT)


def source_path_for_container(container: Path) -> Path:
    container = container.resolve()
    name = container.name
    if name.endswith(VERACRYPT_EXT):
        return container.with_name(name[: -len(VERACRYPT_EXT)])
    if container.suffix.lower() == ".hc":
        return container.with_suffix("")
    return container.with_name(container.name + ".decrypted")


def estimated_container_size(source: Path, settings: VeraCryptSettings | None = None) -> str:
    settings = settings or load_settings().veracrypt
    size = 0
    if source.is_dir():
        for item in source.rglob("*"):
            if item.is_file():
                size += item.stat().st_size
    else:
        size = source.stat().st_size
    padded = max(
        size + settings.size_padding_mb * 1024 * 1024,
        int(size * settings.size_multiplier) + 16 * 1024 * 1024,
        settings.minimum_size_mb * 1024 * 1024,
    )
    return f"{padded // (1024 * 1024)}M"


def free_windows_drive_letter() -> str:
    used = {Path(f"{letter}:\\").drive.upper() for letter in "DEFGHIJKLMNOPQRSTUVWXYZ" if Path(f"{letter}:\\").exists()}
    for letter in reversed("DEFGHIJKLMNOPQRSTUVWXYZ"):
        drive = f"{letter}:"
        if drive.upper() not in used:
            return letter
    raise DewError("No free drive letter is available for VeraCrypt.")


def copy_into_mount(source: Path, mount_root: Path) -> None:
    target = mount_root / source.name
    if source.is_dir():
        shutil.copytree(source, target)
    else:
        shutil.copy2(source, target)


def copy_from_mount(mount_root: Path, output: Path) -> None:
    items = [item for item in mount_root.iterdir() if item.name not in {"System Volume Information", "$RECYCLE.BIN"}]
    if not items:
        raise DewError("The VeraCrypt container did not contain files to decrypt.")
    if len(items) == 1:
        item = items[0]
        target = output
        if item.is_dir():
            if target.exists():
                raise DewError(f"Output path already exists: {target}")
            shutil.copytree(item, target)
        else:
            if output.exists() and output.is_dir():
                target = output / item.name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(item, target)
        return
    output.mkdir(parents=True, exist_ok=True)
    for item in items:
        target = output / item.name
        if item.is_dir():
            shutil.copytree(item, target)
        else:
            shutil.copy2(item, target)


def veracrypt_create_container(
    source: Path,
    password: str,
    keep_source: bool | None = None,
    settings: VeraCryptSettings | None = None,
) -> Path:
    settings = settings or load_settings().veracrypt
    keep_source = settings.keep_source_after_encrypt if keep_source is None else keep_source
    source = source.resolve()
    if not source.exists():
        raise DewError(f"Source does not exist: {source}")
    vc = find_veracrypt()
    container = container_path_for_source(source)
    if container.exists():
        raise DewError(f"Container already exists: {container}")
    size = estimated_container_size(source, settings)

    if os.name == "nt":
        run([
            str(vc), "/create", str(container), "/size", size, "/password", password,
            "/encryption", settings.encryption, "/hash", settings.hash, "/filesystem", settings.filesystem,
            "/pim", settings.pim, "/silent", "/force", "/quit",
        ])
        letter = free_windows_drive_letter()
        try:
            run([str(vc), "/volume", str(container), "/letter", letter, "/password", password, "/pim", settings.pim, "/silent", "/quit"])
            mount_root = Path(f"{letter}:\\")
            copy_into_mount(source, mount_root)
        finally:
            run([str(vc), "/dismount", letter, "/silent", "/quit"])
    else:
        random_source = source if source.is_file() else next((p for p in source.rglob("*") if p.is_file()), source)
        run([
            str(vc), "--text", "--create", str(container), "--size", size, "--password", password,
            "--encryption", settings.encryption, "--hash", settings.hash, "--filesystem", settings.filesystem,
            "--pim", settings.pim, "--keyfiles", "", "--random-source", str(random_source), "--non-interactive",
        ])
        with tempfile.TemporaryDirectory(prefix="dew-vc-mount-") as mount_dir:
            mount_root = Path(mount_dir)
            try:
                run([str(vc), "--text", "--mount", str(container), str(mount_root), "--password", password, "--pim", settings.pim, "--keyfiles", "", "--protect-hidden", "no", "--non-interactive"])
                copy_into_mount(source, mount_root)
            finally:
                run([str(vc), "--text", "--dismount", str(container)])

    if not keep_source:
        if source.is_dir():
            shutil.rmtree(source)
        else:
            source.unlink()
    return container


def veracrypt_decrypt_container(
    container: Path,
    password: str,
    output: Path | None = None,
    keep_container: bool | None = None,
    settings: VeraCryptSettings | None = None,
) -> Path:
    settings = settings or load_settings().veracrypt
    keep_container = settings.keep_container_after_decrypt if keep_container is None else keep_container
    container = container.resolve()
    if not container.exists():
        raise DewError(f"Container does not exist: {container}")
    vc = find_veracrypt()
    output = (output or source_path_for_container(container)).resolve()

    if os.name == "nt":
        letter = free_windows_drive_letter()
        try:
            run([str(vc), "/volume", str(container), "/letter", letter, "/password", password, "/pim", settings.pim, "/silent", "/quit"])
            copy_from_mount(Path(f"{letter}:\\"), output)
        finally:
            run([str(vc), "/dismount", letter, "/silent", "/quit"])
    else:
        with tempfile.TemporaryDirectory(prefix="dew-vc-mount-") as mount_dir:
            mount_root = Path(mount_dir)
            try:
                run([str(vc), "--text", "--mount", str(container), str(mount_root), "--password", password, "--pim", settings.pim, "--keyfiles", "", "--protect-hidden", "no", "--non-interactive"])
                copy_from_mount(mount_root, output)
            finally:
                run([str(vc), "--text", "--dismount", str(container)])

    if not keep_container:
        container.unlink()
    return output




def container_history_repo(container: Path) -> Path:
    container = container.resolve()
    out = container.parent / ARCHIVE_DIR_NAME / "Container History" / container.stem
    out.mkdir(parents=True, exist_ok=True)
    return out / REPO_DIR_NAME


def snapshot_container(container: Path, label: str | None = None) -> DewResult:
    container = container.resolve()
    if not container.exists():
        raise DewError(f"Container does not exist: {container}")
    git = find_executable("git")
    repo = container_history_repo(container)
    ensure_repo(repo, git)
    copy_selection([container], repo)
    commit = commit_repo(repo, git, label or f"dew container history {dt.datetime.now().isoformat(timespec='seconds')}")
    return DewResult(source=container, repo=repo, archive=Path(), commit=commit)


def container_history(container: Path, limit: int = 100) -> list[HistoryEntry]:
    return history(container_history_repo(container), limit=limit)

def hook_variables(container: Path, mount_path: Path | None = None, event: str = "open") -> dict[str, str]:
    now = dt.datetime.now().isoformat(timespec="seconds")
    return {
        "event": event,
        "container": str(container),
        "container_name": container.name,
        "container_stem": container.stem,
        "mount_path": str(mount_path or ""),
        "user": getpass.getuser(),
        "host": os.environ.get("COMPUTERNAME") or os.environ.get("HOSTNAME") or "",
        "timestamp": now,
    }


def expand_hook_text(text: str, variables: dict[str, str]) -> str:
    result = text
    for key, value in variables.items():
        result = result.replace("{" + key + "}", value)
    return result


def run_container_hooks(profile: ContainerProfile | None, event: str, container: Path, mount_path: Path | None = None) -> list[str]:
    if not profile:
        return []
    variables = hook_variables(container, mount_path, event)
    messages: list[str] = []
    for hook in profile.hooks or []:
        if not hook.enabled or hook.event != event:
            continue
        target = expand_hook_text(hook.target, variables)
        payload = expand_hook_text(hook.payload, variables)
        try:
            if hook.kind == "script":
                if not target:
                    raise DewError("script hook target is empty")
                env = os.environ.copy()
                env.update({f"DEW_{key.upper()}": value for key, value in variables.items()})
                completed = subprocess.run(target, shell=True, text=True, input=payload or None, env=env, check=False)
                if completed.returncode != 0:
                    raise DewError(f"script exited with {completed.returncode}")
            elif hook.kind in {"discord", "home_assistant"}:
                if not target:
                    raise DewError("webhook URL is empty")
                body = payload or json.dumps({"content" if hook.kind == "discord" else "event": f"Dew container {event}: {container.name}"})
                data = body.encode("utf-8")
                req = urllib.request.Request(target, data=data, method="POST")
                req.add_header("Content-Type", "application/json")
                with urllib.request.urlopen(req, timeout=15) as response:
                    response.read()
            else:
                raise DewError(f"unknown hook kind: {hook.kind}")
            messages.append(f"{event} hook succeeded: {hook.name}")
        except (OSError, urllib.error.URLError, DewError) as exc:
            messages.append(f"{event} hook failed ({hook.name}): {exc}")
    return messages


def find_container_profile(container: Path) -> ContainerProfile | None:
    container = container.resolve()
    for profile in load_settings().containers or []:
        if profile.path and Path(profile.path).expanduser().resolve() == container:
            return profile
    return None

def watch(paths: list[Path], interval: float = 5.0, once: bool = False) -> None:
    last_commit = ""
    while True:
        result = snapshot(paths)
        if result.commit and result.commit != last_commit:
            print(f"{dt.datetime.now().isoformat(timespec='seconds')} committed {result.commit}", flush=True)
            last_commit = result.commit
        if once:
            return
        time.sleep(interval)


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv and argv[0] == "portable":
        parser = argparse.ArgumentParser(prog="dew-encryption portable", description="Manage portable mode.")
        parser.add_argument("--init", action="store_true", help="Create portable.flag beside the app so settings are stored portably.")
        parser.add_argument("--show", action="store_true", help="Show portable state and settings path.")
        args = parser.parse_args(argv[1:])
        marker = app_base_dir() / "portable.flag"
        if args.init:
            marker.write_text("portable\n", encoding="utf-8")
        print(json.dumps({
            "app_base": str(app_base_dir()),
            "portable": os.environ.get("DEW_ENCRYPTION_PORTABLE") == "1" or marker.exists(),
            "portable_marker": str(marker),
            "settings": str(config_file()),
        }, indent=2))
        return 0

    if argv and argv[0] == "veracrypt-settings":
        parser = argparse.ArgumentParser(prog="dew-encryption veracrypt-settings", description="Show or update remembered VeraCrypt defaults.")
        parser.add_argument("--show", action="store_true", help="Show current VeraCrypt settings as JSON.")
        parser.add_argument("--encryption", help="VeraCrypt encryption algorithm.")
        parser.add_argument("--hash", help="VeraCrypt hash algorithm.")
        parser.add_argument("--filesystem", help="Container filesystem.")
        parser.add_argument("--pim", help="VeraCrypt PIM value.")
        parser.add_argument("--size-padding-mb", type=int, help="Extra MB added to estimated source size.")
        parser.add_argument("--size-multiplier", type=float, help="Multiplier applied to source size estimate.")
        parser.add_argument("--minimum-size-mb", type=int, help="Minimum container size in MB.")
        parser.add_argument("--veracrypt-path", help="Explicit VeraCrypt executable path.")
        parser.add_argument("--keep-source-after-encrypt", choices=["true", "false"], help="Remember whether encrypt keeps original source.")
        parser.add_argument("--keep-container-after-decrypt", choices=["true", "false"], help="Remember whether decrypt keeps the container.")
        args = parser.parse_args(argv[1:])
        settings = load_settings()
        vc = settings.veracrypt
        if args.encryption:
            vc.encryption = args.encryption
        if args.hash:
            vc.hash = args.hash
        if args.filesystem:
            vc.filesystem = args.filesystem
        if args.pim:
            vc.pim = args.pim
        if args.size_padding_mb is not None:
            vc.size_padding_mb = args.size_padding_mb
        if args.size_multiplier is not None:
            vc.size_multiplier = args.size_multiplier
        if args.minimum_size_mb is not None:
            vc.minimum_size_mb = args.minimum_size_mb
        if args.veracrypt_path is not None:
            vc.veracrypt_path = args.veracrypt_path
        if args.keep_source_after_encrypt is not None:
            vc.keep_source_after_encrypt = args.keep_source_after_encrypt == "true"
        if args.keep_container_after_decrypt is not None:
            vc.keep_container_after_decrypt = args.keep_container_after_decrypt == "true"
        if not args.show:
            save_settings(settings)
        print(json.dumps(asdict(settings), indent=2))
        return 0

    if argv and argv[0] == "veracrypt-encrypt":
        parser = argparse.ArgumentParser(prog="dew-encryption veracrypt-encrypt", description="Move a file or folder into a VeraCrypt container.")
        parser.add_argument("sources", nargs="+", help="Files or folders to encrypt into VeraCrypt containers.")
        parser.add_argument("--password", help="VeraCrypt container password. If omitted, a hidden prompt is shown.")
        parser.add_argument("--keep-source", action="store_true", help="Keep the original file or folder after the container is created.")
        parser.add_argument("--remove-source", action="store_true", help="Remove the original file or folder after the container is created.")
        args = parser.parse_args(argv[1:])
        try:
            password = args.password or getpass.getpass("VeraCrypt password: ")
            if not password:
                raise DewError("A VeraCrypt password is required.")
            keep_source = None
            if args.keep_source:
                keep_source = True
            if args.remove_source:
                keep_source = False
            containers = [
                veracrypt_create_container(Path(source), password, keep_source=keep_source)
                for source in unique_paths(args.sources)
            ]
        except DewError as exc:
            print(f"dew encryption failed: {exc}", file=sys.stderr)
            return 1
        for container in containers:
            print(f"VeraCrypt container: {container}")
        return 0

    if argv and argv[0] == "veracrypt-decrypt":
        parser = argparse.ArgumentParser(prog="dew-encryption veracrypt-decrypt", description="Extract files from a VeraCrypt container.")
        parser.add_argument("containers", nargs="+", help="VeraCrypt container paths.")
        parser.add_argument("--password", help="VeraCrypt container password. If omitted, a hidden prompt is shown.")
        parser.add_argument("--output", help="Output file or folder path. Defaults beside the container.")
        parser.add_argument("--remove-container", action="store_true", help="Delete the container after successful extraction.")
        parser.add_argument("--keep-container", action="store_true", help="Keep the container after successful extraction.")
        args = parser.parse_args(argv[1:])
        try:
            password = args.password or getpass.getpass("VeraCrypt password: ")
            if not password:
                raise DewError("A VeraCrypt password is required.")
            if args.output and len(args.containers) > 1:
                raise DewError("--output can only be used with one container.")
            outputs = [
                veracrypt_decrypt_container(
                    Path(container),
                    password,
                    output=Path(args.output) if args.output else None,
                    keep_container=True if args.keep_container else (False if args.remove_container else None),
                )
                for container in unique_paths(args.containers)
            ]
        except DewError as exc:
            print(f"dew encryption failed: {exc}", file=sys.stderr)
            return 1
        for output in outputs:
            print(f"Decrypted to: {output}")
        return 0



    if argv and argv[0] == "container-history":
        parser = argparse.ArgumentParser(prog="dew-encryption container-history", description="Snapshot or inspect Git history for encrypted container files.")
        parser.add_argument("container", help="Container path.")
        parser.add_argument("--snapshot", action="store_true", help="Commit the current container file into its container history repo.")
        parser.add_argument("--limit", type=int, default=25, help="Maximum history rows to print.")
        args = parser.parse_args(argv[1:])
        try:
            container = Path(args.container)
            if args.snapshot:
                result = snapshot_container(container)
                print(f"Container history snapshot: {result.commit}")
                print(f"Repo: {result.repo}")
            for entry in container_history(container, limit=args.limit):
                print(f"{entry.commit}\t{entry.author_date}\t{entry.subject}")
        except DewError as exc:
            print(f"dew encryption failed: {exc}", file=sys.stderr)
            return 1
        return 0

    if argv and argv[0] == "container-hooks":
        parser = argparse.ArgumentParser(prog="dew-encryption container-hooks", description="Run configured container open/close hooks.")
        parser.add_argument("event", choices=["open", "close"], help="Hook event to run.")
        parser.add_argument("container", help="Container path.")
        parser.add_argument("--mount-path", default="", help="Mounted path exposed to hooks.")
        args = parser.parse_args(argv[1:])
        profile = find_container_profile(Path(args.container))
        for message in run_container_hooks(profile, args.event, Path(args.container), Path(args.mount_path) if args.mount_path else None):
            print(message)
        return 0

    if argv and argv[0] == "container-quick-create":
        parser = argparse.ArgumentParser(prog="dew-encryption container-quick-create", description="Create a VeraCrypt container from Explorer/Nautilus with remembered defaults.")
        parser.add_argument("sources", nargs="+", help="Files or folders to turn into containers.")
        parser.add_argument("--password", help="VeraCrypt container password. If omitted, a hidden prompt is shown.")
        args = parser.parse_args(argv[1:])
        try:
            password = args.password or getpass.getpass("VeraCrypt password: ")
            if not password:
                raise DewError("A VeraCrypt password is required.")
            settings = load_settings()
            for source in unique_paths(args.sources):
                container = veracrypt_create_container(source, password, settings=settings.veracrypt)
                profile = ContainerProfile(name=container.stem, path=str(container), theme=ThemeSettings(), hooks=[])
                settings.containers = settings.containers or []
                settings.containers.append(profile)
                print(f"Quick-created container: {container}")
            save_settings(settings)
        except DewError as exc:
            print(f"dew encryption failed: {exc}", file=sys.stderr)
            return 1
        return 0

    if argv and argv[0] == "watch":
        parser = argparse.ArgumentParser(prog="dew-encryption watch", description="Automatically commit selected paths whenever contents change.")
        parser.add_argument("paths", nargs="+", help="Files or folders to watch.")
        parser.add_argument("--interval", type=float, default=5.0, help="Polling interval in seconds.")
        parser.add_argument("--once", action="store_true", help="Run one history snapshot and exit.")
        args = parser.parse_args(argv[1:])
        try:
            watch([Path(p) for p in args.paths], interval=args.interval, once=args.once)
        except DewError as exc:
            print(f"dew encryption failed: {exc}", file=sys.stderr)
            return 1
        return 0

    if argv and argv[0] == "history":
        parser = argparse.ArgumentParser(prog="dew-encryption history", description="Show local Git history for a Dew Encryption archive repo.")
        parser.add_argument("repo", help="Path to .dew-encryption-repo.")
        parser.add_argument("--limit", type=int, default=25)
        args = parser.parse_args(argv[1:])
        try:
            for entry in history(Path(args.repo), limit=args.limit):
                print(f"{entry.commit}\t{entry.author_date}\t{entry.subject}")
        except DewError as exc:
            print(f"dew encryption failed: {exc}", file=sys.stderr)
            return 1
        return 0

    if argv and argv[0] == "details":
        parser = argparse.ArgumentParser(prog="dew-encryption details", description="Show commit metadata and changed files.")
        parser.add_argument("repo", help="Path to .dew-encryption-repo.")
        parser.add_argument("commit", help="Commit hash to inspect.")
        args = parser.parse_args(argv[1:])
        try:
            message, changes = commit_details(Path(args.repo), args.commit)
            print(message)
            print("\nChanged files:")
            for change in changes:
                print(f"{change.status}\t{change.path}")
        except DewError as exc:
            print(f"dew encryption failed: {exc}", file=sys.stderr)
            return 1
        return 0

    if argv and argv[0] == "restore":
        parser = argparse.ArgumentParser(prog="dew-encryption restore", description="Restore a file or folder from a history commit.")
        parser.add_argument("repo", help="Path to .dew-encryption-repo.")
        parser.add_argument("commit", help="Commit hash to restore.")
        parser.add_argument("source", help="Original file or folder path to restore.")
        args = parser.parse_args(argv[1:])
        try:
            restore_commit(Path(args.repo), args.commit, Path(args.source))
        except DewError as exc:
            print(f"dew encryption failed: {exc}", file=sys.stderr)
            return 1
        print(f"Restored {args.source} to {args.commit}")
        return 0

    parser = argparse.ArgumentParser(prog="dew-encryption", description="Commit selected files locally and compress them with 7-Zip.")
    parser.add_argument("paths", nargs="+", help="Files or folders selected in Explorer.")
    parser.add_argument("--password", help="Optional 7z password. Enables header encryption.")
    args = parser.parse_args(argv)
    try:
        result = process([Path(p) for p in args.paths], password=args.password)
    except DewError as exc:
        print(f"dew encryption failed: {exc}", file=sys.stderr)
        return 1
    print(f"Archive: {result.archive}")
    print(f"Repo: {result.repo}")
    print(f"Commit: {result.commit}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
