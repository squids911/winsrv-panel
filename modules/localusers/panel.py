#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Модуль: Локальные пользователи и группы.
* Список пользователей/групп (+ члены группы).
* Создание локального пользователя и добавление в группу (например,
  'Remote Desktop Users').
Пароль пользователя НЕ сохраняется в настройках (вводится каждый раз).
"""

import tkinter as tk
from tkinter import ttk

from framework import BasePanel


class Panel(BasePanel):
    id = "localusers"
    title = "Пользователи и группы"
    order = 65
    CONFIG_SCHEMA = {
        "localusers": {
            "username": ("", "Имя пользователя"),
            "fullName": ("", "Полное имя"),
            "group": ("Remote Desktop Users", "Группа"),
        },
    }

    def build(self, parent):
        box1 = ttk.LabelFrame(parent, text="Просмотр", padding=12)
        box1.pack(fill="both", expand=True, padx=10, pady=10)
        row = ttk.Frame(box1)
        row.pack(fill="x", pady=(0, 8))
        ttk.Label(row, text="Группа (для списка членов)").pack(side="left")
        self.var_list_group = tk.StringVar(value="Remote Desktop Users")
        ttk.Entry(row, textvariable=self.var_list_group).pack(side="left", fill="x", expand=True, padx=8)
        self.btn_list = ttk.Button(box1, text="Показать пользователей/группы", command=self._list)
        self.btn_list.pack(anchor="w")
        ttk.Label(box1, foreground="#555", justify="left",
                  text="Список выводится во вкладку «Журнал».").pack(anchor="w")

        box2 = ttk.LabelFrame(parent, text="Создание пользователя", padding=12)
        box2.pack(fill="x", padx=10, pady=(0, 10))

        lu = self.app.cfg.get("localusers", {})
        self.var_name = tk.StringVar(value=lu.get("username", ""))
        self.var_full = tk.StringVar(value=lu.get("fullName", ""))
        self.var_group = tk.StringVar(value=lu.get("group", "Remote Desktop Users"))
        self.var_pass = tk.StringVar()

        grid = ttk.Frame(box2)
        grid.pack(fill="x")
        grid.columnconfigure(1, weight=1)

        def rowg(r, label, var, show=None):
            ttk.Label(grid, text=label).grid(row=r, column=0, sticky="w", padx=6, pady=4)
            ttk.Entry(grid, textvariable=var, show=show or "").grid(row=r, column=1, sticky="ew", padx=6, pady=4)

        rowg(0, "Имя пользователя", self.var_name)
        rowg(1, "Полное имя", self.var_full)
        rowg(2, "Группа", self.var_group)
        rowg(3, "Пароль", self.var_pass, show="*")

        self.btn_create = ttk.Button(box2, text="Создать пользователя", command=self._create)
        self.btn_create.pack(anchor="w", padx=6, pady=10)

    def _list(self):
        args = ["-Group", self.var_list_group.get().strip()]
        self.app.run_script(self, "list_users.ps1", args, "Список пользователей и групп")

    def _create(self):
        name = self.var_name.get().strip()
        pwd = self.var_pass.get()
        if not name or not pwd:
            self.app.log("\n[Введите имя пользователя и пароль]\n")
            return
        self.app.set_config("localusers", {
            "username": name,
            "fullName": self.var_full.get(),
            "group": self.var_group.get(),
        })
        self.app.run_script(self, "create_user.ps1", [
            "-Name", name,
            "-FullName", self.var_full.get(),
            "-Password", pwd,
            "-Group", self.var_group.get().strip(),
        ], "Создание локального пользователя")
