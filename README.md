# Панель настройки Windows Server 2025

![Python](https://img.shields.io/badge/Python-3.8+-blue)
![License](https://img.shields.io/badge/License-MIT-green)
![Build](https://github.com/squids911/winsrv-panel/actions/workflows/build.yml/badge.svg)

Модульная панель на **Python (Tkinter)** + **PowerShell**. Это **не только RDS** —
это каркас для настройки самых разных параметров Windows Server. RDS — один из
разделов (модулей), остальные добавляются простым созданием папки.

## Интерфейс
* **Слева** — дерево категорий (разделы).
* **Справа** — форма выбранного раздела.
* **Снизу** — журнал (вывод PowerShell в реальном времени).
* Значения меняются **прямо в интерфейсе**. Кнопка «Сохранить настройки» пишет их
  в **реестр Windows**.

## Где хранятся настройки
Ответ на «хранить всё внутри exe»:

* **Умолчания** (значения из вашего ТЗ) **компилируются в exe** — они заданы в
  схемах модулей (`CONFIG_SCHEMA` в каждом `modules/<id>/panel.py`).
* **Изменения** из интерфейса сохраняются в **реестр Windows**:
  `HKCU\Software\WinSrvPanel\<секция>` (по одному значению на параметр).
* При следующем старте программа читает сохранённые значения из реестра, а если
  их нет — использует встроенные умолчания.
* **Никакого внешнего `config.ini` рядом с exe не создаётся** — внешних файлов
  настроек нет.

> Почему не «прямо внутрь файла exe»? Однофайловый exe (PyInstaller `--onefile`)
> при запуске читает сам себя и распаковывается во временную папку — файл при
> этом заблокирован, и дописывать в него во время работы нельзя. Поэтому
> изменяемые значения живут в реестре, а статичные умолчания — внутри exe.

Кнопка **«Сбросить настройки»** удаляет сохранённые значения из реестра и
возвращает встроенные умолчания.

## Архитектура (модули)
Каждый раздел — отдельная папка `modules/<id>/`:

```
modules/<id>/panel.py            # class Panel(BasePanel): CONFIG_SCHEMA + build()
modules/<id>/scripts/*.ps1       # PowerShell-скрипты
```

Ядро (`gui.py` + `framework.py`) само сканирует `modules/`, находит классы
`Panel`, добавляет их в дерево и строит форму. **Чтобы добавить раздел — создайте
папку с `panel.py` и своими скриптами. Ядро не трогаем.**

Уже есть разделы:

| id | Порядок | Раздел | Содержимое |
|----|--------|--------|------------|
| `roles` | 10 | Роли и компоненты | Галочки ролей + `Install-WindowsFeature` (список — `roles.json`) |
| `system` | 20 | Система | Сведения о сервере, активация Windows (`slmgr`) |
| `network` | 30 | Сеть | Список адаптеров, статический IP/DNS |
| `rds` | 40 | Remote Desktop Services | Активация лицензирования, установка CAL (Enterprise), локальные политики |
| `rdscollections` | 45 | RDS — коллекции | Список и создание RD Session Collections (`New-RDSessionCollection`) |
| `security` | 50 | Безопасность | Сводка (RDP, брандмауэр, группа Remote Desktop Users) |
| `ad` | 55 | Active Directory | Установка AD DS, повышение до контроллера домена |
| `services` | 60 | Службы | Список служб, запуск/остановка/перезапуск |
| `localusers` | 65 | Пользователи и группы | Список, создание пользователя, добавление в группу (в т.ч. Remote Desktop Users) |
| `disks` | 75 | Диски и тома | Список дисков/томов, расширение тома |

RDS внутри имеет под-вкладки: **Активация**, **Лицензии (CAL)**, **Локальные политики**.

## Значения по умолчанию (встроены в exe)
```ini
[activation]
firstName = 1            ; Имя (мастер активации)
lastName = 1
company = 1
countryRegion = Belarus
method = AUTO            ; AUTO / WEB / PHONE
reason = 5               ; 5 = первая активация

[licensing]
agreementType = 1        ; 1 = Enterprise
agreementNumber = 6565793
productVersion = 8       ; 4=2012R2,5=2016,6=2019,7=2022,8=2025
productType = 0          ; 0 = на устройство, 1 = на пользователя
licenseCount = 1000

[rdsPolicy]
licenseServers = localhost
licensingMode = 2        ; 2 = на устройство, 4 = на пользователя

[system]
productKey =             ; ключ продукта Windows

[network]
adapter =                ; имя адаптера
ip =
prefixLength = 24
gateway =
dns =

[roles]
includeMgmtTools = 0     ; 0 = не ставить средства управления

[powershell]
exe = powershell         ; powershell или pwsh
```

## Компиляция в EXE
Требования: Python 3, PyInstaller (`pip install pyinstaller`).

```bat
build.bat
```
→ получится `dist\WinSrvPanel.exe`. В exe встраиваются `modules/` и `roles.json`.
Запуск **от имени администратора**.

## Запуск из исходников
```bat
run.bat
```
(или `python gui.py`, от имени администратора — скрипты сами проверяют права).

## Порядок действий (RDS)
1. **Роли и компоненты** → отметьте `Remote Desktop Licensing` (сервер
   лицензирования) и `Remote Desktop Session Host` (хост сеансов) → установить.
2. **RDS → Активация** → «Активировать сервер лицензирования».
3. **RDS → Лицензии (CAL)** → «Установить лицензии».
4. **RDS → Локальные политики** → «Применить политики», затем `gpupdate /force`.
5. Результат — в «Журнале». После установки ролей и CAL обычно нужна перезагрузка.

## Как добавить новый раздел
1. Создайте папку `modules/brandnew/scripts/`.
2. В `modules/brandnew/panel.py`:

```python
from framework import BasePanel

class Panel(BasePanel):
    id = "brandnew"
    title = "Новый раздел"
    order = 70
    CONFIG_SCHEMA = {"brandnew": {"param": ("", "Комментарий")}}

    def build(self, parent):
        # ttk-виджеты в parent
        # вызов PowerShell: self.app.run_script(self, "script.ps1", ["-arg","v"], "Заголовок")
```

3. PowerShell-скрипт — в `scripts/` (ASCII без кириллицы, чтобы оболочка 5.1 читала).
4. Перезапустите программу — раздел появится в дереве. Ядро не меняется.

## Структура проекта
```
winsrv-panel/
├─ gui.py                # главное окно: дерево + модули + журнал
├─ framework.py          # BasePanel, пути, реестровое хранилище, обнаружение модулей
├─ roles.json            # список ролей (встраивается в exe)
├─ roles.example.json    # примеры ролей
├─ run.bat               # запуск из исходников (от администратора)
├─ build.bat             # сборка WinSrvPanel.exe (PyInstaller)
├─ .github/workflows/    # CI: автосборка exe
├─ LICENSE               # MIT
├─ README.md
└─ modules/              # разделы (см. выше): roles, system, network, rds,
                         # rdscollections, security, ad, services, localusers, disks
```
Настройки в файле не хранятся — только в реестре `HKCU\Software\WinSrvPanel`
и во встроенных умолчаниях exe.

## Технические замечания
* **Активация RDS** — провайдер `RDS:\LicenseServer`, при сбое — фолбэк
  `Win32_TSLicenseServer.ActivateServerAutomatic`.
* **CAL** — `Win32_TSLicenseKeyPack.InstallAgreementLicenseKeyPack`
  (`ReturnValue == 0` = успех).
* **Политики** — реестр `HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal
  Services` (`LicenseServers`, `LicensingMode`).
* ⚠️ **Версия продукта `8` (Windows Server 2025)** выведена по последовательности.
  Если CAL даст ненулевой `ReturnValue`, проверьте актуальный код в Remote Desktop
  Licensing Manager и поправьте поле «Версия продукта» в интерфейсе. CAL 2025
  ставит только лицензионный сервер на WS 2025 (у вас так и есть).

## Автоматическая сборка EXE (GitHub Actions)

Workflow `.github/workflows/build.yml` при push в `main` (или вручную из вкладки
**Actions**) на runner `windows-latest` собирает `WinSrvPanel.exe` и публикует его
как **artifact**. Секреты/токены для этого не нужны — только сам репозиторий.

## Лицензия

Проект распространяется под лицензией **MIT** — см. файл `LICENSE`.
