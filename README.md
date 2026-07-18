# Sport Tracker

Откройте `SportTracker.xcodeproj` в Xcode и нажмите кнопку Run. Выберите симулятор iPhone или подключённое устройство.

Для запуска на физическом устройстве укажите свою команду разработки (Signing & Capabilities) в настройках target `SportTracker`.

## Общий чат CloudKit

Экран «Чат» использует публичную базу CloudKit: сообщения доступны всем пользователям приложения, которые вошли в iCloud.

Перед запуском на устройствах:

1. В Xcode откройте target `SportTracker` → **Signing & Capabilities** и включите **iCloud** с **CloudKit**.
2. Выберите или создайте контейнер `iCloud.com.example.SportTracker4564536` для вашей команды разработки.
3. В [CloudKit Console](https://icloud.developer.apple.com/dashboard/) в Development-среде создайте тип записи `CommunityMessage` с полями `text` (String), `author` (String), `authorID` (String), `createdAt` (Date/Time) и `isHidden` (Boolean). Для `createdAt` включите индекс **Sortable**, для `isHidden` — **Queryable**. В правах этого типа включите: **World — Read**, **Authenticated — Create**.
4. Создайте тип `CommunityMessageReport` с полями `messageID` (String), `reportedAuthorID` (String), `reporterID` (String), `reason` (String), `messageText` (String) и `reportedAt` (Date/Time). Для него включите только **Authenticated — Create**: жалобы не должны быть доступны остальным пользователям.
5. В App Store Connect добавьте рабочий **Support URL** с контактами для обращений. Проверяйте жалобы в CloudKit Console ежедневно; чтобы скрыть сообщение для всех, установите у него `isHidden = true` или удалите его.
6. Для релиза разверните схему в Production в CloudKit Console. В проекте уже настроено: Debug использует Development, а Release — Production.

Сообщения в этом чате видны всем пользователям приложения. Не отправляйте в него личные или чувствительные данные.
