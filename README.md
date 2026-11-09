# Bash-lab: sales processing pipeline

A small data pipeline built with **Bash**, **Docker** and **nginx**.

You drop daily sales CSV files into `input/`. A container picks them up every 10 seconds and does four things:

- checks each file
- adds its sales total to a report
- archives each file or sets it aside
- writes a log of everything it did

A small web page then shows the report at `http://localhost:8080`.

```
            ┌──────────────────────────── processor container (runs every 10 s) ───────────────────────────┐
 input/ ──► │ *.tmp  ─────────────────────────────────────────────────────────────────────────►  trash/      │
            │ *.csv  ─► has "unit_price" column? ── yes ─► sum quantity × unit_price ─► result/report.csv  │
            │                     │                                        └──────────────────► archive/    │
            │                     └─────────────── no ──────────────────────────────────────► errors/     │
            │ every step ─────────────────────────────────────────────────────────────────► logs/       │
            └──────────────────────────────────────────────────────────────────────────────────────────────┘
                                                        │
                                       result/ ─► viewer container (nginx) ─► http://localhost:8080
```

## Project layout

| Path | Role |
|---|---|
| [process-sales.sh](process-sales.sh) | The pipeline script: cleans up, validates, totals, archives and logs. |
| [dockerfile](dockerfile) | Alpine image with `bash`, `gawk` and `coreutils`. Runs the script in a loop every 10 s. |
| [docker-compose.yml](docker-compose.yml) | Starts two services: `processor` (the script) and `viewer` (nginx). |
| [viewer.conf](viewer.conf) | nginx config. Serves the page and lists the `result/` folder as JSON. |
| [viewer/index.html](viewer/index.html) | Web page that shows any CSV in `result/` as a table you can sort and filter. |
| [samples/](samples/) | Example input files (good, bad and junk) for testing the pipeline. |

The script creates these folders when it runs. Git ignores them.

| Folder | Content |
|---|---|
| `input/` | Where you drop new files |
| `result/` | `report.csv`, one line per processed file |
| `archive/` | Processed files, renamed `<name>_<YYYY-MM-DD>.csv` |
| `errors/` | CSV files without a `unit_price` column |
| `trash/` | `.tmp` junk files |
| `logs/` | One log file per day: `run_<YYYY-MM-DD>.log` |

## Quick start

Requirements: [Docker Desktop](https://www.docker.com/products/docker-desktop/) or Docker Engine with Compose.

```bash
git clone https://github.com/Aeljirai/bash-lab.git
cd bash-lab

# 1. Build the image and start both containers
docker compose up -d --build

# 2. Feed the pipeline with the sample files
mkdir -p input
cp samples/* input/

# 3. Wait about 10 seconds, then check the results
cat result/report.csv
cat logs/run_$(date +%F).log
```

Open **http://localhost:8080** to see the report in the browser.

Useful commands:

```bash
docker compose logs -f processor   # follow the script output live
docker compose down                # stop everything
```

## How the script works, step by step

[process-sales.sh](process-sales.sh) runs from top to bottom on each pass:

1. **Setup.** Creates all working folders with `mkdir -p`, so the script is safe to re-run. Writes the CSV header `id,date,city,sum` to `result/report.csv` only if the file is missing or empty (`[ -s ... ]`).
2. **Logging helper.** Every message goes through `log()`. It uses `tee -a`, so each line is shown on screen and also appended to `logs/run_<today>.log`.
3. **Remove junk first.** Every `input/*.tmp` file is moved to `trash/`.
4. **Process each CSV** in `input/` with `process_file`:
   - **Validate.** Checks that the header line contains `unit_price`.
   - **Valid file:**
     - `awk` takes the city from the first data row (column 5).
     - `awk` adds up `quantity × unit_price` (columns 3 × 4) over all rows.
     - A new line `id,date,city,sum` is added to the report.
     - The file is moved to `archive/` with today's date in its name.
   - **Invalid file:** it is moved to `errors/` and an `ERROR` line is logged.
5. **Done.** Writes `job finished` to the log.

Each loop of `[ -e "$f" ] || continue` guards against an empty folder. Without it, Bash would try to process the literal pattern `input/*.csv`.

### Expected input format

```csv
order_id,product_name,quantity,unit_price,city
1,The Sinya,10,32.00,Casablanca
2,Huile d'olive,5,75.50,Casablanca
```

### Example output

`result/report.csv`

```csv
id,date,city,sum
1,2026-11-09,Agadir,1782.00
2,2026-11-09,Casablanca,3058.50
3,2026-11-09,Tanger,2939.80
```

`logs/run_2026-11-09.log`

```
[16:46] INFO: job started
[16:46] INFO: moved debug.tmp to trash/
[16:46] INFO: moved sales_test.tmp to trash/
[16:46] INFO: reading input/sales_agadir.csv
[16:46] INFO: sales sum 1782.00
[16:46] INFO: archived as sales_agadir_2026-11-09.csv
...
[16:46] INFO: reading input/sales_fes_bad.csv
[16:46] ERROR: missing column 'unit_price' in sales_fes_bad.csv
[16:46] INFO: job finished
```

## The web viewer

The `viewer` service is a plain `nginx:alpine` container with three read-only mounts:

- `viewer/` is the page itself.
- `result/` holds the data the page reads.
- `viewer.conf` is the server config.

`viewer.conf` turns on `autoindex_format json` for `/result/`. The page fetches that folder listing and fills a dropdown with every CSV in it, so there is no hard-coded file list. You do not need to change the page when new result files appear.

The page parses CSV files with [PapaParse](https://www.papaparse.com/) and can:

- sort by any column (click its header)
- filter rows by text in a chosen column
- refresh automatically every 10 seconds

## Troubleshooting

**No logs or results appear after `docker compose up`**

Check what the container says:

```bash
docker compose logs processor
```

If you see `sh: ./process_sales.sh: not found`, the script name in the `dockerfile` `CMD` does not match the real file name. The file is `process-sales.sh`, with a hyphen, not an underscore. Fix the name, then **rebuild**. The `CMD` line is baked into the image, so a plain restart is not enough:

```bash
docker compose up -d --build
```

**`$'\r': command not found` or `bad interpreter`**

The script was saved with Windows line endings (CRLF). Convert it to LF, either in your editor's status bar or with `dos2unix process-sales.sh`.

**The page at `localhost:8080` is empty**

Nothing has been processed yet. `result/report.csv` only appears after the first pass of the script.

## Known limitations

- **IDs restart at 1 on every run.** `ID` is a counter inside the script, so files processed in separate passes can end up with the same `id`. A fix is to start from the last ID already in the report, for example `ID=$(tail -n +2 result/report.csv | wc -l)`.
- **Only one copy of the script should run at a time.** If you run it on the host while the container is also running, both can pick up the same file. One copy then archives the file, and the other logs a false error because the file is already gone. Use `flock` if you need to guard against this.
- **The city comes from the first data row only.** Each input file should contain a single city.
