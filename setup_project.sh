#!/usr/bin/bash
#
# ==============================================================================
#  setup_project.sh  —  Project Factory for the Student Attendance Tracker
# ==============================================================================
#  Infrastructure as Code [IaC] bootstrapper.
#
#  What this script does, end to end:
#    1. Directory Architecture .... builds attendance_tracker_{input}/ with the
#                                   exact layout the Python app expects.
#    2. File Generation ........... writes attendance_checker.py, assets.csv,
#                                   config.json and reports.log from heredocs
#                                   [no manual copying => reproducible].
#    3. Dynamic Configuration ..... prompts with `read`, rewrites config.json
#                                   thresholds in-place with `sed`.
#    4. Process Management ........ a `trap` catches SIGINT [Ctrl+C], archives
#                                   the half-built project, then cleans up.
#    5. Environment Validation .... a health check confirms python3 is present
#                                   and the directory structure is intact.
#
#  Usage:
#    ./setup_project.sh [deploy_agent]
#       - If [deploy_agent] is omitted, the script will prompt for it.
# ==============================================================================

set -u  # treat unset variables as errors [catches typos early]

# ------------------------------------------------------------------------------
# Globals — recorded up front so the trap can always find its way home.
# ------------------------------------------------------------------------------
START_DIR="$(pwd)"      # where the user launched the script from
PROJECT_DIR=""          # set once we know the {input}; used by the trap
CONFIG_PATH=""          # full path to the config.json we will sed-edit

# Small colour helpers [degrade gracefully if the terminal has no colour].
if [ -t 1 ]; then
    C_OK=$'\033[0;32m'; C_WARN=$'\033[0;33m'; C_ERR=$'\033[0;31m'
    C_INFO=$'\033[0;36m'; C_BOLD=$'\033[1m'; C_RST=$'\033[0m'
else
    C_OK=""; C_WARN=""; C_ERR=""; C_INFO=""; C_BOLD=""; C_RST=""
fi

info()  { echo "${C_INFO}[*]${C_RST} $*"; }
ok()    { echo "${C_OK}[+]${C_RST} $*"; }
warn()  { echo "${C_WARN}[!]${C_RST} $*"; }
err()   { echo "${C_ERR}[x]${C_RST} $*"; }

# ==============================================================================
# 3 [defined early so it is armed the moment the project dir exists].
# PROCESS MANAGEMENT: the SIGINT trap.
# ==============================================================================
# If the user hits Ctrl+C while the project is being built, we don't want to
# leave a half-finished mess behind. Instead we:
#   [a] snapshot whatever exists so far into an archive, then
#   [b] delete the incomplete directory so the workspace stays clean.
# ------------------------------------------------------------------------------
cleanup_on_interrupt() {
    echo
    warn "Interrupt [Ctrl+C] received — rolling back this deployment."

    # Always operate from the launch directory so relative paths behave.
    cd "$START_DIR" 2>/dev/null || true

    if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ]; then
        local archive_base="${PROJECT_DIR}_archive"
        local archive_file="${archive_base}.tar.gz"

        info "Bundling current state into '${archive_file}'..."
        tar -czf "$archive_file" "$PROJECT_DIR" 2>/dev/null \
            && ok "Archive created: ${archive_file}" \
            || err "Could not create archive."

        info "Removing the incomplete directory '${PROJECT_DIR}'..."
        rm -rf "$PROJECT_DIR" \
            && ok "Workspace cleaned." \
            || err "Could not remove '${PROJECT_DIR}'."
    else
        info "No project directory to archive yet — nothing to clean."
    fi

    echo
    warn "Bootstrap aborted by user. Exiting."
    exit 130   # 128 + SIGINT(2) — the conventional exit code for Ctrl+C
}

# Arm the trap right away. [Harmless before PROJECT_DIR is set: the guard above
# simply finds nothing to archive.]
trap cleanup_on_interrupt SIGINT

# ==============================================================================
# 1a. Capture the {input} string for the directory name.
# ==============================================================================
echo "${C_BOLD}=== Attendance Tracker :: Project Factory ===${C_RST}"
echo

