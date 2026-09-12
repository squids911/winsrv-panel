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
        self.btn_install = ttk.Button(bar, text="Установить выбранные", command=self._install, style="Accent.TButton")
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

        # --- Список (слева) + описание (справа), как в Server Manager -------
        pane = ttk.Panedwindow(parent, orient="horizontal")
        pane.pack(side="top", fill="both", expand=True, padx=10, pady=(2, 6))

        cols = ("chk", "name", "status")
        tree_wrap = ttk.Frame(pane)
        self.tree = ttk.Treeview(tree_wrap, show="tree headings", columns=cols, selectmode="browse")
        vsb = ttk.Scrollbar(tree_wrap, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=vsb.set)
        self.tree.heading("#0", text="Компонент")
        self.tree.heading("chk", text="")
        self.tree.heading("name", text="Имя (код)")
        self.tree.heading("status", text="Статус")
        self.tree.column("#0", width=320, anchor="w")
        self.tree.column("chk", width=42, anchor="center")
        self.tree.column("name", width=190, anchor="w")
        self.tree.column("status", width=105, anchor="w")
        self.tree.tag_configure("header", foreground="#e8590c", font=("Segoe UI", 10, "bold"))
        self.tree.tag_configure("installed", foreground="#2f9e44")
        self.tree.tag_configure("notinst", foreground="#495057")
        vsb.pack(side="right", fill="y")
        self.tree.pack(side="left", fill="both", expand=True)
        pane.add(tree_wrap, weight=3)
        self.tree.bind("<Button-1>", self._on_click)
        self.tree.bind("<<TreeviewSelect>>", self._on_select)

        # правая панель описания выбранного компонента
        dframe = ttk.LabelFrame(pane, text="Описание", padding=6)
        pane.add(dframe, weight=2)
        self.details = tk.Text(dframe, wrap="word", state="disabled", relief="flat",
                               font=("Segoe UI", 9))
        self.details.pack(fill="both", expand=True)

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
            data = json.loads(self._extract_json(out))
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

    @staticmethod
    def _extract_json(out):
        """Извлекает JSON-подстроку из вывода скрипта, отбрасывая любой
        посторонний текст до первой '{'/'[' и после последней '}'/']'.
        Защищает разбор, если PowerShell что-то печатает перед JSON
        (например, предупреждения или лишние строки)."""
        text = (out or "").strip()
        # убрать BOM, если вдруг попал
        text = text.lstrip("\ufeff")
        starts = [i for i in (text.find("["), text.find("{")) if i != -1]
        if not starts:
            return text
        start = min(starts)
        end = max(text.rfind("]"), text.rfind("}"))
        if end > start:
            return text[start:end + 1]
        return text[start:]

    def _exists(self, name):
        return any(f.get("Name") == name for f in self.features)

    # ------------------------------------------------------------------ дерево
    def _rebuild(self):
        """Дерево как в Server Manager: сверху группы "Роли"/"Компоненты",
        внутри — иерархия родитель->подкомпоненты (по полю Parent), всё по
        алфавиту. При непустом поиске показывается плоский список совпадений."""
        tree = self.tree
        tree.delete(*tree.get_children())
        query = self.var_search.get().strip().lower()

        def match(f):
            if not query:
                return True
            return query in (f.get("Name") or "").lower() or query in (f.get("DisplayName") or "").lower()

        by_name = {f.get("Name"): f for f in self.features if f.get("Name")}

        def display(f):
            return f.get("DisplayName") or f.get("Name")

        def row_values(f):
            name = f.get("Name")
            chk = CHECK_ON if self.checked.get(name) else CHECK_OFF
            status = "установлено" if f.get("Installed") else "не установлено"
            tag = "installed" if f.get("Installed") else "notinst"
            return chk, status, tag

        # карта детей: parent_name -> [feature, ...]
        children = {}
        tops = []
        for f in self.features:
            p = (f.get("Parent") or "").strip()
            if p and p != f.get("Name") and p in by_name:
                children.setdefault(p, []).append(f)
            else:
                tops.append(f)

        def insert_node(parent_iid, f):
            name = f.get("Name")
            chk, status, tag = row_values(f)
            iid = "f:" + name
            tree.insert(parent_iid, "end", iid=iid, text=display(f),
                        values=(chk, name, status), tags=("item", tag))
            for child in sorted(children.get(name, []), key=lambda c: display(c).lower()):
                insert_node(iid, child)

        total = 0
        if query:
            # плоский список совпадений при поиске
            for f in sorted((f for f in self.features if match(f)),
                            key=lambda c: display(c).lower()):
                chk, status, tag = row_values(f)
                tree.insert("", "end", iid="f:" + f.get("Name"), text=display(f),
                            values=(chk, f.get("Name"), status), tags=("item", tag))
                total += 1
        else:
            # иерархия: сначала "Роли" (Role), затем "Компоненты" (Feature)
            groups = {}
            for f in tops:
                groups.setdefault(f.get("FeatureType") or "Other", []).append(f)
            group_order = {"Role": 0, "Feature": 1}
            for group in sorted(groups.keys(), key=lambda g: (group_order.get(g, 2), g)):
                feats = groups[group]
                label = {"Role": "Роли", "Feature": "Компоненты"}.get(group, group)
                header = tree.insert("", "end", text=f"{label}  ({len(feats)})",
                                     values=("", "", ""), open=True, tags=("header",))
                for f in sorted(feats, key=lambda c: display(c).lower()):
                    insert_node(header, f)
            total = len(self.features)
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

    def _on_select(self, _event=None):
        """Показывает описание выбранного компонента в правой панели."""
        sel = self.tree.selection()
        self.details.configure(state="normal")
        self.details.delete("1.0", "end")
        if not sel:
            self.details.configure(state="disabled")
            return
        iid = sel[0]
        if "f:" not in iid:
            self.details.configure(state="disabled")
            return
        name = iid.split(":", 1)[1]
        feat = next((f for f in self.features if f.get("Name") == name), None)
        if not feat:
            self.details.configure(state="disabled")
            return
        status = "установлено" if feat.get("Installed") else "не установлено"
        lines = [
            ("Имя", feat.get("DisplayName") or name),
            ("Код", name),
            ("Тип", {"Role": "Роль", "Feature": "Компонент"}.get(feat.get("FeatureType"), feat.get("FeatureType") or "-")),
            ("Статус", status),
            ("Путь", feat.get("Path") or "-"),
            ("", ""),
            ("Описание", feat.get("Description") or "—"),
        ]
        for label, value in lines:
            if label:
                self.details.insert("end", f"{label}: ", "bold")
            self.details.insert("end", f"{value}\n")
        self.details.tag_configure("bold", font=("Segoe UI", 9, "bold"))
        self.details.configure(state="disabled")

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
            # PS 5.1 + -File quirk: extra positional values do NOT bind to a
            # [string[]] param (ValueFromRemainingArguments is ignored), so a
            # multi-select like DHCP+DNS failed with PositionalParameterNotFound
            # on the 2nd value. Pass ONE comma-joined string; the script splits.
            args = ["-Features", ",".join(selected)]
            if self.var_mgmt.get():
                args.append("-IncludeManagementTools")
            self.app.run_script(self, "install_roles.ps1", args,
                                "Установка ролей и компонентов")
