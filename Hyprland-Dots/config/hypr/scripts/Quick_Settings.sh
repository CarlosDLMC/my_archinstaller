#!/usr/bin/env bash
# Rofi menu for the desktop's quick settings (SUPER SHIFT E): the mango config
# files to edit, and the settings tools.

# The terminal comes from mango's defaults.conf (var=term,...); the editor is
# $EDITOR, which mango exports from env.conf.
config="$HOME/.config/mango"
term=$(sed -n 's/^var=term,//p' "$config/defaults.conf" 2>/dev/null | tail -n 1)
term="${term:-foot}"
edit="${EDITOR:-nano}"
# ##################################### #

# variables
rofi_theme="$HOME/.config/rofi/config-edit.rasi"
msg='Выберите действие'
iDIR="$HOME/.config/hypr/notify/images"
scriptsDir="$HOME/.config/hypr/scripts"
UserScripts="$HOME/.config/hypr/UserScripts"

# Function to show info notification
show_info() {
    # note.png, not info.png: $iDIR is hypr/notify/images here and there is no
    # info.png in it (nor anywhere in the repo), so every one of these
    # notifications rendered without an icon. note.png is what ScreenShot.sh
    # and ScreenRecord.sh already use for their informational notifications.
    notify-send -i "$iDIR/note.png" "Info" "$1"
}

# Function to display the menu options without numbers
menu() {
    cat <<EOF
--- НАСТРОЙКИ ---
Приложения по умолчанию
Сочетания клавиш
Переменные окружения
Автозапуск
Правила окон
Настройки и оформление
Анимации
Мониторы
Настройки ноутбука
--- УТИЛИТЫ ---
Мониторы (nwg-displays)
Оформление GTK (nwg-look)
Qt-приложения (qt6ct)
Qt-приложения (qt5ct)
Пресеты анимаций
Профиль мониторов
Тема rofi
Поиск сочетаний клавиш
Игровой режим вкл/выкл
EOF
}

# Main function to handle menu selection
main() {
    choice=$(menu | rofi -i -dmenu -config $rofi_theme -mesg "$msg")
    
    # Map choices to corresponding files
    case "$choice" in
    	"Приложения по умолчанию") file="$config/defaults.conf" ;;
        "Сочетания клавиш") file="$config/keybinds.conf" ;;
        "Переменные окружения") file="$config/env.conf" ;;
        "Автозапуск") file="$config/startup.conf" ;;
        "Правила окон") file="$config/rules.conf" ;;
        "Настройки и оформление") file="$config/settings.conf" ;;
        "Анимации") file="$config/animations.conf" ;;
        "Мониторы") file="$config/monitors.conf" ;;
        "Настройки ноутбука") file="$config/laptop.conf" ;;
        "Мониторы (nwg-displays)") 
            if ! command -v nwg-displays &>/dev/null; then
                notify-send -i "$iDIR/error.png" "ОШИБКА" "Сначала установите nwg-displays"
                exit 1
            fi
            nwg-displays ;;
		"Оформление GTK (nwg-look)") 
            if ! command -v nwg-look &>/dev/null; then
                notify-send -i "$iDIR/error.png" "ОШИБКА" "Сначала установите nwg-look"
                exit 1
            fi
            nwg-look ;;
		"Qt-приложения (qt6ct)") 
            if ! command -v qt6ct &>/dev/null; then
                notify-send -i "$iDIR/error.png" "ОШИБКА" "Сначала установите qt6ct"
                exit 1
            fi
            qt6ct ;;
		"Qt-приложения (qt5ct)") 
            if ! command -v qt5ct &>/dev/null; then
                notify-send -i "$iDIR/error.png" "ОШИБКА" "Сначала установите qt5ct"
                exit 1
            fi
            qt5ct ;;
        "Пресеты анимаций") $scriptsDir/Animations.sh ;;
        "Профиль мониторов") $scriptsDir/MonitorProfiles.sh ;;
        "Тема rofi") $scriptsDir/RofiThemeSelector.sh ;;
        "Поиск сочетаний клавиш") $scriptsDir/KeyBinds.sh ;;
        "Игровой режим вкл/выкл") $scriptsDir/GameMode.sh ;;
        *) return ;;  # Do nothing for invalid choices
    esac

    # Open the selected file in the terminal with the text editor
    if [ -n "$file" ]; then
        $term -e $edit "$file"
    fi
}

# Check if rofi is already running
if pidof rofi > /dev/null; then
  pkill rofi
fi

main
