#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Модуль: Единый дашборд быстрой настройки.

Один компактный экран (две колонки, без прокрутки) со списком задач. Отмечаете
галочками нужные операции и нажимаете "Выполнить выбранное" - все выполняются
последовательно, вывод идёт в общий журнал внизу.

Каждая задача = отдельный PowerShell-скрипт в modules/dashboard/scripts/.
Состояние галочек и параметры (адрес Zabbix-прокси) сохраняются в реестр
(HKCU\\Software\\WinSrvPanel\\dashboard).
"""

import tkinter as tk
from tkinter import ttk, messagebox

from framework import BasePanel


# (id, подпись, скрипт, аргументы-по-умолчанию или None если строятся динамически)
SECTIONS = [
    ("Безопасность", [
        ("firewall_off", "Отключить брандмауэр (все профили)", "disable_firewall.ps1", []),
        ("esc_off", "Отключить усиленную конфигурацию IE (ESC)", "disable_esc.ps1", []),
        ("defender_off", "Отключить антивирус (Defender)", "disable_defender.ps1", []),
        ("dep_off", "DEP: только основные программы и службы", "disable_dep.ps1", []),
    ]),
    ("Удалённый доступ", [
        ("rdp_on", "Включить удалённый доступ по RDP", "enable_rdp.ps1", []),
        ("winrm_on", "Удалённое администрирование (WinRM)", "enable_winrm.ps1", []),
    ]),
    ("Система", [
        ("activate", "Активация Windows (ключ 2022 / 2025)", "activate_os.ps1", []),
        ("power_max", "Энергосхема: максимальная производительность", "set_power_high.ps1", []),
    ]),
    ("Профили пользователей", [
        ("profiles_d", "Переместить профили на D:\\Users (нужен D:)", "set_profiles_d.ps1", []),
    ]),
    ("Минимальный софт", [
        ("software", "7-Zip, Chrome, PuTTY, WinSCP", "install_software.ps1", []),
    ]),
    ("Мониторинг — Zabbix Agent 2", [
        ("zabbix_proxy", "Zabbix Agent 2 — через прокси", "zabbix_agent_proxy.ps1", None),
        ("zabbix_direct", "Zabbix Agent 2 — напрямую", "zabbix_agent_server.ps1", []),
    ]),
    ("Remote Desktop Services (RDS)", [
        ("rds_activate", "Активировать сервер лицензирования", "activate_licensing.ps1", None),
        ("rds_cals", "Установить лицензии CAL (Enterprise)", "install_cals.ps1", None),
        ("rds_policy", "Применить локальные политики", "set_rds_policy.ps1", None),
    ]),
]

# Распределение разделов по двум колонкам (чтобы всё влезало без прокрутки).
COLUMN_LAYOUT = [
    ["Безопасность", "Удалённый доступ", "Система", "Профили пользователей"],
    ["Минимальный софт", "Мониторинг — Zabbix Agent 2", "Remote Desktop Services (RDS)"],
]


class Panel(BasePanel):
    id = "dashboard"
    title = "Дашборд"
    order = 5
    CONFIG_SCHEMA = {
        "dashboard": {
            **{tid: ("0", "") for _s, tasks in SECTIONS for (tid, _l, _sc, _a) in tasks},
            "proxyAddr": ("", "IP машины с Zabbix proxy (для ServerActive)"),
            "proxyName": ("TG.SRV-ZABBIX-PROXY", "Имя прокси в Zabbix"),
            "kmsServer": ("kms.kini24.ru", "KMS-сервер (host[:port]) для активации Windows"),
        },
    }

    def build(self, parent):
        self.vars = {}
        self.checks = {}
        cfg = self.app.cfg.get("dashboard", {})

        # --- верхняя панель с кнопками --------------------------------------
        bar = ttk.Frame(parent, padding=(8, 6, 8, 2))
        bar.pack(side="top", fill="x")
        ttk.Label(bar, text="Отметьте операции и нажмите «Выполнить выбранное».",
                  font=("Segoe UI", 9, "bold")).pack(side="left")
        self.btn_run = ttk.Button(bar, text="▶ Выполнить выбранное", command=self._run, style="Accent.TButton")
        self.btn_run.pack(side="right")
        ttk.Button(bar, text="Снять всё", command=self._clear_all).pack(side="right", padx=4)
        ttk.Button(bar, text="Выбрать всё", command=self._select_all).pack(side="right", padx=4)

        # --- две колонки с задачами (без прокрутки) -------------------------
        cols_wrap = ttk.Frame(parent, padding=(8, 2, 8, 2))
        cols_wrap.pack(side="top", fill="both", expand=True)
        cols_wrap.columnconfigure(0, weight=1, uniform="dash")
        cols_wrap.columnconfigure(1, weight=1, uniform="dash")
        cols_wrap.rowconfigure(0, weight=1)

        col_frames = []
        for ci in range(2):
            f = ttk.Frame(cols_wrap)
            f.grid(row=0, column=ci, sticky="nsew", padx=(0, 6) if ci == 0 else (6, 0))
            col_frames.append(f)

        sections_by_title = {title: tasks for title, tasks in SECTIONS}
        for ci, titles in enumerate(COLUMN_LAYOUT):
            for title in titles:
                tasks = sections_by_title.get(title)
                if not tasks:
                    continue
                box = ttk.LabelFrame(col_frames[ci], text=title, padding=(8, 4))
                box.pack(fill="x", pady=(0, 6))
                for tid, label, script, args in tasks:
                    var = tk.BooleanVar(value=cfg.get(tid, "0") == "1")
                    self.vars[tid] = var
                    cb = ttk.Checkbutton(box, text=label, variable=var)
                    cb.pack(anchor="w", pady=0)
                    self.checks[tid] = cb

        # --- параметры (Zabbix и KMS) под колонками --------------------------
        zbox = ttk.LabelFrame(parent, text="Параметры (Zabbix и KMS)", padding=(8, 4))
        zbox.pack(side="top", fill="x", padx=8, pady=(0, 4))
        zrow = ttk.Frame(zbox)
        zrow.pack(fill="x")
        ttk.Label(zrow, text="IP Zabbix-прокси:").pack(side="left")
        self.var_proxy_addr = tk.StringVar(value=cfg.get("proxyAddr", ""))
        ttk.Entry(zrow, textvariable=self.var_proxy_addr, width=18).pack(side="left", padx=(4, 12))
        ttk.Label(zrow, text="Имя прокси:").pack(side="left")
        self.var_proxy_name = tk.StringVar(value=cfg.get("proxyName", "TG.SRV-ZABBIX-PROXY"))
        ttk.Entry(zrow, textvariable=self.var_proxy_name, width=24).pack(side="left", padx=4)

        zrow2 = ttk.Frame(zbox)
        zrow2.pack(fill="x", pady=(2, 0))
        ttk.Label(zrow2, text="KMS-сервер (host[:port]):").pack(side="left")
        self.var_kms = tk.StringVar(value=cfg.get("kmsServer", "kms.kini24.ru"))
        ttk.Entry(zrow2, textvariable=self.var_kms, width=28).pack(side="left", padx=4)

        # --- нижняя подсказка -----------------------------------------------
        self.lbl_hint = ttk.Label(parent, foreground="#555", anchor="w", padding=(10, 0, 10, 4),
                                  text="Проверка диска D: ...")
        self.lbl_hint.pack(side="bottom", fill="x")

        # Задача "профили на D:" недоступна, пока не подтверждён диск D:.
        self.checks["profiles_d"].config(state="disabled")
        self.vars["profiles_d"].set(False)
        self.app.run_capture(self, "has_d_drive.ps1", [], self._on_d_probe)

    # ------------------------------------------------------------------ проверки
    def _on_d_probe(self, payload):
        rc, out, err = payload
        has_d = (rc == 0 and "YES" in (out or "").upper())
        if has_d:
            self.checks["profiles_d"].config(state="normal")
            self.lbl_hint.config(text="Диск D: найден — перенос профилей доступен.")
        else:
            self.vars["profiles_d"].set(False)
            self.checks["profiles_d"].config(state="disabled")
            self.lbl_hint.config(text="Диск D: не найден — перенос профилей недоступен.")

    # ------------------------------------------------------------------ управление
    def _select_all(self):
        for tid, cb in self.checks.items():
            if str(cb.cget("state")) != "disabled":
                self.vars[tid].set(True)

    def _clear_all(self):
        for tid in self.vars:
            self.vars[tid].set(False)

    def _rds_args(self, tid):
        """Аргументы RDS-скриптов из сохранённых настроек (activation/licensing/rdsPolicy)."""
        if tid == "rds_activate":
            a = self.app.cfg.get("activation", {})
            return ["-FirstName", a.get("firstName", "1"),
                    "-LastName", a.get("lastName", "1"),
                    "-Company", a.get("company", "1"),
                    "-CountryRegion", a.get("countryRegion", "Belarus"),
                    "-ConnectionMethod", a.get("method", "AUTO"),
                    "-Reason", str(a.get("reason", "5"))]
        if tid == "rds_cals":
            l = self.app.cfg.get("licensing", {})
            return ["-AgreementType", str(l.get("agreementType", "1")),
                    "-AgreementNumber", l.get("agreementNumber", "6565793"),
                    "-ProductVersion", str(l.get("productVersion", "8")),
                    "-ProductType", str(l.get("productType", "0")),
                    "-LicenseCount", str(l.get("licenseCount", "1000"))]
        if tid == "rds_policy":
            p = self.app.cfg.get("rdsPolicy", {})
            return ["-LicenseServers", p.get("licenseServers", "localhost"),
                    "-LicensingMode", str(p.get("licensingMode", "2"))]
        return []

    def _run(self):
        if self.app.running:
            messagebox.showinfo("Занято", "Операция уже выполняется. Дождитесь завершения.")
            return

        proxy_addr = self.var_proxy_addr.get().strip()
        proxy_name = self.var_proxy_name.get().strip() or "TG.SRV-ZABBIX-PROXY"
        kms = self.var_kms.get().strip()

        if self.vars["zabbix_proxy"].get() and not proxy_addr:
            messagebox.showwarning("Zabbix",
                                   "Для установки Zabbix Agent 2 через прокси укажите "
                                   "IP машины с Zabbix-прокси.")
            return

        calls = []
        for _section, tasks in SECTIONS:
            for tid, label, script, args in tasks:
                if not self.vars[tid].get():
                    continue
                if tid == "zabbix_proxy":
                    a = ["-ProxyAddr", proxy_addr, "-ProxyName", proxy_name]
                elif tid in ("rds_activate", "rds_cals", "rds_policy"):
                    a = self._rds_args(tid)
                elif tid == "activate":
                    a = ["-KmsServer", kms]
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

        self.app.set_config("dashboard", {
            **{tid: ("1" if self.vars[tid].get() else "0") for tid in self.vars},
            "proxyAddr": proxy_addr,
            "proxyName": proxy_name,
            "kmsServer": kms,
        })
        try:
            self.app.save_config()
        except Exception:
            pass

        self.app.run_scripts(self, calls, "Выполнение выбранных операций")
