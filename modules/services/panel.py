#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Модуль: Службы Windows.
* Показать все службы.
* Запустить/остановить/перезапустить/посмотреть статус службы по имени.
"""

import tkinter as tk
from tkinter import ttk

from framework import BasePanel


class Panel(BasePanel):
    id = "services"
    title = "Службы"
    order = 60
    CONFIG_SCHEMA = {}

    def build(self, parent):
        box1 = ttk.LabelFrame(parent, text="Просмотр служб", padding=12)
        box1.pack(fill="both", expand=True, padx=10, pady=10)
        self.btn_list = ttk.Button(box1, text="Показать все службы", command=self._list)
        self.btn_list.pack(anchor="w", pady=(0, 8))
        ttk.Label(box1, foreground="#555", justify="left",
                  text="Список служб выводится во вкладку «Журнал».").pack(anchor="w")

        box2 = ttk.LabelFrame(parent, text="Управление службой", padding=12)
        box2.pack(fill="x", padx=10, pady=(0, 10))

        row = ttk.Frame(box2)
        row.pack(fill="x")
        ttk.Label(row, text="Имя службы").pack(side="left")
        self.var_name = tk.StringVar()
        ent = ttk.Entry(row, textvariable=self.var_name)
        ent.pack(side="left", fill="x", expand=True, padx=8)

        btns = ttk.Frame(box2)
        btns.pack(fill="x", pady=(10, 0))
        for text, action in [("Запустить", "Start"), ("Остановить", "Stop"),
                             ("Перезапустить", "Restart"), ("Статус", "Status")]:
            ttk.Button(btns, text=text, command=lambda a=action: self._action(a)
                       ).pack(side="left", padx=4)

    def _list(self):
        self.app.run_script(self, "get_services.ps1", [], "Список служб")

    def _action(self, action):
        name = self.var_name.get().strip()
        if not name:
            self.app.log("\n[Введите имя службы]\n")
            return
        self.app.run_script(self, "service_action.ps1",
                            ["-Name", name, "-Action", action],
                            f"Служба {name}: {action}")
