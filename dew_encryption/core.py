from __future__ import annotations

import argparse
import datetime as dt
import os
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path


APP_NAME = "Dew Encryption"
REPO_DIR_NAME = ".dew-encryption-repo"
ARCHIVE_DIR_NAME = "Dew Encryption Archives"


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


def find_executable(name: str, fallbacks: list[Path] | None = None) -> Path:
    found = shutil.which(name)
    if found:
        return Path(found)
    for candidate in fallbacks or []:
        if candidate.exists():
            return candidate
    raise DewError(f"Required executable not found: {name}")


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


def selected_root(paths: list[Path]) -> Path:
    resolved = [p.resolve() for p in paths if p.exists()]
    if not resolved:
        raise DewError("No existing files or folders were selected.")
    if len(resolved) == 1:
        return resolved[0]
    common = Path(os.path.commonpath([str(p.parent if p.is_file() else p) for p in resolved]))
    return common.resolve()


def archive_output_dir(source: Path) -> Path:
    if source.is_file():
        base = source.parent
    else:
        base = source
    out = base / ARCHIVE_DIR_NAME
    out.mkdir(parents=True, exist_ok=True)
    return out


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
    repo = archive_output_dir(root) / REPO_DIR_NAME
    ensure_repo(repo, git)
    copy_selection(paths, repo)
    commit = commit_repo(repo, git, f"dew snapshot {dt.datetime.now().isoformat(timespec='seconds')}")
    archive = compress_repo(repo, archive_output_dir(root), seven_zip, password=password)
    return DewResult(source=root, repo=repo, archive=archive, commit=commit)


def snapshot(paths: list[Path], label: str | None = None) -> DewResult:
    git = find_executable("git")
    root = selected_root(paths)
    repo = archive_output_dir(root) / REPO_DIR_NAME
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
