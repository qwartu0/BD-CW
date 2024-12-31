CREATE DATABASE "Dilivery"
    WITH
    OWNER = postgres
    ENCODING = 'UTF8'
    LC_COLLATE = 'Russian_Belarus.1251'
    LC_CTYPE = 'Russian_Belarus.1251'
    LOCALE_PROVIDER = 'libc'
    TABLESPACE = pg_default
    CONNECTION LIMIT = -1
    IS_TEMPLATE = False;
		
delete from users
delete from customers
delete from reviews
delete from orders
delete from delivery_list
delete from courier_info
delete from delivery_route
delete from notifications

CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    first_name VARCHAR(30) NOT NULL,
    last_name VARCHAR(35) NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    street VARCHAR(25) NOT NULL,
    house INT NOT NULL,
    apartment INT NOT NULL,
	x FLOAT NOT NULL,
	y FLOAT NOT NULL,
	insurance BOOLEAN DEFAULT FALSE,
	active_or_deleted VARCHAR(10) DEFAULT 'active',
    recipient_first_name VARCHAR(30) NOT NULL,
    recipient_last_name VARCHAR(35) NOT NULL,
    recipient_phone_number VARCHAR(20) NOT NULL,
    recipient_street VARCHAR(25) NOT NULL,
    recipient_house INT NOT NULL,
    recipient_apartment INT NOT NULL,
    recipient_x FLOAT NOT NULL,
    recipient_y FLOAT NOT NULL,
	packaging_labeling VARCHAR(20) NOT NULL DEFAULT 'none' CHECK (packaging_labeling IN ('packaging', 'labeling', 'packaging_labeling', 'none')),
	preferred_datetime TIMESTAMPTZ NOT NULL
);
CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    customer_id INT NOT NULL,
    date_get TIMESTAMPTZ NOT NULL,
	total_cost FLOAT,
	product_name VARCHAR(50) NOT NULL,
	product_type VARCHAR(10) CHECK (product_type IN ('fragile', 'non-fragile')),
	cargo_weight FLOAT NOT NULL,
	transport_type VARCHAR(20),
    FOREIGN KEY (customer_id) REFERENCES customers (customer_id)
);

CREATE OR REPLACE FUNCTION calculate_total_cost(
    p_cargo_weight FLOAT,
    p_transport_type VARCHAR(20),
    p_insurance BOOLEAN,
    p_packaging_labeling VARCHAR(20),
    p_product_type VARCHAR(10),
    p_sender_x FLOAT,
    p_sender_y FLOAT,
    p_recipient_x FLOAT,
    p_recipient_y FLOAT
) RETURNS NUMERIC(10, 2) AS $$
DECLARE
    v_total_cost NUMERIC(10, 2);
    v_distance FLOAT;
BEGIN
    IF p_cargo_weight IS NULL THEN
        RAISE EXCEPTION 'Cargo weight cannot be null.';
    END IF;

    v_total_cost := p_cargo_weight * 8; -- базовая стоимость за каждый килограмм

    IF p_transport_type = 'car' THEN
        v_total_cost := v_total_cost + 20;
    ELSIF p_transport_type = 'foot' THEN
        v_total_cost := v_total_cost + 10;
    ELSIF p_transport_type = 'train' THEN
        v_total_cost := v_total_cost + 30;
    END IF;

    IF p_insurance THEN
        v_total_cost := v_total_cost + (v_total_cost * 0.1); -- дополнительные 10% от общей стоимости при наличии страховки
    END IF;

    IF p_packaging_labeling = 'none' THEN
        v_total_cost := v_total_cost + 0;
    ELSIF p_packaging_labeling = 'labeling' THEN
        v_total_cost := v_total_cost + 5;
    ELSIF p_packaging_labeling = 'packaging' THEN
        v_total_cost := v_total_cost + 5;
    ELSIF p_packaging_labeling = 'packaging_labeling' THEN
        v_total_cost := v_total_cost + 8;
    END IF;

    IF p_product_type = 'fragile' THEN
        v_total_cost := v_total_cost + 5; -- дополнительные 5 единиц стоимости при хрупком товаре
    END IF;

    -- Расчет расстояния между отправителем и получателем
    v_distance := sqrt(power(p_sender_x - p_recipient_x, 2) + power(p_sender_y - p_recipient_y, 2));

    -- Добавление платы за расстояние
    v_total_cost := v_total_cost + (v_distance * 0.15);

    RETURN v_total_cost;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_total_cost_orders() RETURNS TRIGGER AS $$
DECLARE
    v_customer RECORD;
    v_total_cost NUMERIC(10, 2);
BEGIN
    -- Получаем данные клиента
    SELECT * INTO v_customer FROM customers WHERE customer_id = NEW.customer_id;

    -- Пересчитываем стоимость
    v_total_cost := calculate_total_cost(
        NEW.cargo_weight,
        NEW.transport_type,
        v_customer.insurance,
        v_customer.packaging_labeling,
        NEW.product_type,
        v_customer.x,
        v_customer.y,
        v_customer.recipient_x,
        v_customer.recipient_y
    );

    -- Обновляем поле total_cost
    NEW.total_cost := v_total_cost;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_total_cost_orders
BEFORE INSERT OR UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION update_total_cost_orders();

CREATE OR REPLACE FUNCTION update_total_cost_on_customer_change() RETURNS TRIGGER AS $$
DECLARE
    v_order RECORD;
    v_total_cost NUMERIC(10, 2);
    v_customer RECORD;
BEGIN
    SELECT * INTO v_customer FROM customers WHERE customer_id = NEW.customer_id;

    FOR v_order IN SELECT * FROM orders WHERE customer_id = NEW.customer_id LOOP
        -- Пересчитываем стоимость для каждого заказа клиента
        v_total_cost := calculate_total_cost(
            v_order.cargo_weight,
            v_order.transport_type,
            NEW.insurance,
            NEW.packaging_labeling,
            v_order.product_type,
            NEW.x,
            NEW.y,
            v_customer.recipient_x,
            v_customer.recipient_y
        );

        -- Обновляем стоимость заказа
        UPDATE orders SET total_cost = v_total_cost WHERE order_id = v_order.order_id;
    END LOOP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_total_cost_customers
