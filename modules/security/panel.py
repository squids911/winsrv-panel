#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Модуль: Безопасность (начинаем с краткой сводки).
Служит примером того, как добавить новый раздел:
  * папка modules/security/panel.py (класс Panel от BasePanel);
  * методы/скрипты в modules/security/scripts/*.ps1;
  * необязательная секция в CONFIG_SCHEMA (см. [system], [network]).
"""

import tkinter as tk
from tkinter import ttk

from framework import BasePanel


class Panel(BasePanel):
    id = "security"
    title = "Безопасность"
    order = 50
    CONFIG_SCHEMA = {}

    def build(self, parent):
        box = ttk.LabelFrame(parent, text="Сводка по безопасности", padding=12)
        box.pack(fill="both", expand=True, padx=10, pady=10)

        self.btn = ttk.Button(box, text="Показать сводку", command=self._run)
        self.btn.pack(anchor="w", pady=(0, 8))

        ttk.Label(box, foreground="#555", justify="left", wraplength=720,
                  text=("Раздел-заготовка. Показывает статус RDP, брандмауэра и группу "
                        "«Remote Desktop Users». Здесь удобно добавлять проверки: парольные "
                        "политики, аудит, запрет локального входа, UAC и т.д. — новый скрипт "
                        "в modules/security/scripts и кнопка вызова.")).pack(anchor="w")

    def _run(self):
        self.app.run_script(self, "security_status.ps1", [], "Сводка по безопасности")
