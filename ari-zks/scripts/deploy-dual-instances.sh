#!/bin/bash
# =============================================================================
# ARI-ZKS - Déploiement de deux Web Apps avec volume partagé
# =============================================================================
# Déploie deux Azure Web Apps (App Service) depuis un container registry
# avec un Azure File Share partagé entre les deux instances.
#
# Usage:
#   ./deploy-dual-instances.sh <container-image> [registry-username] [registry-password]
#
# Exemple:
#   ./deploy-dual-instances.sh revolv-registry.azurecr.io/ari-zks:latest
#   ./deploy-dual-instances.sh revolv-registry.azurecr.io/ari-zks:latest myuser mypassword
#
# Note: L'image doit être disponible dans le registry Revolv.
#       Utilisez scripts/revolv-build-push.sh pour build et push l'image.
# =============================================================================

set -e

# -----------------------------------------------------------------------------
# Paramètres
# -----------------------------------------------------------------------------

CONTAINER_IMAGE="${1:-}"
REGISTRY_USERNAME="${2:-}"
REGISTRY_PASSWORD="${3:-}"

if [ -z "$CONTAINER_IMAGE" ]; then
    echo "❌ Usage: $0 <container-image> [registry-username] [registry-password]"
    echo ""
    echo "Exemple:"
    echo "   $0 revolvregistry.azurecr.io/ari-zks:latest"
    echo "   $0 revolvregistry.azurecr.io/ari-zks:latest myuser mypassword"
    echo ""
    echo "Note: L'image doit être disponible dans le registry Revolv."
    echo "      Contactez Revolv pour obtenir l'accès au registry."
    exit 1
fi

# Validation du format de l'image
if [[ ! "$CONTAINER_IMAGE" =~ ^[^/]+/[^/]+ ]]; then
    echo "❌ Format d'image invalide: $CONTAINER_IMAGE"
    echo ""
    echo "Le format attendu est: <registry>/<image-name>[:tag]"
    echo ""
    echo "Exemples valides:"
    echo "   revolv-registry.azurecr.io/ari-zks:latest"
    echo "   revolv-registry.azurecr.io/ari-zks"
    echo "   myregistry.io/myapp:v1.0.0"
    echo ""
    echo "Format invalide détecté:"
    echo "   Vous avez fourni: $CONTAINER_IMAGE"
    echo "   Il manque le nom de l'image après le registry."
    echo ""
    exit 1
fi

echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║        ARI-ZKS - Déploiement Dual Web Apps + Volume Partagé           ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""

# -----------------------------------------------------------------------------
# Demander le nom de l'application
# -----------------------------------------------------------------------------

if [ -z "${APP_NAME:-}" ]; then
    read -p "Nom de l'application (Entrée pour ari-rks-{uuid4short}): " USER_APP_NAME
    if [ -z "$USER_APP_NAME" ]; then
        # Générer un UUID court (8 caractères)
        if command -v uuidgen &> /dev/null; then
            UUID_SHORT=$(uuidgen | tr -d '-' | cut -c1-8)
        else
            UUID_SHORT=$(openssl rand -hex 4)
        fi
        APP_NAME="ari-rks-${UUID_SHORT}"
        echo "   → Utilisation du nom par défaut: $APP_NAME"
    else
        APP_NAME="$USER_APP_NAME"
    fi
fi

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

RESOURCE_GROUP="${RESOURCE_GROUP:-ari-zks-rg}"
LOCATION="${LOCATION:-westeurope}"

# Noms des ressources
WEBAPP_PRIVATE_NAME="private-${APP_NAME}"
WEBAPP_PUBLIC_NAME="public-${APP_NAME}"
APP_SERVICE_PLAN="${APP_NAME}-plan"
STORAGE_ACCOUNT_NAME="${APP_NAME}storage"
FILE_SHARE_NAME="shared-data"
MOUNT_PATH="/app/data"

# Secrets
ENCRYPTION_KEY="${ENCRYPTION_KEY:-$(openssl rand -base64 32)}"
REVOLV_SHARED_SECRET="${REVOLV_SHARED_SECRET:-$(openssl rand -hex 32)}"

# -----------------------------------------------------------------------------
# Vérifications
# -----------------------------------------------------------------------------

echo "📋 Vérification des prérequis..."

if ! command -v az &> /dev/null; then
    echo "❌ Azure CLI n'est pas installé."
    exit 1
fi

if ! az account show &> /dev/null; then
    echo "❌ Vous n'êtes pas connecté à Azure. Exécutez: az login"
    exit 1
fi

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
unset AZURE_SUBSCRIPTION_ID
az account set --subscription "$SUBSCRIPTION_ID"

echo "✅ Azure CLI connecté (Subscription: $SUBSCRIPTION_ID)"

# -----------------------------------------------------------------------------
# Enregistrement des Resource Providers
# -----------------------------------------------------------------------------

echo ""
echo "📦 Vérification des resource providers..."

