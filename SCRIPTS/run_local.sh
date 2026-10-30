#!/usr/bin/env bash
#
# run_local.sh - Run the full externals_rsidis radiative-correction table
# generation locally, end to end.
#
# It prompts for the beam energy, target, scattered-electron (E') grid,
# spectrometer angle grid, and a workflow name. It then:
#   1. builds externals_all if needed,
#   2. writes the RUNPLAN kinematic grid files,
#   3. writes the INP input files,
#   4. runs externals_all for every angle in parallel,
#   5. combines the per-angle tables into one master table.
#
# Usage:
#   ./run_local.sh
#
# All energies are in GeV and all angles are in degrees.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

info() { printf '\033[1;32m[run_local]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[run_local]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[run_local] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

is_num() {
    awk -v v="$1" 'BEGIN{exit !(v ~ /^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$/)}'
}

read_num() {
    local prompt="$1" default="$2" ans
    while true; do
        read -r -p "$prompt [$default]: " ans
        ans="${ans:-$default}"
        if is_num "$ans"; then
            echo "$ans"
            return 0
        fi
        warn "Invalid number: '$ans'"
    done
}

info "externals_rsidis local runner (repo: $ROOT)"

# ---------------------------------------------------------------------------
# 1. Gather settings
# ---------------------------------------------------------------------------

echo
echo "Available targets in TARG/:"
targs=()
for f in TARG/targ.*; do
    [[ -e "$f" ]] || continue
    targs+=("${f#TARG/targ.}")
done
printf '  %s\n' "${targs[@]}"
echo

TARG_DEFAULT="12carbon25_hms"
read -r -p "Target (extension) [$TARG_DEFAULT]: " TARG
TARG="${TARG:-$TARG_DEFAULT}"
[[ -f "TARG/targ.$TARG" ]] || die "target file TARG/targ.$TARG does not exist"

EBEAM="$(read_num "Beam energy [GeV]" "8.5831")"
EPMIN="$(read_num "Minimum scattered electron energy E' [GeV]" "1.35")"
EPMAX="$(read_num "Maximum scattered electron energy E' [GeV]" "1.70")"
EPSTEP="$(read_num "E' step size [GeV]" "0.01")"
THMIN="$(read_num "Theta min [deg]" "24.0")"
THMAX="$(read_num "Theta max [deg]" "34.0")"
THSTEP="$(read_num "Theta step size [deg]" "0.2")"

NAME_DEFAULT="local_run"
read -r -p "Workflow name (used for INP/OUT file names) [$NAME_DEFAULT]: " NAME
NAME="${NAME:-$NAME_DEFAULT}"

if command -v nproc >/dev/null 2>&1; then
    NCPU="$(nproc)"
else
    NCPU="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
fi
JOBS_DEFAULT=$(( NCPU / 2 ))
(( JOBS_DEFAULT > 12 )) && JOBS_DEFAULT=12
(( JOBS_DEFAULT < 1 )) && JOBS_DEFAULT=1
JOBS="$(read_num "Number of parallel angle jobs" "$JOBS_DEFAULT")"

# Validate ranges.
awk -v a="$EPMIN" -v b="$EPMAX" 'BEGIN{exit !(b > a)}' || die "E' max must be greater than E' min"
awk -v a="$THMIN" -v b="$THMAX" 'BEGIN{exit !(b > a)}' || die "theta max must be greater than theta min"
awk -v s="$EPSTEP" 'BEGIN{exit !(s > 0)}' || die "E' step must be positive"
awk -v s="$THSTEP" 'BEGIN{exit !(s > 0)}' || die "theta step must be positive"

# The code stores beam energy with a 3-decimal fixed-width format (F6.3).
EB="$(printf '%.3f' "$EBEAM")"
if awk -v e="$EBEAM" -v eb="$EB" 'BEGIN{exit !(e+0 != eb+0)}'; then
    warn "externals_all keeps 3 decimal places for Ebeam; $EBEAM will be used as $EB GeV"
fi

# ---------------------------------------------------------------------------
# 2. Build externals_all if needed
# ---------------------------------------------------------------------------

if [[ ! -x "$ROOT/externals_all" ]]; then
    info "Building externals_all (this may take a minute)..."
    make -C "$ROOT"
fi
[[ -x "$ROOT/run_extern" ]] || chmod +x "$ROOT/run_extern"

# ---------------------------------------------------------------------------
# 3. Generate RUNPLAN grid files and INP input files
# ---------------------------------------------------------------------------

NTH="$(awk -v a="$THMIN" -v b="$THMAX" -v s="$THSTEP" 'BEGIN{printf "%.0f", (b-a)/s}')"
NP="$(awk -v a="$EPMIN" -v b="$EPMAX" -v s="$EPSTEP" 'BEGIN{printf "%.0f", (b-a)/s}')"

# Guard against a step that does not divide the requested range evenly.
awk -v a="$THMIN" -v b="$THMAX" -v s="$THSTEP" -v n="$NTH" 'BEGIN{exit !(a+n*s != b)}' \
    && warn "theta step does not land exactly on theta max; last angle will be $(awk -v a="$THMIN" -v n="$NTH" -v s="$THSTEP" 'BEGIN{printf "%.1f", a+n*s}') deg"
awk -v a="$EPMIN" -v b="$EPMAX" -v s="$EPSTEP" -v n="$NP" 'BEGIN{exit !(a+n*s != b)}' \
    && warn "E' step does not land exactly on E' max; last point will be $(awk -v a="$EPMIN" -v n="$NP" -v s="$EPSTEP" 'BEGIN{printf "%.4f", a+n*s}') GeV"

mkdir -p INP RUNPLAN OUT runout

# Write one RUNPLAN file per angle (same fixed-width layout make_grid uses)
# and the matching INP file that points externals_all at it.
bases=()
while IFS= read -r ang; do
    [[ -n "$ang" ]] || continue
    angp="${ang/./p}"
    base="${NAME}_${angp}_${TARG}"
    bases+=("$base")

    runplan="RUNPLAN/${EB}gev_th_${ang}deg.inp"
    awk -v eb="$EBEAM" -v pmin="$EPMIN" -v pstep="$EPSTEP" -v np="$NP" -v th="$ang" \
        'BEGIN{
            for (j = 0; j <= np; j++) {
                p = pmin + j * pstep;
                printf "%6.3f %7.4f %7.4f\n", eb, p, th;
            }
        }' > "$runplan"

    {
        echo "input files for EXTERNAL: runplan/target/output"
        echo "RUNPLAN/${EB}gev_th_${ang}deg.inp"
        echo "TARG/targ.${TARG}"
        echo "OUT/${EB}gev_${ang}_${TARG}_details.out"
    } > "INP/${base}.inp"
