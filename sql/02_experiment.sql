-- 02_experiment.sql
-- Runs each step and prints the execution plan.
-- Usage (see README): psql -U postgres -d lab -f 02_experiment.sql
-- Starts with no index other than the primary key.

\echo '=== 0. NO INDEX: lookup by customer ==='
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE customer_id = 4242;

\echo '=== 1. SINGLE-COLUMN INDEX on customer_id ==='
CREATE INDEX idx_orders_customer ON orders (customer_id);
ANALYZE orders;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE customer_id = 4242;

\echo '=== 2. COMPOSITE (customer_id, created_at): filter on both columns ==='
CREATE INDEX idx_orders_customer_created ON orders (customer_id, created_at);
DROP INDEX idx_orders_customer;  -- the composite already covers lookups by customer_id alone
ANALYZE orders;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders
WHERE customer_id = 4242 AND created_at >= now() - interval '90 days';

\echo '=== 2b. SAME INDEX, filtering ONLY on created_at (breaks the leftmost prefix) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE created_at >= now() - interval '1 day';

\echo '=== 3. SELECTIVITY: column with 4 distinct values (status). First WITHOUT an index ==='
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE status = 'paid';

\echo '=== 3b. Now WITH an index on status ==='
CREATE INDEX idx_orders_status ON orders (status);
ANALYZE orders;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE status = 'paid';
DROP INDEX idx_orders_status;

\echo '=== 4. COVERING INDEX: the query only needs customer_id, created_at, amount ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT created_at, amount FROM orders
WHERE customer_id = 4242 AND created_at >= now() - interval '90 days';

CREATE INDEX idx_orders_customer_created_cov
    ON orders (customer_id, created_at) INCLUDE (amount);
VACUUM ANALYZE orders;  -- refreshes the visibility map, required for an Index Only Scan
EXPLAIN (ANALYZE, BUFFERS)
SELECT created_at, amount FROM orders
WHERE customer_id = 4242 AND created_at >= now() - interval '90 days';

\echo '=== 5. WRITE COST: insert 200k rows with only the primary key ==='
DROP INDEX idx_orders_customer_created;
DROP INDEX idx_orders_customer_created_cov;
EXPLAIN (ANALYZE)
INSERT INTO orders (customer_id, status, amount, created_at)
SELECT (random() * 9999)::int + 1, 'pending', 10, now()
FROM generate_series(1, 200000);

\echo '=== 5b. Same insert WITH 2 extra indexes (composite + covering) ==='
CREATE INDEX idx_orders_customer_created ON orders (customer_id, created_at);
CREATE INDEX idx_orders_customer_created_cov
    ON orders (customer_id, created_at) INCLUDE (amount);
EXPLAIN (ANALYZE)
INSERT INTO orders (customer_id, status, amount, created_at)
SELECT (random() * 9999)::int + 1, 'pending', 10, now()
FROM generate_series(1, 200000);
