#!/bin/bash

SUDO_PASS=

temp_pass_rm () {
  echo $PASS | sudo -S -k passwd -d $USER
}

# Убираем спам по поводу GTK
zen_ns () {
    zenity 2> >(grep -v 'Gtk') >&2 "$@"
}

# Окно ошибки zenity
zen_err () {
    zen_ns --error \
        --title="$1" \
        --text="$2"
}

# Окно вопроса zenity
zen_q () {
    zen_ns --question \
        --title="$1" \
        --text="$2" \
        --ok-label="Да" \
        --cancel-label="Нет"
}

# Проверка запускается ли скрипт на SteamOS
if ! command -v steamos-readonly &>/dev/null
then
    zen_err "Ошибка" "Скрипт предназначен для SteamOS!\nЗавершение работы..."
    exit 0
fi

# Проверка на наличие пароля пользователя
PASS_STATUS=$(passwd -S $USER 2> /dev/null)
if [ "${PASS_STATUS:5:2}" = "NP" ]; then
    yes "0000" | passwd $USER # Установка временного пароля

    trap temp_pass_rm EXIT # Сброс пароля при выходе

    SUDO_PASS="0000"

    zen_ns --info \
        --title="Отсутствует пароль sudo" \
        --text="Установлен временный пароль: 0000"
fi

# Функция для исполнения команды от root
sudo_p () {
    if [[ -z "$SUDO_PASS" ]]; then # Запрос пароля если не задан временный
    SUDO_PASS=$(zen_ns --entry \
        --title="sudo" \
        --text="Требуется пароль sudo!" \
        --hide-text)
    fi

    echo "$SUDO_PASS" | sudo --stdin "$@"
}

# Форматирование вывода для окна прогресса zenity
format_output() {
    while IFS= read -r line; do
        echo "# $line"
    done
}

# Окно прогресса zenity со всем выводом
zen_progress () {
    ("$1" 2>/dev/null | format_output) | zenity --progress \
    --width=500 \
    --height=200 \
    --pulsate \
    --auto-kill \
    --auto-close \
    --title="$2" \
    --text="$3"
}

# Функция срабатывающая при ошибках
err_trap () {
    if [[ -z "$@" ]]; then
        ERR_TEXT="Непредвиденная ошибка!"
    else
        ERR_TEXT="$@"
    fi
    zen_err "Ошибка!" "$ERR_TEXT"

    # Возвращение ограничений на запись
    sudo_p steamos-readonly enable || true

    # Чистка временных каталогов
    rm -rf /tmp/openh-* || true

    SUDO_PASS="Nē"

    exit 1
}
trap 'err_trap' ERR

sudo_p steamos-readonly disable || true



# Проверка доступа в интернет и работы DNS
if  ! curl -Is https://github.com | head -1 | grep 200 > /dev/null
then
    err_trap "Нет соединения с интернетом либо не работают DNS\nНет доступа к github.com"
fi

# Версии актуальных библиотек
OPENH_VERSIONS=("2.5.1" "2.5.0" "2.4.1" "2.3.1" "2.3.0" "2.2.0" "2.1.0")

openh_comp () {
    # Создание временного каталога
    TEMP_COMP="$(mktemp -d -t openh-XXXX)"
    cd $TEMP_COMP
    percentage="1"
    for openh in "${OPENH_VERSIONS[@]}"; do

       # Проверка наличия установленной библиотеки
        TARGET_LIB_DIR="$HOME/.local/share/flatpak/extension/org.freedesktop.Platform.openh264/x86_64/$openh/active/files/lib"
        if [[ -f "$TARGET_LIB_DIR/libopenh264.so.$openh" ]]; then
            continue # Пропуск если библиотека уже установлена
        fi

        # Определяем правильную ссылку на скачивание
        case "$openh" in
            "2.5.1") OPENH_DOWN_LINK="https://github.com/cisco/openh264/archive/refs/tags/2.5.1.zip" ;;
            *) OPENH_DOWN_LINK="https://github.com/cisco/openh264/archive/refs/tags/v$openh.zip" ;;
        esac

        echo "Скачивание исходников кодека версии $openh..."
        sleep 1
        (wget --show-progress -O "$TEMP_COMP/openh264.zip" "$OPENH_DOWN_LINK") || err_trap "Не удалось скачать архив"
        unzip -o "$TEMP_COMP/openh264.zip" -d "$TEMP_COMP" || err_trap "Не найден скачанный архив"

        # Удаление архива после распаковки
        rm "$TEMP_COMP/openh264.zip"

        # Компиляция в podman
        echo "Начинается компиляция версии $openh в контейнере. Это займёт время..."
        sleep 1

        OPENH_SOURCE_DIR="$TEMP_COMP/openh264-$openh"

        podman run --rm \
            -v "$OPENH_SOURCE_DIR:/src" \
            -w /src \
            docker.io/alpine:latest \
            sh -c "
                # Установка build-base (gcc, make, libc), nasm и git
                apk add --no-cache build-base nasm git || exit 1

                # Компиляция (включая скрипт версии)
                make || exit 1
            " 2>/dev/null || err_trap "Компиляция внутри контейнера Podman не удалась!"

        mkdir -p "$TARGET_LIB_DIR" || err_trap "Не удалось создать целевой каталог Flatpak"

        mv "$OPENH_SOURCE_DIR/libopenh264.so.$openh" "$TARGET_LIB_DIR/" || err_trap "Не удалось перенести библиотеку"

        # Создание символических ссылок
        cd "$TARGET_LIB_DIR"
        ln -sf "libopenh264.so.$openh" "libopenh264.so"
        ln -sf "libopenh264.so.$openh" "libopenh264.so.6"

        # Удаление каталога с иходниками
        rm -rf "$OPENH_SOURCE_DIR"

        echo "Версия кодека $openh установлена!"
        sleep 1
    done
    rm -rf "$TEMP_COMP"
}
zen_progress openh_comp "Компиляция библиотек"

# Проверка всех установленных кодеков
for openhcheck in "${OPENH_VERSIONS[@]}"; do
    if [[ ! -f "$HOME/.local/share/flatpak/extension/org.freedesktop.Platform.openh264/x86_64/$openhcheck/active/files/lib/libopenh264.so.$openhcheck" ]]; then
        err_trap "Не найдена версия $openhcheck!\nПопробуйте апустить скрипт повторно в терминале."
    fi
done

zen_ns --info \
    --title="Установка openh264" \
    --text="Все версии кодеков установлены!\n2.5.1-2.1.0"


if [[ "$USER" = "deck" ]]; then
    sudo_p steamos-readonly enable || true
fi

SUDO_PASS="Nē"

exit 0
