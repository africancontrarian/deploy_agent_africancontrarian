# deploy_agent — Attendance Tracker Project Factory

A single shell script (`setup_project.sh`) that **bootstraps** a complete Student
Attendance Tracker workspace using *Infrastructure as Code* principles:
reproducible structure, one-command setup, and no human error.

Running the script builds this layout (where `{input}` is the name you provide):

```
attendance_tracker_{input}/
├── attendance_checker.py        # main application logic
├── Helpers/
│   ├── assets.csv               # the student dataset
│   └── config.json              # thresholds + run settings
└── reports/
    └── reports.log              # populated when the app runs
```

> The folder names matter: `attendance_checker.py` reads `Helpers/config.json`,
> `Helpers/assets.csv` and writes `reports/reports.log` using exactly those
> (case-sensitive) paths, so it must be run **from inside** the project directory.

---

## How to run

```bash
# 1. Make the script executable (once)
chmod +x setup_project.sh

# 2a. Run it and pass a project name as an argument...
./setup_project.sh myclass

# 2b. ...or run with no argument and it will prompt you for the name
./setup_project.sh
```

During the run the script will:

1. Create the directory architecture above.
2. Generate all four files from scratch (heredocs — nothing is copied manually).
3. Ask **`Update attendance thresholds now? [y/N]`**
   - Answer `y` to type new **Warning** (default `75`) and **Failure** (default `50`)
     percentages. These are written into `config.json` *in place* using `sed`.
   - Answer `N` (or just press Enter) to keep the defaults.
4. Run a **health check** (confirms `python3` is installed and the structure is intact).

After it finishes, run the application:

```bash
cd attendance_tracker_myclass
python3 attendance_checker.py
cat reports/reports.log
```

---

## How to trigger the archive feature (the SIGINT trap)

The script installs a signal trap. If you **cancel the script mid-build**, it does
*not* leave a half-finished folder behind. Instead it snapshots the current state
into a `.tar.gz` archive and then deletes the incomplete directory.

To trigger it, press **`Ctrl+C`** while the script is running — the easiest moment
is at the `Update attendance thresholds now?` prompt, or during the
`Finalising deployment...` window. You will see:

```
^C
[!] Interrupt (Ctrl+C) received — rolling back this deployment.
[*] Bundling current state into 'attendance_tracker_myclass_archive.tar.gz'...
[+] Archive created: attendance_tracker_myclass_archive.tar.gz
[*] Removing the incomplete directory 'attendance_tracker_myclass'...
[+] Workspace cleaned.
[!] Bootstrap aborted by user. Exiting.
```

Inspect the saved archive at any time with:

```bash
tar -tzf attendance_tracker_myclass_archive.tar.gz   # list contents
tar -xzf attendance_tracker_myclass_archive.tar.gz   # restore it
```

The archive base name follows the spec: `attendance_tracker_{input}_archive`
(stored as a gzip-compressed tarball, so the file is `..._archive.tar.gz`).

---

## What each part of the script demonstrates

| Requirement | Implementation in `setup_project.sh` |
|---|---|
| Directory architecture | `mkdir -p` builds `Helpers/` and `reports/` |
| File generation | quoted-heredoc `cat > file <<'EOF'` writes each file verbatim |
| Dynamic configuration | `read` captures thresholds; `sed -i -E` rewrites `config.json` in place |
| Process management | `trap cleanup_on_interrupt SIGINT` → archive then `rm -rf` |
| Environment validation | `python3 --version` check + per-file structure verification |

### Built-in safeguards
- Refuses to overwrite an existing `attendance_tracker_{input}` directory.
- Non-numeric threshold input falls back to the defaults instead of corrupting `config.json`.
- Empty project name falls back to a timestamp; spaces are converted to underscores.
- Exits with code `130` on Ctrl+C (the conventional code for SIGINT).

---

## Requirements

- A POSIX shell environment with **Bash** (uses `[[ ]]`, `${var,,}`, `sed -E`).
- **Python 3** to run the generated `attendance_checker.py`.
- `tar` (standard on Linux/macOS) for the archive feature.
