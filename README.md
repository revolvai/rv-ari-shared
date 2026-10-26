# rv-ari-shared
## Repository structure
```
├── ari-zks                                 # Zero knowledge Services — déploiement dual instances (private / public)
│   ├── scripts
│   │   └── deploy-azure-dual-instances.sh  # Déploiement Azure via Azure CLI
│   └── terraform
│       ├── azure                           # App Service + Azure Files
│       ├── gcp                             # Cloud Run + GCS + Artifact Registry
│       └── aws                             # Lightsail + Docker + Caddy
```

Voir [ari-zks/README.md](ari-zks/README.md) pour l'architecture, les coûts et la procédure de déploiement par cloud.
