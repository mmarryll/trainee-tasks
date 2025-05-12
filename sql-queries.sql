CREATE SCHEMA stage;
CREATE SCHEMA core;
CREATE SCHEMA mart;

/*Initial load*/
--Stage Layer
CREATE OR REPLACE PROCEDURE load_stage()
LANGUAGE plpgsql
AS $$
BEGIN
  	DROP IF EXISTS TABLE stage.sales;

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
	
	CALL drop_all_tables();
	CALL create_all_tables();

END;
$$;

--Core Layer
CREATE OR REPLACE PROCEDURE drop_all_tables()
LANGUAGE plpgsql
AS $$
BEGIN
  	DROP TABLE IF EXISTS core.orders;
	DROP TABLE IF EXISTS core.products;
	DROP TABLE IF EXISTS core.customers;
	DROP TABLE IF EXISTS core.shipments;
	DROP TABLE IF EXISTS core.locations;
	DROP TABLE IF EXISTS core.sub_categories;
END;
$$;

CREATE OR REPLACE PROCEDURE create_all_tables()
LANGUAGE plpgsql
AS $$
BEGIN
  	CREATE TABLE core.customers (
	id SERIAL PRIMARY KEY,
	customer_id VARCHAR(10) NOT NULL,
	customer_name TEXT NOT NULL,
	segment VARCHAR(20) NOT NULL,
	valid_from TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
	valid_to TIMESTAMP  DEFAULT NULL, 
	is_current BOOLEAN DEFAULT TRUE,
	UNIQUE(customer_id, valid_from)
	);

	CREATE TABLE core.sub_categories(
		sub_category TEXT PRIMARY KEY,
		category TEXT NOT NULL,
		UNIQUE(sub_category, category)
	);
	
	CREATE TABLE core.products (
		product_hash CHAR(32) PRIMARY KEY GENERATED ALWAYS AS (md5(product_id || product_name)) STORED ,
		product_id VARCHAR(15) NOT NULL,
		product_name TEXT NOT NULL,
	    sub_category TEXT NOT NULL,
		FOREIGN KEY(sub_category) REFERENCES core.sub_categories(sub_category)
	);
	
	CREATE TABLE core.locations(
		location_id SERIAL PRIMARY KEY,
		country TEXT NOT NULL,
		region TEXT,
		state TEXT NOT NULL,
		city TEXT NOT NULL,
		postal_code CHAR(5) NOT NULL,
		UNIQUE(country, region, state, city, postal_code)
	);
	
	CREATE TABLE core.shipments (
		ship_id SERIAL PRIMARY KEY,
		ship_date DATE, 
		ship_mode VARCHAR(20) NOT NULL,
		location_id INTEGER NOT NULL,
		UNIQUE(ship_date, ship_mode, location_id),
		FOREIGN KEY (location_id) REFERENCES core.locations(location_id)
	);
	
	CREATE TABLE core.orders (
		id SERIAL PRIMARY KEY,
		order_id VARCHAR(15) NOT NULL,
		order_date DATE NOT NULL,
		active_customer_id INTEGER NOT NULL,
		product_id CHAR(32) NOT NULL,
		ship_id INTEGER NOT NULL,
		sales NUMERIC NOT NULL,
		quantity INTEGER NOT NULL,
		discount NUMERIC NOT NULL,
		profit NUMERIC  NOT NULL,
		UNIQUE(order_id, active_customer_id, product_id, ship_id),
	
		FOREIGN KEY (active_customer_id) REFERENCES core.customers(id),
		FOREIGN KEY (product_id) REFERENCES core.products(product_hash),
		FOREIGN KEY (ship_id) REFERENCES core.shipments(ship_id)
	);
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
END;
$$;

CALL load_from_stage();

