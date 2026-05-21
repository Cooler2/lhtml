# LHT — Project Implementation Plan

**Status:** Draft  
**Purpose:** Overview of components needed to implement the LHT ecosystem in practice.

---

## 1. Core Library (`lht-core`)

Платформонезависимая библиотека — основа всего. Не зависит от UI, сети, или ОС. Тестируется отдельно.

**Язык:** Object Pascal (Delphi) — реюзается и в браузере, и в CLI-инструментах, и потенциально в DOS-порте.

### Модули

| Модуль | Описание |
|---|---|
| **Parser** | Разбор canonical text form (.lht, .lss, .ls) → внутреннее представление |
| **Tokenizer** | Внутреннее представление → бинарный токен-поток (.lhb) |
| **Deserializer** | Бинарный токен-поток → DOM |
| **DOM** | Дерево документа, навигация, мутации |
| **Style engine** | Разрешение классов, констант, состояний (:hover и т.п.) |
| **Layout engine** | Вычисление размеров и позиций (row/flow/block/overlay) |
| **Script VM** | Стек-машина, ~50–70 опкодов |
| **Script compiler** | Исходник (.ls) → байткод |

### Тестирование без браузера

Большинство модулей тестируются консольными утилитами:
- Parser + Tokenizer: `lht-compile input.lht output.lhb`
- Deserializer + DOM: загрузить .lhb, распечатать дерево
- Layout engine: загрузить документ, задать размер окна, вывести дерево с размерами
- Script VM: запустить .ls / .lhbc, вывести лог

---

## 2. Renderer Interface

Абстрактный слой рисования. Core-библиотека вызывает его, не зная о платформе.

Текущая архитектурная цель: layout не должен рисовать напрямую во время обхода
DOM. Сначала формируется display list, затем renderer-backend исполняет готовые
команды.

```text
DOM + resolved attributes
  -> layout engine
  -> display list
  -> renderer backend
```

Минимальные команды display list:

```text
FillRect(x, y, w, h, color)
StrokeRect(x, y, w, h, color)
TextRun(x, baselineY, text, fontFace, fontSize, color)
```

Текстовые команды хранят `baselineY`, а не верхнюю координату. GDI/VCL backend
может отрисовать `TextRun` через `TextOut`, а bitmap/retro backend сам переводит
baseline в верх glyph-а.

```
DrawRect(x, y, w, h, color)
DrawText(x, y, text, font, color)
DrawImage(x, y, img)
ClipPush(x, y, w, h)
ClipPop()
```

### Реализации

| Вариант | Платформа | Примечание |
|---|---|---|
| GDI | Windows 32bit | Для референсного браузера |
| Canvas (TCanvas) | Delphi VCL | Быстрый старт, хорош для прототипа |
| VESA / прямая запись в VRAM | DOS | Целевая платформа |
| Null renderer | Любая | Для тестирования layout без отрисовки |

---

## 3. Platform Layer

Всё что зависит от ОС: окно, события, таймеры, сеть.

### Реализации

| Компонент | Windows (Delphi) | DOS |
|---|---|---|
| Окно / surface | WinAPI / VCL Form | VESA-режим, прямой доступ к VRAM |
| Мышь | WM_MOUSE* | int 33h |
| Клавиатура | WM_KEY* | int 16h / BIOS |
| Таймеры | SetTimer / timeSetEvent | int 8 (IRQ0), 8253 |
| Сеть (Request API) | Indy (TIdHTTP) или WinInet | Packet driver / WATTCP |
| Файловая система | WinAPI | DOS int 21h |

---

## 4. Reference Browser (Windows, Delphi 32bit)

Основной инструмент разработки и демонстрации. Не ретро-платформа, но честная реализация спеки.

### Архитектура

```
[VCL Form]
  └── [LHT Viewport control]  ← кастомный TCustomControl
        ├── lht-core (DOM, layout, VM)
        ├── GDI Renderer
        └── Windows Platform Layer
```

### Функции браузера

Браузер с самого начала проектируется как **разработческая платформа**, а не просто вьювер. Всё что было бы крайне сложно реализовать в DOS — здесь делается нативно средствами Windows/VCL.

#### Навигация
- Адресная строка, навигация вперёд/назад
- Открытие локальных файлов (.lht, .lhb)
- Индикатор загрузки ресурсов