AFTER UPDATE OF insurance, packaging_labeling ON customers
FOR EACH ROW
EXECUTE FUNCTION update_total_cost_on_customer_change();

CREATE TABLE courier_info (
    courier_id SERIAL PRIMARY KEY,
    first_name VARCHAR(30) NOT NULL,
    last_name VARCHAR(35) NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    delivery_type VARCHAR(10) NOT NULL,
	status VARCHAR(10) NOT NULL DEFAULT 'свободен',
	active_or_deleted VARCHAR(10) DEFAULT 'active'
);
CREATE TABLE delivery_list (
    delivery_id SERIAL PRIMARY KEY,
    order_id INT UNIQUE NOT NULL,
    courier_id INT NOT NULL,
    date_arrived TIMESTAMPTZ,
    payment_method VARCHAR(4),
	date_get_by_courier TIMESTAMPTZ,
	status VARCHAR(20) NOT NULL DEFAULT 'В обработке' CHECK (status IN ('В обработке', 'Обработан', 'Принят в доставку', 'Доставлен', 'Отменен')),
	street VARCHAR(50),
    FOREIGN KEY (order_id) REFERENCES orders(order_id),
    FOREIGN KEY (courier_id) REFERENCES courier_info(courier_id)
);


CREATE TABLE reviews (
    review_id SERIAL PRIMARY KEY,
    customer_id INT NOT NULL,
	order_id INT NOT NULL,
    rating FLOAT NOT NULL CHECK (rating >= 0 AND rating <= 5),
    comment TEXT,
    posted_at TIMESTAMPTZ NOT NULL,
	answer VARCHAR(50),
    FOREIGN KEY (customer_id) REFERENCES customers (customer_id),
    FOREIGN KEY (order_id) REFERENCES orders (order_id)
);

CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    customer_id INT,
    courier_id INT,
    login VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(100) NOT NULL,
    FOREIGN KEY (customer_id) REFERENCES customers (customer_id),
    FOREIGN KEY (courier_id) REFERENCES courier_info (courier_id)
);
CREATE TABLE delivery_coverage (
	coverage_id SERIAL PRIMARY KEY,
    coverage_area VARCHAR(20),
    delivery_type VARCHAR(20),
    weight_price NUMERIC(10, 2),
    car_price NUMERIC(10, 2),
    foot_price NUMERIC(10, 2),
    train_price NUMERIC(10, 2),
    distance_price NUMERIC(10, 2)
);

CREATE TABLE notifications (
    notification_id SERIAL PRIMARY KEY,
    customer_id INT NOT NULL,
    message TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL
);
SELECT * FROM notifications

INSERT INTO delivery_coverage (coverage_area, delivery_type, weight_price, car_price, foot_price, train_price, distance_price)
VALUES
('Belarus', 'train', 8, NULL, NULL, 30, 0.15),
	('Belarus', 'foot', 8, NULL, 10, NULL, 0.15),
    ('Belarus', 'car', 8, 20, NULL, NULL, 0.15);

CREATE TABLE delivery_route (
    delivery_id INT,
    timestamp TIMESTAMPTZ,
    new_street VARCHAR(100)
);
select * from delivery_route
---100.000. строк
DO $$
DECLARE
    v_order_id INT;
    v_rating FLOAT;
    v_comment TEXT;
    v_posted_at TIMESTAMPTZ;
BEGIN
    FOR i IN 12..100000 LOOP
        -- Чередуем order_id между 53 и 54
        v_order_id := CASE WHEN i % 2 = 0 THEN 53 ELSE 52 END;
        v_rating := (RANDOM() * 5.0)::FLOAT;
        v_comment := 'This is a review comment number ' || i;
        v_posted_at := NOW() - (RANDOM() * INTERVAL '365 days');

        -- Вставка данных в таблицу reviews
        INSERT INTO reviews (customer_id, order_id, rating, comment, posted_at)
        VALUES (54, v_order_id, v_rating, v_comment, v_posted_at);
    END LOOP;
END $$;




EXPLAIN ANALYZE SELECT * FROM reviews ORDER BY posted_at DESC;

select * from 
CREATE INDEX idx_posted_at ON reviews (posted_at);

---CSV IMPORT AND EXPORT
COPY orders TO 'H:/KYRSACH/orders.csv' DELIMITER ',' CSV HEADER;
COPY reviews TO 'H:/KYRSACH/reviews.csv' DELIMITER ',' CSV HEADER;
COPY reviews FROM 'H:/KYRSACH/reviews.csv' DELIMITER ',' CSV HEADER;

-- Создание ролей
CREATE USER customer WITH PASSWORD '111';
CREATE USER courier WITH PASSWORD '222';
CREATE USER manager WITH PASSWORD '333';









---1
---Процедуры и функции для роли покупателя

---Просмотр и изменение геог покрытия и типов транспорта
CREATE OR REPLACE FUNCTION view_delivery_coverage()
RETURNS SETOF delivery_coverage AS $$
BEGIN
    RETURN QUERY SELECT * FROM delivery_coverage;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE EXECUTE ON FUNCTION view_delivery_coverage() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION view_delivery_coverage() TO customer;
GRANT EXECUTE ON FUNCTION view_delivery_coverage() TO manager;



-- Функция для просмотра таблицы customers
CREATE OR REPLACE FUNCTION view_customers()
RETURNS SETOF customers AS $$
BEGIN
    RETURN QUERY SELECT * FROM customers;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE EXECUTE ON FUNCTION view_customers() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION view_customers() TO customer;
GRANT EXECUTE ON FUNCTION view_customers() TO manager;

