#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Модуль: Роли и компоненты Windows Server.
Устанавливает выбранные роли/компоненты через Install-WindowsFeature.
Список ролей берётся из roles.json (рядом с программой, редактируемый).
"""

import json
import os
import tkinter as tk
from tkinter import ttk, messagebox

from framework import BasePanel


class ScrollableFrame(ttk.Frame):
    def __init__(self, parent):
        super().__init__(parent)
        self.canvas = tk.Canvas(self, highlightthickness=0)
        self.vsb = ttk.Scrollbar(self, orient="vertical", command=self.canvas.yview)
        self.inner = ttk.Frame(self.canvas)
        self.inner.bind(
            "<Configure>", lambda e: self.canvas.configure(scrollregion=self.canvas.bbox("all"))
        )
        self.canvas.bind("<Configure>", lambda e: self.canvas.itemconfigure("win", width=e.width))
        self.canvas.create_window((0, 0), window=self.inner, anchor="nw")
        self.canvas.configure(yscrollcommand=self.vsb.set)
        self.canvas.pack(side="left", fill="both", expand=True)
        self.vsb.pack(side="right", fill="y")


class Panel(BasePanel):
    id = "roles"
    title = "Роли и компоненты"
    order = 10
    CONFIG_SCHEMA = {
        "roles": {
            "includeMgmtTools": ("0", "0 = не ставить средства управления"),
        },
    }

    def build(self, parent):
        bar = ttk.Frame(parent, padding=10)
        bar.pack(side="top", fill="x")
        self.btn_refresh = ttk.Button(bar, text="Обновить список ролей", command=self._reload)
        self.btn_refresh.pack(side="left")
        self.btn_install = ttk.Button(bar, text="Установить выбранные роли", command=self._install)
        self.btn_install.pack(side="left", padx=6)
        self.var_mgmt = tk.BooleanVar(value=self.app.cfg.get("roles", {}).get("includeMgmtTools", "0") == "1")
        ttk.Checkbutton(bar, text="Устанавливать средства управления",
                        variable=self.var_mgmt).pack(side="left")

        container = ScrollableFrame(parent)
        container.pack(side="top", fill="both", expand=True, padx=10, pady=(0, 10))
        self.container = container
        self.role_vars = []
        self._reload()

    def _reload(self):
        for child in self.container.inner.winfo_children():
            child.destroy()
        self.role_vars = []
        data = self._load_roles()
        roles = data.get("roles", []) or []
        if not roles:
            label = ttk.Label(self.container.inner, justify="left", foreground="#555",
                              text=("Список ролей пуст.\n"
                                    "Заполните roles.json (пример: roles.example.json) и нажмите "
                                    "«Обновить список ролей»."))
            label.pack(anchor="w", padx=6, pady=6)
            return
        for i, r in enumerate(roles):
            name = r.get("name", "")
            display = r.get("display", name)
            var = tk.BooleanVar(value=False)
            ttk.Checkbutton(self.container.inner, text=display, variable=var
                            ).grid(row=i, column=0, sticky="w", padx=6, pady=2)
            self.role_vars.append({"name": name, "display": display, "var": var})

    def _load_roles(self):
        path = getattr(self.app, "roles_path", os.path.join(self.app.base_dir, "roles.json"))
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return {}

    def _install(self):
        selected = [rv["name"] for rv in self.role_vars if rv["var"].get()]
        if not selected:
            messagebox.showinfo("Роли", "Не выбрано ни одной роли/компонента.")
            return
        self.app.set_config("roles", {"includeMgmtTools": "1" if self.var_mgmt.get() else "0"})
        args = ["-Features"] + selected
        if self.var_mgmt.get():
            args.append("-IncludeManagementTools")
        self.app.run_script(self, "install_roles.ps1", args, "Установка ролей и компонентов")
