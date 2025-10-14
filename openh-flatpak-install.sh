#!/bin/bash

local SUDO_PASS

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
    if [[ -z "$SUDO_PASS" ]]; then # Запрос пароля если не был введён
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
    ("$1") | (format_output) | zenity --progress \
    --width=500 \
    --pulsate \
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
    zen_err \
        "Ошибка!" \
        "$ERR_TEXT"

    # Удаление nasm и чистка кэша pacman
    if [[ "$USER" = "deck" ]]; then
    sudo_p pacman --noconfirm -Rsn nasm || true
    sudo_p pacman --noconfirm -Scc || true
    sudo_p steamos-readonly enable || true
    fi

    # Чистка временных каталогов
    rm -rf /tmp/tmp.* || true

    SUDO_PASS="Nē"
    exit 1
}
trap 'err_trap' ERR

# Снятие ограничений на запись если запуск на Steam Deck и установка nasm для компиляции
if [[ "$USER" = "deck" ]]; then
    # Запрос пароля sudo
    SUDO_PASS=$(zen_ns --entry \
        --title="sudo" \
        --text="Требуется пароль sudo!" \
        --hide-text)

    sudo_p steamos-readonly disable || true
fi


# Проверка доступа в интернет и работы DNS
if  ! curl -Is https://github.com | head -1 | grep 200 > /dev/null
then
    err_trap "Нет соединения с интернетом либо не работают DNS\nНет доступа к github.com"
fi

# Проверка на наличие nasm
if ! command -v nasm &>/dev/null
then
    sudo_p pacman-key --init
    sudo_p pacman-key --populate
    sudo_p pacman --noconfirm -Sy nasm
fi

# Компиляция библиотек
OPENH_VERSIONS=("2.5.1" "2.5.0" "2.4.1" "2.3.1" "2.3.0" "2.2.0" "2.1.0")
openh_comp () {
    for openh in "${OPENH_VERSIONS[@]}"; do
        TEMP_COMP="$(mktemp -d)"
        cd $TEMP_COMP
        case "$openh" in
            "2.5.1") OPENH_DOWN_LINK="https://github.com/cisco/openh264/archive/refs/tags/2.5.1.zip" ;;
            *) OPENH_DOWN_LINK="https://github.com/cisco/openh264/archive/refs/tags/v$openh.zip" ;;
        esac
        echo "Скачивание исходников кодека версии $openh..."
        sleep 1
        wget --show-progress $OPENH_DOWN_LINK
        case "$openh" in
            "2.5.1") unzip $openh.zip || err_trap "Не найден скачанный архив" ;;
            *) unzip v$openh.zip || err_trap "Не найден скачанный архив" ;;
        esac
        cd openh264-$openh || err_trap "Не найден распакованный каталог"
        echo "Начинается компиляция версии $openh. Это займёт время..."
        sleep 3
        make
        mkdir -p "$HOME/.local/share/flatpak/extension/org.freedesktop.Platform.openh264/x86_64/$openh/active/files/lib"
        mv "libopenh264.so.$openh" "$HOME/.local/share/flatpak/extension/org.freedesktop.Platform.openh264/x86_64/$openh/active/files/lib/libopenh264.so.$openh" || err_trap "Не удалось перенести библиотеку"
        cd "$HOME/.local/share/flatpak/extension/org.freedesktop.Platform.openh264/x86_64/$openh/active/files/lib/"
        ln -sf "libopenh264.so.$openh" "libopenh264.so"
        ln -sf "libopenh264.so.$openh" "libopenh264.so.6"
        rm -rf $TEMP_COMP
        echo "Версия кодека $openh установлена!"
        sleep 3
    done
}
zen_progress openh_comp "Компиляция библиотек"

# Проверка всех установленных кодеков
for openhcheck in "${OPENH_VERSIONS[@]}"; do
    if [[ ! -f "$HOME/.local/share/flatpak/extension/org.freedesktop.Platform.openh264/x86_64/$openhcheck/active/files/lib/libopenh264.so.$openhcheck" ]]; then
        err_trap "Не найдена версия $openhcheck!"
    fi
done

zen_ns --info \
    --title="Установка openh264" \
    --text="Все версии кодеков установлены!\n2.5.1-2.1.0"


if [[ "$USER" = "deck" ]]; then
    sudo_p pacman --noconfirm -Rsn nasm
    sudo_p pacman --noconfirm -Scc
    sudo_p steamos-readonly enable
fi

SUDO_PASS="Nē"
