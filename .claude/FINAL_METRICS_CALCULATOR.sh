#!/bin/bash
# Final Session Metrics Calculator
# Calculates total LOC, files, commits for session summary

PROJECT_ROOT="/Volumes/Bojan - T7/DevVault/Projects/fluxforge-studio"
cd "$PROJECT_ROOT"

echo "📊 FINAL SESSION METRICS — 2026-01-30"
echo "======================================"
echo ""

# Git commits today
echo "🔹 GIT COMMITS (today):"
git log --since="2026-01-30 00:00" --oneline | nl
COMMIT_COUNT=$(git log --since="2026-01-30 00:00" --oneline | wc -l | tr -d ' ')
echo "Total: $COMMIT_COUNT commits"
echo ""

# LOC changes
echo "🔹 LOC CHANGES (since start of day):"
FIRST_COMMIT=$(git log --since="2026-01-30 00:00" --reverse --format="%H" | head -1)
if [ -n "$FIRST_COMMIT" ]; then
  git diff --shortstat "$FIRST_COMMIT"..HEAD
else
  echo "No commits today"
fi
echo ""

# New files
echo "🔹 NEW FILES (today):"
NEW_FILES=$(git diff --name-status "$FIRST_COMMIT"..HEAD 2>/dev/null | grep "^A" | wc -l | tr -d ' ')
echo "Total: $NEW_FILES new files"
echo ""

# Modified files
echo "🔹 MODIFIED FILES (today):"
MOD_FILES=$(git diff --name-status "$FIRST_COMMIT"..HEAD 2>/dev/null | grep "^M" | wc -l | tr -d ' ')
echo "Total: $MOD_FILES modified files"
echo ""

# Documentation files
echo "🔹 DOCUMENTATION (.claude/*.md):"
DOC_COUNT=$(ls -1 .claude/*2026_01_30.md 2>/dev/null | wc -l | tr -d ' ')
echo "Total: $DOC_COUNT session documents"
ls -1 .claude/*2026_01_30.md 2>/dev/null | sed 's|.claude/||'
echo ""

# Flutter analyze status
echo "🔹 BUILD STATUS:"
cd flutter_ui
ANALYZE_RESULT=$(flutter analyze 2>&1 | tail -1)
echo "  $ANALYZE_RESULT"
echo ""

# Final summary
echo "======================================"
echo "📈 SESSION TOTALS:"
echo "  Commits: $COMMIT_COUNT"
echo "  New Files: $NEW_FILES"
echo "  Modified Files: $MOD_FILES"
echo "  Documentation: $DOC_COUNT docs"
echo "  Build: $(echo $ANALYZE_RESULT | grep -q 'No issues' && echo '✅ PASS' || echo '⚠️ CHECK')"
echo "======================================"
