SET ROLE manager;
---Добавление курьера
CALL create_courier('Alex', 'Kuertof', '123456789', 'car', 'cur5', '111');
SELECT * FROM view_courier_info();
---Ответ на отзыв
SELECT * FROM view_reviews();
CALL add_review_answer(4, 'answer');
---Уволить курьера 
CALL delete_courier_info(17);
---Заблокировать покупателя
SELECT * FROM view_customers();
SELECT * FROM block_customer(41);
---Просмотр истории маршрутов
CALL view_delivery_route();
---Информация по доставленым заказам
CALL view_order_details();

---
SELECT * from view_delivery_coverage();
CALL update_delivery_coverage(1, 'Belarus', 'train', 8, NULL, NULL, 30, 0.15);