#### Документ
- Просмотр исходника (.lht) с подсветкой синтаксиса
- Дамп токен-потока — байты + расшифровка каждого токена
- Просмотр бандла (.lhb) — список ресурсов, смещения, размеры

#### Layout visualizer
- Оверлей с границами всех блоков (включается поверх страницы)
- Padding / border / content area — разными цветами (как в DevTools)
- Отображение baseline текстовых строк
- Линейки с реальными пиксельными координатами

#### DOM-инспектор
- Дерево элементов; клик → подсветить элемент на странице и наоборот
- Все атрибуты и вычисленные стили выбранного элемента
- Live-редактирование атрибутов с мгновенным перерендером

#### Скрипты
- Консоль: вывод `log()` + интерактивный ввод выражений
- Пошаговый отладчик VM: step in/over, breakpoints, стек операндов
- Просмотр глобальных переменных и значений во время паузы
- Профайлер: счётчик выполненных опкодов, горячие функции

#### Сеть
- Лог всех Request-запросов: URL, метод, статус, время, размер
- Симуляция медленного соединения (throttling)
- Симуляция недоступности ресурса — для тестирования fallback-ветвей

#### Эмуляция целевой платформы
- Выбор цветности (2 / 16 / 256 / 65536 цветов) — рендерер адаптирует палитру
- Выбор уровня canvas (none / basic / full)
- Ограничение памяти скриптов
- Счётчик опкодов в секунду с оценкой нагрузки на 286 — видно прямо в браузере будет ли страница лагать на целевом железе

### Backbuffer + 2x scale

Рендеринг всегда идёт в backbuffer фиксированного размера (640×480 или 800×600), который выводится на экран с 2x-масштабированием (StretchBlt). Это даёт:
- Реальное ощущение целевого разрешения при разработке
- Естественную двойную буферизацию (нет мерцания)
- Возможность переключать целевое разрешение без изменения кода рендерера

```
[lht-core layout @ 640×480]
      ↓
[GDI Renderer → TBitmap 640×480]
      ↓ StretchBlt 2x
[TCustomControl 1280×960 на экране]
```

Масштаб переключается в настройках (1x для скриншотов, 2x для работы, 3x на HiDPI).

### Варианты реализации viewport

**A. TCustomControl + GDI (рекомендуется)**
- Рисуем в TBitmap (backbuffer), выводим StretchBlt
- Полный контроль, минимум зависимостей

**B. TImage + Bitmap**
- Аналогично, но TImage берёт часть рутины на себя
- Чуть проще старт, меньше гибкости

---

## 5. CLI Tokenizer (`lht-compile`)

Консольный инструмент: canonical text → binary token stream.

```
lht-compile page.lht              → page.lhb
lht-compile page.lht -o out.lhb
lht-compile --check page.lht      → только валидация, без вывода
lht-compile --dump page.lhb       → человекочитаемый дамп токенов
```

**Язык:** Object Pascal (реюз lht-core) или Go (удобнее для серверного deploy).

Используется:
- Как build-шаг для статических сайтов
- Внутри серверного обработчика (вызывается из Perl/FastCGI)

---


## 6. Web Interoperability Library (`lht-html`)

Отдельная библиотека (не часть `lht-core`) для конвертации LHT-документов в HTML. Нужна для двух вещей: раздача сайтов обычным браузерам и индексация поисковиками.

**Принцип:** сервер смотрит на заголовок `Accept` входящего запроса. LHT-браузер шлёт `Accept: application/x-lht` и получает бинарный LHT. Обычный браузер (Chrome, Firefox, Googlebot) шлёт `Accept: text/html` и получает HTML-конвертацию того же документа. Тот же URL, разный ответ — стандартный HTTP content negotiation, не cloaking.

```
GET /page  Accept: application/x-lht  →  бинарный .lhb
GET /page  Accept: text/html          →  HTML (сконвертированный)
```

Сервер добавляет `Vary: Accept` — кэши (CDN, прокси) корректно разделяют варианты.

**Что конвертируется напрямую:** структура документа, текст, ссылки, изображения, базовый layout. **Что теряется или даёт fallback:** LFNT-шрифты (заменяются системными), скриптовая VM (страница остаётся статичной), специфичный для 256-цветного режима рендеринг.

