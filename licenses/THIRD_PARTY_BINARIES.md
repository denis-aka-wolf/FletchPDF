# Native binary inventory

В начальном коммите сторонние CLI-бинарники не поставляются.

Любой добавляемый бинарный компонент должен иметь запись со следующими полями:

- Product and exact version
- Upstream project and download URL
- Download date
- Target OS and architecture
- SHA-256 checksum
- License and included license files
- Build provenance (official release or reproducible build)
- Required notices and source-offer obligations
- Runtime dependencies

Не скачивать и не коммитить исполняемые файлы без проверки происхождения и условий распространения.
