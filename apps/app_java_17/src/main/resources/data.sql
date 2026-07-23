INSERT INTO users (name, email, created_at) VALUES 
('John Doe', 'john@example.com', NOW()),
('Jane Smith', 'jane@example.com', NOW()),
('Bob Johnson', 'bob@example.com', NOW())
ON CONFLICT DO NOTHING;

INSERT INTO orders (user_id, product, amount, status, created_at) VALUES 
(1, 'Laptop', 999.99, 'completed', NOW()),
(1, 'Mouse', 29.99, 'pending', NOW()),
(2, 'Keyboard', 79.99, 'completed', NOW()),
(3, 'Monitor', 299.99, 'shipped', NOW())
ON CONFLICT DO NOTHING;