**Язык:** Go (удобнее для серверного deploy) или Pascal (реюз DOM из lht-core через FFI).

**Место в архитектуре:** зависит от `lht-core` (DOM, Style engine), но не входит в него. Подключается только серверными компонентами.

---

## 7. Server-side Components

### 7.1 Минимальный вариант: статика + build-шаг

Никакой серверной логики. nginx раздаёт pre-compiled `.lhb` файлы.

```nginx
location ~* \.lht$ {
    types { application/lhtml lht; }
    root /var/www;
}
```

Плюсы: максимальная простота, любой хостинг.  
Минусы: нужен build-шаг при каждом изменении.

### 7.2 Perl CGI-обработчик

Скрипт на Perl, запускаемый через nginx + fcgiwrap или Apache mod_cgi.

```perl
#!/usr/bin/perl
# lhtml-handler.pl — токенизирует .lht на лету, кэширует по mtime

my $src   = $document_root . $path;          # /var/www/page.lht
my $cache = $cache_dir     . $path . "b";    # /var/cache/lhtml/page.lhtb

if (needs_regen($src, $cache)) {
    system("lht-compile", $src, "-o", $cache);
}

send_file($cache, "application/lhtml");
```

Плюсы: прозрачный читаемый код, нет скомпилированных бинарников с логикой, легко аудировать.  
Минусы: накладные расходы на запуск интерпретатора Perl (для FastCGI — только один раз при старте).

### 7.3 FastCGI-демон на Go

Долгоживущий процесс, общается с nginx по FastCGI-протоколу.

```
nginx ──fastcgi_pass──► lhtml-fcgi (Go) ──► lht-core (через cgo или subprocess)
```

Плюсы: быстро, in-memory кэш, content negotiation (LHT-* заголовки).  
Минусы: нужен скомпилированный бинарник, сложнее деплой.

**Рекомендация для старта:** вариант 7.2 (Perl). Добавить 7.3 когда понадобится производительность или полный content negotiation.

### 7.4 Content negotiation с HTML-fallback

Расширение любого из вариантов выше: перед отдачей файла проверяется заголовок `Accept`. Если клиент не заявляет `application/x-lht` — вызывается `lht-html` конвертер и отдаётся HTML с заголовком `Vary: Accept`. Это делает LHT-сайты видимыми для обычных браузеров и индексируемыми Гуглом без отдельного зеркала.

---

## 8. Huffman Encoder

Опциональный компонент для сжатия токен-потока.

Встраивается в `lht-compile` как флаг:
```
lht-compile page.lht --huffman -o page.lhb
```

И в FastCGI-демон для отдачи сжатого потока клиентам с `LHT-Encoding: huffman`.

Приоритет: низкий, реализуется после того как базовая цепочка работает.

---

## 9. Порядок реализации (предлагаемый)

```
Фаза 1 — Core + базовый браузер
  1. lht-core: Parser canonical text form
  2. lht-core: DOM + Style engine
  3. lht-core: Layout engine (block/row/flow)
  4. Renderer: GDI/Canvas
  5. Референсный браузер: окно, навигация по файлам

Фаза 2 — Скрипты + сеть
  6. lht-core: Script compiler + VM
  7. Platform: таймеры, Request API (Indy)
  8. Браузер: консоль, инспектор DOM

Фаза 3 — Binary format + сервер
  9. lht-core: Tokenizer + Deserializer
  10. CLI: lht-compile
  11. Сервер: Perl CGI-обработчик

Фаза 4 — Продвинутые возможности
  12. Huffman encoding
  13. lht-html: конвертер LHT → HTML
  14. Content negotiation с HTML-fallback (7.4)
  15. DOS-порт (новый Renderer + Platform layer)
```

---

## 10. Открытые вопросы по реализации

- **Шрифты в браузере:** использовать системные шрифты Windows (GDI) или реализовать LFNT-рендерер сразу?
- **Сеть в DOS:** WATTCP vs Packet Driver — зависит от целевого железа
- **Script JIT:** только на 386+; в референсном браузере не нужен (есть нативный x86-64)
- **Токенизатор:** писать на Pascal (реюз lht-core) или на Go (удобнее для серверного использования)?
- **Bundle формат:** намеренно исключён из v1 — дистрибуция покрывается zip-архивом каталога. Вернуться если появится реальная потребность (медленный канал, холодный кэш).
