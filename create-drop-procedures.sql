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

--Mart Layer
CREATE OR REPLACE PROCEDURE drop_all_views()
LANGUAGE plpgsql
AS $$
BEGIN
	DROP VIEW IF EXISTS mart.fact_orders;
	DROP VIEW IF EXISTS mart.dim_products;
	DROP VIEW IF EXISTS mart.dim_shipments;
  	DROP VIEW IF EXISTS mart.dim_customers;
	 
END;
$$;

CREATE OR REPLACE PROCEDURE create_all_views()
LANGUAGE plpgsql
AS $$
BEGIN
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
	 
END;
$$;

