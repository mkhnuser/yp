BEGIN;



CREATE SCHEMA IF NOT EXISTS raw_data;
CREATE TABLE IF NOT EXISTS raw_data.sales(
  id INT,
  auto VARCHAR(256),
  gasoline_consumption REAL,
  price NUMERIC,
  date DATE,
  person VARCHAR(256),
  phone VARCHAR(256),
  discount REAL,
  brand_origin VARCHAR(256)
);

COPY raw_data.sales(
  id,
  auto,
  gasoline_consumption,
  price,
  date,
  person,
  phone,
  discount,
  brand_origin
) FROM '/cars.csv' WITH CSV HEADER DELIMITER ',' NULL 'null';

CREATE SCHEMA IF NOT EXISTS car_shop;

CREATE TABLE IF NOT EXISTS car_shop.customers(
  id SERIAL PRIMARY KEY, -- Покупателей может быть достаточно много, поэтому SERIAL, а не SMALLSERIAL.
  first_name VARCHAR(64) NOT NULL, -- Зададим ограничение на длину длину имени.
  middle_name VARCHAR(64), -- Зададим ограничение на длину отчества, которое опционально.
  last_name VARCHAR(64) NOT NULL, -- Зададим ограничение на длину фамилии.
  phone VARCHAR(32) NOT NULL -- Зададим ограничение на длину телефона.
);

CREATE TABLE IF NOT EXISTS car_shop.countries(
  id SMALLSERIAL PRIMARY KEY, -- Мы не ожидаем много стран, поэтому SMALLSERIAL, а не SERIAL.
  name VARCHAR(128) -- Имя не может быть большим.
);

CREATE TABLE IF NOT EXISTS car_shop.brands(
  id SMALLSERIAL PRIMARY KEY, -- Мы не ожидаем много брендов, поэтому SMALLSERIAL, а не SERIAL.
  name VARCHAR(64) NOT NULL UNIQUE, -- Имя не может быть большим и должно быть уникальным.
  origin_country_id SMALLINT REFERENCES car_shop.countries DEFAULT NULL -- опциональная страна происхождения бренда.
);

CREATE TABLE IF NOT EXISTS car_shop.colors(
  id SMALLSERIAL PRIMARY KEY, -- Мы не ожидаем много цветов, поэтому SMALLSERIAL, а не SERIAL.
  name VARCHAR(64) NOT NULL UNIQUE -- Имя не может быть большим.
);

CREATE TABLE IF NOT EXISTS car_shop.cars(
  id SERIAL PRIMARY KEY, -- Машин может быть достаточно много, поэтому SERIAL, а не SMALLSERIAL.
  brand_id SMALLINT REFERENCES car_shop.brands NOT NULL, -- Каждая машина всегда принадлежит всего одному бренду, но один бренд может иметь целое множество машин, поэтому связь многие к одному.
  name VARCHAR(64) NOT NULL, -- Зададим ограничение на длину названия машины.
  gasoline_consumption REAL NOT NULL DEFAULT 0 CHECK (gasoline_consumption >= 0 AND gasoline_consumption <= 999), -- Хотим всегда относится к этому полю как к числовому значению. Более того, значение не может превышать трёхзначное число, согласно бизнес требованиям.
  UNIQUE (brand_id, name)
);

CREATE TABLE IF NOT EXISTS car_shop.cars_colors(
  id SERIAL PRIMARY KEY, -- Комбинаций может быть достаточно много.
  car_id INT REFERENCES car_shop.cars,
  color_id SMALLINT REFERENCES car_shop.colors,
  UNIQUE (car_id, color_id)
);

CREATE TABLE IF NOT EXISTS car_shop.car_discount(
  id SMALLSERIAL PRIMARY KEY, -- Мы не ожидаем много скидок, поэтому SMALLSERIAL, а не SERIAL.
  car_id INT REFERENCES car_shop.cars NOT NULL UNIQUE -- Всегда указывает машину, к которой относится скидка. При этом одной машине может принадлежать только одна скидка, т.е. связь один к одному.
);

