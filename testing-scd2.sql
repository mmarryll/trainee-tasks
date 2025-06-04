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
	 'FUR-BO-10001798', 'Furniture', 'Bookcases', 'Bush Somerset Collection Bookcase', 300.00, 1, 0.00, 50.00), --changes for excisted customer
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

CALL insert_dupl();

--checking
SELECT *
FROM core.orders o
JOIN core.customers c ON o.active_customer_id = c.id
WHERE customer_id IN ('CG-12520','NEW-99999')


SELECT customer_id, customer_name, segment, order_date
FROM stage.sales
WHERE customer_id = 'CG-12520'
ORDER BY order_date