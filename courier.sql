SET ROLE courier;
---Посмотреть список курьеров
SELECT * FROM view_courier_info();
---Обновить статус или тип доставки
CALL update_courier_info('cur3', '111', 'свободен', 'car', '+3754488845');
---Просмотр заказов
SELECT * FROM view_orders();
SELECT * FROM calculate_distances('cur3', '111');
---Просмотр информации о покупателе и заказе
SELECT * FROM order_customer_info WHERE order_id = 54; 
---Заполнение delivery_list
SELECT * FROM view_delivery_list();
CALL create_delivery('cur5', '111', 54, 'cash', '2024-05-23 19:32:11.804936+03', 'Francisko0');
---'В обработке', 'Обработан', 'Принят в доставку', 'Доставлен', 'Отменен'
CALL update_delivery('cur5', '111', 54, 'Принят в доставку', 'Yakuba Kolass');






