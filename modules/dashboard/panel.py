#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Модуль: Единый дашборд быстрой настройки.

Вместо множества вкладок - один экран со списком задач. Пользователь отмечает
галочками нужные операции и нажимает "Выполнить выбранное". Все отмеченные
скрипты выполняются ПОСЛЕДОВАТЕЛЬНО, их вывод идёт в общий журнал внизу.

Каждая задача = отдельный PowerShell-скрипт в modules/dashboard/scripts/.
Состояние галочек и параметры (адрес Zabbix-прокси) сохраняются в реестр
(HKCU\\Software\\WinSrvPanel\\dashboard) вместе с остальными настройками.
"""

import tkinter as tk
from tkinter import ttk, messagebox

from framework import BasePanel


# (id, подпись, скрипт, аргументы-по-умолчанию или None если строятся динамически)
SECTIONS = [
    ("Безопасность", [
        ("firewall_off", "Отключить брандмауэр (все профили)", "disable_firewall.ps1", []),
        ("esc_off", "Отключить усиленную конфигурацию безопасности (IE ESC)", "disable_esc.ps1", []),
        ("defender_off", "Отключить антивирус (Windows Defender)", "disable_defender.ps1", []),
        ("dep_off", "Выключить DEP (Data Execution Prevention)", "disable_dep.ps1", []),
    ]),
    ("Удалённый доступ", [
        ("rdp_on", "Включить удалённый доступ по RDP", "enable_rdp.ps1", []),
        ("winrm_on", "Включить удалённое администрирование (WinRM / PS Remoting)", "enable_winrm.ps1", []),
    ]),
    ("Система", [
        ("activate", "Активация Windows (ключ по версии: 2022 / 2025)", "activate_os.ps1", []),
        ("power_max", "Энергопотребление: максимальная производительность", "set_power_high.ps1", []),
    ]),
    ("Профили пользователей", [
        ("profiles_d", "Переместить профили на D:\\Users (нужен диск D:)", "set_profiles_d.ps1", []),
    ]),
    ("Минимальный софт", [
        ("software", "Установить 7-Zip, Chrome, PuTTY, WinSCP", "install_software.ps1", []),
    ]),
    ("Мониторинг — Zabbix Agent 2", [
        ("zabbix_proxy", "Zabbix Agent 2 — через прокси", "zabbix_agent_proxy.ps1", None),
        ("zabbix_direct", "Zabbix Agent 2 — напрямую", "zabbix_agent_server.ps1", []),
    ]),
]


class Panel(BasePanel):
    id = "dashboard"
    title = "Дашборд"
    order = 5
    CONFIG_SCHEMA = {
        "dashboard": {
            # состояние галочек (0/1)
            **{tid: ("0", "") for _s, tasks in SECTIONS for (tid, _l, _sc, _a) in tasks},
            # параметры Zabbix
            "proxyAddr": ("", "IP машины с Zabbix proxy (для ServerActive)"),
            "proxyName": ("TG.SRV-ZABBIX-PROXY", "Имя прокси в Zabbix"),
        },
    }

    def build(self, parent):
        self.vars = {}
        self.checks = {}
        cfg = self.app.cfg.get("dashboard", {})

        # --- верхняя панель с кнопками --------------------------------------
        bar = ttk.Frame(parent, padding=(10, 8, 10, 4))
        bar.pack(side="top", fill="x")
        ttk.Label(bar, text="Отметьте нужные операции и нажмите «Выполнить выбранное».",
                  font=("Segoe UI", 10, "bold")).pack(side="left")
        self.btn_run = ttk.Button(bar, text="▶ Выполнить выбранное", command=self._run)
        self.btn_run.pack(side="right")
        ttk.Button(bar, text="Снять всё", command=self._clear_all).pack(side="right", padx=6)
        ttk.Button(bar, text="Выбрать всё", command=self._select_all).pack(side="right", padx=6)

        # --- прокручиваемая область с задачами ------------------------------
        wrap = ttk.Frame(parent)
        wrap.pack(side="top", fill="both", expand=True, padx=10, pady=(2, 6))
        canvas = tk.Canvas(wrap, highlightthickness=0)
        vsb = ttk.Scrollbar(wrap, orient="vertical", command=canvas.yview)
        canvas.configure(yscrollcommand=vsb.set)
        vsb.pack(side="right", fill="y")
        canvas.pack(side="left", fill="both", expand=True)

        inner = ttk.Frame(canvas)
        win = canvas.create_window((0, 0), window=inner, anchor="nw")

        def _on_inner_config(_e):
            canvas.configure(scrollregion=canvas.bbox("all"))

        def _on_canvas_config(e):
            canvas.itemconfigure(win, width=e.width)

        inner.bind("<Configure>", _on_inner_config)
        canvas.bind("<Configure>", _on_canvas_config)

        # прокрутка колесом мыши
        def _on_wheel(e):
            canvas.yview_scroll(int(-1 * (e.delta / 120)), "units")
        canvas.bind_all("<MouseWheel>", _on_wheel)

        for section, tasks in SECTIONS:
            box = ttk.LabelFrame(inner, text=section, padding=(10, 6))
            box.pack(fill="x", pady=(0, 8), padx=2)
            for tid, label, script, args in tasks:
                var = tk.BooleanVar(value=cfg.get(tid, "0") == "1")
                self.vars[tid] = var
                cb = ttk.Checkbutton(box, text=label, variable=var)
                cb.pack(anchor="w", pady=1)
                self.checks[tid] = cb

        # поле адреса прокси (для zabbix_proxy)
        zbox = ttk.LabelFrame(inner, text="Параметры Zabbix", padding=(10, 6))
        zbox.pack(fill="x", pady=(0, 8), padx=2)
        row1 = ttk.Frame(zbox); row1.pack(fill="x", pady=1)
        ttk.Label(row1, text="IP Zabbix-прокси (ServerActive):").pack(side="left")
        self.var_proxy_addr = tk.StringVar(value=cfg.get("proxyAddr", ""))
        ttk.Entry(row1, textvariable=self.var_proxy_addr, width=22).pack(side="left", padx=6)
        row2 = ttk.Frame(zbox); row2.pack(fill="x", pady=1)
        ttk.Label(row2, text="Имя прокси в Zabbix:").pack(side="left")
        self.var_proxy_name = tk.StringVar(value=cfg.get("proxyName", "TG.SRV-ZABBIX-PROXY"))
        ttk.Entry(row2, textvariable=self.var_proxy_name, width=28).pack(side="left", padx=6)

        # --- нижняя подсказка -----------------------------------------------
        self.lbl_hint = ttk.Label(parent, foreground="#555", anchor="w", padding=(12, 0, 12, 6),
                                  text="Проверка диска D: ...")
        self.lbl_hint.pack(side="bottom", fill="x")

        # Задача "профили на D:" недоступна, пока не подтверждён диск D:.
        self.checks["profiles_d"].config(state="disabled")
        self.vars["profiles_d"].set(False)

        # Асинхронно проверяем наличие диска D: и доступность Zabbix-поля.
        self.app.run_capture(self, "has_d_drive.ps1", [], self._on_d_probe)

    # ------------------------------------------------------------------ проверки
    def _on_d_probe(self, payload):
        rc, out, err = payload
        has_d = (rc == 0 and "YES" in (out or "").upper())
        if has_d:
            self.checks["profiles_d"].config(state="normal")
            self.lbl_hint.config(text="Диск D: найден — перенос профилей доступен. "
                                      "Отметьте задачи и нажмите «Выполнить выбранное».")
        else:
            self.vars["profiles_d"].set(False)
            self.checks["profiles_d"].config(state="disabled")
            self.lbl_hint.config(text="Диск D: не найден — перенос профилей недоступен "
                                      "(галочка неактивна).")

    # ------------------------------------------------------------------ управление
    def _select_all(self):
        for tid, cb in self.checks.items():
            if str(cb.cget("state")) != "disabled":
                self.vars[tid].set(True)

    def _clear_all(self):
        for tid in self.vars:
            self.vars[tid].set(False)

    def _run(self):
        if self.app.running:
            messagebox.showinfo("Занято", "Операция уже выполняется. Дождитесь завершения.")
            return

        proxy_addr = self.var_proxy_addr.get().strip()
        proxy_name = self.var_proxy_name.get().strip() or "TG.SRV-ZABBIX-PROXY"

        # Валидация: для zabbix_proxy нужен адрес прокси.
        if self.vars["zabbix_proxy"].get() and not proxy_addr:
            messagebox.showwarning("Zabbix",
                                   "Для установки Zabbix Agent 2 через прокси укажите "
                                   "IP машины с Zabbix-прокси (поле «IP Zabbix-прокси»).")
            return

        calls = []
        for _section, tasks in SECTIONS:
            for tid, label, script, args in tasks:
                if not self.vars[tid].get():
                    continue
                if tid == "zabbix_proxy":
                    a = ["-ProxyAddr", proxy_addr, "-ProxyName", proxy_name]
                else:
                    a = list(args or [])
                calls.append((script, a, label))

        if not calls:
            messagebox.showinfo("Нечего выполнять", "Отметьте галочками хотя бы одну задачу.")
            return

        names = "\n".join(f"  • {c[2]}" for c in calls)
        if not messagebox.askyesno("Выполнить",
                                   f"Будут выполнены операции ({len(calls)}):\n\n{names}\n\n"
                                   "Продолжить?"):
            return

        # Сохраняем состояние галочек и параметры в реестр.
        self.app.set_config("dashboard", {
            **{tid: ("1" if self.vars[tid].get() else "0") for tid in self.vars},
            "proxyAddr": proxy_addr,
            "proxyName": proxy_name,
        })
        try:
            self.app.save_config()
        except Exception:
            pass

        self.app.run_scripts(self, calls, "Выполнение выбранных операций")
