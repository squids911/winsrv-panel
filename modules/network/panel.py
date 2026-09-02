#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Модуль: Сеть.
* Показать сетевые адаптеры (IP, шлюз, DNS).
* Назначить статический IPv4 / шлюз / DNS выбранному адаптеру.
"""

import tkinter as tk
from tkinter import ttk

from framework import BasePanel


class Panel(BasePanel):
    id = "network"
    title = "Сеть"
    order = 30
    CONFIG_SCHEMA = {
        "network": {
            "adapter": ("", "Имя адаптера"),
            "ip": ("", "IP-адрес"),
            "prefixLength": ("24", "Маска (префикс)"),
            "gateway": ("", "Шлюз"),
            "dns": ("", "DNS-сервер(ы)"),
        },
    }

    def build(self, parent):
        box1 = ttk.LabelFrame(parent, text="Адаптеры", padding=12)
        box1.pack(fill="both", expand=True, padx=10, pady=10)
        self.btn_list = ttk.Button(box1, text="Показать адаптеры", command=self._list)
        self.btn_list.pack(anchor="w", pady=(0, 8))
        ttk.Label(box1, foreground="#555", justify="left",
                  text="Список адаптеров отображается во вкладке «Журнал»."
                       ).pack(anchor="w")

        box2 = ttk.LabelFrame(parent, text="Статическая настройка", padding=12)
        box2.pack(fill="x", padx=10, pady=(0, 10))

        net = self.app.cfg.get("network", {})
        self.var_adapter = tk.StringVar(value=net.get("adapter", ""))
        self.var_ip = tk.StringVar(value=net.get("ip", ""))
        self.var_prefix = tk.StringVar(value=net.get("prefixLength", "24"))
        self.var_gw = tk.StringVar(value=net.get("gateway", ""))
        self.var_dns = tk.StringVar(value=net.get("dns", ""))

        grid = ttk.Frame(box2)
        grid.pack(fill="x")
        grid.columnconfigure(1, weight=1)

        def row(r, label, var):
            ttk.Label(grid, text=label).grid(row=r, column=0, sticky="w", padx=6, pady=4)
            ttk.Entry(grid, textvariable=var).grid(row=r, column=1, sticky="ew", padx=6, pady=4)

        row(0, "Адаптер (имя)", self.var_adapter)
        row(1, "IP-адрес", self.var_ip)
        row(2, "Маска (префикс)", self.var_prefix)
        row(3, "Шлюз (gateway)", self.var_gw)
        row(4, "DNS (через запятую)", self.var_dns)

        self.btn_apply = ttk.Button(box2, text="Применить настройки", command=self._apply)
        self.btn_apply.pack(anchor="w", padx=6, pady=10)

    def _list(self):
        self.app.run_script(self, "get_nics.ps1", [], "Список сетевых адаптеров")

    def _apply(self):
        self.app.set_config("network", {
            "adapter": self.var_adapter.get(),
            "ip": self.var_ip.get(),
            "prefixLength": self.var_prefix.get(),
            "gateway": self.var_gw.get(),
            "dns": self.var_dns.get(),
        })
        self.app.run_script(self, "set_nic.ps1", [
            "-Adapter", self.var_adapter.get(),
            "-IPAddress", self.var_ip.get(),
            "-PrefixLength", self.var_prefix.get(),
            "-Gateway", self.var_gw.get(),
            "-Dns", self.var_dns.get(),
        ], "Статическая настройка сети")
