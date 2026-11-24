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

> **Content notice:** Rule34.xxx is an 18+ site, and this app displays adult material hosted there. Follow the site's terms and the laws that apply to you.

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

### Privacy and credentials

The API user ID and key are stored locally in the system Keychain, which macOS protects and controls. If macOS asks for your login or Keychain password, it is requesting authorization to access those saved credentials. The app uses them for requests to Rule34.xxx when API mode is selected.

### Build

Run the build script from the repository root. With no argument, it opens a menu where you can choose iOS, native macOS, or both release builds:

```sh
./build.sh
```

You can also choose a target directly:

```sh
./build.sh ios
./build.sh mac
./build.sh github
```

The `github` target creates `Rule34Swift.ipa` and `Rule34SwiftMac.dmg` in the repository root. The DMG contains the macOS app and an Applications shortcut. The `mac` target also copies the standalone app to `macOS/build/Rule34SwiftMac.app`. These are development builds: they use ad-hoc signing and are not notarized or prepared for App Store release. The script prepares local files; publish them to a GitHub Release manually.

You can also open either project in Xcode:

```sh
open macOS/Rule34SwiftMac.xcodeproj
open iOS/Rule34Swift.xcodeproj
```

Choose the `Rule34SwiftMac` or `Rule34Swift` scheme, respectively.

### Opening the macOS app

The macOS build is ad-hoc signed and is not notarized, so Gatekeeper may block it on first launch. After trying to open the app, go to **System Settings → Privacy & Security**, scroll to **Security**, choose **Open Anyway** for Rule34SwiftMac, then confirm **Open**. See [Apple's instructions](https://support.apple.com/en-us/102445).

If you trust the copy downloaded from this repository, you can instead remove its quarantine attribute in Terminal:

```sh
xattr -cr /Applications/Rule34SwiftMac.app
```

### Project layout

| Path | Contents |
| --- | --- |
| `Rule34Swift/` | Shared models, services, settings, and persistence |
| `iOS/` | iPhone and iPad Xcode project |
| `macOS/` | Native macOS app and Xcode project |

The iOS and macOS apps keep their local app data separately. Use the favorites JSON import/export to move a collection between them.

### Credits

- **Ruxx** was reviewed as a reference while researching downloader options: [trickerer01/Ruxx](https://github.com/trickerer01/Ruxx).
- The app icon uses artwork by [Paschi on Rule34.xxx](https://rule34.xxx/index.php?page=account&s=profile&uname=paschi), with the artist's permission. It is not covered by the MIT license.

## Русский

Rule34Swift — клиент без рекламы для поиска и просмотра публикаций с Rule34.xxx. В проект входят отдельные приложения для iOS и macOS, которые используют общие сетевые службы, модели, избранное, настройки и кэш изображений.

> **Предупреждение о содержимом:** Rule34.xxx — сайт категории 18+, и приложение показывает размещённые там материалы для взрослых. Соблюдайте правила сайта и законы вашей страны.

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

### Конфиденциальность и данные доступа

ID пользователя и API-ключ хранятся локально в системном Связке ключей, доступ к которому контролирует macOS. Если система попросит пароль пользователя Mac или Связки ключей, она запрашивает разрешение на доступ к сохранённым данным. Приложение использует их для запросов к Rule34.xxx, когда выбран режим API.

### Сборка

Запусти скрипт из корневой папки проекта. Без аргумента появится меню выбора: iOS IPA, нативное приложение macOS или оба файла для релиза.

```sh
./build.sh
```

Можно также сразу указать нужную платформу:

```sh
./build.sh ios
./build.sh mac
./build.sh github
```

Команда `github` создаёт в корне `Rule34Swift.ipa` и `Rule34SwiftMac.dmg`. В DMG находятся приложение macOS и ярлык Applications. Команда `mac` также сохраняет отдельное приложение в `macOS/build/Rule34SwiftMac.app`. Это сборки для разработки: они подписываются ad-hoc, не проходят нотариальное заверение и не подготовлены к публикации в App Store. Скрипт готовит файлы локально; в GitHub Releases их нужно загрузить вручную.

Проекты можно открыть и собрать в Xcode:

```sh
open macOS/Rule34SwiftMac.xcodeproj
open iOS/Rule34Swift.xcodeproj
```

Для Mac выберите схему `Rule34SwiftMac`, для iOS — `Rule34Swift`.

### Первый запуск приложения на macOS

Сборка для macOS подписана ad-hoc и не нотариально заверена, поэтому Gatekeeper может заблокировать первый запуск. Сначала попробуй открыть приложение, затем зайди в **Системные настройки → Конфиденциальность и безопасность**, прокрути до раздела **Безопасность**, нажми **Всё равно открыть** напротив Rule34SwiftMac и подтверди запуск. Подробности — в [инструкции Apple](https://support.apple.com/en-us/102445).

Если ты доверяешь копии, загруженной из этого репозитория, можно вместо этого удалить атрибут карантина через Терминал:

```sh
xattr -cr /Applications/Rule34SwiftMac.app
```

### Структура проекта

| Путь | Содержимое |
| --- | --- |
| `Rule34Swift/` | Общие модели, службы, настройки и локальное хранение данных |
| `iOS/` | Проект Xcode для iPhone и iPad |
| `macOS/` | Нативное приложение и проект Xcode для macOS |

Приложения для iOS и macOS хранят данные отдельно. Перенести избранное между ними можно через импорт и экспорт JSON.

### Благодарности

- **Ruxx** мы изучали как ориентир при поиске решения для загрузчика: [trickerer01/Ruxx](https://github.com/trickerer01/Ruxx).
- В иконке приложения используется artwork автора [Paschi на Rule34.xxx](https://rule34.xxx/index.php?page=account&s=profile&uname=paschi), с разрешения автора. Лицензия MIT его не касается
