#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Модуль: Система.
* Сведения о сервере (имя, домен, ОС, статус активации).
* Активация Windows (ввод ключа + slmgr /ato).
"""

import tkinter as tk
from tkinter import ttk

from framework import BasePanel


class Panel(BasePanel):
    id = "system"
    title = "Система"
    order = 20
    CONFIG_SCHEMA = {
        "system": {
            "productKey": ("", "Ключ продукта Windows (пусто = только активация)"),
        },
    }

    def build(self, parent):
        box1 = ttk.LabelFrame(parent, text="Сведения о сервере", padding=12)
        box1.pack(fill="both", expand=True, padx=10, pady=10)

        self.btn_info = ttk.Button(box1, text="Собрать сведения", command=self._get_info)
        self.btn_info.pack(anchor="w", pady=(0, 8))
        ttk.Label(box1, foreground="#555", justify="left",
                  text="Показывает имя компьютера, домен, версию ОС и статус активации. "
                       "Результат — во вкладке «Журнал»").pack(anchor="w")

        box2 = ttk.LabelFrame(parent, text="Активация Windows", padding=12)
        box2.pack(fill="x", padx=10, pady=(0, 10))

        row = ttk.Frame(box2)
        row.pack(fill="x")
        ttk.Label(row, text="Ключ продукта").pack(side="left")
        self.var_key = tk.StringVar(value=self.app.cfg.get("system", {}).get("productKey", ""))
        ent = ttk.Entry(row, textvariable=self.var_key)
        ent.pack(side="left", fill="x", expand=True, padx=8)

        self.btn_activate = ttk.Button(box2, text="Активировать", command=self._activate)
        self.btn_activate.pack(anchor="w", pady=(10, 0))

    def _get_info(self):
        self.app.run_script(self, "get_system_info.ps1", [], "Сведения о сервере")

    def _activate(self):
        self.app.set_config("system", {"productKey": self.var_key.get()})
        self.app.run_script(self, "activate_windows.ps1",
                            ["-ProductKey", self.var_key.get().strip()],
                            "Активация Windows")
