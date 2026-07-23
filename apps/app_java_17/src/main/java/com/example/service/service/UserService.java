package com.example.service.service;

import com.example.service.entity.User;
import com.example.service.repository.UserRepository;
import com.example.service.util.TransactionLogger;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;

import java.util.HashMap;
import java.util.Map;
import java.util.Random;

@Service
public class UserService {

    @Autowired
    private UserRepository userRepository;

    private final TransactionLogger logger;
    private final Random random;

    public UserService() {
        this.logger = new TransactionLogger();
        this.random = new Random();
    }

    public ResponseEntity<Map<String, Object>> getUser(Long id) {
        String endpoint = "/api/users/" + id;
        long startTime = System.currentTimeMillis();
        int statusCode = 200;

        try {
            // Error aleatorio (15% de probabilidad)
            if (random.nextInt(100) < 15) {
                throw new RuntimeException("Simulated database connection error");
            }

            User user = userRepository.findById(id)
                    .orElseThrow(() -> new RuntimeException("User not found"));

            long latency = System.currentTimeMillis() - startTime;
            logger.log(endpoint, startTime, latency, statusCode);

            Map<String, Object> response = new HashMap<>();
            response.put("id", user.getId());
            response.put("name", user.getName());
            response.put("email", user.getEmail());
            response.put("createdAt", user.getCreatedAt().toString());
            response.put("backend", "java17");

            return ResponseEntity.ok(response);

        } catch (RuntimeException e) {
            statusCode = e.getMessage().contains("not found") ? 404 : 500;
            long latency = System.currentTimeMillis() - startTime;
            logger.log(endpoint, startTime, latency, statusCode);

            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("error", e.getMessage());
            errorResponse.put("backend", "java17");

            return ResponseEntity.status(statusCode).body(errorResponse);
        }
    }

    public ResponseEntity<Map<String, Object>> createUser(Map<String, Object> userData) {
        String endpoint = "/api/users";
        long startTime = System.currentTimeMillis();
        int statusCode = 201;

        try {
            // Error aleatorio (10% de probabilidad)
            if (random.nextInt(100) < 10) {
                throw new RuntimeException("Database write error");
            }

            String name = (String) userData.get("name");
            String email = (String) userData.get("email");

            if (name == null || email == null) {
                throw new IllegalArgumentException("Name and email are required");
            }

            User user = new User(name, email);
            user = userRepository.save(user);

            long latency = System.currentTimeMillis() - startTime;
            logger.log(endpoint, startTime, latency, statusCode);

            Map<String, Object> response = new HashMap<>();
            response.put("id", user.getId());
            response.put("name", user.getName());
            response.put("email", user.getEmail());
            response.put("createdAt", user.getCreatedAt().toString());
            response.put("backend", "java17");
            response.put("message", "User created successfully");

            return ResponseEntity.status(HttpStatus.CREATED).body(response);

        } catch (IllegalArgumentException e) {
            statusCode = 400;
            long latency = System.currentTimeMillis() - startTime;
            logger.log(endpoint, startTime, latency, statusCode);

            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("error", e.getMessage());
            errorResponse.put("backend", "java17");

            return ResponseEntity.status(statusCode).body(errorResponse);

        } catch (Exception e) {
            statusCode = 500;
            long latency = System.currentTimeMillis() - startTime;
            logger.log(endpoint, startTime, latency, statusCode);

            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("error", "Internal server error: " + e.getMessage());
            errorResponse.put("backend", "java17");

            return ResponseEntity.status(statusCode).body(errorResponse);
        }
    }
}
