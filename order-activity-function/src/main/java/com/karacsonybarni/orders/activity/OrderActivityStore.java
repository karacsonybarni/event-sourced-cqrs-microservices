package com.karacsonybarni.orders.activity;

import java.util.List;
import java.util.Map;

interface OrderActivityStore {

    void upsert(Map<String, Object> document);

    List<Map<String, Object>> findByOrderId(String orderId);
}
