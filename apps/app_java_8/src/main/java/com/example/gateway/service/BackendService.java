package com.example.gateway.service;

import com.example.gateway.util.TransactionLogger;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;

import java.util.HashMap;
import java.util.Map;
import java.util.Random;

@Service
public class BackendService {

    @Value("${backend.service.url:http://java17-service:8080}")
    private String backendUrl;

    private final RestTemplate restTemplate;
    private final TransactionLogger logger;
    private final Random random;

    public BackendService() {
        this.restTemplate = new RestTemplate();
        this.logger = new TransactionLogger();
        this.random = new Random();
    }

    public ResponseEntity<Map<String, Object>> fetchUser(String id) {
        String endpoint = "/api/users/" + id;
        return executeRequest(HttpMethod.GET, endpoint, null);
    }

    public ResponseEntity<Map<String, Object>> createUser(Map<String, Object> userData) {
        String endpoint = "/api/users";
        return executeRequest(HttpMethod.POST, endpoint, userData);
    }

    public ResponseEntity<Map<String, Object>> fetchOrders(String userId) {
        String endpoint = "/api/orders/" + userId;
        return executeRequest(HttpMethod.GET, endpoint, null);
    }

    private ResponseEntity<Map<String, Object>> executeRequest(
            HttpMethod method, 
            String endpoint, 
            Map<String, Object> body) {
        
        long startTime = System.currentTimeMillis();
        int statusCode = 200;
        String errorMessage = null;

        try {
            // Inyectar errores aleatorios (10% de probabilidad)
            if (random.nextInt(100) < 10) {
                throw new RuntimeException("Simulated random error in gateway");
            }

            String url = backendUrl + endpoint;
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);

            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(body, headers);
            
            ResponseEntity<Map> response = restTemplate.exchange(
                url, 
                method, 
                entity, 
                Map.class
            );

            statusCode = response.getStatusCodeValue();
            long latency = System.currentTimeMillis() - startTime;
            
            logger.log(endpoint, startTime, latency, statusCode);

            Map<String, Object> responseBody = new HashMap<>(response.getBody());
            responseBody.put("gateway", "java8");
            
            return ResponseEntity.status(statusCode).body(responseBody);

        } catch (HttpClientErrorException e) {
            statusCode = e.getRawStatusCode();
            errorMessage = e.getMessage();
            long latency = System.currentTimeMillis() - startTime;
            logger.log(endpoint, startTime, latency, statusCode);

            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("error", errorMessage);
            errorResponse.put("gateway", "java8");
            errorResponse.put("statusCode", statusCode);
            
            return ResponseEntity.status(statusCode).body(errorResponse);

        } catch (Exception e) {
            statusCode = 500;
            errorMessage = e.getMessage();
            long latency = System.currentTimeMillis() - startTime;
            logger.log(endpoint, startTime, latency, statusCode);

            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("error", "Gateway error: " + errorMessage);
            errorResponse.put("gateway", "java8");
            errorResponse.put("statusCode", statusCode);
            
            return ResponseEntity.status(statusCode).body(errorResponse);
        }
    }
}
