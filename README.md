# Описание
Скрипт автоматической компиляции и установки необходимых версий кодека Openh264 для Flatpak.

Скрипт работает и проверен на Arch-подобных дистрибутивах и SteamOS.

# Скачать
https://github.com/Kaktus-Kidala/FlatpakOpenh264InstallScript/releases/download/0.2/flatpakopenhinstall.desktop


# Что он делает
Скрипт скачивает исходники из https://github.com/cisco/openh264/releases.

Распаковывает архив, компилирует библиотеку и перемещает её в пользовательский каталог. 

# Требования для запуска
* zenity (для отображения уведомлений и окна прогресса)
* wget
* unzip
* base-devel
* nasm 
