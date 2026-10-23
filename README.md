# Postgres Index Lab

What does an index actually do to a table with **1 million rows**? This repo runs the same queries before and after creating indexes and reads the plans with `EXPLAIN (ANALYZE, BUFFERS)`.

It is the practical follow-up to week 1 of my database study routine: B-trees, selectivity, composite indexes and the leftmost prefix rule, covering indexes, write cost, and reading seek vs. scan in an execution plan.

## Results

One run on my machine (Postgres 16 in Docker). Raw output is in [`results/results.txt`](results/results.txt).

| # | Experiment | Plan | Time | Pages touched |
|---|---|---|---|---|
| 0 | `WHERE customer_id = 4242`, no index | Parallel Seq Scan | 31.7 ms | 8,030 |
| 1 | Same query, index on `customer_id` | Bitmap Index Scan | 0.85 ms | 105 |
| 2 | Composite `(customer_id, created_at)`, filter on both | Bitmap Index Scan | 0.19 ms | 26 |
| 2b | Same composite index, filter on `created_at` only | Parallel Seq Scan | 56.7 ms | 8,030 |
| 3 | `WHERE status = 'paid'` (4 distinct values), no index | Seq Scan | 87.5 ms | 8,030 |
| 3b | Same query, index on `status` | Bitmap Heap Scan | 103.7 ms | 8,314 |
| 4a | Select `created_at, amount`, composite index | Bitmap Heap Scan | 0.049 ms | 26 |
| 4b | Same query, covering index `INCLUDE (amount)` | Index Only Scan | 0.039 ms | 4 |
| 5 | Insert 200k rows, primary key only | Insert | 478.7 ms | n/a |
| 5b | Insert 200k rows, PK + 2 extra indexes | Insert | 1,761.8 ms | n/a |

## What the numbers say

- **A plain index turns a table scan into a lookup.** 8,030 pages down to 105, about 37x faster for this query.
- **Column order in a composite index matters.** `(customer_id, created_at)` serves filters on `customer_id` and on both columns, but not on `created_at` alone. That query went back to a Seq Scan (leftmost prefix rule).
- **An index is not always a win.** `status` has 4 distinct values, so the query returns about a third of the table. With the index it was slower (103.7 ms vs 87.5 ms): the database still reads a third of the pages and also pays for going through the index.
- **A covering index saves pages, not necessarily time.** `INCLUDE (amount)` made it an Index Only Scan with `Heap Fetches: 0`, and pages dropped from 26 to 4. Time barely changed because the cache was warm and only 23 rows matched. Look at `Buffers`, not just the clock.
- **Writes pay for every index.** Inserting 200k rows took about 3.7x longer with two extra indexes.

## Run it yourself

Requirements: Docker with Compose.

```bash
docker compose up -d
```

The first start creates the `orders` table and loads 1M rows, which takes a few seconds. Wait until `docker logs index-lab` shows `database system is ready to accept connections` for the second time, then run the experiment.

Linux / macOS / Git Bash:

```bash
docker exec -i index-lab psql -U postgres -d lab < sql/02_experiment.sql
```

Windows PowerShell (it has no `<` redirection):

```powershell
docker cp sql/02_experiment.sql index-lab:/tmp/02_experiment.sql
docker exec index-lab psql -U postgres -d lab -f /tmp/02_experiment.sql | Out-File results/results.txt -Encoding utf8
```

The experiment creates and drops indexes and inserts 400k extra rows, so to run it again from a clean state:

```bash
docker compose down -v
docker compose up -d
```

## Repository layout

```
.
├── docker-compose.yml        Postgres 16, loads sql/01_setup.sql on first start
├── sql/
│   ├── 01_setup.sql          orders table + 1M rows
│   └── 02_experiment.sql     the steps above, with EXPLAIN (ANALYZE, BUFFERS)
└── results/
    └── results.txt           raw output from my run
```

## Caveats

- This is a learning experiment, not a benchmark. It is a single run, on a laptop, in Docker, and absolute times will differ on your machine. The pattern (seek vs. scan, pages touched, write cost) is what to compare.
- The first query runs with a cold cache (`shared read` in the plan), so its time includes disk reads.
- Data is random and uniformly distributed. Real data is usually skewed, which changes what the planner chooses.

## Next steps

- Repeat on SQL Server and compare the plans (seek vs. scan, key lookups).
- Add a skewed dataset to see how selectivity changes the planner's choice.
- Partial indexes and expression indexes.
