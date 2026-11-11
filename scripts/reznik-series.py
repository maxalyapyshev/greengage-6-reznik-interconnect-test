from pathlib import Path
import csv
import datetime
import os
import re
import subprocess
import sys
import time

root = Path(__file__).resolve().parent.parent
os.chdir(root)

os.environ["MSYS_NO_PATHCONV"] = "1"
os.environ["MSYS2_ARG_CONV_EXCL"] = "*"
os.environ["PYTHONUTF8"] = "1"

rounds = int(sys.argv[1]) if len(sys.argv) > 1 else 3
if rounds < 1:
    raise SystemExit("Number of rounds must be positive")

out = root / "results" / (
    "reznik-series-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
)
out.mkdir(parents=True, exist_ok=False)

def run_container(script, logfile):
    result = subprocess.run(
        [
            "docker", "compose", "exec", "-T",
            "--user", "gpadmin", "master", "bash", "-s",
        ],
        input=script.encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    output = result.stdout.decode("utf-8", errors="replace")
    logfile.write_text(output, encoding="utf-8", newline="\n")
    if result.returncode:
        print(output)
        raise SystemExit(f"FAILED. Log: {logfile}")
    return output

subprocess.run(
    [sys.executable, "scripts/prepare.py"],
    check=True,
)

source = Path("scripts/test.sh").read_text(encoding="utf-8")
load = Path("work/interconnect-universal-load.sh").read_text(
    encoding="utf-8"
)

start_anchor = "pids=()"
end_anchor = 'for ((i=1; i<=clients; i++)); do\n  echo "--- worker $i ---"'

if load.count(start_anchor) != 1 or load.count(end_anchor) != 1:
    raise SystemExit("Unexpected workload structure; no tests started")

load = load.replace(
    start_anchor,
    'run_start_ns=$(date +%s%N)\n' + start_anchor,
    1,
)
load = load.replace(
    end_anchor,
    'run_end_ns=$(date +%s%N)\n'
    'printf "T_RUN_NS=%s\\n" "$((run_end_ns-run_start_ns))"\n\n'
    + end_anchor,
    1,
)

(out / "measured-load.sh").write_text(
    load, encoding="utf-8", newline="\n"
)

# Use the existing preparation and checks, but do not run its load stages.
if source.count("IC_PACKET=") != 2:
    raise SystemExit("Unexpected test.sh structure; no tests started")

prepare = source.split("IC_PACKET=", 1)[0]
print("Preparation and checks: once before the series", flush=True)
run_container(prepare, out / "prepare.log")

prefix = """set -euo pipefail
source /opt/lab/scripts/env.sh
exec 9>/tmp/reznik-test.lock
flock -n 9 || { echo 'Another test is running' >&2; exit 2; }
cd /opt/lab/work
"""

row_output = run_container(
    prefix + """
psql -XqAt -v ON_ERROR_STOP=1 -d adb \
  -c 'SELECT count(*) FROM public.interconnect_universal_seed;'
""",
    out / "row-count.log",
)
row_count = int(row_output.strip())

fields = [
    "round", "transport", "packet", "stage", "sessions",
    "repeats", "rows", "payload_repeat", "queue_depth",
    "successful_queries", "payload_bytes_per_query",
    "T_run_s", "B_run_Gbit_s", "t_avg_ms", "B_avg_Gbit_s",
]

with (out / "summary.csv").open(
    "w", encoding="utf-8-sig", newline=""
) as f:
    writer = csv.DictWriter(f, fieldnames=fields)
    writer.writeheader()

    for round_no in range(1, rounds + 1):
        transports = (
            [("udpifc", 8192), ("tcp", 65507)]
            if round_no % 2
            else [("tcp", 65507), ("udpifc", 8192)]
        )

        for transport, packet in transports:
            stages = [
                ("control", 1, 1, 8, 32),
                ("parallel", 2, 10, 16, 32),
            ]

            for stage, clients, repeats, payload, queue in stages:
                label = f"{round_no}-{transport}-{stage}"
                print(f"\nRunning {label}...", flush=True)

                command = (
                    prefix
                    + f"export IC_PACKET={packet}\n"
                    + f"set -- {transport} {clients} {repeats} "
                      f"{payload} {queue}\n"
                    + load
                )
                output = run_container(command, out / f"{label}.log")

                if "All workers completed successfully." not in output:
                    raise SystemExit(f"Missing success marker: {label}")

                durations = [
                    float(x) for x in re.findall(
                        r"^Time:\s+([0-9.]+)\s+ms",
                        output, re.MULTILINE,
                    )
                ]
                ticks = re.findall(
                    r"^T_RUN_NS=(\d+)$", output, re.MULTILINE
                )
                q = clients * repeats

                if len(durations) != q or len(ticks) != 1:
                    raise SystemExit(
                        f"Unexpected timing output: {label}; inspect log"
                    )

                t_run = int(ticks[0]) / 1e9
                t_avg_ms = sum(durations) / q
                v = row_count * 1024 * payload
                b_run = q * v * 8 / (t_run * 1e9)
                b_avg = clients * v * 8 / (t_avg_ms / 1000 * 1e9)

                writer.writerow(dict(zip(fields, [
                    round_no, transport, packet, stage, clients,
                    repeats, row_count, payload, queue,
                    q, v, t_run, b_run, t_avg_ms, b_avg,
                ])))
                f.flush()

                print(
                    f"{transport:6} | {stage:8} | "
                    f"T_run={t_run:.3f} s | "
                    f"B_run={b_run:.3f} Gbit/s | "
                    f"B_avg={b_avg:.3f} Gbit/s",
                    flush=True,
                )
                time.sleep(2)

print(f"\nCompleted. Results: {out.relative_to(root)}")
