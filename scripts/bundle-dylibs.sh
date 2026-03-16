#!/bin/bash
# Bundle all Homebrew dylibs into the .app bundle and fix rpaths.
# This removes the Homebrew dependency for end users.
set -e

APP="$1"
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
    echo "Usage: $0 /path/to/VirtManager.app"
    exit 1
fi

FRAMEWORKS="$APP/Contents/Frameworks"
BINARY="$APP/Contents/MacOS/VirtManager"
mkdir -p "$FRAMEWORKS"

echo "=== Collecting dylibs ==="

# Recursively find all Homebrew dylibs needed
collect_dylibs() {
    local binary="$1"
    otool -L "$binary" 2>/dev/null | grep "/opt/homebrew" | awk '{print $1}' | while read dylib; do
        local name=$(basename "$dylib")
        if [ ! -f "$FRAMEWORKS/$name" ]; then
            echo "  Bundling: $name"
            cp "$dylib" "$FRAMEWORKS/$name"
            chmod 644 "$FRAMEWORKS/$name"
            # Recurse into this dylib's deps
            collect_dylibs "$FRAMEWORKS/$name"
        fi
    done
}

collect_dylibs "$BINARY"

echo ""
echo "=== Fixing install names ==="

# Fix the main binary to look in @executable_path/../Frameworks/
for dylib in "$FRAMEWORKS"/*.dylib; do
    name=$(basename "$dylib")
    old_path=$(otool -L "$BINARY" | grep "$name" | awk '{print $1}' | head -1)
    if [ -n "$old_path" ]; then
        echo "  Binary: $old_path → @executable_path/../Frameworks/$name"
        install_name_tool -change "$old_path" "@executable_path/../Frameworks/$name" "$BINARY" 2>/dev/null || true
    fi
done

# Fix each bundled dylib's own install name and its references to other dylibs
for dylib in "$FRAMEWORKS"/*.dylib; do
    name=$(basename "$dylib")

    # Fix its own install name
    install_name_tool -id "@executable_path/../Frameworks/$name" "$dylib" 2>/dev/null || true

    # Fix references to other Homebrew dylibs
    otool -L "$dylib" 2>/dev/null | grep "/opt/homebrew" | awk '{print $1}' | while read dep; do
        dep_name=$(basename "$dep")
        if [ -f "$FRAMEWORKS/$dep_name" ]; then
            install_name_tool -change "$dep" "@executable_path/../Frameworks/$dep_name" "$dylib" 2>/dev/null || true
        fi
    done
done

echo ""
echo "=== Verifying ==="

# Check no remaining Homebrew references
remaining=$(otool -L "$BINARY" 2>/dev/null | grep "/opt/homebrew" || true)
if [ -n "$remaining" ]; then
    echo "WARNING: Still referencing Homebrew:"
    echo "$remaining"
else
    echo "Binary: OK (no Homebrew references)"
fi

for dylib in "$FRAMEWORKS"/*.dylib; do
    name=$(basename "$dylib")
    remaining=$(otool -L "$dylib" 2>/dev/null | grep "/opt/homebrew" || true)
    if [ -n "$remaining" ]; then
        echo "WARNING: $name still references Homebrew:"
        echo "$remaining"
    fi
done

echo ""
echo "=== Bundled $(ls "$FRAMEWORKS"/*.dylib | wc -l | tr -d ' ') dylibs ==="
ls -lh "$FRAMEWORKS"/*.dylib | awk '{print "  " $NF " (" $5 ")"}'
echo ""
echo "Total Frameworks size: $(du -sh "$FRAMEWORKS" | cut -f1)"