if [ "$#" -ge 1 ] && [ -n "${1:-}" ]; then
    PROJECT_INPUT="$1"
    info "Using project name from argument: '${PROJECT_INPUT}'"
else
    read -r -p "Enter a name/tag for this deployment: " PROJECT_INPUT
fi

# Fall back to a timestamp if the user gives nothing, so we never build a
# directory literally called 'attendance_tracker_'.
if [ -z "${PROJECT_INPUT// /}" ]; then
    PROJECT_INPUT="$(date +%Y%m%d_%H%M%S)"
    warn "No name given — defaulting to '${PROJECT_INPUT}'."
fi

# Replace any spaces with underscores to keep the path tidy.
PROJECT_INPUT="${PROJECT_INPUT// /_}"
PROJECT_DIR="attendance_tracker_${PROJECT_INPUT}"
CONFIG_PATH="${PROJECT_DIR}/Helpers/config.json"

# Refuse to clobber an existing deployment of the same name.
if [ -e "$PROJECT_DIR" ]; then
    err "'${PROJECT_DIR}' already exists. Choose another name or remove it first."
    exit 1
fi

# ==============================================================================
# 1b. DIRECTORY ARCHITECTURE
# ==============================================================================
#   attendance_tracker_{input}/
#   |-- attendance_checker.py
#   |-- Helpers/
#   |   |-- assets.csv
#   |   `-- config.json
#   `-- reports/
#       `-- reports.log
# ------------------------------------------------------------------------------
info "Building directory architecture..."
mkdir -p "${PROJECT_DIR}/Helpers" "${PROJECT_DIR}/reports"
ok "Created ${PROJECT_DIR}/ with Helpers/ and reports/"

# ==============================================================================
# 2. FILE GENERATION [heredocs — the IaC core: files are *code*, not copies]
# ==============================================================================

# --- 2a. The main application logic -------------------------------------------
# Quoted delimiter ('PYEOF') => the body is written verbatim, so Python's
# f-strings, $ and backticks are NOT touched by the shell.
cat > "${PROJECT_DIR}/attendance_checker.py" <<'PYEOF'
import csv
import json
import os
from datetime import datetime

def run_attendance_check():
    # 1. Load Config
    with open('Helpers/config.json', 'r') as f:
        config = json.load(f)
    
    # 2. Archive old reports.log if it exists
    if os.path.exists('reports/reports.log'):
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        os.rename('reports/reports.log', f'reports/reports_{timestamp}.log.archive')

    # 3. Process Data
    with open('Helpers/assets.csv', mode='r') as f, open('reports/reports.log', 'w') as log:
        reader = csv.DictReader(f)
        total_sessions = config['total_sessions']
        
        log.write(f"--- Attendance Report Run: {datetime.now()} ---\n")
        
        for row in reader:
            name = row['Names']
            email = row['Email']
            attended = int(row['Attendance Count'])
            
            # Simple Math: (Attended / Total) * 100
            attendance_pct = (attended / total_sessions) * 100
            
            message = ""
            if attendance_pct < config['thresholds']['failure']:
                message = f"URGENT: {name}, your attendance is {attendance_pct:.1f}%. You will fail this class."
            elif attendance_pct < config['thresholds']['warning']:
                message = f"WARNING: {name}, your attendance is {attendance_pct:.1f}%. Please be careful."
            
            if message:
                if config['run_mode'] == "live":
                    log.write(f"[{datetime.now()}] ALERT SENT TO {email}: {message}\n")
                    print(f"Logged alert for {name}")
                else:
                    print(f"[DRY RUN] Email to {email}: {message}")

if __name__ == "__main__":
    run_attendance_check()
PYEOF
ok "Wrote attendance_checker.py"

# --- 2b. The dataset ----------------------------------------------------------
cat > "${PROJECT_DIR}/Helpers/assets.csv" <<'CSVEOF'
Email,Names,Attendance Count,Absence Count
alice@example.com,Alice Johnson,14,1
bob@example.com,Bob Smith,7,8
charlie@example.com,Charlie Davis,4,11
diana@example.com,Diana Prince,15,0
CSVEOF
ok "Wrote Helpers/assets.csv"

