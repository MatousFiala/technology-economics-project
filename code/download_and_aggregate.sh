#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROCESSED_DIR="$REPO_ROOT/data/processed"
FINAL_DB="$REPO_ROOT/data/citibike_agg.duckdb"
S3_BASE="https://s3.amazonaws.com/tripdata"

mkdir -p "$PROCESSED_DIR"

process_month() {
    local ym=$1
    local ds="$PROCESSED_DIR/${ym}_daily_starts.parquet"
    local de="$PROCESSED_DIR/${ym}_daily_ends.parquet"
    local hs="$PROCESSED_DIR/${ym}_hourly_starts.parquet"

    if [[ -f "$ds" && -f "$de" && -f "$hs" ]]; then
        echo "[$ym] already processed, skipping"
        return
    fi

    local zipfile="$REPO_ROOT/data/${ym}-citibike-tripdata.zip"
    local tmpdir="$REPO_ROOT/data/tmp_${ym}"
    local url="${S3_BASE}/${ym}-citibike-tripdata.zip"

    echo "[$ym] downloading $url"
    if ! curl -fL --progress-bar -o "$zipfile" "$url"; then
        echo "[$ym] download failed, skipping"
        rm -f "$zipfile"
        return
    fi

    echo "[$ym] extracting"
    mkdir -p "$tmpdir"
    unzip -q "$zipfile" -d "$tmpdir"
    rm -f "$zipfile"

    # Find actual CSV files (exclude __MACOSX metadata)
    local csv_glob
    csv_glob=$(find "$tmpdir" -name "*.csv" ! -path "*/__MACOSX/*" | head -1)
    if [[ -z "$csv_glob" ]]; then
        echo "[$ym] no CSV files found in zip, skipping"
        rm -rf "$tmpdir"
        return
    fi

    echo "[$ym] aggregating with duckdb"
    duckdb -c "
SET threads=4;

-- (a) daily starts per station
COPY (
    SELECT
        CAST(started_at AS DATE)  AS date,
        start_station_id,
        start_station_name,
        COUNT(*)                  AS rides
    FROM read_csv('${tmpdir}/*.csv',
                  union_by_name = true,
                  auto_detect   = true,
                  ignore_errors = true)
    WHERE start_station_id IS NOT NULL
    GROUP BY 1, 2, 3
) TO '${ds}' (FORMAT PARQUET);

-- (b) daily ends per station
COPY (
    SELECT
        CAST(ended_at AS DATE)  AS date,
        end_station_id,
        end_station_name,
        COUNT(*)                AS rides
    FROM read_csv('${tmpdir}/*.csv',
                  union_by_name = true,
                  auto_detect   = true,
                  ignore_errors = true)
    WHERE end_station_id IS NOT NULL
    GROUP BY 1, 2, 3
) TO '${de}' (FORMAT PARQUET);

-- (c) hourly starts per station
COPY (
    SELECT
        date_trunc('hour', started_at) AS hour,
        start_station_id,
        start_station_name,
        COUNT(*)                       AS rides
    FROM read_csv('${tmpdir}/*.csv',
                  union_by_name = true,
                  auto_detect   = true,
                  ignore_errors = true)
    WHERE start_station_id IS NOT NULL
    GROUP BY 1, 2, 3
) TO '${hs}' (FORMAT PARQUET);
"

    rm -rf "$tmpdir"
    echo "[$ym] done"
}

# ── Month loop: 202401 → 202601 ──────────────────────────────────────────────
y=2024; m=1
end_ym=202601

while true; do
    ym=$(printf "%d%02d" "$y" "$m")
    process_month "$ym"
    [[ "$ym" == "$end_ym" ]] && break
    m=$((m + 1))
    if [[ $m -gt 12 ]]; then m=1; y=$((y + 1)); fi
done

# ── Concatenate all parquet files into final DuckDB ──────────────────────────
echo "building final database: $FINAL_DB"
duckdb "$FINAL_DB" -c "
CREATE OR REPLACE TABLE daily_starts AS
    SELECT * FROM read_parquet('${PROCESSED_DIR}/*_daily_starts.parquet', union_by_name=TRUE)
    ORDER BY date, start_station_id;

CREATE OR REPLACE TABLE daily_ends AS
    SELECT * FROM read_parquet('${PROCESSED_DIR}/*_daily_ends.parquet', union_by_name=TRUE)
    ORDER BY date, end_station_id;

CREATE OR REPLACE TABLE hourly_starts AS
    SELECT * FROM read_parquet('${PROCESSED_DIR}/*_hourly_starts.parquet', union_by_name=TRUE)
    ORDER BY hour, start_station_id;

SELECT 'daily_starts'  AS tbl, COUNT(*) AS rows FROM daily_starts
UNION ALL
SELECT 'daily_ends',          COUNT(*)          FROM daily_ends
UNION ALL
SELECT 'hourly_starts',       COUNT(*)          FROM hourly_starts;
"

echo "all done"
