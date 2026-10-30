#!/bin/tcsh
#
# run_swif2.tcsh - swif2 farm version of the local end-to-end runner for
# externals_rsidis. Like run_local.tcsh it reads the kinematic settings
# (from a settings file, or interactively), generates the RUNPLAN/INP
# files, and then submits one farm job per angle to swif2 instead of
# running on the local machine.
#
# Usage:
#   ./run_swif2.tcsh [kinematic_settings.tcsh]
#
# The farm workflow uses the "clas12" account by default. Override it in
# the settings file with: set ACCOUNT = <account>
#
# Energies are in GeV and angles are in degrees.

# Resolve repository root (works when run from any directory).
set SCRIPT = $0
if ("$SCRIPT" !~ /*) set SCRIPT = "$cwd/$SCRIPT"
set SCRIPT_DIR = `dirname "$SCRIPT"`
cd "$SCRIPT_DIR/.."
set ROOT = $cwd
cd "$ROOT"

echo ""
echo "[run_swif2] externals_rsidis swif2 runner (repo: $ROOT)"

# ---------------------------------------------------------------------------
# 1. Settings: from a file if given, otherwise prompt
# ---------------------------------------------------------------------------

if ($#argv > 0) then
    if (! -f "$1") then
        echo "[run_swif2] ERROR: settings file not found: $1"
        exit 1
    endif
    echo "[run_swif2] Reading settings from $1"
    source "$1"
    goto settings_loaded
endif

echo ""
echo "Available targets in TARG/:"
foreach f (TARG/targ.*)
    set t = `basename "$f"`
    set t = `echo "$t" | sed 's/^targ\.//'`
    echo "  $t"
end
echo ""

echo -n "Target (extension) [12carbon25_hms]: "
set TARG = $<
if ("$TARG" == "") set TARG = "12carbon25_hms"
if (! -f "TARG/targ.$TARG") then
    echo "[run_swif2] ERROR: target file TARG/targ.$TARG does not exist"
    exit 1
endif

read_ebeam:
    echo -n "Beam energy [GeV] [8.5831]: "
    set EBEAM = $<
    if ("$EBEAM" == "") set EBEAM = "8.5831"
    echo "$EBEAM" | awk '{exit !($0 ~ /^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$/)}'
    if ($status != 0) then
        echo "Invalid number: $EBEAM"
        goto read_ebeam
    endif

read_epmin:
    echo -n "Minimum scattered electron energy E' [GeV] [1.35]: "
    set EPMIN = $<
    if ("$EPMIN" == "") set EPMIN = "1.35"
    echo "$EPMIN" | awk '{exit !($0 ~ /^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$/)}'
    if ($status != 0) then
        echo "Invalid number: $EPMIN"
        goto read_epmin
    endif

read_epmax:
    echo -n "Maximum scattered electron energy E' [GeV] [1.70]: "
    set EPMAX = $<
    if ("$EPMAX" == "") set EPMAX = "1.70"
    echo "$EPMAX" | awk '{exit !($0 ~ /^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$/)}'
    if ($status != 0) then
        echo "Invalid number: $EPMAX"
        goto read_epmax
    endif

read_epstep:
    echo -n "E' step size [GeV] [0.01]: "
    set EPSTEP = $<
    if ("$EPSTEP" == "") set EPSTEP = "0.01"
    echo "$EPSTEP" | awk '{exit !($0 ~ /^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$/)}'
    if ($status != 0) then
        echo "Invalid number: $EPSTEP"
        goto read_epstep
    endif

read_thmin:
    echo -n "Theta min [deg] [24.0]: "
    set THMIN = $<
    if ("$THMIN" == "") set THMIN = "24.0"
    echo "$THMIN" | awk '{exit !($0 ~ /^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$/)}'
    if ($status != 0) then
        echo "Invalid number: $THMIN"
        goto read_thmin
    endif

read_thmax:
    echo -n "Theta max [deg] [34.0]: "
    set THMAX = $<
    if ("$THMAX" == "") set THMAX = "34.0"
    echo "$THMAX" | awk '{exit !($0 ~ /^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$/)}'
    if ($status != 0) then
        echo "Invalid number: $THMAX"
        goto read_thmax
    endif

read_thstep:
    echo -n "Theta step size [deg] [0.2]: "
    set THSTEP = $<
    if ("$THSTEP" == "") set THSTEP = "0.2"
    echo "$THSTEP" | awk '{exit !($0 ~ /^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$/)}'
    if ($status != 0) then
        echo "Invalid number: $THSTEP"
        goto read_thstep
    endif

echo -n "Workflow name (used for INP/OUT file names) [local_run]: "
set NAME = $<
if ("$NAME" == "") set NAME = "local_run"

settings_loaded:

# ---------------------------------------------------------------------------
# 2. Required / optional settings
# ---------------------------------------------------------------------------

if (! $?TARG) then
    echo "[run_swif2] ERROR: settings file is missing TARG"
    exit 1
endif
if (! $?EBEAM) then
    echo "[run_swif2] ERROR: settings file is missing EBEAM"
    exit 1
endif
if (! $?EPMIN) then
    echo "[run_swif2] ERROR: settings file is missing EPMIN"
    exit 1
endif
if (! $?EPMAX) then
    echo "[run_swif2] ERROR: settings file is missing EPMAX"
    exit 1
endif
if (! $?EPSTEP) then
    echo "[run_swif2] ERROR: settings file is missing EPSTEP"
    exit 1
endif
if (! $?THMIN) then
    echo "[run_swif2] ERROR: settings file is missing THMIN"
    exit 1
endif
if (! $?THMAX) then
    echo "[run_swif2] ERROR: settings file is missing THMAX"
    exit 1
endif
if (! $?THSTEP) then
    echo "[run_swif2] ERROR: settings file is missing THSTEP"
    exit 1
endif
if (! $?NAME) then
    echo "[run_swif2] ERROR: settings file is missing NAME"
    exit 1
endif

# Farm settings (override in the settings file if desired).
if (! $?ACCOUNT) set ACCOUNT = clas12
if (! $?TIME)    set TIME    = 86400
if (! $?RAM)     set RAM     = 50000000
if (! $?DISK)    set DISK    = 10000000000

# ---------------------------------------------------------------------------
# 3. Validate ranges
# ---------------------------------------------------------------------------

awk -v a="$EPMIN" -v b="$EPMAX" 'BEGIN{exit !(b > a)}'
if ($status != 0) then
    echo "[run_swif2] ERROR: E' max must be greater than E' min"
    exit 1
endif
awk -v a="$THMIN" -v b="$THMAX" 'BEGIN{exit !(b > a)}'
if ($status != 0) then
    echo "[run_swif2] ERROR: theta max must be greater than theta min"
    exit 1
endif
awk -v s="$EPSTEP" 'BEGIN{exit !(s > 0)}'
if ($status != 0) then
    echo "[run_swif2] ERROR: E' step must be positive"
    exit 1
endif
awk -v s="$THSTEP" 'BEGIN{exit !(s > 0)}'
if ($status != 0) then
    echo "[run_swif2] ERROR: theta step must be positive"
    exit 1
endif

# The code stores beam energy with a 3-decimal fixed-width format (F6.3).
set EB = `echo "$EBEAM" | awk '{printf "%.3f", $1}'`
awk -v e="$EBEAM" -v eb="$EB" 'BEGIN{exit !(e+0 != eb+0)}'
if ($status == 0) then
    echo "[run_swif2] externals_all keeps 3 decimal places for Ebeam; $EBEAM will be used as $EB GeV"
endif

# ---------------------------------------------------------------------------
# 4. Build externals_all if needed
# ---------------------------------------------------------------------------

if (! -x externals_all) then
    echo "[run_swif2] Building externals_all..."
    make
endif
if (! -x run_extern) chmod +x run_extern

# ---------------------------------------------------------------------------
# 5. Generate RUNPLAN grid files and INP input files
# ---------------------------------------------------------------------------

set NTH = `awk -v a="$THMIN" -v b="$THMAX" -v s="$THSTEP" 'BEGIN{printf "%.0f", (b-a)/s}'`
set NP  = `awk -v a="$EPMIN" -v b="$EPMAX" -v s="$EPSTEP" 'BEGIN{printf "%.0f", (b-a)/s}'`

mkdir -p INP RUNPLAN OUT runout hcswif/FARM_SCRIPTS

set ANGLES = /tmp/run_swif2_angles.$$
set BASES  = /tmp/run_swif2_bases.$$
set LIST   = hcswif/FARM_SCRIPTS/${NAME}_${TARG}_list.txt
awk -v a="$THMIN" -v n="$NTH" -v s="$THSTEP" 'BEGIN{for(i=0;i<=n;i++) printf "%.1f\n", a+i*s}' > $ANGLES
rm -f $BASES $LIST

foreach ang (`cat $ANGLES`)
    set angp = `echo "$ang" | tr . p`
    set base = "${NAME}_${angp}_${TARG}"
    echo "$base" >> $BASES

    # RUNPLAN file for this angle (same fixed-width layout make_grid uses).
    set runplan = "RUNPLAN/${EB}gev_th_${ang}deg.inp"
    awk -v eb="$EBEAM" -v pmin="$EPMIN" -v pstep="$EPSTEP" -v np="$NP" -v th="$ang" 'BEGIN{for(j=0;j<=np;j++){p=pmin+j*pstep; printf "%6.3f %7.4f %7.4f\n", eb, p, th}}' > $runplan

    # INP file pointing externals_all at the runplan/target/output.
    echo "input files for EXTERNAL: runplan/target/output" > "INP/${base}.inp"
    echo "RUNPLAN/${EB}gev_th_${ang}deg.inp" >> "INP/${base}.inp"
    echo "TARG/targ.${TARG}" >> "INP/${base}.inp"
    echo "OUT/${EB}gev_${ang}_${TARG}_details.out" >> "INP/${base}.inp"

    # One farm script per angle; each runs run_extern_farm <infile>.
    set scriptfile = "hcswif/FARM_SCRIPTS/${base}.sh"
    cat hcswif/FARM_SCRIPTS/script_header.txt >! $scriptfile
    echo "${ROOT}/run_extern_farm ${base}" >> $scriptfile
    chmod a+x $scriptfile
    echo "${ROOT}/hcswif/FARM_SCRIPTS/${base}.sh" >> $LIST
end

set NBASES = `wc -l < $BASES | tr -d ' '`
@ NP1 = $NP + 1
echo "[run_swif2] Prepared $NBASES angle files ($NP1 E' points each) for target '$TARG'"

# ---------------------------------------------------------------------------
# 6. Make run_extern_farm (cd's into the repo before running)
# ---------------------------------------------------------------------------

echo "cd ${ROOT}" >! dir_file.txt
cat dir_file.txt run_extern >! run_extern_farm
chmod a+x run_extern_farm

# ---------------------------------------------------------------------------
# 7. Submit to swif2
# ---------------------------------------------------------------------------

set WF = externals_${NAME}_${TARG}
echo ""
echo "[run_swif2] Workflow : $WF"
echo "[run_swif2] Account  : $ACCOUNT"
echo "[run_swif2] Jobs     : $NBASES"

echo -n "Proceed? [Y/n]: "
set PROCEED = $<
if ("$PROCEED" =~ [Nn]*) then
    echo "[run_swif2] Aborted."
    rm -f $ANGLES $BASES
    exit 0
endif

# First-run note: if the workflow does not exist yet, swif2 prints an error
# (e.g. "there is no workflow named ..."). This is expected and harmless.
swif2 cancel $WF -delete

cd hcswif
./hcswif.py --mode command --command file $LIST --name $WF --account $ACCOUNT --time $TIME --ram $RAM --disk $DISK
cd "$ROOT"

swif2 import -file hcswif/json/${WF}.json
swif2 run $WF

rm -f $ANGLES $BASES

echo ""
echo "[run_swif2] Submitted. Monitor with:"
echo "    swif2 status $WF"
echo ""
echo "[run_swif2] When all jobs succeed, combine the table with:"
echo "    cd $ROOT/SCRIPTS"
echo "    ./combine_output.sh $TARG $THMIN `expr $NTH + 1` $NAME"
echo ""
echo "[run_swif2] Master table: OUT/${NAME}_${TARG}.out"