CREATE TABLE IF NOT EXISTS car_shop.sales(
  id SERIAL PRIMARY KEY, -- Продаж может быть достаточно много, поэтому SERIAL, а не SMALLSERIAL.
  customer_id INT REFERENCES car_shop.customers NOT NULL, -- Каждая продажа обязана содержать информацию о клиенте.
  car_color_id INT REFERENCES car_shop.cars_colors(id) NOT NULL, -- Каждая продажа обязана содержать информацию о машине и цвете машины, при этом машина не может быть продана дважды, т.е. таблица не может содержать двух строк с одинаковым car_color_id, а это и есть связь один к одному.
  price NUMERIC(9, 2) NOT NULL, -- Необходима точность при расчётах, поэтому используем NUMERIC.
  discount_percent REAL NOT NULL CHECK (discount_percent >= 0 AND discount_percent <= 100), -- Хотим всегда относится к этому полю как к числовому значению.
  date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP -- Используем TIMESTAMP, а не DATE, для большей точности: мы хотим знать, что продажа была совершена или утром или днём и т.д.
);



COMMIT;



BEGIN;



INSERT INTO car_shop.customers(first_name, last_name, phone)
SELECT DISTINCT
  SPLIT_PART(formatted_name, ' ', 1) as first_name,
  SPLIT_PART(formatted_name, ' ', 2) || ' ' || SPLIT_PART(formatted_name, ' ', 3) as last_name,
  phone
FROM (
  SELECT TRIM(REPLACE(TRIM(REPLACE(TRIM(REPLACE(TRIM(REPLACE(TRIM(REPLACE(TRIM(REPLACE(TRIM(REPLACE(TRIM(person), 'Mrs.', '')), 'Miss', '')), 'Dr.', '')), 'MD', '')), 'DVM', '')), 'Mr.', '')), 'DDS', '')) AS formatted_name, phone FROM raw_data.sales
); -- Удалим всё ненужное из строки и будем помнить, что фамилии могут быть составными. Например, Morgan Jr.

INSERT INTO car_shop.countries(
  name
)
SELECT DISTINCT brand_origin FROM raw_data.sales;

INSERT INTO car_shop.brands(
  name,
  origin_country_id
)
SELECT
  DISTINCT SPLIT_PART(TRIM(auto), ' ', 1),
  (SELECT id FROM car_shop.countries WHERE car_shop.countries.name = brand_origin) AS origin_country_id
FROM raw_data.sales;

INSERT INTO car_shop.cars(
  brand_id,
  name,
  gasoline_consumption
)
SELECT DISTINCT
(
  SELECT id FROM car_shop.brands WHERE name = SPLIT_PART(TRIM(auto), ' ', 1)
) AS brand_id,
TRIM(SPLIT_PART(SUBSTR(auto, STRPOS(auto, ' ')), ',', 1)) AS model_name,
CASE WHEN gasoline_consumption IS NULL THEN 0 ELSE gasoline_consumption::REAL END
FROM raw_data.sales;

INSERT INTO car_shop.colors(
  name
)
SELECT DISTINCT TRIM(SPLIT_PART(auto, ',', 2)) FROM raw_data.sales;

INSERT INTO car_shop.cars_colors(car_id, color_id)
SELECT DISTINCT
(
  SELECT id FROM car_shop.cars
  WHERE brand_id = (SELECT id FROM car_shop.brands WHERE name = SPLIT_PART(TRIM(auto), ' ', 1))
  AND name = TRIM(SPLIT_PART(SUBSTR(auto, STRPOS(auto, ' ')), ',', 1))
),
(SELECT id FROM car_shop.colors WHERE car_shop.colors.name = TRIM(SPLIT_PART(auto, ',', 2)))
FROM raw_data.sales;

