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
import time
import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext

import framework as fw
from framework import BasePanel, get_app_dir, get_resource_dir

# Номер сборки: виден в заголовке окна и в журнале, чтобы по любому
# скриншоту/логу можно было понять, какой именно EXE запущен.
BUILD_ID = "2026-09-12 #10"

# Палитра в стиле тулзы миграции почты: тёмные панели, оранжевый акцент,
# светло-серый фон, чёрная консоль журнала.
HDR     = "#1b1b1b"   # верхняя/нижняя панели
ACCENT  = "#e8590c"   # оранжевый акцент
ACCENT_D = "#d9480f"
BG      = "#eef1f4"   # фон рабочей области
CARD    = "#ffffff"   # карточки/поля
DARKBTN = "#343a40"   # тёмные кнопки
TEXT    = "#212529"
BORDER  = "#c6ccd2"

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
        self.title(f"Панель настройки Windows Server 2025 — сборка {BUILD_ID}")
        self.geometry("1040x720")
        self.minsize(900, 640)
        self._setup_theme()

        self.base_dir = BASE_DIR
        self.roles_path = ROLES_PATH

        self._discover_modules()
        self.schema = self._build_schema()
        # Настройки: умолчания из схем (в exe) + сохранённые значения из реестра.
        self.cfg = fw.registry_read(self.schema)

        self.log_queue = queue.Queue()
        self.events_queue = queue.Queue()
        self.running = False
        self.is_admin = False   # определяется асинхронно при старте (_check_admin)
        self._panel_instances = {}
        self._frame_shown = None

        self._build_ui()
        self._log(f"Сборка {BUILD_ID}. Номер виден в заголовке окна и здесь — "
                  f"по нему легко понять, какой EXE запущен.\n")
        # показать первый раздел
        if self.modules:
            self._select(os.path.basename(self.modules[0].src_dir))
        self.after(100, self._poll_log_queue)
        # определить права администратора сразу после старта (не блокируя UI)
        self.after(150, self._check_admin)
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

    # ------------------------------------------------------------------ тема
    def _setup_theme(self):
        """Оформление в палитре тулзы миграции: тёмные панели, оранжевый
        акцент, светло-серый фон, белые карточки, чёрная консоль журнала."""
        style = ttk.Style(self)
        try:
            style.theme_use("clam")
        except Exception:
            pass
        self.configure(bg=BG)
        style.configure(".", background=BG, foreground=TEXT, bordercolor=BORDER)
        style.configure("TFrame", background=BG)
        style.configure("TLabel", background=BG, foreground=TEXT)
        style.configure("TCheckbutton", background=BG, foreground=TEXT)
        style.configure("TRadiobutton", background=BG, foreground=TEXT)
        style.configure("TEntry", fieldbackground=CARD, bordercolor=BORDER)
        style.configure("TButton", background=CARD, foreground=TEXT,
                        bordercolor=BORDER, padding=3)
        style.map("TButton", background=[("active", "#e9ecef"), ("pressed", "#dee2e6")])
        style.configure("Accent.TButton", background=ACCENT, foreground="white",
                        bordercolor=ACCENT, padding=4)
        style.map("Accent.TButton", background=[("active", ACCENT_D)])
        style.configure("Dark.TButton", background=DARKBTN, foreground="white",
                        bordercolor=DARKBTN)
        style.map("Dark.TButton", background=[("active", "#23272b")])
        style.configure("TLabelFrame", background=CARD, bordercolor=BORDER, relief="solid")
        style.configure("TLabelFrame.Label", background=CARD, foreground=TEXT)
        style.configure("Treeview", background=CARD, fieldbackground=CARD,
                        foreground=TEXT, bordercolor=BORDER)
        style.map("Treeview", background=[("selected", ACCENT)],
                  foreground=[("selected", "white")])
        style.configure("Horizontal.TProgressbar", troughcolor=BG, background=ACCENT)

    # ------------------------------------------------------------------ UI
    def _build_ui(self):
        top = tk.Frame(self, bg=HDR)
        top.pack(side="top", fill="x")
        tk.Label(top, text="Панель настройки Windows Server", bg=HDR, fg="#ffffff",
                 font=("Segoe UI", 13, "bold")).pack(side="left", padx=(12, 6), pady=9)
        tk.Label(top, text=f"сборка {BUILD_ID}", bg=HDR, fg=ACCENT,
                 font=("Segoe UI", 9, "bold")).pack(side="left", pady=9)

        self.btn_admin = tk.Button(top, text="Проверить права", bg=DARKBTN, fg="white",
                                   activebackground="#23272b", activeforeground="white",
                                   bd=0, padx=10, pady=4,
                                   command=lambda: self._check_admin(quiet=False))
        self.btn_admin.pack(side="right", padx=(0, 10), pady=7)
        self.lbl_admin = tk.Label(top, text="Права: проверка...", bg=HDR, fg="#ffa94d")
        self.lbl_admin.pack(side="right", padx=8)
        self.btn_elevate = tk.Button(top, text="Запустить от администратора", bg=ACCENT,
                                     fg="white", activebackground=ACCENT_D,
                                     activeforeground="white", bd=0, padx=10, pady=4,
                                     command=self._relaunch_elevated)
        self.btn_elevate.pack(side="right", padx=6, pady=7)
        self.btn_save = tk.Button(top, text="Сохранить настройки", bg=DARKBTN, fg="white",
                                  activebackground="#23272b", activeforeground="white",
                                  bd=0, padx=10, pady=4, command=self.save_config)
        self.btn_save.pack(side="right", padx=6, pady=7)
        self.btn_reset = tk.Button(top, text="Сбросить настройки", bg=DARKBTN, fg="white",
                                   activebackground="#23272b", activeforeground="white",
                                   bd=0, padx=10, pady=4, command=self.reset_config)
        self.btn_reset.pack(side="right", padx=6, pady=7)

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

        logbar = ttk.Frame(logframe)
        logbar.pack(side="top", fill="x", pady=(0, 2))
        ttk.Button(logbar, text="Копировать выделенное",
                   command=self._copy_log_sel).pack(side="right", padx=2)
        ttk.Button(logbar, text="Копировать всё",
                   command=self._copy_log_all).pack(side="right", padx=2)

        self.log_text = scrolledtext.ScrolledText(logframe, wrap="word", state="disabled",
                                                  height=12, font=("Consolas", 9),
                                                  bg="#0d0d0d", fg="#e9ecef",
                                                  insertbackground="#ffffff",
                                                  selectbackground=ACCENT,
                                                  border=0, highlightthickness=0)
        self.log_text.pack(fill="both", expand=True)
        self.log_text.bind("<Button-3>", self._log_menu)

        self.status_var = tk.StringVar(value="Готово.")
        status = tk.Label(self, textvariable=self.status_var, anchor="w",
                          bg=HDR, fg="#f1f3f5", padx=8, pady=4)
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
        if not self._require_admin():
            return
        script = os.path.join(panel.scripts_dir, script_name)
        if not os.path.exists(script):
            messagebox.showerror("Ошибка", f"Скрипт не найден: {script}")
            return
        exe = self.cfg.get("powershell", {}).get("exe", "powershell")
        cmd = [exe, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script] + args
        self._log(f"\n{'=' * 70}\n{self._ts()}=== {header} ===\n")
        self.status_var.set(f"Выполняется: {header} ...")
        self._set_busy(True)
        threading.Thread(target=self._run_process, args=(cmd,), daemon=True).start()

    def run_scripts(self, panel, calls, header):
        """Последовательно выполняет НЕСКОЛЬКО скриптов в одном фоновом потоке.
        calls = [(script_name, args_list, subheader), ...].
        Используется единым дашбордом: одна кнопка 'Выполнить' для всех
        отмеченных галочками задач. Вывод каждого скрипта идёт в общий журнал."""
        if self.running:
            messagebox.showinfo("Занято", "Операция уже выполняется. Дождитесь завершения.")
            return
        if not self._require_admin():
            return
        if not calls:
            messagebox.showinfo("Нечего выполнять", "Отметьте галочками хотя бы одну задачу.")
            return
        exe = self.cfg.get("powershell", {}).get("exe", "powershell")
        cmds = []
        for script_name, args, subheader in calls:
            script = os.path.join(panel.scripts_dir, script_name)
            if not os.path.exists(script):
                messagebox.showerror("Ошибка", f"Скрипт не найден: {script}")
                return
            cmd = [exe, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script] + list(args)
            cmds.append((cmd, subheader))
        self._log(f"\n{'=' * 70}\n{self._ts()}=== {header} ===\n")
        self.status_var.set(f"Выполняется: {header} ...")
        self._set_busy(True)
        threading.Thread(target=self._run_process_seq, args=(cmds,), daemon=True).start()

    def _run_process_seq(self, cmds):
        """Последовательно запускает список команд PowerShell, складывая вывод
        в log_queue. В конце выводит итог по пунктам и отправляет маркер
        завершения '__DONE__'."""
        total = len(cmds)
        results = []
        for idx, (cmd, subheader) in enumerate(cmds, 1):
            self.log_queue.put(f"\n{'-' * 66}\n{self._ts()}--- [{idx}/{total}] {subheader} ---\n")
            rc, err = None, None
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
                self.log_queue.put(f"\n{self._ts()}[exit code: {rc}]\n")
            except Exception as e:
                err = str(e)
                self.log_queue.put(f"\n[Ошибка запуска PowerShell]: {e}\n")
            results.append((subheader, rc, err))

        ok = sum(1 for _, rc, err in results if err is None and rc == 0)
        lines = ["", "=" * 70, f"{self._ts()}ИТОГ ПО ПУНКТАМ:", ""]
        for subheader, rc, err in results:
            if err is not None:
                lines.append(f"  [ОШИБКА] {subheader} — не удалось запустить: {err}")
            elif rc == 0:
                lines.append(f"  [ВЫПОЛНЕНО] {subheader}")
            else:
                lines.append(f"  [ОШИБКА] {subheader} — код возврата {rc}")
        lines.append("")
        tail = f"Выполнено: {ok} из {total}"
        if ok != total:
            tail += f", с ошибками: {total - ok}"
        lines.append(tail)
        lines.append("=" * 70 + "\n")
        self.log_queue.put("\n".join(lines))
        self.log_queue.put(("__SUMMARY__", ok, total))
        self.log_queue.put("__DONE__")

    def run_capture(self, panel, script_name, args, on_done):
        """Запускает скрипт, собирает stdout ПОЛНОСТЬЮ и отдаёт результат
        (rc, stdout, stderr) в callback on_done (выполняется в главном потоке).
        Используется для запросов структурированных данных (например, JSON)."""
        script = os.path.join(panel.scripts_dir, script_name)
        if not os.path.exists(script):
            messagebox.showerror("Ошибка", f"Скрипт не найден: {script}")
            return
        exe = self.cfg.get("powershell", {}).get("exe", "powershell")
        cmd = [exe, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script] + args

        def worker():
            try:
                proc = subprocess.run(
                    cmd, capture_output=True, text=True, encoding="utf-8",
                    errors="replace", timeout=180, creationflags=fw.CREATE_NO_WINDOW,
                )
                payload = (proc.returncode, proc.stdout, proc.stderr)
            except Exception as e:
                payload = (-1, "", str(e))
            self.events_queue.put(("capture", on_done, payload))

        threading.Thread(target=worker, daemon=True).start()

    def _run_process(self, cmd):
        rc = None
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
            self.log_queue.put(("__SUMMARY__", 1 if rc == 0 else 0, 1))
            self.log_queue.put("__DONE__")

    def _poll_log_queue(self):
        try:
            while True:
                item = self.log_queue.get_nowait()
                if item == "__DONE__":
                    self.running = False
                    self._set_busy(False)
                    self._log(f"\n{self._ts()}[операция завершена]\n")
                elif isinstance(item, tuple) and item and item[0] == "__SUMMARY__":
                    _, ok, total = item
                    if ok == total:
                        self.status_var.set(f"Готово: {ok}/{total} выполнено.")
                    else:
                        self.status_var.set(f"Готово с ошибками: {ok}/{total} выполнено.")
                else:
                    self._append_log(item)
        except queue.Empty:
            pass

        # События (capture-запросы) — выполняем callback в главном потоке.
        try:
            while True:
                kind, cb, payload = self.events_queue.get_nowait()
                if kind == "capture":
                    try:
                        cb(payload)
                    except Exception as e:
                        self._append_log(f"\n[Ошибка обработки данных]: {e}\n")
        except queue.Empty:
            pass

        self.after(100, self._poll_log_queue)

    def _set_busy(self, busy):
        state = "disabled" if busy else "normal"
        self.btn_save.configure(state=state)

    # ------------------------------------------------------------------ журнал
    def _ts(self):
        """Отметка времени для журнала."""
        return time.strftime("[%H:%M:%S] ")

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

    # ------------------------------------------------------------------ копирование журнала
    def _copy_log_all(self):
        """Копирует весь журнал в буфер обмена."""
        try:
            self.clipboard_clear()
            self.clipboard_append(self.log_text.get("1.0", "end"))
            self.status_var.set("Журнал скопирован в буфер обмена.")
        except Exception as e:
            messagebox.showerror("Ошибка", f"Не удалось скопировать журнал: {e}")

    def _copy_log_sel(self):
        """Копирует выделенный фрагмент журнала (или весь, если нет выделения)."""
        try:
            sel = self.log_text.get("sel.first", "sel.last")
        except Exception:
            sel = ""
        if not sel:
            self._copy_log_all()
            return
        try:
            self.clipboard_clear()
            self.clipboard_append(sel)
            self.status_var.set("Выделенный текст скопирован.")
        except Exception as e:
            messagebox.showerror("Ошибка", f"Не удалось скопировать: {e}")

    def _select_all_log(self):
        self.log_text.tag_add("sel", "1.0", "end")

    def _log_menu(self, event):
        """Контекстное меню журнала (правая кнопка мыши)."""
        m = tk.Menu(self, tearoff=0)
        m.add_command(label="Копировать выделенное", command=self._copy_log_sel)
        m.add_command(label="Выделить всё", command=self._select_all_log)
        m.add_command(label="Копировать весь журнал", command=self._copy_log_all)
        try:
            m.tk_popup(event.x_root, event.y_root)
        finally:
            m.grab_release()

    # ------------------------------------------------------------------ права
    def _check_admin(self, quiet=True):
        """Определяет, запущена ли панель от администратора. Обновляет флаг
        self.is_admin, индикатор и видимость кнопки повышения. При quiet=True
        (автопроверка при старте) не показывает модальные окна."""
        exe = self.cfg.get("powershell", {}).get("exe", "powershell")
        try:
            out = subprocess.run([exe, "-NoProfile", "-Command", ADMIN_CHECK_CMD],
                                 capture_output=True, text=True, timeout=20,
                                 creationflags=fw.CREATE_NO_WINDOW)
            self.is_admin = "True" in (out.stdout or "")
        except Exception as e:
            self.is_admin = False
            if not quiet:
                messagebox.showerror("Ошибка", f"Не удалось проверить права: {e}")
            return

        if self.is_admin:
            self.lbl_admin.config(text="Права: администратор", foreground="#69db7c")
            try:
                self.btn_elevate.pack_forget()
            except Exception:
                pass
            self.status_var.set("Права администратора подтверждены.")
            if not quiet:
                messagebox.showinfo("Права администратора",
                                    "Сеанс запущен от имени администратора.")
        else:
            self.lbl_admin.config(text="Права: НЕТ (нужен администратор)", foreground="#ff8787")
            try:
                self.btn_elevate.pack(side="right", padx=6)
            except Exception:
                pass
            self.status_var.set("Нет прав администратора — операции будут отклонены.")
            if not quiet:
                messagebox.showwarning("Права администратора",
                                       "Программа запущена БЕЗ прав администратора.\n"
                                       "Нажмите «Запустить от администратора» или перезапустите\n"
                                       "её от имени администратора.")

    def _require_admin(self):
        """Возвращает True, если права есть. Иначе предлагает перезапуск
        от администратора и возвращает False."""
        if self.is_admin:
            return True
        if messagebox.askyesno("Нужны права администратора",
                               "Панель запущена без прав администратора — операции "
                               "будут отклонены.\n\nПерезапустить панель от имени "
                               "администратора сейчас?"):
            self._relaunch_elevated()
        return False

    def _relaunch_elevated(self):
        """Перезапускает панель с повышением прав (UAC) и закрывает текущее окно."""
        if os.name != "nt":
            messagebox.showinfo("Повышение прав",
                                "Автоматическое повышение доступно только в Windows.\n"
                                "Перезапустите программу от имени администратора.")
            return
        try:
            import ctypes
            if getattr(sys, "frozen", False):
                target = sys.executable
                params = ""
            else:
                target = sys.executable
                params = '"%s"' % os.path.abspath(sys.argv[0])
            # ShellExecuteW с глаголом "runas" запрашивает UAC. Возврат > 32 = успех.
            rc = ctypes.windll.shell32.ShellExecuteW(
                None, "runas", target, params, BASE_DIR, 1)
            if rc and rc > 32:
                try:
                    self.save_config()
                except Exception:
                    pass
                self.destroy()
            else:
                messagebox.showwarning("Повышение прав",
                                       "Не удалось перезапустить от администратора "
                                       f"(код {rc}).\nЗакройте панель и запустите её "
                                       "от имени администратора вручную.")
        except Exception as e:
            messagebox.showerror("Повышение прав",
                                 f"Не удалось перезапустить от администратора: {e}")

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
