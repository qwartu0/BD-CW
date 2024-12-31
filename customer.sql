SET ROLE customer;
---Данные покупателя
CALL insert_customer(
    'John', -- first_name
    'Doe', -- last_name
    '123456789', -- phone_number
    'Main Street', -- street
    123, -- house
    456, -- apartment
    1.234, -- x
    5.678, -- y
    'cus5', -- login
    '111', -- password
    TRUE, -- insurance
    'Jane', -- recipient_first_name
    'Smith', -- recipient_last_name
    '987654321', -- recipient_phone_number
    'Second Street', -- recipient_street
    789, -- recipient_house
    321, -- recipient_apartment
    100.876, -- recipient_x
    48.321, -- recipient_y
    'packaging', -- packaging_labeling
    '2024-05-22 16:06:00' -- preferred_datetime
);
---'packaging', 'labeling', 'packaging_labeling', 'none'
CALL update_customer_data('cus4','111',false,'packaging_labeling');
SELECT delete_customer('cus3', '111');

---Расчёт стоимости заказа
CALL calculate_total_cost2(10, 'car', false, 'none', 'fragile', 10.0, 25.0, 100.0, 50.0);
---Заказы
SELECT * FROM view_orders2('cus4', '111');
CALL create_order('cus5', '111', 'Ноутбук', 'fragile', 2.5, 'car');
---Отзывы к продукту и возможность 
SELECT * FROM view_reviews();
CALL insert_order_review('cus4', '111',53, 4.5, 'Отличная доставка!');
CALL update_order_review('cus2', '111', 42, 4.8, 'Отличная доставка!');
SELECT delete_order_review('cus2', '111', 42);
-- Просмотр delivery_lisT
SELECT * FROM view_delivery_list();
SELECT * FROM view_delivery_list2('cus5', '111');
---Время доставки
SELECT calculate_time_difference('cus5', '111');
---Уведомления 
SELECT * FROM get_customer_notifications('cus5', '111');
---
SELECT * from view_delivery_coverage();









