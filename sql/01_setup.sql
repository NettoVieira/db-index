-- 01_setup.sql
-- Creates the `orders` table and loads 1 million rows.
-- Runs automatically on the first start of the container (see docker-compose.yml).

CREATE TABLE orders (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id int           NOT NULL,
    status      text          NOT NULL,
    amount      numeric(10,2) NOT NULL,
    created_at  timestamptz   NOT NULL
);

INSERT INTO orders (customer_id, status, amount, created_at)
SELECT
    (random() * 9999)::int + 1,                                               -- 10k customers (~100 orders each)
    (ARRAY['pending','paid','shipped','cancelled'])[1 + (random() * 3)::int], -- 4 statuses, ~25% each
    round((random() * 990 + 10)::numeric, 2),
    now() - (random() * interval '730 days')                                  -- last 2 years
FROM generate_series(1, 1000000);

VACUUM ANALYZE orders;
