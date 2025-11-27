# Locust Load Generator for K8Shop
FROM python:3.11-slim

WORKDIR /locust

# Install locust and dependencies
RUN pip install --no-cache-dir \
    locust==2.42.5 \
    "requests>=2.32.2,<2.32.5"

# Copy locustfile
COPY locustfile.py .

# Expose ports for Locust web UI and communication
EXPOSE 8089 5557

# Set default command
# Can be overridden in Kubernetes deployment
CMD ["locust", "--host=http://catalog-service.bookstore.svc.cluster.local:8080"]
