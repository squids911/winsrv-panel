# Инструкция: автосборка EXE из репозитория через GitHub Actions

Эта инструкция нужна, чтобы **в любом новом чате (Arena.ai)** дать агенту доступ к
GitHub и настроить автоматическую сборку EXE из нужного репозитория *на Windows
Server 2025*.

> **Главное понимание.** Токен и настройки **не передаются между чатами**
> автоматически. Каждый чат — отдельная изолированная среда (свой `gh`, своя
> папка, свой `~/.config/gh/hosts.yml`). Поэтому в новом чате нужно повторить
> шаги ниже — вставить токен и настроить git заново.

---

## 1. Что нужно от вас (создать токен)

Самый безопасный вариант — **Fine-grained token только на нужный репозиторий**, а
не на весь аккаунт.

1. GitHub → **Settings → Developer settings → Personal access tokens →
   Fine-grained tokens → Generate new token**.
2. **Resource owner:** `squids911` (ваш аккаунт).
3. **Repository access:** только нужный репозиторий (например, `winsrv-panel`).
4. **Permissions** (минимально необходимые):
   - **Contents** — Read and write
   - **Workflows** — Read and write
   - **Actions** — Read (чтобы скачивать artifact)
   - **Metadata** — Read (включается автоматически)
5. **Expiration** — длинный срок (или no expiration), иначе доступ потеряется.
6. Скопируйте токен (он показывается один раз).

> Если хотите доступ «ко всему» — создайте **Classic token** с правами
> `repo`, `workflow`, `gist`, `read:org`. Но для работы достаточно fine-grained
> токена на конкретный репозиторий.

---

## 2. Команды, которые надо дать агенту (вставить токен)

Скопируйте этот блок в другой чат, заменив `ВАШ_ТОКЕН` и `НАЗВАНИЕ_РЕПО`:

```bash
# (a) Установить GitHub CLI, если его нет
(gh --version >/dev/null 2>&1 || sudo apt-get install -y gh)

# (b) Войти с токеном — передаётся через stdin, не попадает в историю
printf '%s' 'ВАШ_ТОКЕН' | gh auth login --hostname github.com --git-protocol https --with-token

# (c) Настроить git credential helper
gh auth setup-git

# (d) Клонировать нужный репозиторий (или перейти в уже существующий)
git clone https://github.com/squids911/НАЗВАНИЕ_РЕПО.git
cd НАЗВАНИЕ_РЕПО

# (e) Задать git-идентичность
git config user.name  "squids911"
git config user.email "squids911@users.noreply.github.com"
```

Проверка, что всё действует:

```bash
gh auth status
git remote -v
git fetch origin main
```

---

## 3. Workflow для сборки EXE

Поместите файл в `.github/workflows/build.yml` **нужного репозитория**.

### 3.1 Для этого проекта (winsrv-panel — панель настройки Windows Server)

```yaml
name: Build EXE
on:
  push:
    branches: [ main ]
  pull_request:
  workflow_dispatch:
jobs:
  build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.12' }
      - run: pip install pyinstaller
      - shell: bash
        run: |
          python -m PyInstaller --noconfirm --clean --onefile --windowed \
            --name WinSrvPanel \
            --add-data "modules;modules" \
            --add-data "roles.json;." \
            gui.py
      - uses: actions/upload-artifact@v4
        with:
          name: WinSrvPanel
          path: dist/WinSrvPanel.exe
          if-no-files-found: error
```

### 3.2 Универсальный шаблон (для любого Python-проекта, собираемого в exe)

Поправьте только `--name` и `--add-data` под свой проект (точка с запятой —
разделитель пути для Windows-раннера; для мак/линукс было бы `:`).

```yaml
name: Build EXE
on:
  push:
    branches: [ main ]
  pull_request:
  workflow_dispatch:
jobs:
  build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.12' }
      - run: pip install pyinstaller
      - shell: bash
        run: |
          python -m PyInstaller --noconfirm --clean --onefile --windowed \
            --name ИмяПрограммы \
            --add-data "modules;modules" \
            --add-data "assets;assets" \
            ваш_главный.py
      - uses: actions/upload-artifact@v4
        with:
          name: ИмяПрограммы
          path: dist/ИмяПрограммы.exe
          if-no-files-found: error
```

