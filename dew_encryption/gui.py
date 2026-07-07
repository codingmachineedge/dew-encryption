from __future__ import annotations

import queue
import subprocess
import sys
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

from .core import (
    DewError,
    commit_details,
    create_archive_for_repo,
    history,
    process,
    repo_for_source,
    restore_commit,
    snapshot,
)


class DewFileManager(tk.Tk):
    def __init__(self, initial_paths: list[Path] | None = None, open_history: bool = False) -> None:
        super().__init__()
        self.title("Dew Encryption")
        self.geometry("1120x700")
        self.minsize(940, 560)
        self.selected: list[Path] = []
        self.events: queue.Queue[str] = queue.Queue()
        self.watch_stop = threading.Event()
        self.watch_thread: threading.Thread | None = None
        self._build()
        for path in initial_paths or []:
            self._add(path)
        if open_history:
            self.notebook.select(self.history_tab)
            self.refresh_history()
        self.after(100, self._drain_events)

    def _build(self) -> None:
        self.columnconfigure(0, weight=1)
        self.rowconfigure(1, weight=1)

        bar = ttk.Frame(self, padding=10)
        bar.grid(row=0, column=0, sticky="ew")
        ttk.Button(bar, text="Add Files", command=self.add_files).pack(side="left", padx=(0, 8))
        ttk.Button(bar, text="Add Folder", command=self.add_folder).pack(side="left", padx=(0, 8))
        ttk.Button(bar, text="Remove", command=self.remove_selected).pack(side="left", padx=(0, 8))
        ttk.Button(bar, text="Run Dew Encryption", command=self.run_job).pack(side="right")

        self.notebook = ttk.Notebook(self)
        self.notebook.grid(row=1, column=0, sticky="nsew", padx=10, pady=(0, 10))

        body = ttk.Frame(self.notebook, padding=(0, 0, 0, 0))
        self.notebook.add(body, text="Files")
        body.columnconfigure(0, weight=1)
        body.rowconfigure(0, weight=1)

        self.tree = ttk.Treeview(body, columns=("path", "kind"), show="headings", selectmode="extended")
        self.tree.heading("path", text="Path")
        self.tree.heading("kind", text="Type")
        self.tree.column("path", width=760)
        self.tree.column("kind", width=120, anchor="center")
        self.tree.grid(row=0, column=0, sticky="nsew")

        scroll = ttk.Scrollbar(body, orient="vertical", command=self.tree.yview)
        scroll.grid(row=0, column=1, sticky="ns")
        self.tree.configure(yscrollcommand=scroll.set)

        self.log = tk.Text(body, height=8, wrap="word")
        self.log.grid(row=1, column=0, columnspan=2, sticky="ew", pady=(10, 0))
        self.log.insert("end", "Select files or folders, then run Dew Encryption.\n")
        self.log.configure(state="disabled")

        self.history_tab = ttk.Frame(self.notebook)
        self.notebook.add(self.history_tab, text="History")
        self.history_tab.columnconfigure(0, weight=1)
        self.history_tab.columnconfigure(1, weight=1)
        self.history_tab.rowconfigure(1, weight=1)

        history_bar = ttk.Frame(self.history_tab, padding=(0, 0, 0, 10))
        history_bar.grid(row=0, column=0, columnspan=2, sticky="ew")
        ttk.Button(history_bar, text="Refresh History", command=self.refresh_history).pack(side="left", padx=(0, 8))
        ttk.Button(history_bar, text="Snapshot Now", command=self.snapshot_now).pack(side="left", padx=(0, 8))
        ttk.Button(history_bar, text="Start Auto History", command=self.start_watch).pack(side="left", padx=(0, 8))
        ttk.Button(history_bar, text="Stop Auto History", command=self.stop_watch).pack(side="left", padx=(0, 8))
        ttk.Button(history_bar, text="Create Archive", command=self.create_archive).pack(side="left", padx=(0, 8))
        ttk.Button(history_bar, text="Restore Selected", command=self.restore_selected).pack(side="left", padx=(0, 8))
        ttk.Button(history_bar, text="Open Source", command=self.open_source).pack(side="left", padx=(0, 8))
        ttk.Button(history_bar, text="Open Repo", command=self.open_repo).pack(side="left")

        self.history_tree = ttk.Treeview(self.history_tab, columns=("commit", "date", "subject"), show="headings")
        self.history_tree.heading("commit", text="Commit")
        self.history_tree.heading("date", text="Date")
        self.history_tree.heading("subject", text="Subject")
        self.history_tree.column("commit", width=90, anchor="center")
        self.history_tree.column("date", width=220)
        self.history_tree.column("subject", width=360)
        self.history_tree.grid(row=1, column=0, sticky="nsew", padx=(0, 10))
        self.history_tree.bind("<<TreeviewSelect>>", self.show_history_details)

        self.details = tk.Text(self.history_tab, wrap="word")
        self.details.grid(row=1, column=1, sticky="nsew")
        self.details.insert("end", "Select a commit to view details and changed files.\n")
        self.details.configure(state="disabled")

    def add_files(self) -> None:
        for item in filedialog.askopenfilenames(title="Select files"):
            self._add(Path(item))

    def add_folder(self) -> None:
        folder = filedialog.askdirectory(title="Select folder")
        if folder:
            self._add(Path(folder))

    def remove_selected(self) -> None:
        selected_ids = set(self.tree.selection())
        self.selected = [p for p in self.selected if str(p) not in selected_ids]
        for item in selected_ids:
            self.tree.delete(item)

    def run_job(self) -> None:
        if not self.selected:
            messagebox.showinfo("Dew Encryption", "Select at least one file or folder first.")
            return
        paths = list(self.selected)
        self._log("Starting Dew Encryption job...")
        threading.Thread(target=self._worker, args=(paths,), daemon=True).start()

    def _worker(self, paths: list[Path]) -> None:
        try:
            result = process(paths)
            self.events.put(f"Archive: {result.archive}\nRepo: {result.repo}\nCommit: {result.commit}\n::refresh-history::")
        except DewError as exc:
            self.events.put(f"Failed: {exc}\n")

    def start_watch(self) -> None:
        if not self.selected:
            messagebox.showinfo("Dew Encryption", "Select at least one file or folder first.")
            return
        if self.watch_thread and self.watch_thread.is_alive():
            self._log("Auto history is already running.")
            return
        self.watch_stop.clear()
        paths = list(self.selected)
        self.watch_thread = threading.Thread(target=self._watch_worker, args=(paths,), daemon=True)
        self.watch_thread.start()
        self._log("Auto history started.")

    def stop_watch(self) -> None:
        self.watch_stop.set()
        self._log("Auto history stopped.")

    def snapshot_now(self) -> None:
        if not self.selected:
            messagebox.showinfo("Dew Encryption", "Select a file history folder first.")
            return
        try:
            result = snapshot([self.selected[0]])
        except DewError as exc:
            self._set_details(f"Snapshot failed: {exc}\n")
            return
        self._log(f"History snapshot: {result.commit}")
        self.refresh_history()

    def create_archive(self) -> None:
        repo = self._active_repo()
        if not repo:
            messagebox.showinfo("Dew Encryption", "Select a file history folder first.")
            return
        try:
            archive = create_archive_for_repo(repo)
        except DewError as exc:
            self._set_details(f"Archive failed: {exc}\n")
            return
        self._log(f"Archive created: {archive}")

    def restore_selected(self) -> None:
        repo = self._active_repo()
        source = self._active_source()
        selected = self.history_tree.selection()
        if not repo or not source or not selected:
            messagebox.showinfo("Dew Encryption", "Select a source folder and a history commit first.")
            return
        commit = selected[0]
        if not messagebox.askyesno("Restore History", f"Restore {source} to commit {commit}? Current files at that path will be replaced."):
            return
        try:
            restore_commit(repo, commit, source)
        except DewError as exc:
            self._set_details(f"Restore failed: {exc}\n")
            return
        self._log(f"Restored {source} to {commit}")

    def open_source(self) -> None:
        source = self._active_source()
        if source:
            subprocess.Popen(["explorer", str(source)])

    def open_repo(self) -> None:
        repo = self._active_repo()
        if repo:
            subprocess.Popen(["explorer", str(repo)])

    def refresh_history(self) -> None:
        for item in self.history_tree.get_children():
            self.history_tree.delete(item)
        repo = self._active_repo()
        if not repo:
            self._set_details("Select a file or folder with Dew Encryption history first.\n")
            return
        try:
            for entry in history(repo):
                self.history_tree.insert("", "end", iid=entry.commit, values=(entry.commit, entry.author_date, entry.subject))
        except DewError as exc:
            self._set_details(f"Failed to load history: {exc}\n")

    def show_history_details(self, _event: object | None = None) -> None:
        repo = self._active_repo()
        selected = self.history_tree.selection()
        if not repo or not selected:
            return
        commit = selected[0]
        try:
            message, changes = commit_details(repo, commit)
        except DewError as exc:
            self._set_details(f"Failed to load commit details: {exc}\n")
            return
        lines = [message, "", "Changed files:"]
        lines.extend(f"{change.status}  {change.path}" for change in changes)
        self._set_details("\n".join(lines) + "\n")

    def _add(self, path: Path) -> None:
        path = path.resolve()
        if path in self.selected:
            return
        self.selected.append(path)
        kind = "Folder" if path.is_dir() else "File"
        self.tree.insert("", "end", iid=str(path), values=(str(path), kind))

    def _log(self, text: str) -> None:
        self.log.configure(state="normal")
        self.log.insert("end", text.rstrip() + "\n")
        self.log.see("end")
        self.log.configure(state="disabled")

    def _drain_events(self) -> None:
        while True:
            try:
                message = self.events.get_nowait()
                refresh = "::refresh-history::" in message
                self._log(message.replace("::refresh-history::", "").rstrip())
                if refresh:
                    self.refresh_history()
            except queue.Empty:
                break
        self.after(100, self._drain_events)

    def _watch_worker(self, paths: list[Path]) -> None:
        last_commit = ""
        while not self.watch_stop.is_set():
            try:
                result = snapshot(paths)
                if result.commit and result.commit != last_commit:
                    self.events.put(f"Auto history commit: {result.commit}\n::refresh-history::")
                    last_commit = result.commit
            except DewError as exc:
                self.events.put(f"Auto history failed: {exc}\n")
            self.watch_stop.wait(5.0)

    def _active_repo(self) -> Path | None:
        source = self._active_source()
        if not source:
            return None
        return repo_for_source(source)

    def _active_source(self) -> Path | None:
        if not self.selected:
            return None
        return self.selected[0].resolve()

    def _set_details(self, text: str) -> None:
        self.details.configure(state="normal")
        self.details.delete("1.0", "end")
        self.details.insert("end", text)
        self.details.configure(state="disabled")


def main() -> None:
    open_history = "--history" in sys.argv[1:]
    paths = [Path(arg) for arg in sys.argv[1:] if arg != "--history"]
    app = DewFileManager(paths, open_history=open_history)
    app.mainloop()


if __name__ == "__main__":
    main()
