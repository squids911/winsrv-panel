#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Панель настройки Windows Server (модульная).

Экран: слева дерево категорий (разделы), справа форма раздела, снизу журнал.
Разделы автоматически загружаются из modules/<id>/panel.py (класс Panel от
framework.BasePanel). Добавить раздел = создать папку modules/<id> с panel.py.

Настройки хранятся во ВСТРОЕННЫХ в exe умолчаниях (схемы модулей) и в РЕЕСТРЕ
Windows (HKCU\\Software\\WinSrvPanel). Изменения из GUI сохраняются в реестр;
никакого внешнего config.ini рядом с exe не требуется.
"""

import json
import os
import queue
import subprocess
import sys
import threading
import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext

import framework as fw
from framework import BasePanel, get_app_dir, get_resource_dir

# Каталог с framework.py (нужен модулям для `from framework import BasePanel`).
for _p in (get_resource_dir(), get_app_dir()):
    if _p not in sys.path:
        sys.path.insert(0, _p)

BASE_DIR = get_app_dir()
RESOURCE_DIR = get_resource_dir()
MODULES_DIR = os.path.join(RESOURCE_DIR, "modules")

# Список ролей: берём из ВСТРОЕННОГО ресурса (внутри exe). Если рядом с exe
# лежит свой roles.json — используем его (удобно для крупной настройки).
ROLES_PATH = os.path.join(RESOURCE_DIR, "roles.json")
if os.path.exists(os.path.join(BASE_DIR, "roles.json")):
    ROLES_PATH = os.path.join(BASE_DIR, "roles.json")

ADMIN_CHECK_CMD = (
    "([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent())"
    ".IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)"
)


class DeployApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Панель настройки Windows Server 2025")
        self.geometry("1040x720")
        self.minsize(900, 640)

        self.base_dir = BASE_DIR
        self.roles_path = ROLES_PATH

        self._discover_modules()
        self.schema = self._build_schema()
        # Настройки: умолчания из схем (в exe) + сохранённые значения из реестра.
        self.cfg = fw.registry_read(self.schema)

        self.log_queue = queue.Queue()
        self.running = False
        self._panel_instances = {}
        self._frame_shown = None

        self._build_ui()
        # показать первый раздел
        if self.modules:
            self._select(os.path.basename(self.modules[0].src_dir))
        self.after(100, self._poll_log_queue)
        self.protocol("WM_DELETE_WINDOW", self._on_close)

    # ------------------------------------------------------------------ модули
    def _discover_modules(self):
        self.modules = fw.discover_modules(MODULES_DIR, BasePanel)

    def _build_schema(self):
        schema = {
            "powershell": {
                "exe": ("powershell", "PowerShell: powershell или pwsh"),
            }
        }
        for cls in self.modules:
            for section, items in cls.CONFIG_SCHEMA.items():
                schema.setdefault(section, {}).update(items)
        return schema

    # ------------------------------------------------------------------ UI
    def _build_ui(self):
        top = ttk.Frame(self, padding=(10, 8))
        top.pack(side="top", fill="x")
        ttk.Label(top, text="Панель настройки Windows Server 2025",
                  font=("Segoe UI", 13, "bold")).pack(side="left")

        self.btn_admin = ttk.Button(top, text="Проверить права администратора",
                                    command=self._check_admin)
        self.btn_admin.pack(side="right")
        self.btn_save = ttk.Button(top, text="Сохранить настройки", command=self.save_config)
        self.btn_save.pack(side="right", padx=6)
        self.btn_reset = ttk.Button(top, text="Сбросить настройки",
                                    command=self.reset_config)
        self.btn_reset.pack(side="right", padx=6)

        # Основная область: дерево + контент
        main = ttk.Panedwindow(self, orient="horizontal")
        main.pack(side="top", fill="both", expand=True, padx=8, pady=(0, 6))

        left = ttk.Frame(main, padding=(4, 4))
        ttk.Label(left, text="Разделы", font=("Segoe UI", 10, "bold")).pack(anchor="w", padx=4)
        self.tree = ttk.Treeview(left, show="tree", selectmode="browse")
        self.tree.pack(fill="both", expand=True, pady=(4, 0))
        self.tree.bind("<<TreeviewSelect>>", self._on_tree_select)

        self.content = ttk.Frame(main, padding=4)
        main.add(left, weight=1)
        main.add(self.content, weight=3)

        # Заполнить дерево
        for cls in self.modules:
            self.tree.insert("", "end", iid=os.path.basename(cls.src_dir), text=cls.title)

        # Журнал
        logframe = ttk.LabelFrame(self, text="Журнал", padding=4)
        logframe.pack(side="bottom", fill="x", padx=8, pady=(0, 8), ipady=4)
        self.log_text = scrolledtext.ScrolledText(logframe, wrap="word", state="disabled",
                                                  height=12, font=("Consolas", 9))
        self.log_text.pack(fill="both", expand=True)

        self.status_var = tk.StringVar(value="Готово.")
        status = ttk.Label(self, textvariable=self.status_var, anchor="w", relief="sunken",
                           padding=(6, 3))
        status.pack(side="bottom", fill="x")

    def _on_tree_select(self, _event=None):
        sel = self.tree.selection()
        if sel:
            self._select(sel[0])

    def _select(self, pid):
        cls = self._class_for(pid)
        if cls is None:
            return
        if pid not in self._panel_instances:
            frame = ttk.Frame(self.content, padding=8)
            panel = cls(self)
            panel.build(frame)
            self._panel_instances[pid] = (frame, panel)
        else:
            frame, panel = self._panel_instances[pid]
        if self._frame_shown is not None and self._frame_shown is not frame:
            self._frame_shown.pack_forget()
        frame.pack(fill="both", expand=True)
        self._frame_shown = frame
        try:
            panel.on_show()
        except Exception:
            pass

    def _class_for(self, pid):
        for cls in self.modules:
            if os.path.basename(cls.src_dir) == pid:
                return cls
        return None

    # ------------------------------------------------------------------ конфигурация
    def set_config(self, section, items):
        self.cfg.setdefault(section, {})
        self.cfg[section].update({str(k): str(v) for k, v in items.items()})

    def get_config(self, section, key, default=""):
        return self.cfg.get(section, {}).get(key, default)

    def save_config(self):
        """Сохраняет текущие значения в реестр (HKCU\\Software\\WinSrvPanel)."""
        if not hasattr(self, "schema"):
            return
        try:
            fw.registry_write(self.cfg)
            self._log("Настройки сохранены в реестр (HKCU\\Software\\WinSrvPanel)\n")
            self.status_var.set("Настройки сохранены.")
        except Exception as e:
            messagebox.showerror("Ошибка", f"Не удалось сохранить настройки: {e}")

    def reset_config(self):
        """Сбрасывает настройки к значениям по умолчанию (очищает сохранённое)."""
        if not messagebox.askyesno("Сброс настроек",
                                   "Вернуть все настройки к значениям по умолчанию?\n"
                                   "Сохранённые значения в реестре будут удалены."):
            return
        fw.registry_clear(self.schema)
        self.cfg = fw.registry_read(self.schema)  # снова умолчания
        self._log("Настройки сброшены к значениям по умолчанию.\n")
        self.status_var.set("Настройки сброшены.")
        messagebox.showinfo("Сброс настроек",
                            "Настройки возвращены к значениям по умолчанию.\n"
                            "Перезапустите программу, чтобы обновить открытые формы.")

    # ------------------------------------------------------------------ PowerShell
    def run_script(self, panel, script_name, args, header):
        if self.running:
            messagebox.showinfo("Занято", "Операция уже выполняется. Дождитесь завершения.")
            return
        script = os.path.join(panel.scripts_dir, script_name)
        if not os.path.exists(script):
            messagebox.showerror("Ошибка", f"Скрипт не найден: {script}")
            return
        exe = self.cfg.get("powershell", {}).get("exe", "powershell")
        cmd = [exe, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script] + args
        self._log(f"\n{'=' * 70}\n=== {header} ===\n")
        self.status_var.set(f"Выполняется: {header} ...")
        self._set_busy(True)
        threading.Thread(target=self._run_process, args=(cmd,), daemon=True).start()

    def _run_process(self, cmd):
        try:
            proc = subprocess.Popen(
                cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, encoding="utf-8", errors="replace", bufsize=1,
                creationflags=fw.CREATE_NO_WINDOW,
            )
            for line in iter(proc.stdout.readline, ""):
                self.log_queue.put(line)
            proc.stdout.close()
            rc = proc.wait()
            self.log_queue.put(f"\n[exit code: {rc}]\n")
        except Exception as e:
            self.log_queue.put(f"\n[Ошибка запуска PowerShell]: {e}\n")
        finally:
            self.log_queue.put("__DONE__")

    def _poll_log_queue(self):
        try:
            while True:
                item = self.log_queue.get_nowait()
                if item == "__DONE__":
                    self.running = False
                    self._set_busy(False)
                    self.status_var.set("Операция завершена.")
                    self._log("\n[операция завершена]\n")
                else:
                    self._append_log(item)
        except queue.Empty:
            pass
        self.after(100, self._poll_log_queue)

    def _set_busy(self, busy):
        state = "disabled" if busy else "normal"
        self.btn_save.configure(state=state)

    # ------------------------------------------------------------------ журнал
    def _log(self, text):
        self.log_text.configure(state="normal")
        self.log_text.insert("end", text)
        self.log_text.see("end")
        self.log_text.configure(state="disabled")

    def _append_log(self, text):
        self.log_text.configure(state="normal")
        self.log_text.insert("end", text)
        self.log_text.see("end")
        self.log_text.configure(state="disabled")

    # ------------------------------------------------------------------ права
    def _check_admin(self):
        exe = self.cfg.get("powershell", {}).get("exe", "powershell")
        try:
            out = subprocess.run([exe, "-NoProfile", "-Command", ADMIN_CHECK_CMD],
                                 capture_output=True, text=True, timeout=20,
                                 creationflags=fw.CREATE_NO_WINDOW)
            is_admin = "True" in (out.stdout or "")
        except Exception as e:
            messagebox.showerror("Ошибка", f"Не удалось проверить права: {e}")
            return
        if is_admin:
            messagebox.showinfo("Права администратора", "Сеанс запущен от имени администратора.")
            self.status_var.set("Права администратора подтверждены.")
        else:
            messagebox.showwarning("Права администратора",
                                   "Программа запущена БЕЗ прав администратора.\n"
                                   "Запустите её от имени администратора.")

    def _on_close(self):
        try:
            self.save_config()
        except Exception:
            pass
        self.destroy()


def main():
    app = DeployApp()
    app.mainloop()


if __name__ == "__main__":
    main()