# --- 2c. The configuration [default thresholds; sed may rewrite below] --------
cat > "${PROJECT_DIR}/Helpers/config.json" <<'JSONEOF'
{
    "thresholds": {
        "warning": 75,
        "failure": 50
    },
    "run_mode": "live",
    "total_sessions": 15
}
JSONEOF
ok "Wrote Helpers/config.json"

# --- 2d. An empty report log so the structure is complete on day one ----------
: > "${PROJECT_DIR}/reports/reports.log"
ok "Initialised reports/reports.log"

# ==============================================================================
# 3b. DYNAMIC CONFIGURATION  [read + sed in-place edit]
# ==============================================================================
echo
read -r -p "Update attendance thresholds now? [y/N]: " UPDATE_CHOICE

case "${UPDATE_CHOICE,,}" in
    y|yes)
        # --- Warning threshold ------------------------------------------------
        read -r -p "  New WARNING threshold % [default 75]: " WARN_IN
        WARN="${WARN_IN:-75}"
        if ! [[ "$WARN" =~ ^[0-9]+$ ]]; then
            warn "'${WARN}' is not a number — keeping default 75."
            WARN=75
        fi

        # --- Failure threshold ------------------------------------------------
        read -r -p "  New FAILURE threshold % [default 50]: " FAIL_IN
        FAIL="${FAIL_IN:-50}"
        if ! [[ "$FAIL" =~ ^[0-9]+$ ]]; then
            warn "'${FAIL}' is not a number — keeping default 50."
            FAIL=50
        fi

        # --- Stream-edit config.json in place ---------------------------------
        # -E: extended regex.  \1 keeps the "key": prefix, we swap only the number.
        sed -i -E "s/(\"warning\"[[:space:]]*:[[:space:]]*)[0-9]+/\1${WARN}/" "$CONFIG_PATH"
        sed -i -E "s/(\"failure\"[[:space:]]*:[[:space:]]*)[0-9]+/\1${FAIL}/" "$CONFIG_PATH"

        ok "config.json updated  ->  warning=${WARN}%, failure=${FAIL}%"
        ;;
    *)
        info "Keeping default thresholds (warning=75%, failure=50%)."
        ;;
esac

# ==============================================================================
# Interrupt-test window — gives a clear moment to demo the trap on video.
# Press Ctrl+C here [or at any prompt above] to trigger archive + cleanup.
# ==============================================================================
echo
info "Finalising deployment... [press ${C_BOLD}Ctrl+C${C_RST}${C_INFO} now to test the archive trap]"
sleep 3

# ==============================================================================
# 4. ENVIRONMENT VALIDATION [Health Check]
# ==============================================================================
echo
echo "${C_BOLD}--- Health Check ---${C_RST}"

# --- 4a. Is python3 available? ------------------------------------------------
if python --version >/dev/null 2>&1; then
    ok "python detected: $(python --version 2>&1)"
else
    warn "python NOT found. Install Python 3 before running attendance_checker.py."
fi

# --- 4b. Is the directory structure intact? -----------------------------------
STRUCTURE_OK=true
for required in \
    "${PROJECT_DIR}/attendance_checker.py" \
    "${PROJECT_DIR}/Helpers/assets.csv" \
    "${PROJECT_DIR}/Helpers/config.json" \
    "${PROJECT_DIR}/reports/reports.log"
do
    if [ -e "$required" ]; then
        ok "present: ${required}"
    else
        err "MISSING: ${required}"
        STRUCTURE_OK=false
    fi
done

# ==============================================================================
# Done.
# ==============================================================================
echo
if [ "$STRUCTURE_OK" = true ]; then
    echo "${C_OK}${C_BOLD}=== Deployment complete: ${PROJECT_DIR} ===${C_RST}"
    echo "Next steps:"
    echo "    cd ${PROJECT_DIR}"
    echo "    python3 attendance_checker.py"
    echo "    cat reports/reports.log"
else
    err "Deployment finished with structural problems [see above]."
    exit 1
fi

# The setup completed normally, so we no longer need the interrupt handler.
trap - SIGINT
