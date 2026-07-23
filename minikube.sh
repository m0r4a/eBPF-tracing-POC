#!/usr/bin/env bash
#
# Creates and destroys the local cluster the POC runs on.
#
# Beyond a plain `minikube start`, this mounts the BPF filesystem inside
# the node, which the eBPF agents need in order to schedule at all.

set -euo pipefail

ACTION="${1:-}"

# Config
#
# CPUs and memory are the heaviest requirement here. Lower them if your
# machine cannot spare it; the application itself is small, but two JVMs
# plus an agent on every node adds up. On Windows and macOS these come out
# of the Docker Desktop VM, so raise its limits first or minikube will
# refuse to start.
#
# Every value can be overridden from the environment, for example:
#   CPUS=4 MEMORY=6144 ./minikube.sh create

MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-minikube}"
K8S_VERSION="${K8S_VERSION:-v1.35.1}"
# docker is the one driver available on Linux, macOS, WSL2 and Windows.
DRIVER="${MINIKUBE_DRIVER:-docker}"
CPUS="${CPUS:-10}"
MEMORY="${MEMORY:-12280}"
DISK_SIZE="${DISK_SIZE:-20g}"
ADDONS=("metrics-server")

# ANSI colours

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
	log_error "Usage: $0 {create|destroy}"
	exit 1
}

# Mounts the BPF filesystem inside the node.
#
# Beyla mounts /sys/fs/bpf with hostPath type Directory, so without this
# its DaemonSet never schedules and the only clue is a mount error that
# says nothing about eBPF. OBI uses DirectoryOrCreate and is fine either
# way.
#
# The sudo here belongs to the minikube node, not to your machine, so this
# works the same from Linux, macOS, WSL2 or Windows. Everything eBPF in
# this repo happens inside that node.
#
# Note this does not survive `minikube stop`. After restarting a stopped
# cluster, run the mount command below by hand.
mount_bpf() {
	log_info "Setting up the BPF filesystem for the eBPF agents..."

	# A failure here usually just means it is already mounted, so check
	# that before warning about it.
	if minikube ssh --profile "${MINIKUBE_PROFILE}" -- "sudo mount -t bpf bpf /sys/fs/bpf" 2>/dev/null; then
		log_success "BPF filesystem mounted at /sys/fs/bpf"
	else
		if minikube ssh --profile "${MINIKUBE_PROFILE}" -- "mount | grep -q '/sys/fs/bpf type bpf'"; then
			log_info "BPF filesystem was already mounted"
		else
			log_warn "Could not mount the BPF filesystem. Check by hand with 'minikube ssh'."
		fi
	fi
}

# Actions

create_cluster() {
	log_info "Creating Minikube cluster"
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
		log_info "Enabling addon: ${addon}"
		minikube addons enable "${addon}" --profile="${MINIKUBE_PROFILE}"
	done

	# The step that makes this different from a plain `minikube start`.
	mount_bpf

	log_success "Cluster created and configured"

	log_info "Versions:"
	kubectl version --client
}

# Deletes the whole cluster, not just the application. Use
# `k8s/deploy.sh rm` if you only want to remove the workloads.
destroy_cluster() {
	log_warn "Deleting Minikube cluster (${MINIKUBE_PROFILE})"
	minikube delete --profile="${MINIKUBE_PROFILE}"
	log_success "Cluster deleted"
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