---

## 4. Запушить и проверить

```bash
git add -A
git commit -m "Add CI build workflow"
git push origin main
```

Что произойдёт:
1. GitHub подхватит workflow `Build EXE`.
2. На runner `windows-latest` установится Python 3.12 + PyInstaller.
3. Соберётся exe и выложится как **artifact** (блок **Artifacts** на странице
   запуска, внизу справа).
4. Смотреть запуски: **Actions → Build EXE**.
5. Запустить вручную: **Actions → Build EXE → Run workflow** (работает благодаря
   `workflow_dispatch`).

---

## 5. Как скачать результат

- Открыть: `https://github.com/squids911/НАЗВАНИЕ_РЕПО/actions`
- Выбрать **Build EXE** → последний успешный запуск → **Artifacts → WinSrvPanel**
  → скачать ZIP, внутри `.exe`.
- Или из чата попросить агента: `gh run download` / `gh api .../artifacts`.

---

## 6. Про сохранение доступа между сессиями

Среда снапшотит **файлы проекта** и `~/.config/gh/hosts.yml` (где живёт токен), но
**сбрасывает** установленный `gh` и **`.git/config`** (remote, identity). Поэтому
удобно держать в репозитории скрипт `setup_git.sh`, который восстанавливает всё
одной командой.

Пример (адаптируйте под свой репозиторий):

```bash
# в корне репозитория: setup_git.sh
#!/usr/bin/env bash
set -u
REPO_URL="https://github.com/squids911/НАЗВАНИЕ_РЕПО.git"
REPO_USER="squids911"
REPO_EMAIL="squids911@users.noreply.github.com"

# 1) gh
command -v gh >/dev/null 2>&1 || sudo apt-get install -y gh
# 2) auth (если уже есть токен в ~/.config/gh/hosts.yml — просто покажет его)
gh auth status >/dev/null 2>&1 || echo "No gh auth. Run: printf '%s' 'ТОКЕН' | gh auth login ... --with-token"
gh auth setup-git
# 3) identity + remote
git config user.name  "$REPO_USER"
git config user.email "$REPO_EMAIL"
git remote remove origin 2>/dev/null
git remote add origin "$REPO_URL"
# 4) sync
git fetch origin main
```

Сохраните его в репозитории и закоммитьте. В новом чате после клонирования
достаточно запустить `bash setup_git.sh`.

---

## 7. Частые вопросы

**Нужен ли токен, чтобы CI сам собирался?**
Нет. Workflow собирается от встроенного токена GitHub Actions. Токен от вас нужен
агенту (чату) только чтобы **пушить** файлы (в т.ч. `.github/workflows/`) и
читать/скачивать artifacts. Если workflow уже лежит в репозитории — CI работает и
без вашего токена.

**Почему `gh` пропадает между сессиями?**
Среда сбрасывает установленные пакеты. `sudo apt-get install -y gh` решает это;
токен при этом сохраняется в `~/.config/gh/hosts.yml`.

**Почему репозиторий не пушится?**
Часто — удалённый `origin` сброшен (`.git/config` не снапшотится). Пересоздайте
`git remote add origin <URL>` (см. шаг 2 / setup_git.sh).

**Как чинить кириллицу в выводе PowerShell?**
Добавьте в начало каждого `.ps1`:
```powershell
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$OutputEncoding = [System.Text.Encoding]::UTF8
```
И держите `.ps1` строго в ASCII (ни один символ выше 127), иначе PowerShell 5.1 без
BOM его неверно прочитает.

**Локальный запуск без сборки:**
```bat
pip install pyinstaller
build.bat
```
→ `dist\WinSrvPanel.exe`.

---

## 8. Полезные команды агента

```bash
# список последних запусков CI
gh run list --workflow build.yml --limit 5

# дождаться завершения конкретного запуска
gh run watch <RUN_ID> --exit-status

# скачать артефакт в текущую папку
gh run download <RUN_ID> --name WinSrvPanel

# посмотреть содержимое артефакта
gh api repos/squids911/НАЗВАНИЕ_РЕПО/actions/artifacts
```
