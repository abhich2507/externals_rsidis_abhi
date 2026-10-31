#!/bin/tcsh
#
# cleanup.tcsh - remove all generated run/build artifacts from the repo.
#
# Removes:
#   OUT/*                (keeps .gitignore)
#   RUNPLAN/*            (keeps .gitignore)
#   runout/*             (keeps .gitignore)
#   INP/*                (keeps .gitignore and rsidis.template)
#   hcswif/FARM_SCRIPTS/* (keeps .gitignore and script_header.txt)
#   hcswif/json/*        (keeps .gitignore)
#   make_grid/a.out
#   root: *.o, externals_all, run_extern_farm
#
# Usage:
#   ./cleanup.tcsh          # asks for confirmation
#   ./cleanup.tcsh --yes    # skips confirmation

# Resolve repository root (works when run from any directory).
set SCRIPT = $0
if ("$SCRIPT" !~ /*) set SCRIPT = "$cwd/$SCRIPT"
set SCRIPT_DIR = `dirname "$SCRIPT"`
cd "$SCRIPT_DIR/.."
set ROOT = $cwd
cd "$ROOT"

set YES = 0
if ($#argv > 0) then
    if ("$1" == "--yes" || "$1" == "-y") set YES = 1
endif

echo ""
echo "[cleanup] repo: $ROOT"
echo "[cleanup] will remove:"
echo "    OUT/*                 (except .gitignore)"
echo "    RUNPLAN/*             (except .gitignore)"
echo "    runout/*              (except .gitignore)"
echo "    INP/*                 (except .gitignore and rsidis.template)"
echo "    hcswif/FARM_SCRIPTS/* (except .gitignore and script_header.txt)"
echo "    hcswif/json/*         (except .gitignore)"
echo "    make_grid/a.out"
echo "    *.o, externals_all, run_extern_farm (repo root)"

if ($YES == 0) then
    echo -n "Proceed? [y/N]: "
    set ANS = $<
    if ("$ANS" !~ [Yy]*) then
        echo "[cleanup] Aborted. Nothing removed."
        exit 0
    endif
endif

# Count files under the run-output directories before cleaning.
set BEFORE = `find OUT RUNPLAN runout INP hcswif/FARM_SCRIPTS hcswif/json -type f | wc -l`

# Per-directory removal, always keeping .gitignore (and the template/header).
if (-d OUT)                 find OUT                 -mindepth 1 -not -name '.gitignore' -delete
if (-d RUNPLAN)             find RUNPLAN             -mindepth 1 -not -name '.gitignore' -delete
if (-d runout)              find runout              -mindepth 1 -not -name '.gitignore' -delete
if (-d INP)                 find INP                 -mindepth 1 -not -name '.gitignore' -not -name 'rsidis.template' -delete
if (-d hcswif/FARM_SCRIPTS) find hcswif/FARM_SCRIPTS -mindepth 1 -not -name '.gitignore' -not -name 'script_header.txt' -delete
if (-d hcswif/json)         find hcswif/json         -mindepth 1 -not -name '.gitignore' -delete

# Build artifacts.
if (-e make_grid/a.out) rm -f make_grid/a.out
find . -maxdepth 1 -type f -name '*.o' -delete
rm -f externals_all run_extern_farm

set AFTER = `find OUT RUNPLAN runout INP hcswif/FARM_SCRIPTS hcswif/json -type f | wc -l`
@ REMOVED = $BEFORE - $AFTER

echo ""
echo "[cleanup] Done. Removed $REMOVED generated files."
echo "[cleanup] Kept: all .gitignore files, INP/rsidis.template, hcswif/FARM_SCRIPTS/script_header.txt"
