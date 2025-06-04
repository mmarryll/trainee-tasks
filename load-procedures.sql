CREATE OR REPLACE PROCEDURE load_stage()
LANGUAGE plpgsql
AS $$
BEGIN
  	DROP TABLE IF EXISTS stage.sales;

	CREATE TABLE stage.sales (
		row_id INTEGER,
		order_id VARCHAR(15),
		order_date TEXT,
		ship_date TEXT, 
		ship_mode VARCHAR(20),
		customer_id VARCHAR(10),
		customer_name TEXT,
		segment VARCHAR(20),
		country TEXT,
		city TEXT,
		state TEXT,
		postal_code CHAR(5),
		region TEXT,
		product_id VARCHAR(15),
		category TEXT,
		sub_category TEXT,
		product_name TEXT,
		sales NUMERIC,
		quantity INTEGER,
		discount NUMERIC,
		profit NUMERIC
	);
	
	COPY stage.sales FROM 'C:/Program Files/PostgreSQL/17/data/Sample - Superstore.csv'WITH (FORMAT csv, HEADER true, ENCODING 'WIN1252');
	
	ALTER TABLE stage.sales
	ALTER COLUMN order_date TYPE DATE
	USING TO_DATE(order_date, 'MM/DD/YYYY');
	
	ALTER TABLE stage.sales
	ALTER COLUMN ship_date TYPE DATE
	USING TO_DATE(ship_date, 'MM/DD/YYYY');

	CALL drop_all_views();
	CALL drop_all_tables();
	CALL create_all_tables();

END;
$$;

CREATE OR REPLACE PROCEDURE load_locations()
LANGUAGE plpgsql
AS $$
BEGIN
 	INSERT INTO core.locations(country, region, state, city, postal_code)
	SELECT DISTINCT country, region, state, city, postal_code
	FROM stage.sales
	ON CONFLICT(country, region, state, city, postal_code) DO NOTHING;
END;
$$;

CREATE OR REPLACE PROCEDURE load_sub_categories()
LANGUAGE plpgsql
AS $$
BEGIN
 	INSERT INTO core.sub_categories(sub_category, category)
	SELECT DISTINCT sub_category, category
	FROM stage.sales
	ON CONFLICT(sub_category) DO NOTHING;
END;
$$;

CREATE OR REPLACE PROCEDURE load_shipments()
LANGUAGE plpgsql
AS $$
BEGIN
	WITH shipments_to_insert AS(
		SELECT DISTINCT s.ship_date,  s.ship_mode, l.location_id AS location_id
		FROM stage.sales s
		JOIN core.locations l 
		ON l.country = s.country
			AND l.region = s.region
			AND l.state = s.state
			AND l.city = s.city
			AND l.postal_code = s.postal_code
	)
	INSERT INTO core.shipments(ship_date, ship_mode, location_id)
	SELECT *
	FROM shipments_to_insert
	ON CONFLICT(ship_date, ship_mode, location_id) DO NOTHING;
END;
$$;

CREATE OR REPLACE PROCEDURE load_customers()
LANGUAGE plpgsql
AS $$
BEGIN
    DROP TABLE IF EXISTS temp_changes;

    CREATE TEMP TABLE temp_changes AS 
    SELECT customer_id, order_date, customer_name, segment,
        LAG(customer_name) OVER (PARTITION BY customer_id ORDER BY order_date) AS previous_name,
        LAG(segment) OVER (PARTITION BY customer_id ORDER BY order_date) AS previous_segment
    FROM stage.sales;

    UPDATE core.customers c
    SET is_current = FALSE, valid_to = t.order_date
    FROM (
        SELECT customer_id, order_date
        FROM temp_changes
        WHERE previous_name IS NULL OR customer_name <> previous_name OR segment <> previous_segment
    ) t
    WHERE c.customer_id = t.customer_id
      AND c.is_current = TRUE;

    INSERT INTO core.customers (customer_id, customer_name, segment, valid_from)
    SELECT DISTINCT customer_id, customer_name, segment, order_date
    FROM temp_changes
    WHERE previous_name IS NULL OR customer_name <> previous_name OR segment <> previous_segment
    ON CONFLICT (customer_id, valid_from) DO NOTHING;

    WITH customers_with_changes AS (
        SELECT DISTINCT customer_id
        FROM temp_changes
    ),
    ranked AS (
        SELECT c.id,
            ROW_NUMBER() OVER (PARTITION BY c.customer_id ORDER BY c.valid_from DESC) AS rank,
            LEAD(c.valid_from) OVER (PARTITION BY c.customer_id ORDER BY c.valid_from) AS next_valid_from
        FROM core.customers c
        JOIN customers_with_changes ch ON c.customer_id = ch.customer_id
    )
    UPDATE core.customers c
    SET
        is_current = (ranked.rank = 1),
        valid_to = ranked.next_valid_from
    FROM ranked
    WHERE c.id = ranked.id;
END;
$$;

CREATE OR REPLACE PROCEDURE load_products()
LANGUAGE plpgsql
AS $$
BEGIN
	WITH products_to_insert AS(
		SELECT DISTINCT s.product_id,  s.product_name, 
		sc.sub_category AS sub_category
		FROM stage.sales s
		JOIN core.sub_categories sc ON sc.sub_category = s.sub_category
	)
	INSERT INTO core.products(product_id, product_name, sub_category)
	SELECT product_id, product_name, sub_category
	FROM products_to_insert
	ON CONFLICT(product_hash) DO NOTHING;
END;
$$;

CREATE OR REPLACE PROCEDURE load_orders()
LANGUAGE plpgsql
AS $$
BEGIN
	INSERT INTO core.orders(order_id, order_date, active_customer_id, product_id, 
	ship_id, sales, quantity, discount, profit)
	SELECT s.order_id, s.order_date, c.id, p.product_hash, sh.ship_id,
	s.sales, s.quantity, s.discount, s.profit
    FROM stage.sales s
	JOIN core.customers c 
	ON c.customer_id = s.customer_id 
		AND s.order_date >= c.valid_from
	  	AND (s.order_date < c.valid_to OR c.valid_to IS NULL)
	JOIN core.products p ON p.product_id = s.product_id AND p.product_name = s.product_name
	JOIN core.locations l
	ON l.country = s.country
	  AND l.region = s.region
	  AND l.state = s.state
	  AND l.city = s.city
	  AND l.postal_code = s.postal_code
	JOIN core.shipments sh
	ON sh.ship_date = s.ship_date 
	AND sh.ship_mode = s.ship_mode 
	AND sh.location_id = l.location_id
	ON CONFLICT(order_id, active_customer_id, product_id, ship_id) DO NOTHING;
END;
$$;

CREATE OR REPLACE PROCEDURE load_from_stage()
LANGUAGE plpgsql
AS $$
BEGIN
	CALL load_stage();
	CALL load_locations();
	CALL load_sub_categories();
	CALL load_shipments();
	CALL load_customers();
	CALL load_products();
	CALL load_orders();
	CALL create_all_views();
END;
$$;