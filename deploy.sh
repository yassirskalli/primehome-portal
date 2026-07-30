#!/bin/bash
# =============================================================================
# Prime Home Portail — Script de déploiement production (stack unifiée)
# Usage :
#   ./deploy.sh erp        → rebuild + push ERP (api + frontend)
#   ./deploy.sh sav        → rebuild + push SAV (backend + frontend)
#   ./deploy.sh devis      → rebuild + push Devis (backend + frontend)
#   ./deploy.sh all        → rebuild + push toutes les images
#   ./deploy.sh restart    → redémarrage sans rebuild (pull dernières images)
# =============================================================================

set -euo pipefail

REGISTRY="ghcr.io/yassirskalli"
COMPOSE_FILE="docker-compose.prod.yml"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[deploy]${NC} $1"; }
warn() { echo -e "${YELLOW}[warn]${NC}   $1"; }
fail() { echo -e "${RED}[error]${NC}  $1"; exit 1; }

# ── Vérifications ─────────────────────────────────────────────────────────────

[ -f ".env" ]              || fail ".env introuvable — copier .env.example et renseigner les valeurs"
[ -f "$COMPOSE_FILE" ]     || fail "$COMPOSE_FILE introuvable"
command -v docker &>/dev/null || fail "Docker non installé"

TARGET="${1:-all}"
[[ "$TARGET" =~ ^(erp|sav|devis|all|restart)$ ]] || \
    fail "Usage: ./deploy.sh [erp|sav|devis|all|restart]"

# ── Commit automatique si des changements non commités existent ───────────────

if [[ "$TARGET" != "restart" ]]; then
    if ! git diff --quiet || ! git diff --cached --quiet; then
        warn "Changements non commités détectés."
        read -rp "Message de commit (entrée = 'fix: patch prod'): " MSG
        MSG="${MSG:-fix: patch prod}"
        git add -A
        git commit -m "$MSG"
        log "Commit créé : $MSG"
    fi

    GIT_SHA=$(git rev-parse --short HEAD)
    log "SHA commit : $GIT_SHA"

    log "Push git..."
    git push origin main
fi

# ── Fonctions build ───────────────────────────────────────────────────────────

build_erp() {
    log "Build ERP API..."
    docker build -t "$REGISTRY/primehome-erp-api:latest" \
                 -t "$REGISTRY/primehome-erp-api:$GIT_SHA" \
                 ../miele_erp/app
    docker push "$REGISTRY/primehome-erp-api:latest"
    docker push "$REGISTRY/primehome-erp-api:$GIT_SHA"

    log "Build ERP Frontend..."
    docker build -t "$REGISTRY/primehome-erp-frontend:latest" \
                 -t "$REGISTRY/primehome-erp-frontend:$GIT_SHA" \
                 ../miele_erp/frontend
    docker push "$REGISTRY/primehome-erp-frontend:latest"
    docker push "$REGISTRY/primehome-erp-frontend:$GIT_SHA"
}

build_sav() {
    log "Build SAV Backend..."
    docker build -t "$REGISTRY/primehome-sav-backend:latest" \
                 -t "$REGISTRY/primehome-sav-backend:$GIT_SHA" \
                 ../sav/miele-sav/backend
    docker push "$REGISTRY/primehome-sav-backend:latest"
    docker push "$REGISTRY/primehome-sav-backend:$GIT_SHA"

    log "Build SAV Frontend..."
    docker build -t "$REGISTRY/primehome-sav-frontend:latest" \
                 -t "$REGISTRY/primehome-sav-frontend:$GIT_SHA" \
                 ../sav/miele-sav/frontend
    docker push "$REGISTRY/primehome-sav-frontend:latest"
    docker push "$REGISTRY/primehome-sav-frontend:$GIT_SHA"
}

build_devis() {
    log "Build Devis Backend..."
    docker build -t "$REGISTRY/primehome-devis-backend:latest" \
                 -t "$REGISTRY/primehome-devis-backend:$GIT_SHA" \
                 ../devis_miele/backend
    docker push "$REGISTRY/primehome-devis-backend:latest"
    docker push "$REGISTRY/primehome-devis-backend:$GIT_SHA"

    log "Build Devis Frontend..."
    docker build -t "$REGISTRY/primehome-devis-frontend:latest" \
                 -t "$REGISTRY/primehome-devis-frontend:$GIT_SHA" \
                 ../devis_miele/frontend
    docker push "$REGISTRY/primehome-devis-frontend:latest"
    docker push "$REGISTRY/primehome-devis-frontend:$GIT_SHA"
}

# ── Build ─────────────────────────────────────────────────────────────────────

case "$TARGET" in
    erp)     build_erp ;;
    sav)     build_sav ;;
    devis)   build_devis ;;
    all)     build_erp; build_sav; build_devis ;;
    restart) log "Mode restart — pas de rebuild." ;;
esac

# ── Redémarrage ───────────────────────────────────────────────────────────────

log "Pull + redémarrage..."
case "$TARGET" in
    erp)
        docker compose -f "$COMPOSE_FILE" pull erp_api erp_frontend
        docker compose -f "$COMPOSE_FILE" up -d --no-deps erp_api erp_frontend
        ;;
    sav)
        docker compose -f "$COMPOSE_FILE" pull sav_backend sav_frontend
        docker compose -f "$COMPOSE_FILE" up -d --no-deps sav_backend sav_frontend
        ;;
    devis)
        docker compose -f "$COMPOSE_FILE" pull devis_backend devis_frontend
        docker compose -f "$COMPOSE_FILE" up -d --no-deps devis_backend devis_frontend
        ;;
    all|restart)
        docker compose -f "$COMPOSE_FILE" pull
        docker compose -f "$COMPOSE_FILE" up -d
        ;;
esac

# ── Vérification santé ────────────────────────────────────────────────────────

log "Vérification santé..."
sleep 8
curl -sf http://localhost/ > /dev/null 2>&1 && log "✅ Portail OK" || warn "⚠️  Portail ne répond pas encore"
curl -sf http://localhost/commandes/api/health > /dev/null 2>&1 && log "✅ ERP API OK" || warn "⚠️  ERP API ne répond pas encore"

if [[ "$TARGET" != "restart" ]]; then
    log "✅ Déploiement terminé — sha: $GIT_SHA"
else
    log "✅ Redémarrage terminé"
fi
