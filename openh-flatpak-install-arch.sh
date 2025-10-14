#!/bin/bash

local SUDO_PASS
export percentage="0"
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
        --ok-label="$3" \
        --cancel-label="$4"
}

# Функция для исполнения команды от root
sudo_p () {
    if [[ -z "$SUDO_PASS" ]]; then
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

# Функция срабатывающая при ошибках
err_trap () {
    if [[ -z "$@" ]]; then
        ERR_TEXT="Непредвиденная ошибка!"
    else
        ERR_TEXT="$@"
    fi
    zen_err "Ошибка!" "$ERR_TEXT"

    # Чистка временных каталогов
    rm -rf /tmp/openh-* || true

    SUDO_PASS="Nē"

    exit 1
}
trap 'err_trap' ERR

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

# Проверка запускается ли скрипт на SteamOS
if command -v steam-readonly &>/dev/null
then
    zen_err "Ошибка" "Скрипт НЕ предназначен для SteamOS!\nЗавершение работы..."
    exit 0
fi

# Проверка доступа в интернет и работы DNS
if  ! curl -Is https://github.com | head -1 | grep 200 > /dev/null
then
    err_trap "Нет соединения с интернетом либо не работают DNS\nНет доступа к github.com"
fi

# Проверка на наличие nasm и его установка с компиляторами base-devel
if ! command -v nasm &>/dev/null
then
    if (( zen_q "Не установлены компиляторы" "Установить необходимые компиляторы?" "Установить" "Отмена" )); then
        sudo_p pacman-key --init
        sudo_p pacman-key --populate
        sudo_p pacman --noconfirm -Sy base-devel nasm || err_trap "Не удалось установить компилятор!"
    else
        zen_ns --info --title="Отмена установки" --text="Отсутствуют необходимые компиляторы"
        exit 1
    fi
fi

# Версии актуальных библиотек
OPENH_VERSIONS=("2.5.1" "2.5.0" "2.4.1" "2.3.1" "2.3.0" "2.2.0" "2.1.0")

openh_comp () {
    # Создание временного каталога
    TEMP_COMP="$(mktemp -d -t openh-XXXX)"
    cd $TEMP_COMP
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

        echo "Начинается компиляция версии $openh. Это займёт время..."
        sleep 1

        OPENH_SOURCE_DIR="$TEMP_COMP/openh264-$openh"

        cd $OPENH_SOURCE_DIR
        make 2>/dev/null || err_trap "Не удалось скомпилировать библиотеку!"
        cd $TEMP_COMP


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

SUDO_PASS="Nē"

exit 0
