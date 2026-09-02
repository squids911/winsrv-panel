#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Модуль: RDS — коллекции сеансов (RD Session Collections).
Требует развёрнутого развёртывания RDS с Connection Broker.
"""

import tkinter as tk
from tkinter import ttk

from framework import BasePanel


class Panel(BasePanel):
    id = "rdscollections"
    title = "RDS — коллекции"
    order = 45
    CONFIG_SCHEMA = {
        "rdscollections": {
            "collectionName": ("", "Имя коллекции"),
            "sessionHost": ("", "FQDN хоста сеансов"),
            "connectionBroker": ("", "FQDN брокера подключений"),
            "description": ("", "Описание коллекции"),
        },
    }

    def build(self, parent):
        col = self.app.cfg.get("rdscollections", {})
        self.var_broker = tk.StringVar(value=col.get("connectionBroker", ""))
        self.var_name = tk.StringVar(value=col.get("collectionName", ""))
        self.var_host = tk.StringVar(value=col.get("sessionHost", ""))
        self.var_desc = tk.StringVar(value=col.get("description", ""))
        self.var_admin = tk.BooleanVar(value=False)

        box1 = ttk.LabelFrame(parent, text="Просмотр коллекций", padding=12)
        box1.pack(fill="both", expand=True, padx=10, pady=10)
        row = ttk.Frame(box1)
        row.pack(fill="x", pady=(0, 8))
        ttk.Label(row, text="Брокер подключений").pack(side="left")
        ttk.Entry(row, textvariable=self.var_broker).pack(side="left", fill="x", expand=True, padx=8)
        self.btn_list = ttk.Button(box1, text="Показать коллекции", command=self._list)
        self.btn_list.pack(anchor="w", pady=(0, 4))
        ttk.Label(box1, foreground="#555", justify="left",
                  text="Список коллекций выводится во вкладку «Журнал».").pack(anchor="w")

        box2 = ttk.LabelFrame(parent, text="Создание коллекции", padding=12)
        box2.pack(fill="x", padx=10, pady=(0, 10))
        grid = ttk.Frame(box2)
        grid.pack(fill="x")
        grid.columnconfigure(1, weight=1)

        def rowg(r, label, var):
            ttk.Label(grid, text=label).grid(row=r, column=0, sticky="w", padx=6, pady=4)
            ttk.Entry(grid, textvariable=var).grid(row=r, column=1, sticky="ew", padx=6, pady=4)

        rowg(0, "Имя коллекции", self.var_name)
        rowg(1, "Хост сеансов (FQDN)", self.var_host)
        rowg(2, "Брокер подключений", self.var_broker)
        rowg(3, "Описание", self.var_desc)
        ttk.Checkbutton(grid, text="Дать админ-привилегии",
                        variable=self.var_admin).grid(row=4, column=1, sticky="w", padx=6, pady=4)

        self.btn_create = ttk.Button(box2, text="Создать коллекцию", command=self._create)
        self.btn_create.pack(anchor="w", padx=6, pady=10)

    def _list(self):
        broker = self.var_broker.get().strip()
        if not broker:
            self.app.log("\n[Укажите брокер подключений]\n")
            return
        self.app.run_script(self, "list_collections.ps1", ["-ConnectionBroker", broker],
                            "Список RDS-коллекций")

    def _create(self):
        self.app.set_config("rdscollections", {
            "collectionName": self.var_name.get(),
            "sessionHost": self.var_host.get(),
            "connectionBroker": self.var_broker.get(),
            "description": self.var_desc.get(),
        })
        args = [
            "-CollectionName", self.var_name.get(),
            "-SessionHost", self.var_host.get(),
            "-ConnectionBroker", self.var_broker.get(),
            "-Description", self.var_desc.get(),
        ]
        if self.var_admin.get():
            args.append("-GrantAdminPrivilege")
        self.app.run_script(self, "create_collection.ps1", args, "Создание RDS-коллекции")
