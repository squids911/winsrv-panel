#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Модуль: Active Directory.
* Установка роли AD DS (+ средства управления).
* Повышение сервера до контроллера домена (новый лес).

ВНИМАНИЕ: повышение до DC требует статический IP/DNS и выполняется с
перезагрузкой сервера. Пароль DSRM в настройки НЕ сохраняется (вводится каждый раз).
"""

import tkinter as tk
from tkinter import ttk

from framework import BasePanel


class Panel(BasePanel):
    id = "ad"
    title = "Active Directory"
    order = 55
    CONFIG_SCHEMA = {
        "ad": {
            "domainName": ("", "Домен (например corp.local)"),
            "netbiosName": ("", "NetBIOS-имя (например CORP, до 15 симв.)"),
        },
    }

    def build(self, parent):
        nb = ttk.Notebook(parent)
        nb.pack(fill="both", expand=True, padx=8, pady=8)
        self._build_role(nb)
        self._build_promote(nb)

    def _build_role(self, nb):
        tab = ttk.Frame(nb, padding=12)
        nb.add(tab, text="Установка роли")
        self.btn_role = ttk.Button(tab, text="Установить AD DS (роль + средства управления)",
                                   command=self._install_role)
        self.btn_role.pack(anchor="w", pady=(0, 8))
        ttk.Label(tab, foreground="#555", justify="left", wraplength=720,
                  text="Устанавливает роль AD Domain Services и средства управления. "
                       "После установки сервер можно повысить до контроллера домена. "
                       "Рекомендуется сначала назначить статический IP и DNS.").pack(anchor="w")

    def _install_role(self):
        self.app.run_script(self, "install_ad_role.ps1", [], "Установка роли AD DS")

    def _build_promote(self, nb):
        tab = ttk.Frame(nb, padding=12)
        nb.add(tab, text="Повышение до DC")

        ad = self.app.cfg.get("ad", {})
        self.var_dom = tk.StringVar(value=ad.get("domainName", ""))
        self.var_net = tk.StringVar(value=ad.get("netbiosName", ""))
        self.var_pass = tk.StringVar()

        grid = ttk.Frame(tab)
        grid.pack(fill="x")
        grid.columnconfigure(1, weight=1)

        def row(r, label, widget):
            ttk.Label(grid, text=label).grid(row=r, column=0, sticky="w", padx=6, pady=4)
            widget.grid(row=r, column=1, sticky="ew", padx=6, pady=4)

        row(0, "Имя домена", ttk.Entry(grid, textvariable=self.var_dom))
        row(1, "NetBIOS-имя", ttk.Entry(grid, textvariable=self.var_net))
        row(2, "Пароль DSRM", ttk.Entry(grid, textvariable=self.var_pass, show="*"))

        ttk.Label(tab, foreground="#a33", justify="left", wraplength=720,
                  text="ОПАСНО: повышение до контроллера домена — необратимо, требует "
                       "статического IP/DNS и перезагрузки. Пароль DSRM не сохраняется "
                       "в настройках.").pack(anchor="w", fill="x", pady=(8, 0))

        self.btn_promote = ttk.Button(tab, text="Повысить до контроллера домена",
                                      command=self._promote)
        self.btn_promote.pack(anchor="w", padx=12, pady=10)

    def _promote(self):
        dom = self.var_dom.get().strip()
        pwd = self.var_pass.get()
        if not dom or not pwd:
            self.app.log("\n[Укажите имя домена и пароль DSRM]\n")
            return
        self.app.set_config("ad", {"domainName": dom, "netbiosName": self.var_net.get().strip()})
        args = ["-DomainName", dom]
        if self.var_net.get().strip():
            args += ["-NetbiosName", self.var_net.get().strip()]
        args += ["-SafeModePassword", pwd]
        self.app.run_script(self, "promote_dc.ps1", args,
                            "Повышение сервера до контроллера домена")
