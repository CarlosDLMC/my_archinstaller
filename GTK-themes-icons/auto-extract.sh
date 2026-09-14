#!/bin/bash

# Set colors for output messages
OK="$(tput setaf 2)[OK]$(tput sgr0)"
ERROR="$(tput setaf 1)[ERROR]$(tput sgr0)"

# Set the name of the log file to include the current date and time
SLOG="install-$(date +%Y%m%d-%H%M%S)_themes.log"

# Function to extract files with overwrite option
extract_files() {
    local source_dir="$1"      # Source directory containing files
    local destination="$2"     # Destination directory for extraction
    local extraction_type="$3" # Type of extraction: "tar" or "unzip"

    if [ -d "$source_dir" ]; then
        echo "Extracting files from '$source_dir' directory to '$destination'..."
        if [ "$extraction_type" == "tar" ]; then
            for file in "$source_dir"/*.tar.gz; do
                if [ -f "$file" ]; then
                    echo "Extracting $file to $destination..."
                    tar -xzf "$file" -C "$destination" --overwrite && echo "$OK Extracted $file to $destination" || echo "$ERROR Extraction of $file failed"
                fi
            done
        elif [ "$extraction_type" == "unzip" ]; then
            for file in "$source_dir"/*.zip; do
                if [ -f "$file" ]; then
                    echo "Extracting $file to $destination..."
                    unzip -o -q "$file" -d "$destination" && echo "$OK Extracted $file to $destination" || echo "$ERROR Extraction of $file failed"
                fi
            done
        else
            echo "${ERROR} Invalid extraction type '$extraction_type'."
            return 1
        fi
        echo "$OK Extraction from '$source_dir' directory completed"
    else
        echo "${ERROR} Source directory '$source_dir' does not exist."
        return 1
    fi
}

# Create directories if they don't exist
mkdir -p ~/.icons
mkdir -p ~/.themes

# Extract files from 'theme' directory to ~/.themes using tar and log output
extract_files "theme" ~/.themes "tar" 2>&1 | tee -a "$SLOG"

# Extract files from 'icon' directory to ~/.icons using unzip and log output
extract_files "icon" ~/.icons "unzip" 2>&1 | tee -a "$SLOG"

# Rebuild the icon caches after extracting.
#
# The shipped archives carry an icon-theme.cache from whenever upstream built
# them, and extracting stamps the theme directory with the current time - so the
# cache is always older than the directory it describes, which is exactly how
# GTK decides a cache is stale. It then walks the whole theme on every GTK
# application start instead; Flat-Remix-Blue-Dark is ~40k files over 319MB.
# Rebuilding takes well under a second per theme.
#
# Cursor themes (Bibata) have an index.theme but no icon directories.
# gtk-update-icon-cache exits 0 and writes nothing for those, so they need no
# special case.
refresh_icon_caches() {
    if ! command -v gtk-update-icon-cache >/dev/null 2>&1; then
        echo "${ERROR} gtk-update-icon-cache not found - icon caches left stale"
        return 1
    fi

    for theme_dir in "$HOME"/.icons/*/; do
        [ -f "${theme_dir}index.theme" ] || continue

        if gtk-update-icon-cache -f -t "$theme_dir" >/dev/null 2>&1; then
            echo "$OK Refreshed icon cache for $(basename "$theme_dir")"
        else
            echo "${ERROR} Could not refresh icon cache for $(basename "$theme_dir")"
        fi
    done
}

refresh_icon_caches 2>&1 | tee -a "$SLOG"
