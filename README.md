<div align="center">
  <img src="docs/assets/app-icon.png" width="112" alt="Rule34Swift app icon">
  <h1>Rule34Swift</h1>
  <p>A native SwiftUI client for browsing Rule34.xxx on iPhone, iPad, and macOS.</p>

  <p>
    <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-5.0-F05138?logo=swift&logoColor=white" alt="Swift 5"></a>
    <a href="https://developer.apple.com/xcode/swiftui/"><img src="https://img.shields.io/badge/UI-SwiftUI-147EFB?logo=apple&logoColor=white" alt="SwiftUI"></a>
    <img src="https://img.shields.io/badge/iOS-16%2B-000000?logo=apple&logoColor=white" alt="iOS 16 or newer">
    <img src="https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white" alt="macOS 13 or newer">
  </p>
  <p><a href="#english">English</a> · <a href="#русский">Русский</a></p>
</div>

## English

Rule34Swift is an ad-free client for searching and viewing posts from Rule34.xxx. The project contains separate iOS and native macOS apps, with shared networking, models, favorites, settings, and image caching.

> **Content notice:** This client can display adult material hosted by Rule34.xxx. Follow the site's terms and the laws that apply to you.

### Features

- No ads in the app interface.
- Search with either the Rule34.xxx website parser or the DAPI source.
- Browse tag suggestions and use Rule34 search operators, including exclusions, wildcards, and OR groups.
- View images and videos in a full-screen viewer with zoom and playback controls.
- Save posts locally and import or export favorites as JSON.
- Choose separate quality levels for gallery previews and the viewer; manage the image cache.
- Filter AI posts in booru mode and handle CAPTCHA or age-verification responses.

### Requirements

- macOS with Xcode and the Xcode command-line tools installed.
- iOS deployment target: **iOS 16 or later**.
- Native Mac deployment target: **macOS 13 or later**.
- API user ID and key are needed when using the API search source. Website/booru search is selected by default.

### Build

Run the build script from the repository root:

```sh
./build.sh mac
```

The native macOS app is written to `macOS/build/Rule34SwiftMac.app`.

To build the iOS package:

```sh
./build.sh ios
```

This creates `Rule34Swift.ipa` in the repository root. Running `./build.sh` without an argument opens a target selection prompt. These are development builds; the script applies ad-hoc signing and does not notarize or prepare releases for the App Store.

You can also open either project in Xcode:

```sh
open macOS/Rule34SwiftMac.xcodeproj
open iOS/Rule34Swift.xcodeproj
```

Choose the `Rule34SwiftMac` or `Rule34Swift` scheme, respectively.

### Project layout

| Path | Contents |
| --- | --- |
| `Rule34Swift/` | Shared models, services, settings, and persistence |
| `iOS/` | iPhone and iPad Xcode project |
| `macOS/` | Native macOS app and Xcode project |

The iOS and macOS apps keep their local app data separately. Use the favorites JSON import/export to move a collection between them.

## Русский

Rule34Swift — клиент без рекламы для поиска и просмотра публикаций с Rule34.xxx. В проект входят отдельные приложения для iOS и macOS, которые используют общие сетевые службы, модели, избранное, настройки и кэш изображений.

> **Предупреждение о содержимом:** приложение может показывать материалы для взрослых с Rule34.xxx. Соблюдайте правила сайта и законы вашей страны.

### Возможности

- В интерфейсе приложения нет рекламы.
- Поиск через HTML-парсер Rule34.xxx или DAPI.
- Подсказки тегов и операторы поиска Rule34: исключения, шаблоны со `*` и группы «ИЛИ».
- Полноэкранный просмотр изображений и видео, масштабирование и управление воспроизведением.
- Локальное избранное, импорт и экспорт сохранённых постов в JSON.
- Отдельный выбор качества обложек и изображений в просмотрщике, управление кэшем.
- Фильтр AI-постов в режиме booru, обработка CAPTCHA и проверки возраста.

### Требования

- macOS с установленными Xcode и инструментами командной строки Xcode.
- Минимальная версия iOS: **iOS 16**.
- Минимальная версия нативного приложения для Mac: **macOS 13**.
- Для поиска через API нужны ID пользователя и API-ключ. По умолчанию выбран поиск через сайт/booru.

### Сборка

Запустите скрипт сборки из корневой папки проекта:

```sh
./build.sh mac
```

Собранное приложение macOS появится в `macOS/build/Rule34SwiftMac.app`.

Чтобы собрать пакет iOS:

```sh
./build.sh ios
```

Файл `Rule34Swift.ipa` появится в корневой папке проекта. Если запустить `./build.sh` без аргумента, скрипт предложит выбрать платформу. Это сборки для разработки: скрипт применяет ad-hoc подпись, но не выполняет нотариальное заверение и не готовит приложение к публикации в App Store.

Проекты можно открыть и собрать в Xcode:

```sh
open macOS/Rule34SwiftMac.xcodeproj
open iOS/Rule34Swift.xcodeproj
```

Для Mac выберите схему `Rule34SwiftMac`, для iOS — `Rule34Swift`.

### Структура проекта

| Путь | Содержимое |
| --- | --- |
| `Rule34Swift/` | Общие модели, службы, настройки и локальное хранение данных |
| `iOS/` | Проект Xcode для iPhone и iPad |
| `macOS/` | Нативное приложение и проект Xcode для macOS |

Приложения для iOS и macOS хранят данные отдельно. Перенести избранное между ними можно через импорт и экспорт JSON.
