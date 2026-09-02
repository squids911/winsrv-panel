#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Модуль: Диски и тома.
* Список дисков/разделов/томов.
* Расширение тома на максимальный доступный размер.
"""

import tkinter as tk
from tkinter import ttk

from framework import BasePanel


class Panel(BasePanel):
    id = "disks"
    title = "Диски и тома"
    order = 75
    CONFIG_SCHEMA = {
        "disks": {
            "driveLetter": ("", "Буква тома (например C)"),
        },
    }

    def build(self, parent):
        box1 = ttk.LabelFrame(parent, text="Диски", padding=12)
        box1.pack(fill="both", expand=True, padx=10, pady=10)
        self.btn_list = ttk.Button(box1, text="Показать диски/разделы/тома", command=self._list)
        self.btn_list.pack(anchor="w", pady=(0, 8))
        ttk.Label(box1, foreground="#555", justify="left",
                  text="Список дисков выводится во вкладку «Журнал».").pack(anchor="w")

        box2 = ttk.LabelFrame(parent, text="Расширение тома", padding=12)
        box2.pack(fill="x", padx=10, pady=(0, 10))
        row = ttk.Frame(box2)
        row.pack(fill="x")
        ttk.Label(row, text="Буква тома").pack(side="left")
        self.var_dl = tk.StringVar(value=self.app.cfg.get("disks", {}).get("driveLetter", "C"))
        ttk.Entry(row, textvariable=self.var_dl).pack(side="left", fill="x", expand=True, padx=8)
        self.btn_extend = ttk.Button(box2, text="Расширить (до максимума)", command=self._extend)
        self.btn_extend.pack(anchor="w", pady=(10, 0))
        ttk.Label(box2, foreground="#555", justify="left", wraplength=720,
                  text="Расширяет том на максимально доступный размер (нужно свободное место "
                       "на диске и не распределённое пространство после раздела).").pack(anchor="w")

    def _list(self):
        self.app.run_script(self, "get_disks.ps1", [], "Список дисков и томов")

    def _extend(self):
        dl = self.var_dl.get().strip()
        if not dl:
            self.app.log("\n[Укажите букву тома]\n")
            return
        self.app.set_config("disks", {"driveLetter": dl})
        self.app.run_script(self, "extend_volume.ps1", ["-DriveLetter", dl],
                            "Расширение тома")
