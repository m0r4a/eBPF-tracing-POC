package com.example.service.util;

import java.text.SimpleDateFormat;
import java.util.Date;

public class TransactionLogger {
    
    private static final SimpleDateFormat DATE_FORMAT = new SimpleDateFormat("yyyy-MM-dd");
    private static final SimpleDateFormat TIME_FORMAT = new SimpleDateFormat("HH:mm:ss.SSS");

    public void log(String endpoint, long startTimeMillis, long latencyMs, int statusCode) {
        Date startDate = new Date(startTimeMillis);
        Date endDate = new Date(startTimeMillis + latencyMs);

        String logEntry = String.format("%s|%s|%s|%d|%s|%d",
            DATE_FORMAT.format(startDate),
            TIME_FORMAT.format(startDate),
            TIME_FORMAT.format(endDate),
            latencyMs,
            endpoint,
            statusCode
        );

        System.out.println(logEntry);
    }
}