/*Secondary Load*/
CREATE OR REPLACE PROCEDURE insert_dupl()
LANGUAGE plpgsql
AS $$
BEGIN 
	INSERT INTO stage.sales (
	    row_id, order_id, order_date, ship_date, ship_mode, customer_id,
	    customer_name, segment, country, city, state, postal_code, region,
	    product_id, category, sub_category, product_name, sales, quantity, discount, profit
	) VALUES
	(9995, 'CA-2016-152156', '12/1/2025', '16/4/2025', 'Second Class', 'CG-12520',
	 'Claire Gute-NEW', 'Consumer', 'United States', 'Henderson', 'Kentucky', '42420', 'South',
	 'FUR-BO-10001798', 'Furniture', 'Bookcases', 'Bush Somerset Collection Bookcase', 300.00, 1, 0.00, 50.00), --changes for excicted customer
	(9996, 'US-2025-999999', '5/1/2025', '5/3/2025', 'Standard Class', 'NEW-99999',
	 'John Doe', 'Corporate', 'United States', 'New York', 'New York', '10001', 'East',
	 'OFF-LA-10000240', 'Office Supplies', 'Labels', 'Self-Adhesive Address Labels for Typewriters by Universal', 50.00, 2, 0.00, 10.00), -- new customer
	(9997,'CA-2016-152156', '12/1/2025', '16/4/2025', 'Second Class', 'CG-12520',
	 'Claire Gute-NEW', 'Consumer', 'United States', 'Henderson', 'Kentucky', '42420', 'South',
	 'FUR-BO-10001798', 'Furniture', 'Bookcases', 'Bush Somerset Collection Bookcase', 300.00, 1, 0.00, 50.00), -- full dupl
	 (9998, 'CA-2016-152156', '12/2/2025', '18/2/2025', 'Second Class', 'CG-12520',
	 'Claire Gute-NEW', 'Corporate', 'United States', 'Henderson', 'Kentucky', '42420', 'South',
	 'FUR-BO-10001798', 'Furniture', 'Bookcases', 'Bush Somerset Collection Bookcase', 300.00, 1, 0.00, 50.00), -- another changes
	(9999, 'CA-2016-152156', '13/2/2025', '20/2/2025', 'Second Class', 'CG-12520',
	 'Claire Gute-NEW2', 'Consumer', 'United States', 'Henderson', 'Kentucky', '42420', 'South',
	 'FUR-BO-10001798', 'Furniture', 'Bookcases', 'Bush Somerset Collection Bookcase', 300.00, 1, 0.00, 50.00), -- another changes
	 (10000, 'CA-2016-152156', '20/2/2025', '2/3/2025', 'Second Class', 'CG-12520',
	 'Claire Gute-NEW2', 'Consumer', 'United States', 'Henderson', 'Kentucky', '42420', 'South',
	 'FUR-BO-10001798', 'Furniture', 'Bookcases', 'Bush Somerset Collection Bookcase', 300.00, 1, 0.00, 50.00); -- changes for scd1 
END;
$$;

--checking



SELECT *
FROM core.orders o
JOIN core.customers c ON o.active_customer_id = c.id
WHERE customer_id IN ('CG-12520','NEW-99999')


SELECT customer_id, customer_name, segment, order_date
FROM stage.sales
WHERE customer_id = 'CG-12520'
ORDER BY order_date

--Mart Layer
CREATE OR REPLACE VIEW mart.dim_customers AS
SELECT * 
FROM core.customers;

CREATE OR REPLACE VIEW mart.dim_shipments AS
SELECT ship_id, ship_date, ship_mode, country, region, state, city, postal_code
FROM core.shipments sh
JOIN core.locations l ON l.location_id = sh.location_id;

CREATE OR REPLACE VIEW mart.dim_products AS
SELECT product_hash, product_id, product_name, p.sub_category, category
FROM core.products p
JOIN core.sub_categories sb ON sb.sub_category = p.sub_category;

CREATE OR REPLACE VIEW mart.fact_orders AS
SELECT *
FROM core.orders;