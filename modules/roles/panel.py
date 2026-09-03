#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Модуль: Роли и компоненты Windows Server.

Здесь выводится ПОЛНЫЙ список всех доступных ролей и компонентов прямо с сервера
(Get-WindowsFeature). Пользователь отмечает галочками нужное и установливает через
Install-WindowsFeature. Есть группировка (роли / компоненты), живой поиск по имени
и статус (установлено / не установлено).

Скрипты:
  * get_features.ps1  — список всех ролей/компонентов (JSON);
  * install_roles.ps1 — установка выбранных.
"""

import json
import tkinter as tk
from tkinter import ttk, messagebox

from framework import BasePanel

CHECK_ON = "\u2611"   # ☑
CHECK_OFF = "\u2610"  # ☐


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
        self.features = []      # кэш всех объектов {Name, DisplayName, ...}
        self.checked = {}       # name -> True

        # --- Панель инструментов -------------------------------------------
        bar = ttk.Frame(parent, padding=(10, 8, 10, 4))
        bar.pack(side="top", fill="x")

        self.btn_refresh = ttk.Button(bar, text="Загрузить список (с сервера)",
                                      command=self._load)
        self.btn_refresh.pack(side="left")
        self.btn_install = ttk.Button(bar, text="Установить выбранные", command=self._install)
        self.btn_install.pack(side="left", padx=6)
        self.var_mgmt = tk.BooleanVar(value=self.app.cfg.get("roles", {}).get("includeMgmtTools", "0") == "1")
        ttk.Checkbutton(bar, text="Средства управления",
                        variable=self.var_mgmt).pack(side="left")
        self.btn_all = ttk.Button(bar, text="Выбрать всё", command=self._select_all)
        self.btn_all.pack(side="left", padx=6)
        self.btn_none = ttk.Button(bar, text="Снять всё", command=self._select_none)
        self.btn_none.pack(side="left")

        # --- Строка поиска ---------------------------------------------------
        srow = ttk.Frame(parent, padding=(10, 4, 10, 2))
        srow.pack(side="top", fill="x")
        ttk.Label(srow, text="Поиск:").pack(side="left")
        self.var_search = tk.StringVar()
        ent = ttk.Entry(srow, textvariable=self.var_search)
        ent.pack(side="left", fill="x", expand=True, padx=6)
        ent.bind("<KeyRelease>", lambda e: self._rebuild())
        self.lbl_count = ttk.Label(srow, text="")
        self.lbl_count.pack(side="right", padx=4)

        # --- Дерево ----------------------------------------------------------
        cols = ("chk", "name", "status")
        self.tree = ttk.Treeview(parent, show="tree headings", columns=cols, selectmode="browse")
        self.tree.heading("#0", text="Компонент")
        self.tree.heading("chk", text="")
        self.tree.heading("name", text="Имя (код)")
        self.tree.heading("status", text="Статус")
        self.tree.column("#0", width=340, anchor="w")
        self.tree.column("chk", width=46, anchor="center")
        self.tree.column("name", width=200, anchor="w")
        self.tree.column("status", width=110, anchor="w")
        self.tree.tag_configure("header", foreground="#0070c0", font=("Segoe UI", 10, "bold"))
        self.tree.tag_configure("installed", foreground="#0a7a2f")
        self.tree.tag_configure("notinst", foreground="#333")
        self.tree.pack(side="top", fill="both", expand=True, padx=10, pady=(2, 10))
        self.tree.bind("<Button-1>", self._on_click)

        # --- нижняя строка с подсказкой -------------------------------------
        self.lbl_hint = ttk.Label(parent, foreground="#555", anchor="w", padding=(12, 0, 12, 6),
                                  text="Клик по строке — отметить/снять галочку. "
                                       "Загрузка списка идёт с сервера через Get-WindowsFeature.")
        self.lbl_hint.pack(side="bottom", fill="x")

        self._load()

    # ------------------------------------------------------------------ данные
    def _load(self):
        self.lbl_hint.config(text="Загрузка списка ролей/компонентов...")
        self.app.status_var.set("Загрузка списка ролей/компонентов...")
        # keep any user's selected checks across reloads
        self.app.run_capture(self, "get_features.ps1", [], self._on_data)

    def _on_data(self, payload):
        rc, out, err = payload
        if rc != 0:
            self.lbl_hint.config(text="Не удалось получить список ролей. Проверьте, что вы "
                                      "администратор и роль ServerManager доступна.")
            self.app._append_log(f"\n[Ошибка получения списка ролей] rc={rc}\n{out}\n{err}\n")
            messagebox.showerror("Ошибка",
                                 "Не удалось получить список ролей/компонентов.\n"
                                 "Скрипт get_features.ps1 завершился с ошибкой.")
            return
        try:
            data = json.loads(out.strip())
        except Exception as e:
            self.lbl_hint.config(text="Не удалось разобрать список ролей.")
            self.app._append_log(f"\n[Ошибка разбора JSON]: {e}\n{out}\n")
            return
        if not isinstance(data, list):
            data = [data]
        # убрать записи без имени
        self.features = [f for f in data if isinstance(f, dict) and f.get("Name")]
        self.checked = {name: True for name in self.checked if self._exists(name)}
        self._rebuild()
        installed = sum(1 for f in self.features if f.get("Installed"))
        if self.features:
            self.lbl_hint.config(text=f"Всего: {len(self.features)} (установлено: {installed}). "
                                      "Клик по строке — отметить/снять галочку.")
            self.lbl_count.config(text=f"Отмечено: {sum(self.checked.values())} / {len(self.features)}")
        else:
            self.lbl_hint.config(
                text="Список ролей/компонентов пуст. Это типично для клиентской Windows "
                     "(Home/Pro/Enterprise): командлет Get-WindowsFeature доступен на "
                     "Windows Server. На сервере/виртуалке список заполнится автоматически.")
        self.app.status_var.set("Список ролей загружен.")

    def _exists(self, name):
        return any(f.get("Name") == name for f in self.features)

    # ------------------------------------------------------------------ дерево
    def _rebuild(self):
        tree = self.tree
        tree.delete(*tree.get_children())
        query = self.var_search.get().strip().lower()

        def match(f):
            if not query:
                return True
            return query in (f.get("Name") or "").lower() or query in (f.get("DisplayName") or "").lower()

        groups = {}
        for f in self.features:
            if match(f):
                groups.setdefault(f.get("FeatureType") or "Other", []).append(f)

        total = 0
        for group in sorted(groups.keys()):
            feats = groups[group]
            label = {"Role": "Роли", "Feature": "Компоненты"}.get(group, group)
            parent = tree.insert("", "end", text=f"{label}  ({len(feats)})",
                                 values=("", "", ""), open=True, tags=("header",))
            for f in feats:
                name = f.get("Name")
                chk = CHECK_ON if self.checked.get(name) else CHECK_OFF
                status = "установлено" if f.get("Installed") else "не установлено"
                tag = "installed" if f.get("Installed") else "notinst"
                item_text = f.get("DisplayName") or name
                tree.insert(parent, "end", iid="f:" + name, text=item_text,
                            values=(chk, name, status), tags=("item", tag))
                total += 1
        self.lbl_count.config(text=f"Отмечено: {sum(self.checked.values())} / {total}")

    def _on_click(self, event):
        iid = self.tree.identify_row(event.y)
        if not iid:
            return
        tags = tuple(self.tree.item(iid, "tags") or ())
        if "item" not in tags:
            # Group header: toggle collapse/expand
            if "header" in tags:
                if self.tree.item(iid, "open"):
                    self.tree.item(iid, open=False)
                else:
                    self.tree.item(iid, open=True)
            return
        # extract feature name from iid (prefixed "f:")
        name = iid.split(":", 1)[1]
        self.checked[name] = not self.checked.get(name, False)
        self.tree.item(iid, values=(CHECK_ON if self.checked[name] else CHECK_OFF,
                                    name, "установлено" if self._installed(name) else "не установлено"))
        self.lbl_count.config(text=f"Отмечено: {sum(self.checked.values())}")

    def _installed(self, name):
        for f in self.features:
            if f.get("Name") == name:
                return bool(f.get("Installed"))
        return False

    # ------------------------------------------------------------------ управление
    def _select_all(self):
        self.checked = {f.get("Name"): True for f in self.features}
        self._rebuild()

    def _select_none(self):
        self.checked = {}
        self._rebuild()

    def _install(self):
        selected = [n for n, v in self.checked.items() if v]
        if not selected:
            messagebox.showinfo("Роли", "Не выбрано ни одной роли/компонента.")
            return
        if messagebox.askyesno("Установка", f"Установить выбранные роли/компоненты?\n\n"
                                            f"Выбрано: {len(selected)}"):
            self.app.set_config("roles", {"includeMgmtTools": "1" if self.var_mgmt.get() else "0"})
            args = ["-Features"] + selected
            if self.var_mgmt.get():
                args.append("-IncludeManagementTools")
            self.app.run_script(self, "install_roles.ps1", args,
                                "Установка ролей и компонентов")
