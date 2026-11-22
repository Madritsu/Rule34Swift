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

#### Build on GitHub

After the workflow is pushed to GitHub, open the repository's **Actions** tab, select **Build and release Rule34Swift**, and click **Run workflow**. Enter a new version tag such as `v1.0.0`. A short release intro is optional; if you leave it blank, GitHub generates the release notes automatically. The workflow builds both apps and publishes a release with these assets:

- `Rule34Swift-iOS.ipa`
- `Rule34Swift-macOS.dmg`

The workflow runs on a GitHub-hosted macOS machine because Xcode builds for Apple platforms require macOS. Its configuration is in `.github/workflows/build.yml`. Automatic notes are based on changes since the previous release; descriptive commit or pull request titles make them easier to read.

#### Build locally

Run the build script from the repository root. With no argument, it opens a menu where you can choose iOS IPA or the native macOS app:

```sh
./build.sh
```

You can also choose a target directly:

```sh
./build.sh ios
./build.sh mac
```

The macOS app is written to `macOS/build/Rule34SwiftMac.app`; the iOS build creates `Rule34Swift.ipa` in the repository root. These are development builds: they use ad-hoc signing and are not notarized or prepared for App Store release.

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

### Credits

- **Ruxx** was reviewed as a reference while researching downloader options: [trickerer01/Ruxx](https://github.com/trickerer01/Ruxx).
- The current app icon uses artwork by [Paschi on Rule34.xxx](https://rule34.xxx/index.php?page=account&s=profile&uname=paschi). The icon is still in development and may change.

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

#### Сборка на GitHub

После отправки workflow на GitHub открой вкладку **Actions**, выбери **Build and release Rule34Swift** и нажми **Run workflow**. Укажи новый тег версии, например `v1.0.0`. Короткое вступление к описанию релиза можно написать по желанию; если оставить поле пустым, GitHub автоматически сформирует список изменений. Workflow соберёт оба приложения и опубликует релиз с файлами:

- `Rule34Swift-iOS.ipa`
- `Rule34Swift-macOS.dmg`

Сборка запускается на macOS-машине GitHub, потому что Xcode собирает приложения для платформ Apple на macOS. Настройки workflow находятся в `.github/workflows/build.yml`. Автоматическое описание формируется по изменениям с прошлого релиза; понятные названия коммитов и pull request делают его легче для чтения.

#### Локальная сборка

Запусти скрипт из корневой папки проекта. Без аргумента появится меню выбора: iOS IPA или нативное приложение macOS.

```sh
./build.sh
```

Можно также сразу указать нужную платформу:

```sh
./build.sh ios
./build.sh mac
```

Приложение macOS появится в `macOS/build/Rule34SwiftMac.app`, а файл iOS — в корневой папке как `Rule34Swift.ipa`. Это сборки для разработки: они подписываются ad-hoc, не проходят нотариальное заверение и не подготовлены к публикации в App Store.

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

### Благодарности

- **Ruxx** мы изучали как ориентир при поиске решения для загрузчика: [trickerer01/Ruxx](https://github.com/trickerer01/Ruxx).
- В текущей иконке используется artwork автора [Paschi на Rule34.xxx](https://rule34.xxx/index.php?page=account&s=profile&uname=paschi). Иконка ещё в разработке и может измениться.