for provider in Microsoft.Storage Microsoft.Web Microsoft.ContainerRegistry; do
    state=$(az provider show --namespace "$provider" --query "registrationState" -o tsv 2>/dev/null || echo "NotRegistered")
    if [ "$state" != "Registered" ]; then
        echo "   Enregistrement de $provider..."
        az provider register --namespace "$provider" --wait
    fi
done

echo "✅ Resource providers OK"

# -----------------------------------------------------------------------------
# Affichage configuration
# -----------------------------------------------------------------------------

echo ""
echo "📍 Configuration:"
echo "   Container Image: $CONTAINER_IMAGE"
echo "   Resource Group: $RESOURCE_GROUP"
echo "   Location: $LOCATION"
echo "   Web App Private: $WEBAPP_PRIVATE_NAME"
echo "   Web App Public: $WEBAPP_PUBLIC_NAME"
echo "   Storage: $STORAGE_ACCOUNT_NAME"
echo ""

read -p "Continuer? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Annulé."
    exit 1
fi

# -----------------------------------------------------------------------------
# Étape 1: Resource Group
# -----------------------------------------------------------------------------

echo ""
echo "📦 Création du Resource Group..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none 2>/dev/null || true
echo "✅ Resource Group: $RESOURCE_GROUP"

# -----------------------------------------------------------------------------
# Étape 2: Storage Account + File Share
# -----------------------------------------------------------------------------

echo ""
echo "💾 Création du Storage Account..."

