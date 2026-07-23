#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-}"

# Config

MINIKUBE_PROFILE="minikube"
K8S_VERSION="v1.28.2"
DRIVER="docker"
CPUS=10
MEMORY=12280
DISK_SIZE="20g"
ADDONS=("metrics-server")

# Colores en ANSI

GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
RESET="\033[0m"

# Logging

log_info() { echo -e "${BLUE}[INFO]${RESET} $*"; }
log_success() { echo -e "${GREEN}[OK]${RESET}   $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
log_error() { echo -e "${RED}[ERR]${RESET}  $*"; }

usage() {
	log_error "Uso: $0 {create|destroy}"
	exit 1
}

mount_bpf() {
	log_info "Configurando sistema de archivos BPF para OBI..."

	# Intentamos montar. Si falla (porque ya está montado), no rompemos el script (|| true)
	if minikube ssh --profile "${MINIKUBE_PROFILE}" -- "sudo mount -t bpf bpf /sys/fs/bpf" 2>/dev/null; then
		log_success "BPF montado exitosamente en /sys/fs/bpf"
	else
		# Verificamos si ya estaba montado para no alarmar
		if minikube ssh --profile "${MINIKUBE_PROFILE}" -- "mount | grep -q '/sys/fs/bpf type bpf'"; then
			log_info "El sistema de archivos BPF ya estaba montado."
		else
			log_warn "No se pudo montar BPF automáticamente. Revisa manualmente con 'minikube ssh'."
		fi
	fi
}

# Acciones

create_cluster() {
	log_info "Creando cluster Minikube"
	log_info "Profile: ${MINIKUBE_PROFILE}"
	log_info "Kubernetes: ${K8S_VERSION}"
	log_info "Driver: ${DRIVER}"

	minikube start \
		--profile="${MINIKUBE_PROFILE}" \
		--driver="${DRIVER}" \
		--cpus="${CPUS}" \
		--memory="${MEMORY}" \
		--disk-size="${DISK_SIZE}" \
		--kubernetes-version="${K8S_VERSION}"

	for addon in "${ADDONS[@]}"; do
		log_info "Habilitando addon: ${addon}"
		minikube addons enable "${addon}" --profile="${MINIKUBE_PROFILE}"
	done

	# Paso extra para OBI/eBPF
	mount_bpf

	log_success "Cluster creado y configurado correctamente"

	log_info "Versiones:"
	kubectl version --client
}

destroy_cluster() {
	log_warn "Eliminando cluster Minikube (${MINIKUBE_PROFILE})"
	minikube delete --profile="${MINIKUBE_PROFILE}"
	log_success "Cluster eliminado"
}

# Main

case "${ACTION}" in
create)
	create_cluster
	;;
destroy)
	destroy_cluster
	;;
*)
	usage
	;;
esac
