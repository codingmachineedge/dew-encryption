from __future__ import annotations

import queue
import threading
import tkinter as tk
from dataclasses import replace
from pathlib import Path
from tkinter import messagebox, ttk

from .core import (
    ContainerProfile,
    DewError,
    ThemeSettings,
    load_settings,
    process,
    save_settings,
    source_path_for_container,
    unique_paths,
    veracrypt_create_container,
    veracrypt_decrypt_container,
)


ACTION_TITLES = {
    "archive": "Encrypt files to 7z",
    "container_quick_create": "Quick-create VeraCrypt container",
    "veracrypt_encrypt": "Encrypt with VeraCrypt",
    "veracrypt_decrypt": "Decrypt VeraCrypt container",
}


class EncryptionActionDialog(tk.Tk):
    def __init__(self, action: str, paths: list[Path]) -> None:
        super().__init__()
        self.action = action
        self.paths = [path.resolve() for path in paths]
        self.settings = load_settings()
        self.events: queue.Queue[tuple[str, object]] = queue.Queue()
        self.running = False

        self.title(f"Dew Encryption - {ACTION_TITLES[action]}")
        self.geometry("720x680" if action != "archive" else "680x480")
        self.minsize(620, 420)
        self.protocol("WM_DELETE_WINDOW", self._close_requested)
        self._build()
        self.after(100, self._drain_events)

    def _build(self) -> None:
        root = ttk.Frame(self, padding=18)
        root.pack(fill="both", expand=True)
        root.columnconfigure(0, weight=1)

        ttk.Label(root, text=ACTION_TITLES[self.action], font=("Segoe UI", 17, "bold")).grid(row=0, column=0, sticky="w")
        ttk.Label(
            root,
            text="Review the selected paths and settings. Dew Encryption will not begin until you click Continue.",
            wraplength=650,
        ).grid(row=1, column=0, sticky="ew", pady=(4, 12))

        selected = tk.Listbox(root, height=min(6, max(2, len(self.paths))))
        selected.grid(row=2, column=0, sticky="ew")
        for path in self.paths:
            selected.insert("end", str(path))

        password_frame = ttk.LabelFrame(root, text="Password", padding=12)
        password_frame.grid(row=3, column=0, sticky="ew", pady=(12, 8))
        password_frame.columnconfigure(1, weight=1)
        self.password = tk.StringVar()
        self.confirm_password = tk.StringVar()
        ttk.Label(password_frame, text="Password").grid(row=0, column=0, sticky="w", padx=(0, 10), pady=4)
        ttk.Entry(password_frame, textvariable=self.password, show="*").grid(row=0, column=1, sticky="ew", pady=4)
        if self.action != "veracrypt_decrypt":
            ttk.Label(password_frame, text="Confirm password").grid(row=1, column=0, sticky="w", padx=(0, 10), pady=4)
            ttk.Entry(password_frame, textvariable=self.confirm_password, show="*").grid(row=1, column=1, sticky="ew", pady=4)

        self.keep_source = tk.BooleanVar(value=True)
        self.keep_container = tk.BooleanVar(value=True)
        self.save_defaults = tk.BooleanVar(value=True)
        self.output_path = tk.StringVar()
        self.vc_vars: dict[str, tk.Variable] = {}
        next_row = 4
        if self.action != "archive":
            self._build_veracrypt_settings(root, next_row)
            next_row += 1
        else:
            parent = self.paths[0].parent if self.paths else Path.cwd()
            ttk.Label(root, text=f"The encrypted 7z file will be created beside the selection in: {parent}", wraplength=650).grid(
                row=next_row, column=0, sticky="ew", pady=(4, 8)
            )
            next_row += 1

        progress_frame = ttk.Frame(root)
        progress_frame.grid(row=next_row, column=0, sticky="ew", pady=(10, 0))
        progress_frame.columnconfigure(0, weight=1)
        self.progress = ttk.Progressbar(progress_frame, mode="indeterminate")
        self.progress.grid(row=0, column=0, sticky="ew")
        self.status = tk.StringVar(value="Ready")
        ttk.Label(progress_frame, textvariable=self.status).grid(row=1, column=0, sticky="w", pady=(4, 0))

        buttons = ttk.Frame(root)
        buttons.grid(row=next_row + 1, column=0, sticky="e", pady=(14, 0))
        self.continue_button = ttk.Button(buttons, text="Continue", command=self._start)
        self.continue_button.pack(side="left", padx=(0, 8))
        self.cancel_button = ttk.Button(buttons, text="Cancel", command=self._close_requested)
        self.cancel_button.pack(side="left")

    def _build_veracrypt_settings(self, root: ttk.Frame, row: int) -> None:
        vc = self.settings.veracrypt
        frame = ttk.LabelFrame(root, text="VeraCrypt settings", padding=12)
        frame.grid(row=row, column=0, sticky="ew", pady=(4, 8))
        frame.columnconfigure(1, weight=1)
        fields = [
            ("Encryption algorithm", "encryption", vc.encryption),
            ("Hash", "hash", vc.hash),
            ("Filesystem", "filesystem", vc.filesystem),
            ("PIM", "pim", vc.pim),
            ("Size padding MB", "size_padding_mb", str(vc.size_padding_mb)),
            ("Size multiplier", "size_multiplier", str(vc.size_multiplier)),
            ("Minimum size MB", "minimum_size_mb", str(vc.minimum_size_mb)),
            ("VeraCrypt executable", "veracrypt_path", vc.veracrypt_path),
        ]
        for field_row, (label, key, value) in enumerate(fields):
            variable = tk.StringVar(value=value)
            self.vc_vars[key] = variable
            ttk.Label(frame, text=label).grid(row=field_row, column=0, sticky="w", padx=(0, 10), pady=3)
            ttk.Entry(frame, textvariable=variable).grid(row=field_row, column=1, sticky="ew", pady=3)

        option_row = len(fields)
        if self.action == "veracrypt_decrypt":
            if len(self.paths) == 1:
                output = source_path_for_container(self.paths[0])
                if output.exists():
                    output = output.with_name(output.name + ".decrypted")
                self.output_path.set(str(output))
                ttk.Label(frame, text="Output path").grid(row=option_row, column=0, sticky="w", padx=(0, 10), pady=3)
                ttk.Entry(frame, textvariable=self.output_path).grid(row=option_row, column=1, sticky="ew", pady=3)
                option_row += 1
            ttk.Checkbutton(frame, text="Keep encrypted container after successful decrypt", variable=self.keep_container).grid(
                row=option_row, column=0, columnspan=2, sticky="w", pady=(6, 0)
            )
        else:
            ttk.Checkbutton(frame, text="Keep original files/folders after successful encryption", variable=self.keep_source).grid(
                row=option_row, column=0, columnspan=2, sticky="w", pady=(6, 0)
            )
        ttk.Checkbutton(frame, text="Save these VeraCrypt settings as defaults", variable=self.save_defaults).grid(
            row=option_row + 1, column=0, columnspan=2, sticky="w", pady=(3, 0)
        )

    def _validated_veracrypt_settings(self):
        vc = self.settings.veracrypt
        try:
            return replace(
                vc,
                encryption=str(self.vc_vars["encryption"].get()).strip() or "AES",
                hash=str(self.vc_vars["hash"].get()).strip() or "SHA-512",
                filesystem=str(self.vc_vars["filesystem"].get()).strip() or "exFAT",
                pim=str(self.vc_vars["pim"].get()).strip() or "0",
                size_padding_mb=int(str(self.vc_vars["size_padding_mb"].get())),
                size_multiplier=float(str(self.vc_vars["size_multiplier"].get())),
                minimum_size_mb=int(str(self.vc_vars["minimum_size_mb"].get())),
                veracrypt_path=str(self.vc_vars["veracrypt_path"].get()).strip(),
                keep_source_after_encrypt=bool(self.keep_source.get()),
                keep_container_after_decrypt=bool(self.keep_container.get()),
            )
        except ValueError as exc:
            raise DewError(f"Invalid numeric VeraCrypt setting: {exc}") from exc

    def _start(self) -> None:
        if self.running:
            return
        password = self.password.get()
        if not password:
            messagebox.showerror("Dew Encryption", "Enter a password before continuing.", parent=self)
            return
        if self.action != "veracrypt_decrypt" and password != self.confirm_password.get():
            messagebox.showerror("Dew Encryption", "Password and confirmation do not match.", parent=self)
            return
        if self.action in {"container_quick_create", "veracrypt_encrypt"} and not self.keep_source.get():
            if not messagebox.askyesno(
                "Remove originals after encryption?",
                "The original files/folders will be deleted only after the VeraCrypt container is created, mounted, copied, and dismounted successfully. Continue?",
                parent=self,
            ):
                return
        if self.action == "veracrypt_decrypt" and not self.keep_container.get():
            if not messagebox.askyesno(
                "Remove encrypted containers after decrypt?",
                "The encrypted container files will be deleted after successful extraction. Continue?",
                parent=self,
            ):
                return

        try:
            vc_settings = self._validated_veracrypt_settings() if self.action != "archive" else None
        except DewError as exc:
            messagebox.showerror("Dew Encryption", str(exc), parent=self)
            return

        self.running = True
        self.continue_button.configure(state="disabled")
        self.cancel_button.configure(state="disabled")
        self.progress.start(12)
        self.status.set("Starting...")
        options = {
            "keep_source": bool(self.keep_source.get()),
            "keep_container": bool(self.keep_container.get()),
            "save_defaults": bool(self.save_defaults.get()),
            "output_path": self.output_path.get(),
        }
        threading.Thread(target=self._worker, args=(password, vc_settings, options), daemon=True).start()

    def _worker(self, password: str, vc_settings: object | None, options: dict[str, object]) -> None:
        try:
            results: list[str] = []
            if self.action == "archive":
                self.events.put(("status", "Creating Git snapshot and encrypted 7z archive..."))
                result = process(self.paths, password=password)
                results.append(str(result.archive))
            elif self.action in {"container_quick_create", "veracrypt_encrypt"}:
                if options["save_defaults"] and vc_settings is not None:
                    self.settings.veracrypt = vc_settings
                for index, source in enumerate(unique_paths([str(path) for path in self.paths]), start=1):
                    self.events.put(("status", f"Encrypting {index} of {len(self.paths)}: {source.name}"))
                    container = veracrypt_create_container(
                        source,
                        password,
                        keep_source=bool(options["keep_source"]),
                        settings=vc_settings,
                    )
                    results.append(str(container))
                    if self.action == "container_quick_create":
                        existing = {
                            str(Path(profile.path).expanduser().resolve()).casefold()
                            for profile in self.settings.containers or []
                            if profile.path
                        }
                        if str(container.resolve()).casefold() not in existing:
                            self.settings.containers = self.settings.containers or []
                            self.settings.containers.append(
                                ContainerProfile(name=container.stem, path=str(container), theme=ThemeSettings(), hooks=[])
                            )
                if options["save_defaults"] or self.action == "container_quick_create":
                    save_settings(self.settings)
            else:
                if options["save_defaults"] and vc_settings is not None:
                    self.settings.veracrypt = vc_settings
                    save_settings(self.settings)
                for index, container in enumerate(unique_paths([str(path) for path in self.paths]), start=1):
                    self.events.put(("status", f"Decrypting {index} of {len(self.paths)}: {container.name}"))
                    output_value = str(options["output_path"])
                    output = Path(output_value) if len(self.paths) == 1 and output_value else None
                    restored = veracrypt_decrypt_container(
                        container,
                        password,
                        output=output,
                        keep_container=bool(options["keep_container"]),
                        settings=vc_settings,
                    )
                    results.append(str(restored))
            self.events.put(("complete", results))
        except Exception as exc:
            self.events.put(("error", str(exc)))

    def _drain_events(self) -> None:
        try:
            while True:
                kind, payload = self.events.get_nowait()
                if kind == "status":
                    self.status.set(str(payload))
                elif kind == "complete":
                    self.running = False
                    self.progress.stop()
                    self.status.set("Complete")
                    messagebox.showinfo("Dew Encryption", "Completed:\n\n" + "\n".join(payload), parent=self)
                    self.destroy()
                    return
                elif kind == "error":
                    self.running = False
                    self.progress.stop()
                    self.status.set("Failed")
                    self.continue_button.configure(state="normal")
                    self.cancel_button.configure(state="normal")
                    messagebox.showerror("Dew Encryption", str(payload), parent=self)
        except queue.Empty:
            pass
        self.after(100, self._drain_events)

    def _close_requested(self) -> None:
        if self.running:
            messagebox.showwarning(
                "Dew Encryption is still working",
                "This window cannot close until the current encryption/decryption job finishes.",
                parent=self,
            )
            return
        self.destroy()


def run_action_dialog(action: str, paths: list[Path]) -> None:
    dialog = EncryptionActionDialog(action, paths)
    dialog.mainloop()
