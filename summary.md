# Nephio on kubeadm Baremetal Kubernetes Cluster
(Note:  For the nephio webui pod crashloopbackoff a fix is provided in the fix.md)
## 📌 Overview
This repository contains a bash script that automates the installation of **Nephio** on a **real Kubernetes cluster provisioned with kubeadm on baremetal**.  

Unlike other test setups that use **KIND (Kubernetes in Docker)**, this script creates and configures a **real kubeadm-based cluster** on an Ubuntu host, making it closer to production infrastructure.

The script provisions:
- A **Kubernetes control plane** using kubeadm.  
- **Flannel CNI** for pod networking.  
- **Local Path Provisioner** for basic storage.  
- **Metal³ Baremetal Operator v0.11.0**, required for Nephio’s CAPM3 integration.  
- **Nephio installation** from the official GitHub repository.  

This makes it a practical environment for learning, testing, and running Nephio on a non-Kind, real cluster.

---

## ⚙️ What the Script Does
### Step-by-step Highlights
1. **System Preparation**
   - Updates and installs dependencies.  
   - Disables swap (mandatory for Kubernetes).  
   - Configures kernel modules and sysctl parameters.  

2. **Container Runtime**
   - Installs and configures **containerd** (systemd cgroup driver).  
   - Installs Docker (optional, for compatibility with Nephio test-infra scripts).  

3. **Kubernetes Installation**
   - Adds Kubernetes apt repo (v1.34).  
   - Installs kubeadm, kubelet, kubectl.  
   - Initializes the cluster with `kubeadm init`.  
   - Configures `kubectl` for the current user.  

4. **Networking & Storage**
   - Deploys **Flannel CNI**.  
   - Deploys **local-path-provisioner** and marks it as default StorageClass.  

5. **Metal³ Baremetal Operator**
   - Installs Metal³ CRDs and operator (CAPM3 support).  
   - Installs **cert-manager** for operator certificate handling.  
   - Waits until the operator is ready.  

6. **Nephio Installation**
   - Runs the official Nephio `init.sh` script from [nephio-project/test-infra](https://github.com/nephio-project/test-infra).  
   - Uses environment variables (DockerHub credentials, kubeconfig context).  
   - Installs Nephio controllers and components into the cluster.  

---

## ✅ Why This Is Important
- Provides a **reproducible way** to bring up Nephio on a real cluster instead of containerized KIND-based setups.  
- Helps understand the **infrastructure prerequisites** for Nephio:  
  - CNI & storage setup  
  - Baremetal operator (Metal³)  
  - kubeadm provisioning  
- Useful for **learning, experimentation, and CI testing**.  

---

## Current Use Case
This script is designed for:
- Testing and development of Nephio.
- Creating a reproducible baremetal environment without Kind/dockerized clusters.
- Gaining hands-on understanding of the full stack (Kubernetes + Metal³ + Nephio).
- It is not yet production-ready, but provides a strong foundation for learning and prototyping.
## ⚠️ Limitations
This script is **NOT production-ready**. Current limitations include:
- **Single-node cluster** (control-plane taint removed to schedule workloads).  
- **Basic CNI (Flannel)** — not scalable for large deployments.  
- **Local path storage** — not suitable for persistent, distributed workloads.  
- **Secrets in plain text** (DockerHub credentials in script).  
- Pulls directly from the **main branch** of Nephio — no version pinning.  
- No **HA (High Availability)** setup for control plane or etcd.  
- No **monitoring/logging/backup** configuration.  

---

## 🚀 Plan for Production-Grade Deployment
For deploying Nephio in a production-like environment, the following improvements are required:

1. **Cluster Setup**
   - Use **multi-node kubeadm HA setup** or **ClusterAPI**.  
   - Deploy **3 control plane nodes** and **multiple workers**.  
   - Add a **load balancer** in front of control plane API servers.  

2. **Networking**
   - Replacing Flannel with a production CNI such as **Calico** or **Cilium**.  
   - Enable **network policies** for security.  

3. **Storage**
   - Use **distributed storage** like Ceph, Rook, or cloud block storage.  
   - Ensure persistent volumes are HA and fault-tolerant.  

4. **Security**
   - Store DockerHub and other credentials in **Kubernetes Secrets** or HashiCorp Vault.  
   - Enable **RBAC policies** and enforce PodSecurity Standards.  
   - TLS hardening and API audit logging.  

5. **Observability**
   - Install **Prometheus + Grafana** for monitoring.  
   - Install **Loki/ELK stack** for centralized logging.  
   - Setup **alerting rules** for cluster health.  

6. **Resilience**
   - Enable **etcd snapshots** and backup strategies.  
   - Implement **disaster recovery** plans.  
   - Use Kubernetes upgrade plans with version pinning.  

7. **Nephio Installation**
   - Pin to **stable tagged releases** instead of `main`.  
   - Use GitOps (ArgoCD/Flux) for repeatable deployments.  
   - Validate with **conformance tests**.  

---

## 📖 Conclusion
This script demonstrates how to **bootstrap Nephio on a real kubeadm-based Kubernetes cluster on baremetal**.  

It is excellent for **learning, testing, and lab/demo purposes**, but not meant for production.  

For the **LFX project**, this serves as a solid foundation to:
- Exploring Nephio’s requirements on real Kubernetes clusters.  
- Documenting  the gap between **lab/demo setups** and **production-ready deployments**.  
- Planning  the migration path towards a **HA, secure, production-grade cluster** running Nephio.  

---

## 📝 Next Steps for the Project
- Finalize a **multi-node kubeadm HA cluster script**.  
- Replace Flannel with Calico/Cilium.  
- Replace local-path storage with Ceph/Rook.  
- Move credentials to Kubernetes secrets.  
- Test and document Nephio deployment on this upgraded setup.  


- Lab Mode → Single-node script (current setup).
- Production Mode → Multi-node HA setup with best practices.
---
