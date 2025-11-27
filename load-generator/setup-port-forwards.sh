#!/usr/bin/env bash
#
# Script de ayuda para configurar port-forwards de los servicios K8Shop
# Útil para desarrollo/testing local del load-generator
#
set -euo pipefail

NAMESPACE="${NAMESPACE:-bookstore}"

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Verificar kubectl
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl no está instalado"
    exit 1
fi

log_info "Configurando port-forwards para K8Shop en namespace '$NAMESPACE'..."
echo ""

# Array de servicios y puertos locales
declare -A SERVICES=(
    ["catalog-service"]=8080
    ["cart-service"]=8081
    ["order-service"]=8082
    ["recommendation-service"]=8083
)

# Crear port-forwards en background
PIDS=()
for service in "${!SERVICES[@]}"; do
    local_port="${SERVICES[$service]}"
    
    log_info "Port-forward: $service -> localhost:$local_port"
    kubectl port-forward -n "$NAMESPACE" "svc/$service" "$local_port:8080" &
    PIDS+=($!)
done

echo ""
log_info "Port-forwards activos. Variables de entorno sugeridas:"
echo ""
echo "export CATALOG_SERVICE_URL=http://localhost:8080"
echo "export CART_SERVICE_URL=http://localhost:8081"
echo "export ORDER_SERVICE_URL=http://localhost:8082"
echo "export RECOMMENDATION_SERVICE_URL=http://localhost:8083"
echo ""
log_warn "Presiona Ctrl+C para detener todos los port-forwards"
echo ""

# Función para limpiar al salir
cleanup() {
    echo ""
    log_info "Deteniendo port-forwards..."
    for pid in "${PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    log_info "Limpieza completada"
    exit 0
}

trap cleanup SIGINT SIGTERM

# Esperar indefinidamente
wait
