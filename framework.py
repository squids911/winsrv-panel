#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
framework.py — базовые элементы модульной панели настройки Windows Server.

Содержит:
  * BasePanel — базовый класс для всех разделов (модулей).
  * Функции работы с путями (исходники vs PyInstaller EXE).
  * Хранилище настроек в РЕЕСТРЕ Windows (HKCU\\Software\\WinSrvPanel).
      - Умолчания компилируются в exe (схемы модулей);
      - изменения из GUI сохраняются в реестр и читаются при следующем старте;
      - никакого внешнего config.ini рядом с exe не создаётся.
  * Функции config.ini сохранены как опциональный экспорт/импорт (для разработки).
  * Обнаружение модулей (сканирование modules/*/panel.py).
"""

import configparser
import importlib.util
import inspect
import os
import sys

CREATE_NO_WINDOW = 0x08000000 if os.name == "nt" else 0

# Ключ реестра, где хранятся настройки (HKCU\Software\WinSrvPanel\<section>).
APP_REG_ROOT = "Software\\WinSrvPanel"


# --------------------------------------------------------------------- пути
def get_app_dir():
    """Каталог запускаемого файла (exe или .py)."""
    if getattr(sys, "frozen", False):
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.abspath(__file__))


def get_resource_dir():
    """Каталог со встроенными ресурсами (modules/, roles.json)."""
    if getattr(sys, "frozen", False):
        return getattr(sys, "_MEIPASS", os.path.dirname(sys.executable))
    return os.path.dirname(os.path.abspath(__file__))


# --------------------------------------------------------------------- реестр
def _winreg():
    try:
        import winreg  # доступен только на Windows
        return winreg
    except Exception:
        return None


def registry_read(schema):
    """Читает настройки из реестра в {section: {key: value}}.

    Отсутствующие ключи берутся из умолчаний схемы. Вне Windows (разработка)
    возвращает просто умолчания схемы (сохранение недоступно).
    """
    cfg = {section: {k: v[0] for k, v in items.items()}
           for section, items in schema.items()}  # значения = умолчания
    wr = _winreg()
    if wr is None:
        return cfg
    for section in cfg:
        path = APP_REG_ROOT + "\\" + section
        try:
            key = wr.OpenKey(wr.HKEY_CURRENT_USER, path)
        except OSError:
            continue
        try:
            for k in cfg[section]:
                try:
                    val, _ = wr.QueryValueEx(key, k)
                    cfg[section][k] = str(val)
                except OSError:
                    pass
        finally:
            wr.CloseKey(key)
    return cfg


def registry_write(cfg):
    """Сохраняет настройки в реестр (по секциям). Возвращает True при успехе."""
    wr = _winreg()
    if wr is None:
        return False
    for section, items in cfg.items():
        path = APP_REG_ROOT + "\\" + section
        try:
            key = wr.CreateKeyEx(wr.HKEY_CURRENT_USER, path, 0, wr.KEY_SET_VALUE)
        except OSError:
            continue
        try:
            for k, v in items.items():
                wr.SetValueEx(key, k, 0, wr.REG_SZ, str(v))
        finally:
            wr.CloseKey(key)
    return True


def registry_clear(schema):
    """Удаляет сохранённые настройки (возврат к умолчаниям)."""
    wr = _winreg()
    if wr is None:
        return
    for section in schema:
        try:
            wr.DeleteKey(wr.HKEY_CURRENT_USER, APP_REG_ROOT + "\\" + section)
        except OSError:
            pass
    try:
        wr.DeleteKey(wr.HKEY_CURRENT_USER, APP_REG_ROOT)
    except OSError:
        pass


# --------------------------------------------------------------------- config.ini (экспорт/импорт, опционально)
def generate_ini(path, schema):
    """Записывает config.ini из схемы {section: {key: (default, comment)}}."""
    lines = ["; Windows Server - панель настройки", "; config.ini - значения по умолчанию", ""]
    for section, items in schema.items():
        lines.append(f"[{section}]")
        for key, (value, comment) in items.items():
            if comment:
                lines.append(f"; {comment}")
            lines.append(f"{key} = {value}")
        lines.append("")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def update_ini_in_place(path, updates):
    """Заменяет значения по ключам, сохраняя комментарии. unknown строки не трогаются."""
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except FileNotFoundError:
        lines = []
    out, cur = [], None
    sections_present, keys_present = set(), set()
    for line in lines:
        s = line.strip()
        if s.startswith("[") and s.endswith("]"):
            cur = s[1:-1].strip()
            sections_present.add(cur)
            out.append(line)
            continue
        if "=" in s and not s.startswith(";") and cur is not None:
            key = s.split("=", 1)[0].strip()
            if key in updates.get(cur, {}):
                out.append(f"{key} = {updates[cur][key]}")
                keys_present.add((cur, key))
                continue
        out.append(line)
    for section, keys in updates.items():
        if section not in sections_present:
            out.append(f"[{section}]")
        for key, value in keys.items():
            if (section, key) not in keys_present:
                out.append(f"{key} = {value}")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")


def read_config(path, schema):
    """Читает config.ini в dict; вставляет умолчания из схемы (для разработки)."""
    cfg = {section: {k: v[0] for k, v in items.items()}
           for section, items in schema.items()}
    cp = configparser.ConfigParser(interpolation=None)
    cp.read(path, encoding="utf-8")
    for section, items in schema.items():
        if cp.has_section(section):
            for key, (default, _c) in items.items():
                cfg[section][key] = cp.get(section, key, fallback=default)
    return cfg


# --------------------------------------------------------------------- модули
def discover_modules(modules_dir, base_cls):
    """Сканирует modules/*/panel.py и возвращает список классов-панелей (отсортировано)."""
    result = []
    if not os.path.isdir(modules_dir):
        return result
    for entry in sorted(os.listdir(modules_dir)):
        folder = os.path.join(modules_dir, entry)
        if not os.path.isdir(folder):
            continue
        panel_py = os.path.join(folder, "panel.py")
        if not os.path.exists(panel_py):
            continue
        try:
            spec = importlib.util.spec_from_file_location(f"rdsmod_{entry}", panel_py)
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
        except Exception as e:
            print(f"Failed to import module '{entry}': {e}")
            continue
        cls = None
        for name in dir(mod):
            obj = getattr(mod, name)
            if inspect.isclass(obj) and issubclass(obj, base_cls) and obj is not base_cls:
                cls = obj
                break
        if cls is None:
            continue
        cls.id = cls.id or entry
        cls.src_dir = folder
        cls.scripts_dir = os.path.join(folder, "scripts")
        result.append(cls)
    result.sort(key=lambda c: (c.order, c.title))
    return result


class BasePanel:
    """Базовый класс раздела. Подкласс задаёт:
       id      — уникальный идентификатор (папки модуля);
       title   — название в дереве;
       order   — порядок сортировки;
       CONFIG_SCHEMA — {section: {key: (default, comment)}} для настроек (умолчания в exe).
    """

    id = ""
    title = "Раздел"
    order = 100
    CONFIG_SCHEMA = {}
    src_dir = ""
    scripts_dir = ""

    def __init__(self, app):
        self.app = app

    def build(self, parent):
        """Создать виджеты панели в parent (ttk.Frame)."""
        raise NotImplementedError

    def on_show(self):
        """Вызывается при показе раздела."""
        pass
