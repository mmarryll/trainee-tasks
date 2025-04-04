/*Display the number of films in each category, sorted in descending order.*/
SELECT category.name, COUNT(*) AS num_films
FROM film_category
INNER JOIN category ON film_category.category_id = category.category_id
GROUP BY category.name
ORDER BY num_films DESC

/*Display the top 10 actors whose films were rented the most, sorted in descending order.*/
SELECT CONCAT(actor.first_name, ' ', actor.last_name) AS actor_name, COUNT(rental.rental_id) AS num_rentals
FROM film_actor
INNER JOIN film ON film_actor.film_id = film.film_id
INNER JOIN actor ON film_actor.actor_id = actor.actor_id
INNER JOIN inventory ON film.film_id = inventory.film_id
INNER JOIN rental ON inventory.inventory_id = rental.inventory_id
GROUP BY actor.first_name, actor.last_name
ORDER BY num_rentals DESC
LIMIT 10

/*Display the category of films that generated the highest revenue.*/
SELECT category.name, SUM(payment.amount) AS revenue
FROM film
INNER JOIN inventory ON film.film_id = inventory.film_id
INNER JOIN rental ON inventory.inventory_id = rental.inventory_id
INNER JOIN payment ON rental.rental_id = payment.rental_id
INNER JOIN film_category ON film.film_id = film_category.film_id
INNER JOIN category ON film_category.category_id = category.category_id
GROUP BY category.name
ORDER BY revenue DESC
LIMIT 1

/*Display the titles of films not present in the inventory. Write the query without using the IN operator.*/
SELECT film.film_id, title
FROM film
WHERE NOT EXISTS (
    SELECT 1 FROM inventory 
    WHERE film.film_id = inventory.film_id
);

/*Display the top 3 actors who appeared the most in films within the "Children" category. If multiple actors have the same count, include all.*/
WITH RankedActors AS(
	SELECT actor.actor_id, actor.first_name, actor.last_name, COUNT(film.title) AS total_films, DENSE_RANK() OVER(ORDER BY COUNT(film.title) DESC) AS actor_rank
	FROM actor
	INNER JOIN film_actor ON actor.actor_id = film_actor.actor_id
	INNER JOIN film ON film_actor.film_id = film.film_id
	INNER JOIN film_category ON film.film_id = film_category.film_id
	INNER JOIN category ON film_category.category_id = category.category_id
	WHERE category.name = 'Children'
	GROUP BY actor.actor_id, actor.first_name, actor.last_name
	ORDER BY total_films DESC
)
SELECT first_name, last_name, total_films
FROM RankedACtors 
WHERE actor_rank <=3

/*Display cities with the count of active and inactive customers (active = 1). Sort by the count of inactive customers in descending order.*/
SELECT city, COUNT(CASE WHEN customer.active = 1 THEN 1 END) AS num_active_customers, 
COUNT(CASE WHEN customer.active = 0 THEN 1 END) AS num_inactive_customers
FROM customer
INNER JOIN address ON customer.address_id = address.address_id
INNER JOIN city ON address.city_id = city.city_id
GROUP BY city
ORDER BY num_inactive_customers DESC 

/*Display the film category with the highest total rental hours in cities where customer.address_id belongs to that city and starts with the letter "a". Do the same for cities containing the symbol "-". Write this in a single query.*/
WITH RentalHours AS (
	SELECT category.name AS category_name, SUM(EXTRACT(EPOCH FROM rental.return_date - rental.rental_date) / 3600) AS rental_hours,
	city.city AS city
	FROM film 
	INNER JOIN film_category ON film.film_id = film_category.film_id
	INNER JOIN category ON film_category.category_id = category.category_id
	INNER JOIN inventory ON film.film_id = inventory.film_id
	INNER JOIN rental ON inventory.inventory_id = rental.inventory_id
	INNER JOIN customer ON rental.customer_id = customer.customer_id
	INNER JOIN address ON customer.address_id = address.address_id
	INNER JOIN city ON address.city_id = city.city_id
	GROUP BY category.name, city.city
),
FirstCondition AS (
	SELECT category_name, SUM(rental_hours) AS total_rental_hours
	FROM RentalHours
	WHERE city LIKE 'A%'
	GROUP BY category_name
	ORDER BY total_rental_hours DESC LIMIT 1
),
SecondCondition AS(
	SELECT category_name, SUM(rental_hours) AS total_rental_hours
	FROM RentalHours
	WHERE city LIKE '%-%'
	GROUP BY category_name
	ORDER BY total_rental_hours DESC LIMIT 1
)
SELECT 'A% condition' AS condition, category_name, total_rental_hours
FROM FirstCondition
UNION ALL
SELECT '%-% condition' AS condition, category_name, total_rental_hours
FROM SecondCondition



