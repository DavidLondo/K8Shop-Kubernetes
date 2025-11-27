import os
import random
import json
from locust import HttpUser, task, between
from locust.contrib.fasthttp import FastHttpUser


class K8ShopUser(FastHttpUser):
    """
    Simulates a user browsing the K8Shop bookstore
    Uses exponential distribution for realistic traffic patterns
    """
    
    # Distribución exponencial (wait time)
    # lambda = 1/mean, entonces lambda=1.0 significa tiempo medio de espera de 1 segundo
    # Por lo tanto, un lambda más alto = tiempos de espera más cortos (más solicitudes)
    wait_time = lambda self: random.expovariate(1.0)
    
    catalog_host = os.getenv(
        "CATALOG_SERVICE_URL", 
        "http://catalog-service.bookstore.svc.cluster.local:8080"
    )
    cart_host = os.getenv(
        "CART_SERVICE_URL",
        "http://cart-service.bookstore.svc.cluster.local:8080"
    )
    order_host = os.getenv(
        "ORDER_SERVICE_URL",
        "http://order-service.bookstore.svc.cluster.local:8080"
    )
    recommendation_host = os.getenv(
        "RECOMMENDATION_SERVICE_URL",
        "http://recommendation-service.bookstore.svc.cluster.local:8080"
    )
    
    def on_start(self):
        """Initialize user session"""
        self.user_id = f"user-{random.randint(1000, 9999)}"
        self.session_id = f"session-{random.randint(10000, 99999)}"
        
    @task(10)
    def browse_catalog(self):
        """Browse product catalog - most common action"""
        with self.client.get(
            f"{self.catalog_host}/catalog",
            catch_response=True,
            name="/catalog - browse"
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Got status code {response.status_code}")
    
    @task(5)
    def search_catalog(self):
        """Search for products"""
        search_terms = ["python", "kubernetes", "docker", "microservices", "devops"]
        term = random.choice(search_terms)
        
        with self.client.get(
            f"{self.catalog_host}/catalog?q={term}",
            catch_response=True,
            name="/catalog - search"
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Search failed: {response.status_code}")
    
    @task(3)
    def filter_by_price(self):
        """Filter products by price range"""
        max_price = random.choice([20, 30, 50, 100])
        
        with self.client.get(
            f"{self.catalog_host}/catalog?max={max_price}",
            catch_response=True,
            name="/catalog - filter"
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Filter failed: {response.status_code}")
    
    @task(7)
    def view_cart(self):
        """View shopping cart"""
        with self.client.get(
            f"{self.cart_host}/cart/{self.user_id}",
            catch_response=True,
            name="/cart - view"
        ) as response:
            if response.status_code in [200, 404]:  # 404 is OK for empty cart
                response.success()
            else:
                response.failure(f"Cart view failed: {response.status_code}")
    
    @task(4)
    def add_to_cart(self):
        """Add item to cart"""
        sku = f"SKU-{random.randint(100, 999)}"
        payload = {
            "userId": self.user_id,
            "sku": sku,
            "quantity": random.randint(1, 3)
        }
        
        with self.client.post(
            f"{self.cart_host}/cart",
            json=payload,
            catch_response=True,
            name="/cart - add"
        ) as response:
            if response.status_code in [200, 201]:
                response.success()
            else:
                response.failure(f"Add to cart failed: {response.status_code}")
    
    @task(2)
    def update_cart_item(self):
        """Update cart item quantity"""
        sku = f"SKU-{random.randint(100, 999)}"
        payload = {
            "userId": self.user_id,
            "sku": sku,
            "quantity": random.randint(1, 5)
        }
        
        with self.client.put(
            f"{self.cart_host}/cart",
            json=payload,
            catch_response=True,
            name="/cart - update"
        ) as response:
            if response.status_code in [200, 404]:
                response.success()
            else:
                response.failure(f"Update cart failed: {response.status_code}")
    
    @task(1)
    def remove_from_cart(self):
        """Remove item from cart"""
        sku = f"SKU-{random.randint(100, 999)}"
        
        with self.client.delete(
            f"{self.cart_host}/cart/{self.user_id}/{sku}",
            catch_response=True,
            name="/cart - remove"
        ) as response:
            if response.status_code in [200, 204, 404]:
                response.success()
            else:
                response.failure(f"Remove from cart failed: {response.status_code}")
    
    @task(2)
    def create_order(self):
        """Create an order"""
        items = [
            {
                "sku": f"SKU-{random.randint(100, 999)}",
                "qty": random.randint(1, 2),
                "price": round(random.uniform(10.0, 100.0), 2)
            }
            for _ in range(random.randint(1, 3))
        ]
        
        payload = {
            "userId": self.user_id,
            "items": items
        }
        
        with self.client.post(
            f"{self.order_host}/orders",
            json=payload,
            catch_response=True,
            name="/orders - create"
        ) as response:
            if response.status_code in [200, 201]:
                response.success()
            else:
                response.failure(f"Create order failed: {response.status_code}")
    
    @task(3)
    def get_recommendations(self):
        """Get product recommendations"""
        product_id = f"p-{random.randint(100, 999)}"
        strategy = random.choice(["popular", "related"])
        
        with self.client.get(
            f"{self.recommendation_host}/recommendations?productId={product_id}&strategy={strategy}&limit=5",
            catch_response=True,
            name="/recommendations - get"
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Recommendations failed: {response.status_code}")
    
    @task(1)
    def check_health(self):
        """Health check endpoints"""
        services = [
            (self.catalog_host, "catalog"),
            (self.cart_host, "cart"),
            (self.order_host, "order"),
            (self.recommendation_host, "recommendation")
        ]
        
        service_host, service_name = random.choice(services)
        
        with self.client.get(
            f"{service_host}/healthz",
            catch_response=True,
            name=f"/healthz - {service_name}"
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Health check failed: {response.status_code}")


class HighTrafficUser(K8ShopUser):
    wait_time = lambda self: random.expovariate(2.0)  # Faster requests
    

class SlowBrowserUser(K8ShopUser):
    wait_time = lambda self: random.expovariate(0.5)  # Slower requests
