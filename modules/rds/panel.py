#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Модуль: Remote Desktop Services (RDS) — лицензирование и политики.

Разделы внутри (под-вкладки):
  * Активация сервера лицензирования (метод AUTO).
  * Установка лицензий CAL (Enterprise, на устройство).
  * Локальные политики (RD Session Host > Licensing).
"""

import tkinter as tk
from tkinter import ttk

from framework import BasePanel

AGREEMENT_TYPES = {
    "Select (250+ компьютеров)": 0,
    "Enterprise (250+ компьютеров)": 1,
    "Campus": 2,
    "School": 3,
    "Service Provider (SPLA)": 4,
    "Open / Другое (Open Value, Open License)": 5,
}
PRODUCT_TYPES = {
    "На устройство (Per Device)": 0,
    "На пользователя (Per User)": 1,
}
LICENSING_MODES = {
    "На устройство (Per Device)": 2,
    "На пользователя (Per User)": 4,
}


class Panel(BasePanel):
    id = "rds"
    title = "Remote Desktop Services (RDS)"
    order = 40
    CONFIG_SCHEMA = {
        "activation": {
            "firstName": ("1", "FirstName (мастер активации)"),
            "lastName": ("1", "LastName"),
            "company": ("1", "Organization"),
            "countryRegion": ("Belarus", "Страна/регион"),
            "method": ("AUTO", "Метод: AUTO / WEB / PHONE"),
            "reason": ("5", "Причина: 5 = первая активация"),
        },
        "licensing": {
            "agreementType": ("1", "Программа: 1 = Enterprise"),
            "agreementNumber": ("6565793", "Номер соглашения"),
            "productVersion": ("8", "Версия: 4=2012R2,5=2016,6=2019,7=2022,8=2025"),
            "productType": ("0", "Тип: 0 = на устройство, 1 = на пользователя"),
            "licenseCount": ("1000", "Количество лицензий"),
        },
        "rdsPolicy": {
            "licenseServers": ("localhost", "Сервер(ы) лицензирования"),
            "licensingMode": ("2", "Режим: 2 = на устройство, 4 = на пользователя"),
        },
    }

    def build(self, parent):
        nb = ttk.Notebook(parent)
        nb.pack(fill="both", expand=True, padx=8, pady=8)
        self._build_activation(nb)
        self._build_licensing(nb)
        self._build_policy(nb)

    # --- Активация ---------------------------------------------------------
    def _build_activation(self, nb):
        tab = ttk.Frame(nb, padding=12)
        nb.add(tab, text="Активация")

        grid = ttk.Frame(tab)
        grid.pack(fill="x")
        grid.columnconfigure(1, weight=1)

        act = self.app.cfg.get("activation", {})
        self.var_first = tk.StringVar(value=act.get("firstName", "1"))
        self.var_last = tk.StringVar(value=act.get("lastName", "1"))
        self.var_company = tk.StringVar(value=act.get("company", "1"))
        self.var_country = tk.StringVar(value=act.get("countryRegion", "Belarus"))
        self.var_method = tk.StringVar(value=act.get("method", "AUTO"))
        self.var_reason = tk.StringVar(value=str(act.get("reason", "5")))

        def row(r, label, widget):
            ttk.Label(grid, text=label).grid(row=r, column=0, sticky="w", padx=6, pady=4)
            widget.grid(row=r, column=1, sticky="ew", padx=6, pady=4)

        row(0, "Имя (FirstName)", ttk.Entry(grid, textvariable=self.var_first))
        row(1, "Фамилия (LastName)", ttk.Entry(grid, textvariable=self.var_last))
        row(2, "Организация (Company)", ttk.Entry(grid, textvariable=self.var_company))
        row(3, "Страна/регион", ttk.Entry(grid, textvariable=self.var_country))

        ttk.Label(grid, text="Метод активации").grid(row=4, column=0, sticky="w", padx=6, pady=4)
        ttk.Combobox(grid, textvariable=self.var_method, values=["AUTO", "WEB", "PHONE"],
                     state="readonly", width=12).grid(row=4, column=1, sticky="w", padx=6, pady=4)
        row(5, "Причина (Reason)", ttk.Entry(grid, textvariable=self.var_reason))

        ttk.Label(tab, foreground="#555", justify="left", wraplength=760, padding=(12, 4),
                  text=("Метод AUTO (онлайн-активация), причина 5 = активация сервера впервые. "
                        "Заполняются FirstName/LastName/Company и страна; сведения об организации "
                        "пропускаются (мастер активации).")).pack(anchor="w", fill="x", pady=(8, 0))

        self.btn_activate = ttk.Button(tab, text="Активировать сервер лицензирования",
                                       command=self._activate)
        self.btn_activate.pack(anchor="w", padx=12, pady=10)

    def _activate(self):
        self._save_values_to_config()
        self.app.run_script(self, "activate_licensing.ps1", [
            "-FirstName", self.var_first.get(),
            "-LastName", self.var_last.get(),
            "-Company", self.var_company.get(),
            "-CountryRegion", self.var_country.get(),
            "-ConnectionMethod", self.var_method.get(),
            "-Reason", self.var_reason.get(),
        ], "Активация сервера лицензирования")

    # --- Лицензии ----------------------------------------------------------
    def _build_licensing(self, nb):
        tab = ttk.Frame(nb, padding=12)
        nb.add(tab, text="Лицензии (CAL)")

        grid = ttk.Frame(tab)
        grid.pack(fill="x")
        grid.columnconfigure(1, weight=1)

        lic = self.app.cfg.get("licensing", {})
        agr_code = int(lic.get("agreementType", "1"))
        self.var_agr_type = tk.StringVar(value=self._reverse(AGREEMENT_TYPES, agr_code,
                                                             "Enterprise (250+ компьютеров)"))
        self.var_agr_num = tk.StringVar(value=lic.get("agreementNumber", "6565793"))
        self.var_ver = tk.StringVar(value=str(lic.get("productVersion", "8")))
        pt_code = int(lic.get("productType", "0"))
        self.var_prod_type = tk.StringVar(value=self._reverse(PRODUCT_TYPES, pt_code,
                                                              "На устройство (Per Device)"))
        self.var_count = tk.StringVar(value=str(lic.get("licenseCount", "1000")))

        def row(r, label, widget):
            ttk.Label(grid, text=label).grid(row=r, column=0, sticky="w", padx=6, pady=4)
            widget.grid(row=r, column=1, sticky="ew", padx=6, pady=4)

        ttk.Label(grid, text="Программа лицензирования").grid(row=0, column=0, sticky="w", padx=6, pady=4)
        ttk.Combobox(grid, textvariable=self.var_agr_type,
                     values=list(AGREEMENT_TYPES.keys()), state="readonly"
                     ).grid(row=0, column=1, sticky="ew", padx=6, pady=4)
        row(1, "Номер соглашения", ttk.Entry(grid, textvariable=self.var_agr_num))
        row(2, "Версия продукта (код)", ttk.Entry(grid, textvariable=self.var_ver))
        ttk.Label(grid, text="Тип лицензии").grid(row=3, column=0, sticky="w", padx=6, pady=4)
        ttk.Combobox(grid, textvariable=self.var_prod_type,
                     values=list(PRODUCT_TYPES.keys()), state="readonly"
                     ).grid(row=3, column=1, sticky="ew", padx=6, pady=4)
        row(4, "Кол-во лицензий", ttk.Entry(grid, textvariable=self.var_count))

        ttk.Label(tab, foreground="#555", justify="left", wraplength=760, padding=(12, 4),
                  text=("Код версии продукта: 4 = 2012/2012 R2, 5 = 2016, 6 = 2019, 7 = 2022, "
                        "8 = 2025. Тип «на устройство» = Per Device (0); «на пользователя» = "
                        "Per User (1).")).pack(anchor="w", fill="x", pady=(8, 0))

        self.btn_install_cals = ttk.Button(tab, text="Установить лицензии",
                                           command=self._install_cals)
        self.btn_install_cals.pack(anchor="w", padx=12, pady=10)

    def _install_cals(self):
        self._save_values_to_config()
        agr = AGREEMENT_TYPES.get(self.var_agr_type.get(), 1)
        ptype = PRODUCT_TYPES.get(self.var_prod_type.get(), 0)
        self.app.run_script(self, "install_cals.ps1", [
            "-AgreementType", str(agr),
            "-AgreementNumber", self.var_agr_num.get(),
            "-ProductVersion", self.var_ver.get(),
            "-ProductType", str(ptype),
            "-LicenseCount", self.var_count.get(),
        ], "Установка лицензий RDS CAL")

    # --- Локальные политики ------------------------------------------------
    def _build_policy(self, nb):
        tab = ttk.Frame(nb, padding=12)
        nb.add(tab, text="Локальные политики")

        grid = ttk.Frame(tab)
        grid.pack(fill="x")
        grid.columnconfigure(1, weight=1)

        pol = self.app.cfg.get("rdsPolicy", {})
        self.var_lic_srv = tk.StringVar(value=pol.get("licenseServers", "localhost"))
        mode = int(pol.get("licensingMode", "2"))
        self.var_lic_mode = tk.StringVar(value=self._reverse(LICENSING_MODES, mode,
                                                             "На устройство (Per Device)"))

        ttk.Label(grid, text="Серверы лицензирования").grid(row=0, column=0, sticky="w", padx=6, pady=4)
        ttk.Entry(grid, textvariable=self.var_lic_srv).grid(row=0, column=1, sticky="ew", padx=6, pady=4)
        ttk.Label(grid, text="Режим лицензирования").grid(row=1, column=0, sticky="w", padx=6, pady=4)
        ttk.Combobox(grid, textvariable=self.var_lic_mode,
                     values=list(LICENSING_MODES.keys()), state="readonly"
                     ).grid(row=1, column=1, sticky="ew", padx=6, pady=4)

        ttk.Label(tab, foreground="#555", justify="left", wraplength=760, padding=(12, 4),
                  text=("Эквивалент gpedit.msc: Компьютерная конфигурация > Административные "
                        "шаблоны > Компоненты Windows > Службы удалённых рабочих столов > "
                        "Узел сеансов удалённого рабочего стола > Лицензирование. Записывается "
                        "в HKLM\\SOFTWARE\\Policies\\Microsoft\\Windows NT\\Terminal Services "
                        "(LicenseServers, LicensingMode). Локальная политика имеет приоритет над "
                        "настройками RDMS.")).pack(anchor="w", fill="x", pady=(8, 0))

        self.btn_apply_policy = ttk.Button(tab, text="Применить политики",
                                           command=self._apply_policy)
        self.btn_apply_policy.pack(anchor="w", padx=12, pady=10)

    def _apply_policy(self):
        self._save_values_to_config()
        mode = LICENSING_MODES.get(self.var_lic_mode.get(), 2)
        self.app.run_script(self, "set_rds_policy.ps1", [
            "-LicenseServers", self.var_lic_srv.get(),
            "-LicensingMode", str(mode),
        ], "Применение локальных политик лицензирования RDS")

    # --- helpers ------------------------------------------------------------
    def _save_values_to_config(self):
        act = {
            "firstName": self.var_first.get(),
            "lastName": self.var_last.get(),
            "company": self.var_company.get(),
            "countryRegion": self.var_country.get(),
            "method": self.var_method.get(),
            "reason": str(int(self.var_reason.get() or 5)),
        }
        agr = AGREEMENT_TYPES.get(self.var_agr_type.get(), 1)
        ptype = PRODUCT_TYPES.get(self.var_prod_type.get(), 0)
        lic = {
            "agreementType": str(agr),
            "agreementNumber": self.var_agr_num.get(),
            "productVersion": str(int(self.var_ver.get() or 8)),
            "productType": str(ptype),
            "licenseCount": str(int(self.var_count.get() or 1000)),
        }
        mode = LICENSING_MODES.get(self.var_lic_mode.get(), 2)
        pol = {
            "licenseServers": self.var_lic_srv.get(),
            "licensingMode": str(mode),
        }
        self.app.set_config("activation", act)
        self.app.set_config("licensing", lic)
        self.app.set_config("rdsPolicy", pol)

    @staticmethod
    def _reverse(mapping, code, default):
        for label, val in mapping.items():
            if val == code:
                return label
        return default
