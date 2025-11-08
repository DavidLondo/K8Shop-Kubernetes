\set ON_ERROR_STOP on

WITH upserted AS (
  INSERT INTO catalog.products (id, sku, title, description, price, image_url, tags)
  VALUES
    (gen_random_uuid(), 'BOOK-001', 'The Pragmatic Programmer', 'Timeless tips for software craftsmen by Hunt & Thomas', 44.95, 'https://covers.openlibrary.org/b/isbn/9780135957059-L.jpg', ARRAY['programming','best-seller']),
    (gen_random_uuid(), 'BOOK-002', 'Clean Architecture', 'Robert C. Martin on crafting resilient software systems', 38.50, 'https://covers.openlibrary.org/b/isbn/9780134494166-L.jpg', ARRAY['architecture','programming']),
    (gen_random_uuid(), 'BOOK-003', 'Designing Data-Intensive Applications', 'Martin Kleppmann dives into modern data systems', 56.00, 'https://covers.openlibrary.org/b/isbn/9781449373320-L.jpg', ARRAY['data','distributed-systems']),
    (gen_random_uuid(), 'BOOK-004', 'Deep Work', 'Cal Newport explores strategies for focused success', 24.00, 'https://covers.openlibrary.org/b/isbn/9781455586691-L.jpg', ARRAY['productivity','focus']),
    (gen_random_uuid(), 'BOOK-005', 'Atomic Habits', 'James Clear on building better habits every day', 21.00, 'https://covers.openlibrary.org/b/isbn/9780735211292-L.jpg', ARRAY['self-improvement','habits']),
    (gen_random_uuid(), 'BOOK-006', 'The Phoenix Project', 'A novel about IT, DevOps, and helping your business win', 29.99, 'https://covers.openlibrary.org/b/isbn/9781942788294-L.jpg', ARRAY['devops','novel'])
  ON CONFLICT (sku) DO UPDATE
    SET title = EXCLUDED.title,
        description = EXCLUDED.description,
        price = EXCLUDED.price,
        image_url = EXCLUDED.image_url,
        tags = EXCLUDED.tags,
        updated_at = now()
  RETURNING id, sku
)
INSERT INTO catalog.product_inventory (product_id, available)
SELECT id, CASE sku
  WHEN 'BOOK-001' THEN 45
  WHEN 'BOOK-002' THEN 32
  WHEN 'BOOK-003' THEN 27
  WHEN 'BOOK-004' THEN 60
  WHEN 'BOOK-005' THEN 80
  ELSE 22
END
FROM upserted
ON CONFLICT (product_id) DO UPDATE
  SET available = EXCLUDED.available,
      updated_at = now();
