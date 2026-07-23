package com.example.service.service;

import com.example.service.entity.Order;
import com.example.service.repository.OrderRepository;
import com.example.service.util.TransactionLogger;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.stream.Collectors;

@Service
public class OrderService {

    @Autowired
    private OrderRepository orderRepository;

    private final TransactionLogger logger;
    private final Random random;

    public OrderService() {
        this.logger = new TransactionLogger();
        this.random = new Random();
    }

    public ResponseEntity<Map<String, Object>> getOrdersByUser(Long userId) {
        String endpoint = "/api/orders/" + userId;
        long startTime = System.currentTimeMillis();
        int statusCode = 200;

        try {
            // Error aleatorio (12% de probabilidad)
            if (random.nextInt(100) < 12) {
                throw new RuntimeException("Query timeout");
            }

            List<Order> orders = orderRepository.findByUserId(userId);

            long latency = System.currentTimeMillis() - startTime;
            logger.log(endpoint, startTime, latency, statusCode);

            List<Map<String, Object>> ordersList = orders.stream()
                    .map(order -> {
                        Map<String, Object> orderMap = new HashMap<>();
                        orderMap.put("id", order.getId());
                        orderMap.put("userId", order.getUserId());
                        orderMap.put("product", order.getProduct());
                        orderMap.put("amount", order.getAmount());
                        orderMap.put("status", order.getStatus());
                        orderMap.put("createdAt", order.getCreatedAt().toString());
                        return orderMap;
                    })
                    .collect(Collectors.toList());

            Map<String, Object> response = new HashMap<>();
            response.put("userId", userId);
            response.put("orders", ordersList);
            response.put("count", ordersList.size());
            response.put("backend", "java17");

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            statusCode = 500;
            long latency = System.currentTimeMillis() - startTime;
            logger.log(endpoint, startTime, latency, statusCode);

            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("error", e.getMessage());
            errorResponse.put("backend", "java17");

            return ResponseEntity.status(statusCode).body(errorResponse);
        }
    }
}
