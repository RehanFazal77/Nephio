## 🚨 Important System Parameter Check  

During deployment, the **Nephio WebUI pod** may go into **CrashLoopBackOff** if Linux inotify limits are too low.  

### 🔎 Why these parameters are necessary
- Nephio WebUI (and many modern web-based Kubernetes controllers) use **file watchers** heavily (to detect configuration changes, reload settings, watch logs, etc.).  
- Linux controls the number of file watchers and inotify instances using these sysctl parameters:  
  - `fs.inotify.max_user_watches`: Maximum number of files that a single user can watch simultaneously.  
  - `fs.inotify.max_user_instances`: Maximum number of inotify instances (file watching sessions) per user.  
- If these limits are too low, the WebUI cannot start properly, fails to allocate watchers, and the pod enters **CrashLoopBackOff**, halting the deployment process.  

---

### ✅ How to check current values
Run the following commands:  

```bash
cat /proc/sys/fs/inotify/max_user_watches
cat /proc/sys/fs/inotify/max_user_instances
Typical default values on many Linux distributions are 8192 for max_user_watches and 128 for max_user_instances
These defaults are too low for Nephio WebUI, which requires much higher limits.

```
### ⚙️ How to set the correct value
To set the recommended values persistently:
```bash
echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.conf
echo "fs.inotify.max_user_instances=512" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```
    This increases the limits high enough for the WebUI and other Kubernetes workloads that rely on file watchers.
    The changes take effect immediately and also persist across reboots.

### ⚠️ Will this cause issues in the system?
- No, it is safe to increase these values.
- The only trade-off is slightly higher kernel memory usage since more file watchers can be created. Each inotify watch consumes a small amount of memory (a few hundred bytes).
- On modern machines, even with hundreds of thousands of watches, the memory usage is negligible compared to available system RAM.
- These higher values are commonly recommended by Kubernetes, Docker Desktop, and tools like VSCode, so they’re a well-established safe practice.

### ✅ In short:
    These parameters must be checked and set before Nephio deployment.
    Without them, the Nephio WebUI pod will fail and halt the deployment.
    Increasing them is safe and ensures a smooth setup.