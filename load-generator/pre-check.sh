#!/usr/bin/env bash
#
# Script de verificación pre-deployment para load-generator en AWS
# Verifica que el cluster esté listo antes de desplegar
#
set -euo pipefail

NAMESPACE="${NAMESPACE:-bookstore}"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

log_info() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

log_error() {
    echo -e "${RED}✗${NC} $1"
    ((ERRORS++))
}

log_step() {
    echo -e "${BLUE}==>${NC} $1"
}

# Header
echo ""
echo "=========================================="
echo "  K8Shop Load Generator Pre-Check (AWS)"
echo "=========================================="
echo ""

# 1. Verificar kubectl
log_step "1. Verificando kubectl..."
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl no está instalado"
else
    KUBECTL_VERSION=$(kubectl version --client -o json 2>/dev/null | grep -o '"gitVersion":"[^"]*"' | cut -d'"' -f4)
    log_info "kubectl instalado: $KUBECTL_VERSION"
fi

# 2. Verificar conexión al cluster
log_step "2. Verificando conexión al cluster..."
if kubectl cluster-info &> /dev/null; then
    CLUSTER_NAME=$(kubectl config current-context)
    log_info "Conectado al cluster: $CLUSTER_NAME"
else
    log_error "No se puede conectar al cluster K8s"
    echo "  Ejecuta: export KUBECONFIG=~/.kube/bookstore-config"
    exit 1
fi

# 3. Verificar namespace
log_step "3. Verificando namespace '$NAMESPACE'..."
if kubectl get namespace "$NAMESPACE" &> /dev/null; then
    log_info "Namespace '$NAMESPACE' existe"
else
    log_error "Namespace '$NAMESPACE' no existe"
    echo "  Ejecuta: kubectl create namespace $NAMESPACE"
fi

# 4. Verificar servicios
log_step "4. Verificando servicios K8Shop..."
SERVICES=("catalog-service" "cart-service" "order-service" "recommendation-service")
for service in "${SERVICES[@]}"; do
    if kubectl get svc -n "$NAMESPACE" "$service" &> /dev/null; then
        ENDPOINTS=$(kubectl get endpoints -n "$NAMESPACE" "$service" -o jsonpath='{.subsets[0].addresses}' 2>/dev/null)
        if [[ -n "$ENDPOINTS" && "$ENDPOINTS" != "null" ]]; then
            log_info "Servicio '$service' activo con endpoints"
        else
            log_warn "Servicio '$service' existe pero no tiene endpoints (pods corriendo?)"
        fi
    else
        log_warn "Servicio '$service' no encontrado"
    fi
done

# 5. Verificar NetworkPolicies
log_step "5. Verificando NetworkPolicies..."
if kubectl get networkpolicy -n "$NAMESPACE" default-deny-all &> /dev/null; then
    log_info "NetworkPolicy default-deny-all existe"
    
    # Verificar si existe la NetworkPolicy del load-generator
    if kubectl get networkpolicy -n "$NAMESPACE" load-generator-egress &> /dev/null; then
        log_info "NetworkPolicy load-generator-egress ya existe"
    else
        log_warn "NetworkPolicy load-generator-egress no existe (se aplicará durante deployment)"
    fi
else
    log_warn "NetworkPolicy default-deny-all no existe (cluster sin NetworkPolicies?)"
fi

# 6. Verificar metrics-server (para HPA)
log_step "6. Verificando metrics-server..."
if kubectl get apiservice v1beta1.metrics.k8s.io &> /dev/null; then
    if kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes &> /dev/null; then
        log_info "metrics-server funcional"
    else
        log_warn "metrics-server instalado pero no responde"
    fi
else
    log_warn "metrics-server no instalado (HPAs no funcionarán)"
    echo "  Instala: kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
fi

# 7. Verificar recursos disponibles en nodos
log_step "7. Verificando recursos en nodos EC2..."
NODES=$(kubectl get nodes -o json 2>/dev/null)
if [[ -n "$NODES" ]]; then
    NODE_COUNT=$(echo "$NODES" | jq '.items | length')
    log_info "Nodos detectados: $NODE_COUNT"
    
    # Verificar si metrics-server funciona para obtener uso de recursos
    if kubectl top nodes &> /dev/null; then
        echo ""
        kubectl top nodes | head -5
        echo ""
    else
        log_warn "No se pueden obtener métricas de nodos (metrics-server no disponible)"
    fi
else
    log_error "No se pueden listar nodos"
fi

# 8. Verificar Docker image (opcional)
log_step "8. Verificando Docker image..."
IMAGE="davidlondo/k8shop-load-generator:latest"
if command -v docker &> /dev/null; then
    if docker pull "$IMAGE" &> /dev/null 2>&1; then
        log_info "Docker image '$IMAGE' accesible"
    else
        log_warn "No se puede hacer pull de '$IMAGE' (¿necesitas hacer build/push?)"
        echo "  Ejecuta: cd load-generator && ./build.sh"
    fi
else
    log_warn "Docker no instalado (no se puede verificar la imagen)"
fi

# 9. Verificar CoreDNS
log_step "9. Verificando CoreDNS..."
if kubectl get pods -n kube-system -l k8s-app=kube-dns | grep -q Running; then
    log_info "CoreDNS corriendo"
else
    log_error "CoreDNS no está corriendo (DNS no funcionará)"
fi

# 10. Verificar si ya existe un load-generator
log_step "10. Verificando deployment existente..."
if kubectl get deployment -n "$NAMESPACE" load-generator &> /dev/null; then
    log_warn "Ya existe un deployment 'load-generator' (se actualizará en re-apply)"
else
    log_info "No hay deployment previo de load-generator"
fi

# Resumen
echo ""
echo "=========================================="
echo "  Resumen de Pre-Check"
echo "=========================================="
if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
    echo -e "${GREEN}✓ Todo listo para desplegar!${NC}"
    echo ""
    echo "Siguientes pasos:"
    echo "  1. cd load-generator"
    echo "  2. kubectl apply -f k8s/networkpolicy.yaml"
    echo "  3. kubectl apply -f k8s/load-generator-master.yaml"
    echo "  4. kubectl port-forward -n bookstore svc/load-generator 8089:8089"
    exit 0
elif [[ $ERRORS -eq 0 ]]; then
    echo -e "${YELLOW}⚠ Encontradas $WARNINGS advertencias${NC}"
    echo "  Puedes continuar, pero algunas funcionalidades podrían no funcionar."
    exit 0
else
    echo -e "${RED}✗ Encontrados $ERRORS errores y $WARNINGS advertencias${NC}"
    echo "  Corrige los errores antes de desplegar."
    exit 1
fi
