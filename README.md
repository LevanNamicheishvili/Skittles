# Team AI Game

ედიტორი Mac-ისთვის (მოგვიანებით Windows-ისთვისაც), სადაც გუნდი AI-სთან ერთად აწყობს პატარა თამაშს და ამ პროცესში სწავლობს AI-სთან გუნდურად მუშაობას.

## სტრუქტურა

| საქაღალდე | შინაარსი |
| --- | --- |
| `spec/` | წესები, JSON სქემები, პროტოკოლი და საერთო ტესტები. აქედან იწყება ყველაფერი |
| `server/` | Node + TypeScript: წესების საცნობარო იმპლემენტაცია. ეტაპ 3-დან აქ ოთახის სერვერიც იქნება |
| `app/` | Flutter აპი macOS-ისთვის |
| `docs/` | გადაწყვეტილებები და დიზაინის საფუძველი |

## მოთხოვნები

- Node 24 ან უფრო ახალი
- Flutter 3.47.7 (`~/development/flutter/bin` უნდა იყოს `PATH`-ში)
- Xcode 27, არჩეული აქტიურ ინსტრუმენტად: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`. სანამ ეს არ გაკეთებულა, Flutter-ის ბრძანებებს წინ მიუწერეთ `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`

## ტესტები

```bash
cd server && npm install && npm test && npm run typecheck
```

```bash
cd app && flutter analyze && flutter test
```

## აპის გაშვება

```bash
cd app && flutter run -d macos
```
