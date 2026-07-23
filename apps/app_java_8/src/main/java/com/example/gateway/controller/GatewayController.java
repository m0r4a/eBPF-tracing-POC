package com.example.gateway.controller;

import com.example.gateway.service.BackendService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api")
public class GatewayController {

    @Autowired
    private BackendService backendService;

    @GetMapping("/users/{id}")
    public ResponseEntity<Map<String, Object>> getUser(@PathVariable String id) {
        return backendService.fetchUser(id);
    }

    @PostMapping("/users")
    public ResponseEntity<Map<String, Object>> createUser(@RequestBody Map<String, Object> userData) {
        return backendService.createUser(userData);
    }

    @GetMapping("/orders/{userId}")
    public ResponseEntity<Map<String, Object>> getOrders(@PathVariable String userId) {
        return backendService.fetchOrders(userId);
    }

    @GetMapping("/health")
    public ResponseEntity<Map<String, String>> health() {
        Map<String, String> response = new HashMap<>();
        response.put("status", "UP");
        response.put("service", "java8-gateway");
        return ResponseEntity.ok(response);
    }
}