done < <(awk -v a="$THMIN" -v n="$NTH" -v s="$THSTEP" 'BEGIN{for(i=0;i<=n;i++) printf "%.1f\n", a+i*s}')

info "Prepared ${#bases[@]} angle files ($((NP + 1)) E' points each) for target '$TARG'"

# ---------------------------------------------------------------------------
# 4. Confirm and run
# ---------------------------------------------------------------------------

echo
printf 'Ready to run %d angle files with %d parallel jobs.\n' "${#bases[@]}" "$JOBS"
read -r -p "Proceed? [Y/n]: " proceed
[[ "$proceed" =~ ^[Nn] ]] && { info "Aborted."; exit 0; }

runlist="$(mktemp)"
printf '%s\n' "${bases[@]}" > "$runlist"

info "Running externals_all (logs: runout/<name>.out, results: OUT/<name>.out)..."
pids=()
count=0
while IFS= read -r base; do
    [[ -n "$base" ]] || continue
    ./run_extern "$base" &
    pids+=("$!")
    count=$((count + 1))
    if (( count % JOBS == 0 )); then
        wait "${pids[@]}" || true
        pids=()
    fi
done < "$runlist"
if (( ${#pids[@]} > 0 )); then
    wait "${pids[@]}" || true
fi
rm -f "$runlist"

# ---------------------------------------------------------------------------
# 5. Verify outputs and combine
# ---------------------------------------------------------------------------

missing=0
for base in "${bases[@]}"; do
    if [[ ! -s "OUT/${base}.out" ]]; then
        warn "missing or empty output: OUT/${base}.out"
        missing=1
    fi
done
(( missing )) && die "some jobs failed; inspect runout/*.out for details"

combined="OUT/${NAME}_${TARG}.out"
cat SCRIPTS/header.txt > "$combined"
for base in "${bases[@]}"; do
    cat "OUT/${base}.out" >> "$combined"
done

info "Done."
info "  Master table : $combined"
info "  Per-angle    : OUT/${NAME}_*_${TARG}.out (and _int.out)"
info "  Logs         : runout/${NAME}_*_${TARG}.out"
