#!/bin/bash
# FluxForge Studio — Project-wide AppleDouble Cleanup
# Briše SVE ._* fajlove iz projekta (osim target/ i .git/)
# Razlog: macOS kreira ._* na ExFAT/NTFS volumima → codesign greške, disk waste
#
# Korišćenje:
#   ./scripts/clean-appledouble.sh          # Briše + ispisuje rezultat
#   ./scripts/clean-appledouble.sh --dry    # Samo prikazuje šta bi obrisao
#   ./scripts/clean-appledouble.sh --quiet  # Briše bez ispisa pojedinačnih fajlova

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

DRY_RUN=false
QUIET=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry|--dry-run)
            DRY_RUN=true
            shift
            ;;
        --quiet|-q)
            QUIET=true
            shift
            ;;
        *)
            echo "Usage: $0 [--dry-run] [--quiet]"
            exit 1
            ;;
    esac
done

# Pronađi sve ._* fajlove, preskačući target/ i .git/
FILES=$(find "$PROJECT_ROOT" \
    -name '._*' \
    -type f \
    -not -path '*/target/*' \
    -not -path '*/.git/*' \
    -not -path '*/build/*' \
    -not -path '*/DerivedData/*' \
    2>/dev/null || true)

if [ -z "$FILES" ]; then
    [ "$QUIET" = false ] && echo "✅ Nema AppleDouble fajlova — projekat je čist."
    exit 0
fi

# Izračunaj count i veličinu
COUNT=$(echo "$FILES" | wc -l | tr -d ' ')
TOTAL_SIZE=$(echo "$FILES" | xargs -I{} stat -f%z "{}" 2>/dev/null | awk '{s+=$1}END{print s}' || echo "0")
SIZE_MB=$(echo "scale=1; $TOTAL_SIZE / 1048576" | bc 2>/dev/null || echo "?")

if [ "$DRY_RUN" = true ]; then
    echo "🔍 DRY RUN — pronađeno $COUNT AppleDouble fajlova (~${SIZE_MB}MB)"
    echo ""
    if [ "$QUIET" = false ]; then
        echo "$FILES" | while read -r f; do
            echo "  ❌ $f"
        done
    fi
    echo ""
    echo "Pokreni bez --dry-run da obrišeš."
    exit 0
fi

# Brisanje
if [ "$QUIET" = false ]; then
    echo "🧹 Brisanje $COUNT AppleDouble fajlova (~${SIZE_MB}MB)..."
    echo ""
fi

DELETED=0
echo "$FILES" | while read -r f; do
    if [ -f "$f" ]; then
        rm -f "$f"
        [ "$QUIET" = false ] && echo "  ✓ $(echo "$f" | sed "s|$PROJECT_ROOT/||")"
        DELETED=$((DELETED + 1))
    fi
done

echo ""
echo "✅ Obrisano $COUNT AppleDouble fajlova (~${SIZE_MB}MB oslobođeno)"
