#!/usr/bin/env bash
# Rofi menu for Hyprland quick settings (SUPER SHIFT E)
# Updated for UserConfigs/configs separation

# Default terminal and EDITOR come from UserConfigs/01-UserDefaults.lua. It is a
# plain Lua table (no hl.* calls), so the stock `lua` interpreter can read it.
defaults_file="$HOME/.config/hypr/UserConfigs/01-UserDefaults.lua"
eval "$(DEFAULTS="$defaults_file" lua -e 'local d = dofile(os.getenv("DEFAULTS")); for k, v in pairs(d) do print(k .. "=" .. string.format("%q", v)) end')"
edit="${EDITOR:-${editor:-nano}}"
# ##################################### #

# variables
configs="$HOME/.config/hypr/configs"
UserConfigs="$HOME/.config/hypr/UserConfigs"
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
--- СВОИ НАСТРОЙКИ ---
Приложения по умолчанию
Свои сочетания клавиш
Свои переменные окружения
Свой автозапуск
Свои правила окон
Свои настройки
Своё оформление
Свои анимации
Настройки ноутбука
--- СИСТЕМНЫЕ НАСТРОЙКИ ---
Системные сочетания клавиш
Системный автозапуск
Системные правила окон
Системные настройки
--- УТИЛИТЫ ---
Мониторы (nwg-displays)
Рабочие столы (nwg-displays)
Оформление GTK (nwg-look)
Qt-приложения (qt6ct)
Qt-приложения (qt5ct)
Анимации Hyprland
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
    	"Приложения по умолчанию") file="$UserConfigs/01-UserDefaults.lua" ;;
        "Свои переменные окружения") file="$UserConfigs/ENVariables.lua" ;;
        "Свои сочетания клавиш") file="$UserConfigs/UserKeybinds.lua" ;;
        "Свой автозапуск") file="$UserConfigs/Startup_Apps.lua" ;;
        "Свои правила окон") file="$UserConfigs/WindowRules.lua" ;;
        "Свои настройки") file="$UserConfigs/UserSettings.lua" ;;
        "Своё оформление") file="$UserConfigs/UserDecorations.lua" ;;
        "Свои анимации") file="$UserConfigs/UserAnimations.lua" ;;
        "Настройки ноутбука") file="$UserConfigs/Laptops.lua" ;;
        "Системные сочетания клавиш") file="$configs/Keybinds.lua" ;;
        "Системный автозапуск") file="$configs/Startup_Apps.lua" ;;
        "Системные правила окон") file="$configs/WindowRules.lua" ;;
        "Системные настройки") file="$configs/SystemSettings.lua" ;;
        "Мониторы (nwg-displays)") 
            if ! command -v nwg-displays &>/dev/null; then
                notify-send -i "$iDIR/error.png" "ОШИБКА" "Сначала установите nwg-displays"
                exit 1
            fi
            nwg-displays ;;
        "Рабочие столы (nwg-displays)") 
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
        "Анимации Hyprland") $scriptsDir/Animations.sh ;;
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
