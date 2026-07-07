from __future__ import annotations

import queue
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

from .core import DewError, process


class DewFileManager(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("Dew Encryption")
        self.geometry("980x620")
        self.minsize(820, 500)
        self.selected: list[Path] = []
        self.events: queue.Queue[str] = queue.Queue()
        self._build()
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

        body = ttk.Frame(self, padding=(10, 0, 10, 10))
        body.grid(row=1, column=0, sticky="nsew")
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
            self.events.put(f"Archive: {result.archive}\nRepo: {result.repo}\nCommit: {result.commit}\n")
        except DewError as exc:
            self.events.put(f"Failed: {exc}\n")

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
                self._log(self.events.get_nowait())
            except queue.Empty:
                break
        self.after(100, self._drain_events)


def main() -> None:
    app = DewFileManager()
    app.mainloop()


if __name__ == "__main__":
    main()
