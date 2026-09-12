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
msg=' ⁉️ Choose what to do ⁉️'
iDIR="$HOME/.config/swaync/images"
scriptsDir="$HOME/.config/hypr/scripts"
UserScripts="$HOME/.config/hypr/UserScripts"

# Function to show info notification
show_info() {
    notify-send -i "$iDIR/info.png" "Info" "$1"
}

# Function to display the menu options without numbers
menu() {
    cat <<EOF
--- USER CUSTOMIZATIONS ---
Edit User Defaults
Edit User Keybinds
Edit User ENV variables
Edit User Startup Apps (overlay)
Edit User Window Rules (overlay)
Edit User Settings
Edit User Decorations
Edit User Animations
Edit User Laptop Settings
--- SYSTEM DEFAULTS  ---
Edit System Default Keybinds
Edit System Default Startup Apps
Edit System Default Window Rules
Edit System Default Settings
--- UTILITIES ---
Configure Monitors (nwg-displays)
Configure Workspace Rules (nwg-displays)
GTK Settings (nwg-look)
QT Apps Settings (qt6ct)
QT Apps Settings (qt5ct)
Choose Hyprland Animations
Choose Monitor Profiles
Choose Rofi Themes
Search for Keybinds
Toggle Game Mode
Switch Dark-Light Theme
EOF
}

# Main function to handle menu selection
main() {
    choice=$(menu | rofi -i -dmenu -config $rofi_theme -mesg "$msg")
    
    # Map choices to corresponding files
    case "$choice" in
    	"Edit User Defaults") file="$UserConfigs/01-UserDefaults.lua" ;;
        "Edit User ENV variables") file="$UserConfigs/ENVariables.lua" ;;
        "Edit User Keybinds") file="$UserConfigs/UserKeybinds.lua" ;;
        "Edit User Startup Apps (overlay)") file="$UserConfigs/Startup_Apps.lua" ;;
        "Edit User Window Rules (overlay)") file="$UserConfigs/WindowRules.lua" ;;
        "Edit User Settings") file="$UserConfigs/UserSettings.lua" ;;
        "Edit User Decorations") file="$UserConfigs/UserDecorations.lua" ;;
        "Edit User Animations") file="$UserConfigs/UserAnimations.lua" ;;
        "Edit User Laptop Settings") file="$UserConfigs/Laptops.lua" ;;
        "Edit System Default Keybinds") file="$configs/Keybinds.lua" ;;
        "Edit System Default Startup Apps") file="$configs/Startup_Apps.lua" ;;
        "Edit System Default Window Rules") file="$configs/WindowRules.lua" ;;
        "Edit System Default Settings") file="$configs/SystemSettings.lua" ;;
        "Configure Monitors (nwg-displays)") 
            if ! command -v nwg-displays &>/dev/null; then
                notify-send -i "$iDIR/error.png" "E-R-R-O-R" "Install nwg-displays first"
                exit 1
            fi
            nwg-displays ;;
        "Configure Workspace Rules (nwg-displays)") 
            if ! command -v nwg-displays &>/dev/null; then
                notify-send -i "$iDIR/error.png" "E-R-R-O-R" "Install nwg-displays first"
                exit 1
            fi
            nwg-displays ;;
		"GTK Settings (nwg-look)") 
            if ! command -v nwg-look &>/dev/null; then
                notify-send -i "$iDIR/error.png" "E-R-R-O-R" "Install nwg-look first"
                exit 1
            fi
            nwg-look ;;
		"QT Apps Settings (qt6ct)") 
            if ! command -v qt6ct &>/dev/null; then
                notify-send -i "$iDIR/error.png" "E-R-R-O-R" "Install qt6ct first"
                exit 1
            fi
            qt6ct ;;
		"QT Apps Settings (qt5ct)") 
            if ! command -v qt5ct &>/dev/null; then
                notify-send -i "$iDIR/error.png" "E-R-R-O-R" "Install qt5ct first"
                exit 1
            fi
            qt5ct ;;
        "Choose Hyprland Animations") $scriptsDir/Animations.sh ;;
        "Choose Monitor Profiles") $scriptsDir/MonitorProfiles.sh ;;
        "Choose Rofi Themes") $scriptsDir/RofiThemeSelector.sh ;;
        "Search for Keybinds") $scriptsDir/KeyBinds.sh ;;
        "Toggle Game Mode") $scriptsDir/GameMode.sh ;;
        "Switch Dark-Light Theme") $scriptsDir/DarkLight.sh ;;
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
