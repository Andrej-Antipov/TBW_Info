# ⚡️ SSD Watch (macOS Menu Bar Utility)
---

## 🇺🇸 English Description

**SSD Watch** is an ultra-lightweight, native macOS system monitor that lives right in your Menu Bar. It provides real-time tracking of your SSD's second-by-second write speeds, cumulative data transfer volume, and overall health (Lifetime TBW). 

The app features full **English & Russian localization** using Apple's modern **String Catalog** system with a seamless environment hot-relaunch mechanism.

### 🎯 Key Features
* **Ultra-Compact UI**: Minimalist 360x220px interface optimized to avoid workspace clutter.
* **Live Dynamic Chart**: High-performance SwiftUI graph with an adaptive auto-scaling Y-axis that responds perfectly to extreme write loads (up to 4 GB/s+).
* **0.0% Idle CPU Overhead**: Energy-efficient architecture. The high-frequency second-by-second `iostat` polling is strictly passive and triggers only when the popover graph window is open.
* **Dual-Click Architecture**: Left click triggers the live popover graph; right click drops a native context menu.
* **S.M.A.R.T. Diagnostics Window**: Deep on-demand extraction of full raw NVMe telemetry (serial numbers, temperature logs, health health logs) via an isolated standalone window.
* **Clean Menu Bar Tooltip**: Strict non-intrusive hovering tooltip stripped of rapid fluctuations, showing only cumulative session bytes and overall lifetime wear.

### 📦 Build & Installation
1. Clone the repository to your local Mac.
2. Ensure you have the universal binary version of `smartctl` added to your main application resources.
3. Open `SSDWatch.xcodeproj` in Xcode 16+.
4. ⚠️ **Important**: Go to *Signing & Capabilities* and **remove App Sandbox** (required to allow the application to execute background tasks and fetch telemetry values).
5. Press `Cmd + R` to compile, log, and run.

---

## 🇷🇺 Описание на русском

**SSD Watch** — это ультра-легковесный, нативный системный монитор для строки меню macOS. Приложение обеспечивает посекундный мониторинг реальной скорости записи на диски, ведет точный учет переданного объема данных за сессию и контролирует суммарный пожизненный износ накопителя (Lifetime TBW).

Утилита поддерживает **полную русскую и английскую локализацию** на базе современной системы **String Catalog** от Apple с возможностью бесшовного переключения интерфейса на лету.

### 🎯 Ключевые возможности
* **Ультра-компактный дизайн**: Минималистичное окно размером всего 360x220 пикселей, не занимающее лишнего пространства на экране.
* **Умный живой график**: Высокопроизводительный SwiftUI-компонент с адаптивной шкалой Y, мгновенно подстраивающейся под экстремальные пики записи (вплоть до 4 ГБ/с и выше).
* **0.0% нагрузки на CPU в простое**: Максимальная энергоэффективность. Высокочастотный посекундный опрос `iostat` полностью «спит» и активируется только в те моменты, когда окно графика открыто пользователем.
* **Раздельные клики**: Левый клик вызывает всплывающее окно с графиками; правый — нативное контекстное меню AppKit.
* **Окно S.M.A.R.T. диагностики**: Углубленный вывод полной текстовой телеметрии NVMe-контроллера (серийные номера, температура, логи ошибок) в отдельном просторном окне по требованию (On-Demand).
* **Лаконичный тултип**: Строгая всплывающая подсказка при наведении мыши, очищенная от постоянно прыгающих цифр скорости, показывающая только накопленные гигабайты за сессию и общий износ.

### 📦 Сборка и запуск
1. Склонируйте репозиторий на ваш Mac.
2. Убедитесь, что универсальная (Universal Binary) версия утилиты `smartctl` упакована внутрь ресурсов проекта.
3. Откройте проект в Xcode 16+.
4. ⚠️ **Важно**: В настройках *Signing & Capabilities* полностью **удалите App Sandbox** (это критически необходимо для доступа к низкоуровневым счетчикам ввода-вывода и запуска диагностических процессов).
5. Нажмите `Cmd + Shift + K` для очистки кэша, затем `Cmd + R` для сборки и запуска.

---

## 🛠️ Tech Stack / Стек технологий
* **Frontend**: SwiftUI (`Charts` framework for real-time visualization).
* **Backend**: AppKit Lifecycle Core, Combine bindings, Grand Central Dispatch (`GCD`).
* **Localization**: Xcode String Catalogs (`.xcstrings`) with environment hot-relaunch.
* **Data Sources**: `/usr/sbin/iostat`, `/usr/sbin/diskutil`, and bundled universal `smartctl` binary package.

## 📄 License / Лицензия
This project is licensed under the **MIT License**.