-- Процедура для заполнения таблицы customers
CREATE OR REPLACE PROCEDURE insert_customer(
    first_name VARCHAR(30),
    last_name VARCHAR(35),
    phone_number VARCHAR(20),
    street VARCHAR(25),
    house INT,
    apartment INT,
    x FLOAT,
    y FLOAT,
    login VARCHAR(50),
    password VARCHAR(100),
    insurance BOOLEAN,
    recipient_first_name VARCHAR(30),
    recipient_last_name VARCHAR(35),
    recipient_phone_number VARCHAR(20),
    recipient_street VARCHAR(25),
    recipient_house INT,
    recipient_apartment INT,
    recipient_x FLOAT,
    recipient_y FLOAT,
    packaging_labeling VARCHAR(20),
    preferred_datetime TIMESTAMPTZ
)
AS $$
DECLARE
    customer_id_var INT;
BEGIN
    INSERT INTO customers (
        first_name, last_name, phone_number, street, house, apartment, x, y, insurance,
        recipient_first_name, recipient_last_name, recipient_phone_number, recipient_street,
        recipient_house, recipient_apartment, recipient_x, recipient_y, packaging_labeling,
        preferred_datetime
    )
    VALUES (
        first_name, last_name, phone_number, street, house, apartment, x, y, insurance,
        recipient_first_name, recipient_last_name, recipient_phone_number, recipient_street,
        recipient_house, recipient_apartment, recipient_x, recipient_y, packaging_labeling,
        preferred_datetime
    )
    RETURNING customer_id INTO customer_id_var;

    INSERT INTO users (customer_id, login, password)
    VALUES (customer_id_var, login, password);
    
    RAISE NOTICE 'Покупатель успешно добавлен. ID покупателя: %', customer_id_var;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE ALL ON PROCEDURE insert_customer(VARCHAR, VARCHAR, VARCHAR, VARCHAR, INT, INT, FLOAT, FLOAT, VARCHAR, VARCHAR, BOOLEAN, VARCHAR, VARCHAR, VARCHAR, VARCHAR, INT, INT, FLOAT, FLOAT, VARCHAR, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE insert_customer(VARCHAR, VARCHAR, VARCHAR, VARCHAR, INT, INT, FLOAT, FLOAT, VARCHAR, VARCHAR, BOOLEAN, VARCHAR, VARCHAR, VARCHAR, VARCHAR, INT, INT, FLOAT, FLOAT, VARCHAR, TIMESTAMPTZ) TO customer;


-- Процедура для изменения таблицы customers
CREATE OR REPLACE PROCEDURE update_customer_data(
    p_login VARCHAR(50),
    p_password VARCHAR(100),
    p_new_insurance BOOLEAN,
    p_new_packaging_labeling VARCHAR(20)
)
AS $$
DECLARE
    v_customer_id INT;
    v_active_or_deleted VARCHAR(10);
BEGIN
    SELECT c.customer_id, c.active_or_deleted
    INTO v_customer_id, v_active_or_deleted
    FROM customers c
    JOIN users u ON c.customer_id = u.customer_id
    WHERE u.login = p_login AND u.password = p_password;

    IF v_customer_id IS NOT NULL THEN
        IF v_active_or_deleted = 'deleted' THEN
            RAISE EXCEPTION 'Account is deleted. Cannot update customer data.';
        ELSE
            UPDATE customers
            SET 
                insurance = p_new_insurance,
                packaging_labeling = p_new_packaging_labeling
            WHERE customer_id = v_customer_id;

            RAISE NOTICE 'Customer data updated successfully';
        END IF;
    ELSE
        RAISE EXCEPTION 'Invalid login or password';
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON PROCEDURE update_customer_data(VARCHAR, VARCHAR, BOOLEAN, VARCHAR) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE update_customer_data(VARCHAR, VARCHAR, BOOLEAN, VARCHAR) TO customer;


-- Удаление покупателя
CREATE OR REPLACE FUNCTION delete_customer(p_login VARCHAR(50), p_password VARCHAR(100))
RETURNS VOID AS $$
DECLARE
    v_customer_id INT;
BEGIN
    SELECT customer_id INTO v_customer_id
    FROM users
    WHERE login = p_login AND password = p_password;

    IF v_customer_id IS NOT NULL THEN
        -- Установка значения active_or_deleted в 'deleted'
        UPDATE customers
        SET active_or_deleted = 'deleted'
        WHERE customer_id = v_customer_id;

        RAISE NOTICE 'Customer deleted successfully';
    ELSE
        RAISE EXCEPTION 'Invalid login or password';
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION delete_customer(VARCHAR, VARCHAR) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION delete_customer(VARCHAR, VARCHAR) TO customer;

---Подсчёт общей стоимости
CREATE OR REPLACE PROCEDURE calculate_total_cost2(
    p_cargo_weight FLOAT,
    p_transport_type VARCHAR(20),
    p_insurance BOOLEAN,
    p_packaging_labeling VARCHAR(20),
    p_product_type VARCHAR(10),
    p_sender_x FLOAT,
    p_sender_y FLOAT,
    p_recipient_x FLOAT,
    p_recipient_y FLOAT
)
AS $$
DECLARE
    v_total_cost NUMERIC(10,2);
    v_distance FLOAT;
BEGIN
    IF p_cargo_weight IS NULL THEN
        RAISE EXCEPTION 'Cargo weight cannot be null.';
    END IF;

    v_total_cost := p_cargo_weight * 8; -- базовая стоимость за каждый килограмм

    IF p_transport_type = 'car' THEN
        v_total_cost := v_total_cost + 20;
    ELSIF p_transport_type = 'foot' THEN
        v_total_cost := v_total_cost + 10;
    ELSIF p_transport_type = 'train' THEN
        v_total_cost := v_total_cost + 30;
    END IF;

    IF p_insurance THEN
        v_total_cost := v_total_cost + (v_total_cost * 0.1); -- дополнительные 10% от общей стоимости при наличии страховки
    END IF;

    IF p_packaging_labeling = 'none' THEN
        v_total_cost := v_total_cost + 0;
    ELSIF p_packaging_labeling = 'labeling' THEN
        v_total_cost := v_total_cost + 5;
    ELSIF p_packaging_labeling = 'packaging' THEN
        v_total_cost := v_total_cost + 5;
    ELSIF p_packaging_labeling = 'packaging_labeling' THEN
        v_total_cost := v_total_cost + 8;
    END IF;

    IF p_product_type = 'fragile' THEN
        v_total_cost := v_total_cost + 5; -- дополнительные 5 единиц стоимости при хрупком товаре
    END IF;

    -- Расчет расстояния между отправителем и получателем
    v_distance := sqrt(power(p_sender_x - p_recipient_x, 2) + power(p_sender_y - p_recipient_y, 2));

    -- Добавление платы за расстояние
    v_total_cost := v_total_cost + (v_distance * 0.15);

    RAISE NOTICE 'Total cost calculated: %', TO_CHAR(v_total_cost, 'FM999999999.99');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON PROCEDURE calculate_total_cost2(FLOAT, VARCHAR, BOOLEAN, VARCHAR, VARCHAR, FLOAT, FLOAT, FLOAT, FLOAT) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE calculate_total_cost2(FLOAT, VARCHAR, BOOLEAN, VARCHAR, VARCHAR, FLOAT, FLOAT, FLOAT, FLOAT) TO customer;
-- Процедура для просмотра таблицы product_reviews
CREATE OR REPLACE FUNCTION view_reviews()
RETURNS TABLE (
    review_id INT,
    customer_id INT,
    order_id INT,
    rating FLOAT,
    comment TEXT,
    posted_at TIMESTAMP WITH TIME ZONE,
	answer VARCHAR(50)
)
AS $$
BEGIN
    RETURN QUERY SELECT * FROM reviews;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE EXECUTE ON FUNCTION view_reviews() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION view_reviews() TO customer;
GRANT EXECUTE ON FUNCTION view_reviews() TO manager;
-- Процедура для заполнения таблицы product_reviews
CREATE OR REPLACE PROCEDURE insert_order_review(
    p_login VARCHAR(50),
    p_password VARCHAR(100),
    p_order_id INT,
    p_rating FLOAT,
    p_comment TEXT
)
AS $$
DECLARE
    v_customer_id INT;
    v_active_or_deleted VARCHAR(10);
BEGIN
    SELECT c.customer_id, c.active_or_deleted
    INTO v_customer_id, v_active_or_deleted
    FROM customers c
    JOIN users u ON c.customer_id = u.customer_id
    WHERE u.login = p_login AND u.password = p_password;

    IF v_customer_id IS NOT NULL THEN
        IF v_active_or_deleted = 'deleted' THEN
            RAISE EXCEPTION 'Account is deleted. Cannot insert order review.';
        ELSE
            -- Проверяем, принадлежит ли указанный заказ данному клиенту
            IF EXISTS (SELECT 1 FROM orders WHERE order_id = p_order_id AND customer_id = v_customer_id) THEN
                INSERT INTO reviews (customer_id, order_id, rating, comment, posted_at)
                VALUES (v_customer_id, p_order_id, p_rating, p_comment, CURRENT_TIMESTAMP);

                RAISE NOTICE 'Order review inserted successfully';
            ELSE
                RAISE EXCEPTION 'Order does not belong to the customer';
            END IF;
        END IF;
    ELSE
        RAISE EXCEPTION 'Invalid login or password';
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON PROCEDURE insert_order_review(VARCHAR, VARCHAR, INT, FLOAT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE insert_order_review(VARCHAR, VARCHAR, INT, FLOAT, TEXT) TO customer;

-- Процедура для изменения таблицы product_reviews
CREATE OR REPLACE PROCEDURE update_order_review(
    p_login VARCHAR(50),
    p_password VARCHAR(100),
    p_order_id INT,
    p_rating FLOAT,
    p_comment TEXT
)
AS $$
DECLARE
    v_customer_id INT;
    v_active_or_deleted VARCHAR(10);
BEGIN
    SELECT c.customer_id, c.active_or_deleted
    INTO v_customer_id, v_active_or_deleted
    FROM customers c
    JOIN users u ON c.customer_id = u.customer_id
    WHERE u.login = p_login AND u.password = p_password;

    IF v_customer_id IS NOT NULL THEN
        IF v_active_or_deleted = 'deleted' THEN
            RAISE EXCEPTION 'Account is deleted. Cannot update order review.';
        ELSE
            -- Проверяем, принадлежит ли указанный заказ данному клиенту
            IF EXISTS (SELECT 1 FROM orders WHERE order_id = p_order_id AND customer_id = v_customer_id) THEN
                UPDATE reviews
                SET rating = p_rating, comment = p_comment
                WHERE order_id = p_order_id AND customer_id = v_customer_id;

                IF FOUND THEN
                    RAISE NOTICE 'Order review updated successfully';
                ELSE
                    RAISE EXCEPTION 'No review found for the specified order and customer';
                END IF;
            ELSE
                RAISE EXCEPTION 'Order does not belong to the customer';
            END IF;
        END IF;
    ELSE
        RAISE EXCEPTION 'Invalid login or password';
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON PROCEDURE update_order_review(VARCHAR, VARCHAR, INT, FLOAT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE update_order_review(VARCHAR, VARCHAR, INT, FLOAT, TEXT) TO customer;

-- Функция для удаления строки из таблицы product_reviews
CREATE OR REPLACE FUNCTION delete_order_review(
    p_login VARCHAR(50),
    p_password VARCHAR(100),
    p_order_id INT
)
RETURNS VOID AS $$
DECLARE
    v_customer_id INT;
    v_active_or_deleted VARCHAR(10);
BEGIN
    -- Проверка аутентификации
    SELECT c.customer_id, c.active_or_deleted
    INTO v_customer_id, v_active_or_deleted
    FROM customers c
    JOIN users u ON c.customer_id = u.customer_id
    WHERE u.login = p_login AND u.password = p_password;

    IF v_customer_id IS NULL THEN
        RAISE EXCEPTION 'Invalid login or password';
    END IF;

    IF v_active_or_deleted = 'deleted' THEN
        RAISE EXCEPTION 'Account is deleted. Cannot delete order review.';
    END IF;

    -- Удаление отзыва о заказе
    DELETE FROM reviews
    WHERE customer_id = v_customer_id AND order_id = p_order_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION delete_order_review(VARCHAR, VARCHAR, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION delete_order_review(VARCHAR, VARCHAR, INT) TO customer;
-- Функции для просмотра таблицы orders
CREATE OR REPLACE FUNCTION view_orders2(p_login VARCHAR(50), p_password VARCHAR(100))
RETURNS TABLE (
    order_id INT,
    customer_id INT,
    date_get TIMESTAMPTZ,
    total_cost FLOAT,
    product_name VARCHAR(50),
    product_type VARCHAR(10),
    cargo_weight FLOAT,
    transport_type VARCHAR(20)
)
AS $$
DECLARE
    v_customer_id INT;
    v_active_or_deleted VARCHAR(10);
BEGIN
    -- Проверка аутентификации
    SELECT c.customer_id, c.active_or_deleted
    INTO v_customer_id, v_active_or_deleted
    FROM customers c
    JOIN users u ON c.customer_id = u.customer_id
    WHERE u.login = p_login AND u.password = p_password;

    IF v_customer_id IS NULL THEN
        RAISE EXCEPTION 'Invalid login or password';
    END IF;

    IF v_active_or_deleted = 'deleted' THEN
        RAISE EXCEPTION 'Account deleted. Cannot view orders.';
    END IF;

    -- Просмотр заказов
    RETURN QUERY
    SELECT o.order_id, o.customer_id, o.date_get, o.total_cost, o.product_name, o.product_type, o.cargo_weight, o.transport_type
    FROM orders o
    WHERE o.customer_id = v_customer_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE EXECUTE ON FUNCTION view_orders2(VARCHAR, VARCHAR) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION view_orders2(VARCHAR, VARCHAR) TO customer;

--Функция view_orders просмотр заказов
CREATE OR REPLACE FUNCTION view_orders()
RETURNS TABLE (
    order_id INT,
    customer_id INT,
    date_get TIMESTAMPTZ,
    total_cost FLOAT,
    product_name VARCHAR(50),
    product_type VARCHAR(10),
    cargo_weight FLOAT,
    transport_type VARCHAR(20)
)
AS $$
BEGIN
    RETURN QUERY SELECT o.order_id, o.customer_id, o.date_get, o.total_cost, o.product_name, o.product_type, o.cargo_weight, o.transport_type FROM orders o;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE EXECUTE ON FUNCTION view_orders() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION view_orders() TO courier;
-- Процедура для заполнения таблицы orders
CREATE OR REPLACE PROCEDURE create_order(
    p_login VARCHAR(50),
    p_password VARCHAR(100),
    p_product_name VARCHAR(50),
    p_product_type VARCHAR(15),
    p_cargo_weight FLOAT,
    p_transport_type VARCHAR(20)
)
AS $$
DECLARE
    v_customer_id INT;
    v_current_time TIMESTAMPTZ := NOW();
    v_customer_status VARCHAR(10);
BEGIN
    -- Проверка логина и пароля пользователя
    SELECT u.customer_id, c.active_or_deleted INTO v_customer_id, v_customer_status
    FROM users u
    JOIN customers c ON u.customer_id = c.customer_id
    WHERE u.login = p_login AND u.password = p_password;

    IF v_customer_id IS NULL THEN
        RAISE EXCEPTION 'Invalid login or password.';
    END IF;

    IF v_customer_status = 'deleted' THEN
        RAISE EXCEPTION 'Customer is deleted and cannot place an order.';
    END IF;

    -- Вставка заказа в таблицу orders
    INSERT INTO orders (customer_id, date_get, product_name, product_type, cargo_weight, transport_type)
    VALUES (v_customer_id, v_current_time, p_product_name, p_product_type, p_cargo_weight, p_transport_type);
    
    RAISE NOTICE 'Order created successfully.';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON PROCEDURE create_order(VARCHAR, VARCHAR,VARCHAR,VARCHAR, FLOAT, VARCHAR) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE create_order(VARCHAR, VARCHAR,VARCHAR,VARCHAR, FLOAT, VARCHAR) TO customer;






-- Процедура для просмотра таблицы delivery_list
CREATE OR REPLACE FUNCTION view_delivery_list()
RETURNS TABLE (
    delivery_id INT,
    order_id INT,
    courier_id INT,
    date_arrived TIMESTAMPTZ,
    payment_method VARCHAR(4),
    date_get_by_courier TIMESTAMPTZ,
    status VARCHAR(20),
	street VARCHAR(50)
)
AS $$
BEGIN
    RETURN QUERY SELECT * FROM delivery_list;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE EXECUTE ON FUNCTION view_delivery_list() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION view_delivery_list() TO customer;


CREATE OR REPLACE FUNCTION view_delivery_list2(p_login VARCHAR(50), p_password VARCHAR(50))
RETURNS TABLE (
    delivery_id INT,
    order_id INT,
    courier_id INT,
    date_arrived TIMESTAMPTZ,
    payment_method VARCHAR(4),
    date_get_by_courier TIMESTAMPTZ,
    status VARCHAR(20),
    street VARCHAR(50),
    phone_number VARCHAR(20)
)
AS $$
BEGIN
    RETURN QUERY
    SELECT dl.delivery_id, dl.order_id, dl.courier_id, dl.date_arrived, dl.payment_method, dl.date_get_by_courier,
           dl.status, dl.street, ci.phone_number
    FROM delivery_list dl
    INNER JOIN orders o ON dl.order_id = o.order_id
    INNER JOIN customers c ON o.customer_id = c.customer_id
    INNER JOIN users u ON c.customer_id = u.customer_id
    INNER JOIN courier_info ci ON dl.courier_id = ci.courier_id
    WHERE u.login = p_login AND u.password = p_password AND c.active_or_deleted = 'active';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION view_delivery_list2(VARCHAR, VARCHAR) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION view_delivery_list2(VARCHAR, VARCHAR) TO customer;

-- Создание функции для вычисления разницы во времени
CREATE OR REPLACE FUNCTION calculate_time_difference(p_login VARCHAR(50), p_password VARCHAR(50))
RETURNS INTERVAL
AS $$
DECLARE
    v_difference INTERVAL;
    v_active_or_deleted VARCHAR(10);
BEGIN
    -- Проверка аутентификации
    IF EXISTS (
        SELECT 1
        FROM customers c
        JOIN users u ON c.customer_id = u.customer_id
        WHERE u.login = p_login AND u.password = p_password
    ) THEN
        -- Проверка статуса аккаунта
        SELECT active_or_deleted INTO v_active_or_deleted
        FROM customers c
        JOIN users u ON c.customer_id = u.customer_id
        WHERE u.login = p_login AND u.password = p_password;

        IF v_active_or_deleted = 'deleted' THEN
            RAISE EXCEPTION 'Account deleted. Cannot calculate time difference.';
        END IF;

        -- Вычисление разницы времени
        SELECT date_arrived - date_get_by_courier INTO v_difference
        FROM delivery_list
        WHERE order_id IN (
            SELECT order_id
            FROM orders
            WHERE customer_id = (
                SELECT customer_id
                FROM users
                WHERE login = p_login AND password = p_password
            )
        );

        RETURN v_difference;
    ELSE
        RAISE EXCEPTION 'Invalid login or password';
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION calculate_time_difference(VARCHAR, VARCHAR) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION calculate_time_difference(VARCHAR, VARCHAR) TO customer;

---просмотр уведомлений 
CREATE OR REPLACE FUNCTION get_customer_notifications(
    p_login VARCHAR(50),
    p_password VARCHAR(50)
)
RETURNS TABLE (
    notification_id INT,
    customer_id INT,
    message TEXT,
    created_at TIMESTAMPTZ
)
AS $$
BEGIN
    RETURN QUERY
    SELECT n.notification_id, n.customer_id, n.message, n.created_at
    FROM notifications n
    JOIN users u ON n.customer_id = u.customer_id
    WHERE u.login = p_login AND u.password = p_password;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid login or password';
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE EXECUTE ON FUNCTION get_customer_notifications(VARCHAR, VARCHAR) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_customer_notifications(VARCHAR, VARCHAR) TO customer;

---2
---Процедуры для курьера 
-- Процедура для просмотра строки в таблице courier_infо
CREATE OR REPLACE FUNCTION view_courier_info()
RETURNS TABLE (
    courier_id INT,
    first_name VARCHAR(30),
    last_name VARCHAR(35),
    phone_number VARCHAR(20),
    delivery_type VARCHAR(5),
    status VARCHAR(10),
    active_or_deleted VARCHAR(10)
)
AS $$
BEGIN
    RETURN QUERY SELECT ci.courier_id, ci.first_name, ci.last_name, ci.phone_number, ci.delivery_type, ci.status,  ci.active_or_deleted FROM courier_info ci;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE EXECUTE ON FUNCTION view_courier_info() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION view_courier_info() TO manager;

--Процедура update_courier_info
CREATE OR REPLACE PROCEDURE update_courier_info(
    IN p_login VARCHAR(50),
    IN p_password VARCHAR(50),
    IN p_status VARCHAR(10),
    IN p_delivery_type VARCHAR(5),
    IN p_phone VARCHAR(20)
)
AS $$
DECLARE
    v_courier_id INT;
    v_active_or_deleted VARCHAR(10);
BEGIN
    -- Получение courier_id на основе login из таблицы users
    SELECT courier_id INTO v_courier_id
    FROM users
    WHERE login = p_login AND password = p_password;

    IF v_courier_id IS NOT NULL THEN
        -- Проверка статуса аккаунта курьера
        SELECT active_or_deleted INTO v_active_or_deleted
        FROM courier_info
        WHERE courier_id = v_courier_id;

        IF v_active_or_deleted = 'deleted' THEN
            RAISE EXCEPTION 'Account deleted. Cannot update courier info.';
        END IF;

        -- Обновление информации о курьере
        UPDATE courier_info
        SET status = p_status, delivery_type = p_delivery_type,
            phone_number = p_phone
        WHERE courier_id = v_courier_id;

        RAISE NOTICE 'Courier info updated successfully';
    ELSE
        RAISE EXCEPTION 'Invalid login or password';
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON PROCEDURE update_courier_info(
    IN p_login VARCHAR(50),
    IN p_password VARCHAR(50),
    IN p_status VARCHAR(10),
    IN p_delivery_type VARCHAR(5),
    IN p_phone VARCHAR(20)
) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE update_courier_info(
    IN p_login VARCHAR(50),
    IN p_password VARCHAR(50),
    IN p_status VARCHAR(10),
    IN p_delivery_type VARCHAR(5),
    IN p_phone VARCHAR(20)
) TO courier;

-- Процедура для заполнения строки в таблице delivery_list
CREATE OR REPLACE PROCEDURE create_delivery(
    IN p_login VARCHAR(50),
    IN p_password VARCHAR(50),
    IN p_order_id INT,
    IN p_payment_method VARCHAR(4),
    IN p_date_arrived TIMESTAMPTZ,
    IN p_street VARCHAR(50)
)
AS $$
DECLARE
    v_courier_id INT;
    v_active_or_deleted VARCHAR(10);
    v_delivery_id INT;
BEGIN
    -- Получение courier_id на основе login из таблицы courier_info
    SELECT courier_id INTO v_courier_id
    FROM courier_info
    WHERE courier_id = (SELECT courier_id FROM users WHERE login = p_login AND password = p_password);

    IF v_courier_id IS NOT NULL THEN
        -- Проверка статуса аккаунта курьера
        SELECT active_or_deleted INTO v_active_or_deleted
        FROM courier_info
        WHERE courier_id = v_courier_id;

        IF v_active_or_deleted = 'deleted' THEN
            RAISE EXCEPTION 'Account deleted. Cannot create delivery.';
        END IF;

        -- Проверка, что заказ не был уже взят другим курьером
        IF EXISTS (
            SELECT 1
            FROM delivery_list
            WHERE order_id = p_order_id
        ) THEN
            RAISE EXCEPTION 'Order is already assigned to a courier';
        ELSE
            -- Создание записи в таблице delivery_list
            INSERT INTO delivery_list (order_id, courier_id, payment_method, date_arrived, date_get_by_courier, street)
            VALUES (p_order_id, v_courier_id, p_payment_method, p_date_arrived, NOW(), p_street)
            RETURNING delivery_id INTO v_delivery_id;

            -- Изменение статуса курьера на "занят"
            UPDATE courier_info
            SET status = 'занят'
            WHERE courier_id = v_courier_id;

            -- Добавление записи в таблицу delivery_route
            INSERT INTO delivery_route (delivery_id, timestamp, new_street)
            VALUES (v_delivery_id, NOW(), p_street);

            RAISE NOTICE 'Delivery created successfully';
        END IF;
    ELSE
        RAISE EXCEPTION 'Invalid login or password';
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON PROCEDURE create_delivery(
    IN p_login VARCHAR(50),
    IN p_password VARCHAR(50),
    IN p_order_id INT,
    IN p_payment_method VARCHAR(4),
    IN p_date_arrived TIMESTAMPTZ,
	IN p_street varchar(50)
) FROM PUBLIC;

GRANT EXECUTE ON PROCEDURE create_delivery(
    IN p_login VARCHAR(50),
    IN p_password VARCHAR(50),
    IN p_order_id INT,
    IN p_payment_method VARCHAR(4),
    IN p_date_arrived TIMESTAMPTZ,
	IN p_street varchar(50)
) TO courier;
---изменение статуса
CREATE OR REPLACE PROCEDURE update_delivery(
    IN p_login VARCHAR(50),
    IN p_password VARCHAR(50),
    IN p_order_id INT,
    IN p_status VARCHAR(20),
    IN p_street VARCHAR(100)
)
AS $$
DECLARE
    v_courier_id INT;
    v_delivery_id INT;
    v_payment_method VARCHAR(4);
    v_date_arrived TIMESTAMPTZ;
    v_active_or_deleted VARCHAR(10);
    v_customer_id INT;
BEGIN
    -- Получение courier_id на основе login из таблицы courier_info
    SELECT courier_id INTO v_courier_id
    FROM courier_info
    WHERE courier_id = (SELECT courier_id FROM users WHERE login = p_login AND password = p_password);

    IF v_courier_id IS NOT NULL THEN
        -- Проверка статуса аккаунта курьера
        SELECT active_or_deleted INTO v_active_or_deleted
        FROM courier_info
        WHERE courier_id = v_courier_id;

        IF v_active_or_deleted = 'deleted' THEN
            RAISE EXCEPTION 'Account deleted. Cannot update delivery.';
        END IF;

        -- Проверка наличия доставки для указанного заказа и курьера
        SELECT delivery_id, payment_method, date_arrived
        INTO v_delivery_id, v_payment_method, v_date_arrived
        FROM delivery_list
        WHERE courier_id = v_courier_id AND order_id = p_order_id;

        IF v_delivery_id IS NULL THEN
            RAISE EXCEPTION 'Delivery not found for the specified courier and order';
        ELSE
            -- Обновление статуса и столбца "улица" в таблице delivery_list
            UPDATE delivery_list
            SET status = p_status,
                street = p_street
            WHERE delivery_id = v_delivery_id;

            -- Добавление записи в таблицу delivery_route
            INSERT INTO delivery_route (delivery_id, timestamp, new_street)
            VALUES (v_delivery_id, NOW(), p_street);

            -- Получение customer_id на основе order_id из таблицы orders
            SELECT customer_id INTO v_customer_id
            FROM orders
            WHERE order_id = p_order_id;

            -- Добавление записи об уведомлении в таблицу notifications
            INSERT INTO notifications (customer_id, message, created_at)
            VALUES (v_customer_id, 'Status updated: ' || p_status, NOW());

            RAISE NOTICE 'Delivery updated successfully';
        END IF;
    ELSE
        RAISE EXCEPTION 'Invalid login or password';
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE EXECUTE ON PROCEDURE update_delivery(VARCHAR, VARCHAR, INT, VARCHAR, VARCHAR) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE update_delivery(VARCHAR, VARCHAR, INT, VARCHAR, VARCHAR) TO courier;


CREATE TYPE DistanceResult AS (
    order_id INT,
    distance FLOAT
);



---информцаия о покупателях и заказах 
CREATE VIEW order_customer_info AS
SELECT
    o.order_id,
    o.date_get,
    o.total_cost,
    o.product_name,
    o.product_type,
    o.cargo_weight,
    o.transport_type,
    c.customer_id,
    c.first_name AS customer_first_name,
    c.last_name AS customer_last_name,
    c.phone_number AS customer_phone_number,
    c.street AS customer_street,
    c.house AS customer_house,
    c.apartment AS customer_apartment,
    c.x AS customer_x,
    c.y AS customer_y,
    c.insurance,
    c.packaging_labeling,
    c.recipient_first_name,
    c.recipient_last_name,
    c.recipient_phone_number,
    c.recipient_street,
    c.recipient_house,
    c.recipient_apartment,
    c.recipient_x,
    c.recipient_y,
    c.preferred_datetime
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id;



---3
---Курьера добавить
CREATE OR REPLACE PROCEDURE create_courier(
    IN p_first_name VARCHAR(30),
    IN p_last_name VARCHAR(35),
    IN p_phone_number VARCHAR(20),
    IN p_delivery_type VARCHAR(5),
    IN p_login VARCHAR(50),
    IN p_password VARCHAR(100)
)
AS $$
DECLARE
    v_courier_id INT;
BEGIN
    INSERT INTO courier_info (first_name, last_name, phone_number, delivery_type)
    VALUES (p_first_name, p_last_name, p_phone_number, p_delivery_type)
    RETURNING courier_id INTO v_courier_id;

    INSERT INTO users (courier_id, login, password)
    VALUES (v_courier_id, p_login, p_password);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON PROCEDURE create_courier(IN VARCHAR, IN VARCHAR, IN VARCHAR, IN VARCHAR ,IN VARCHAR, IN VARCHAR) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE create_courier(IN VARCHAR, IN VARCHAR, IN VARCHAR, IN VARCHAR, IN VARCHAR, IN VARCHAR) TO manager;
----Уволнение курьера
CREATE OR REPLACE PROCEDURE delete_courier_info(p_courier_id INT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Обновление статуса информации о курьере
    UPDATE courier_info SET active_or_deleted = 'deleted' WHERE courier_id = p_courier_id;

    RAISE NOTICE 'Courier info and associated user marked as deleted successfully';
END;
$$;

REVOKE ALL ON PROCEDURE delete_courier_info(INT) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE delete_courier_info(INT) TO manager;
---Блокировака покупателя
CREATE OR REPLACE FUNCTION block_customer(p_customer_id INT)
RETURNS VOID AS $$
BEGIN
    -- Установка значения active_or_deleted в 'deleted'
    UPDATE customers
    SET active_or_deleted = 'deleted'
    WHERE customer_id = p_customer_id;

    RAISE NOTICE 'Customer deleted successfully';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE ALL ON FUNCTION block_customer(INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION block_customer(INT) TO manager;
---Ответы на отзывы
CREATE OR REPLACE PROCEDURE add_review_answer(
    p_review_id INT,
    p_answer VARCHAR(50)
) SECURITY DEFINER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Добавление ответа на отзыв
    UPDATE reviews
    SET answer = p_answer
    WHERE review_id = p_review_id;

    RAISE NOTICE 'Review answer added successfully';
END;
$$;

REVOKE ALL ON PROCEDURE add_review_answer(INT, VARCHAR) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE add_review_answer(INT, VARCHAR) TO manager;
---История маршрутов
CREATE OR REPLACE PROCEDURE view_delivery_route()
AS $$
DECLARE
    v_row delivery_route%ROWTYPE;
BEGIN
    -- Выбор всех записей из таблицы delivery_route
    FOR v_row IN SELECT * FROM delivery_route LOOP
        -- Вывод информации о каждой записи
        RAISE NOTICE 'Delivery ID: %, Timestamp: %, New Street: %',
            v_row.delivery_id, v_row.timestamp, v_row.new_street;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE ALL ON PROCEDURE view_delivery_route() FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE view_delivery_route() TO manager;

---Иформация о полученных заказах 
CREATE OR REPLACE PROCEDURE view_order_details()
AS $$
DECLARE
    order_row RECORD;
    route_row RECORD;
BEGIN
    FOR order_row IN SELECT dl.delivery_id, dl.order_id, dl.courier_id, dl.date_arrived, dl.payment_method, dl.date_get_by_courier, dl.status, dl.street,
                            c.phone_number, c.recipient_phone_number,
                            o.product_name, o.product_type, o.cargo_weight, o.transport_type
                     FROM delivery_list dl
                     JOIN orders o ON dl.order_id = o.order_id
                     JOIN customers c ON o.customer_id = c.customer_id
                     WHERE dl.status = 'Доставлен'
    LOOP
        -- Вывод информации о заказе
        RAISE INFO 'Order ID: %, Phone: %, Recipient Phone: %, Product: %, Type: %, Weight: % kg, Transport: %',
            order_row.order_id,
            order_row.phone_number,
            order_row.recipient_phone_number,
            order_row.product_name,
            order_row.product_type,
            order_row.cargo_weight,
            order_row.transport_type;
        
        -- Вывод информации о маршруте доставки
        FOR route_row IN SELECT timestamp, new_street
                          FROM delivery_route
                          WHERE delivery_id = order_row.delivery_id
        LOOP
            RAISE INFO 'Timestamp: %, New Street: %',
                route_row.timestamp,
                route_row.new_street;
        END LOOP;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
GRANT EXECUTE ON PROCEDURE view_order_details() TO manager;
REVOKE EXECUTE ON PROCEDURE view_order_details() FROM public;

CREATE OR REPLACE PROCEDURE update_delivery_coverage(
    p_coverage_id INT,
    p_coverage_area VARCHAR(20),
    p_delivery_type VARCHAR(20),
    p_weight_price NUMERIC(10, 2),
    p_car_price NUMERIC(10, 2),
    p_foot_price NUMERIC(10, 2),
    p_train_price NUMERIC(10, 2),
    p_distance_price NUMERIC(10, 2)
)
AS $$
BEGIN
    UPDATE delivery_coverage
    SET coverage_area = p_coverage_area,
        delivery_type = p_delivery_type,
        weight_price = p_weight_price,
        car_price = p_car_price,
        foot_price = p_foot_price,
        train_price = p_train_price,
        distance_price = p_distance_price
    WHERE coverage_id = p_coverage_id;
        
    IF FOUND THEN
        RAISE NOTICE 'Data updated successfully.';
    ELSE
        RAISE EXCEPTION 'No matching records found.';
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
GRANT EXECUTE ON PROCEDURE update_delivery_coverage(INT, VARCHAR(20), VARCHAR(20), NUMERIC(10, 2), NUMERIC(10, 2), NUMERIC(10, 2), NUMERIC(10, 2), NUMERIC(10, 2)) TO manager;
REVOKE EXECUTE ON PROCEDURE update_delivery_coverage(INT, VARCHAR(20), VARCHAR(20), NUMERIC(10, 2), NUMERIC(10, 2), NUMERIC(10, 2), NUMERIC(10, 2), NUMERIC(10, 2)) FROM public;