INSERT INTO car_shop.sales(
  customer_id,
  car_color_id,
  price,
  discount_percent,
  date
)
SELECT DISTINCT
(SELECT id FROM car_shop.customers WHERE car_shop.customers.phone = raw_data.sales.phone),
(SELECT id FROM car_shop.cars_colors WHERE car_shop.cars_colors.car_id = (
  SELECT id FROM car_shop.cars
  WHERE brand_id = (SELECT id FROM car_shop.brands WHERE name = SPLIT_PART(TRIM(auto), ' ', 1))
  AND name = TRIM(SPLIT_PART(SUBSTR(auto, STRPOS(auto, ' ')), ',', 1))
)
AND
car_shop.cars_colors.color_id = (SELECT id FROM car_shop.colors WHERE car_shop.colors.name = TRIM(SPLIT_PART(SUBSTR(auto, STRPOS(auto, ' ')), ',', 2)))
),
price, discount::REAL, date FROM raw_data.sales;



COMMIT;



-- 1.
SELECT
  (SUM(CASE WHEN gasoline_consumption = 0 THEN 1 ELSE 0 END)::REAL / COUNT(*)) * 100
  AS nulls_percentage_gasoline_consumption
FROM car_shop.cars;

-- 2.
SELECT
  car_shop.brands.name AS brand_name,
  EXTRACT(YEAR FROM date) AS year,
  ROUND(AVG(price), 2) AS price_avg
FROM car_shop.brands
INNER JOIN car_shop.cars ON car_shop.brands.id = car_shop.cars.brand_id
INNER JOIN car_shop.sales ON car_shop.cars.id = car_shop.sales.car_color_id
GROUP BY car_shop.brands.name, EXTRACT(YEAR FROM car_shop.sales.date)
ORDER BY brand_name, year;

-- 3.
SELECT
  EXTRACT(MONTH FROM date) AS month,
  EXTRACT(YEAR FROM date) AS year,
  ROUND(AVG(price), 2) AS price_avg
FROM car_shop.sales
WHERE EXTRACT(YEAR FROM date) = 2022
GROUP BY EXTRACT(YEAR FROM date), EXTRACT(MONTH FROM date)
ORDER BY month;

-- 4.
SELECT
  first_name || ' ' || last_name AS person,
  STRING_AGG(car_shop.brands.name || ' ' || car_shop.cars.name, ', ')
FROM car_shop.customers
INNER JOIN car_shop.sales ON car_shop.customers.id = car_shop.sales.customer_id
INNER JOIN car_shop.cars ON car_shop.sales.car_color_id = car_shop.cars.id
INNER JOIN car_shop.brands ON car_shop.cars.brand_id = car_shop.brands.id
GROUP BY first_name || ' ' || last_name
ORDER BY person;

-- 5.
SELECT
  (CASE WHEN car_shop.countries.name IS NULL THEN 'N/A' ELSE car_shop.countries.name END) AS brand_origin,
  MIN(
    CASE 
      WHEN discount_percent != 100 THEN price::REAL / (1 - (discount_percent::REAL / 100))
      ELSE 0
    END
  ),-- Быть может, кто-то получил машину бесплатно.
  MAX(
    CASE 
      WHEN discount_percent != 100 THEN price::REAL / (1 - (discount_percent::REAL / 100))
      ELSE 0
    END
  ) -- Быть может, кто-то получил машину бесплатно.
FROM car_shop.brands
LEFT JOIN car_shop.countries ON car_shop.brands.origin_country_id = car_shop.countries.id
INNER JOIN car_shop.cars ON car_shop.brands.id = car_shop.cars.brand_id
INNER JOIN car_shop.sales ON car_shop.cars.id = car_shop.sales.car_color_id
GROUP BY car_shop.countries.name;

-- 6.
SELECT
SUM(CASE WHEN phone LIKE '+1%' THEN 1 ELSE 0 END) AS persons_from_usa_count
FROM car_shop.customers;