# Nettoyer le nom (lowercase, alphanum, 3-24 chars)
STORAGE_ACCOUNT_NAME=$(echo "$STORAGE_ACCOUNT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9' | cut -c1-24)

az storage account create \
    --name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --output none

STORAGE_KEY=$(az storage account keys list \
    --resource-group "$RESOURCE_GROUP" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --query "[0].value" -o tsv)

echo "✅ Storage Account: $STORAGE_ACCOUNT_NAME"

echo ""
echo "📁 Création du File Share..."
az storage share create \
    --name "$FILE_SHARE_NAME" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --account-key "$STORAGE_KEY" \
    --quota 5 \
    --output none

echo "✅ File Share: $FILE_SHARE_NAME"

# -----------------------------------------------------------------------------
# Étape 3: App Service Plan (Linux containers)
# -----------------------------------------------------------------------------

echo ""
echo "📋 Création de l'App Service Plan..."

az appservice plan create \
    --name "$APP_SERVICE_PLAN" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --is-linux \
    --sku B1 \
    --output none

echo "✅ App Service Plan: $APP_SERVICE_PLAN"

# -----------------------------------------------------------------------------
# Étape 4: Extraire les infos du registry
# -----------------------------------------------------------------------------

# Extraire le registry server et le nom de l'image depuis l'image complète
# Exemple: revolvregistry.azurecr.io/ari-zks:latest
#   REGISTRY_SERVER = revolvregistry.azurecr.io
#   IMAGE_NAME_ONLY = ari-zks:latest
REGISTRY_SERVER=$(echo "$CONTAINER_IMAGE" | cut -d'/' -f1)
IMAGE_NAME_ONLY=$(echo "$CONTAINER_IMAGE" | cut -d'/' -f2-)
ACR_NAME=$(echo "$REGISTRY_SERVER" | cut -d'.' -f1)

echo ""
echo "🐳 Registry détecté: $REGISTRY_SERVER (ACR: $ACR_NAME)"
echo "   Image: $IMAGE_NAME_ONLY"

# Utiliser les credentials fournis en paramètres ou essayer de les récupérer
if [ -n "$REGISTRY_USERNAME" ] && [ -n "$REGISTRY_PASSWORD" ]; then
    echo "✅ Utilisation des credentials fournis en paramètres"
    ACR_USERNAME="$REGISTRY_USERNAME"
    ACR_PASSWORD="$REGISTRY_PASSWORD"
elif [[ "$REGISTRY_SERVER" == *.azurecr.io ]]; then
    # Essayer de récupérer les credentials ACR automatiquement
    ACR_USERNAME=$(az acr credential show --name "$ACR_NAME" --query username -o tsv 2>/dev/null || echo "")
    ACR_PASSWORD=$(az acr credential show --name "$ACR_NAME" --query "passwords[0].value" -o tsv 2>/dev/null || echo "")
    
    if [ -z "$ACR_USERNAME" ] || [ -z "$ACR_PASSWORD" ]; then
        echo "⚠️  Registry externe détecté (registry Revolv)"
        echo "   Veuillez fournir les credentials du registry Revolv"
        read -p "Registry Username: " ACR_USERNAME
        read -s -p "Registry Password: " ACR_PASSWORD
        echo ""
    else
        echo "✅ Credentials ACR récupérés automatiquement"
    fi
else
    echo "⚠️  Registry non-Azure détecté"
    echo "   Veuillez fournir les credentials"
    read -p "Registry Username: " ACR_USERNAME
    read -s -p "Registry Password: " ACR_PASSWORD
    echo ""
fi

# -----------------------------------------------------------------------------
# Étape 5: Créer Web App Private
# -----------------------------------------------------------------------------

echo ""
echo "🚀 Création de Web App Private: $WEBAPP_PRIVATE_NAME..."

az webapp create \
    --name "$WEBAPP_PRIVATE_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --plan "$APP_SERVICE_PLAN" \
    --container-image-name "$IMAGE_NAME_ONLY" \
    --container-registry-url "https://$REGISTRY_SERVER" \
    --container-registry-user "$ACR_USERNAME" \
    --container-registry-password "$ACR_PASSWORD" \
    --output none

# Configuration des variables d'environnement
az webapp config appsettings set \
    --name "$WEBAPP_PRIVATE_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --settings \
        WEBSITES_PORT=8000 \
        ENV=azure \
        INSTANCE_ID=private \
        ALLOW_PRIVATE_ACCESS=true \
        ENCRYPTION_KEY="$ENCRYPTION_KEY" \
        REVOLV_SHARED_SECRET="$REVOLV_SHARED_SECRET" \
        DATABASE_URL="sqlite:////${MOUNT_PATH#/}/data.db" \
    --output none

# Monter le File Share
az webapp config storage-account add \
    --name "$WEBAPP_PRIVATE_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --custom-id "shared-storage" \
    --storage-type AzureFiles \
    --share-name "$FILE_SHARE_NAME" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --access-key "$STORAGE_KEY" \
    --mount-path "$MOUNT_PATH" \
    --output none

WEBAPP_PRIVATE_URL=$(az webapp show --name "$WEBAPP_PRIVATE_NAME" --resource-group "$RESOURCE_GROUP" --query "defaultHostName" -o tsv)
echo "✅ Web App Private: https://$WEBAPP_PRIVATE_URL"

# -----------------------------------------------------------------------------
# Étape 6: Créer Web App Public
# -----------------------------------------------------------------------------

echo ""
echo "🚀 Création de Web App Public: $WEBAPP_PUBLIC_NAME..."

az webapp create \
    --name "$WEBAPP_PUBLIC_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --plan "$APP_SERVICE_PLAN" \
    --container-image-name "$IMAGE_NAME_ONLY" \
    --container-registry-url "https://$REGISTRY_SERVER" \
    --container-registry-user "$ACR_USERNAME" \
    --container-registry-password "$ACR_PASSWORD" \
    --output none

# Configuration des variables d'environnement
az webapp config appsettings set \
    --name "$WEBAPP_PUBLIC_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --settings \
        WEBSITES_PORT=8000 \
        ENV=azure \
        INSTANCE_ID=public \
        ALLOW_PRIVATE_ACCESS=false \
        ENCRYPTION_KEY="$ENCRYPTION_KEY" \
        REVOLV_SHARED_SECRET="$REVOLV_SHARED_SECRET" \
        DATABASE_URL="sqlite:////${MOUNT_PATH#/}/data.db" \
    --output none

# Monter le File Share
az webapp config storage-account add \
    --name "$WEBAPP_PUBLIC_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --custom-id "shared-storage" \
    --storage-type AzureFiles \
    --share-name "$FILE_SHARE_NAME" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --access-key "$STORAGE_KEY" \
    --mount-path "$MOUNT_PATH" \
    --output none

WEBAPP_PUBLIC_URL=$(az webapp show --name "$WEBAPP_PUBLIC_NAME" --resource-group "$RESOURCE_GROUP" --query "defaultHostName" -o tsv)
echo "✅ Web App Public: https://$WEBAPP_PUBLIC_URL"

# -----------------------------------------------------------------------------
# Résumé
# -----------------------------------------------------------------------------

echo ""
echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║                    🎉 Déploiement Terminé!                            ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "📍 Web Apps:"
echo "   Web App Private: https://$WEBAPP_PRIVATE_URL"
echo "   Web App Public: https://$WEBAPP_PUBLIC_URL"
echo ""
echo "💾 Volume partagé:"
echo "   Storage: $STORAGE_ACCOUNT_NAME"
echo "   File Share: $FILE_SHARE_NAME"
echo "   Mount Path: $MOUNT_PATH"
echo ""
echo "🔑 Secrets:"
echo "   ENCRYPTION_KEY=$ENCRYPTION_KEY"
echo "   REVOLV_SHARED_SECRET=$REVOLV_SHARED_SECRET"
echo ""
echo "🔧 Commandes utiles:"
echo "   # Logs Web App Private:"
echo "   az webapp log tail --name $WEBAPP_PRIVATE_NAME --resource-group $RESOURCE_GROUP"
echo ""
echo "   # Logs Web App Public:"
echo "   az webapp log tail --name $WEBAPP_PUBLIC_NAME --resource-group $RESOURCE_GROUP"
echo ""
echo "   # Restart:"
echo "   az webapp restart --name $WEBAPP_PRIVATE_NAME --resource-group $RESOURCE_GROUP"
echo "   az webapp restart --name $WEBAPP_PUBLIC_NAME --resource-group $RESOURCE_GROUP"
echo ""
