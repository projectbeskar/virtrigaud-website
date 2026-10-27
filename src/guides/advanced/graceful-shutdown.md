<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Graceful Shutdown

`spec.powerState: OffGraceful` asks the provider to shut the guest operating system down through the guest tools (VMware Tools, the QEMU guest agent, ACPI) instead of cutting the power. This gives the guest the chance to stop services and flush its file systems.

## Power states

| `spec.powerState` | Meaning |
|-------------------|---------|
| `On` | Power on the VM |
| `Off` | Hard power-off: no notification to the guest |
| `OffGraceful` | Guest shutdown through the guest tools, with a provider-specific fallback to a hard power-off ([below](#how-each-provider-shuts-down)) |

Quote the value in YAML (`powerState: "OffGraceful"`, `"On"`, `"Off"`): YAML 1.1, which `kubectl` uses, reads a bare `On` or `Off` as a boolean.

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VirtualMachine
metadata:
  name: my-vm
spec:
  powerState: "OffGraceful"
  # providerRef, classRef, imageRef, ...
```

The observed `status.powerState` of a VM that is down is `Off` whichever of `Off` or `OffGraceful` was requested, and a VM observed `Off` satisfies `OffGraceful`: once it is off, no graceful shutdown is sent again. `kubectl get vm` shows `Stopped` in the `PHASE` column.

## How each provider shuts down

The manager sends the graceful shutdown with a **fixed timeout of 60 seconds**. The timeout is not configurable in v0.4.1.

!!! warning "`spec.lifecycle.gracefulShutdownTimeout` and the `preStop` hook have no effect"
    The `lifecycle` block (`gracefulShutdownTimeout`, `preStop`, `postStart`) is accepted by the API but is not read by any controller or provider in v0.4.0: the shutdown timeout stays at 60 seconds and no `preStop` command runs before the shutdown. The examples that still show the block carry a note to this effect. To run something inside the guest before a shutdown, do it before you change `spec.powerState` (for example over SSH or from your own automation). See [Advanced VM lifecycle](advanced-lifecycle.md#lifecycle-hooks).

| Provider | What happens on `OffGraceful` |
|----------|-------------------------------|
| **vSphere** | The provider reads the VM's VMware Tools status. If it is not `toolsOk` or `toolsOld`, or cannot be read, it **falls back at once** to a hard power-off. Otherwise it calls `ShutdownGuest` and polls the power state every 2 seconds. If the VM has not powered off within the timeout (60 s), or `ShutdownGuest` fails, it falls back to a hard power-off |
| **libvirt** | `virsh shutdown <domain>` (the guest handles the ACPI request, through the QEMU guest agent where available). The command returns as soon as the request is sent; the provider does **not** wait for the guest or escalate when a timeout passes. It falls back to `virsh destroy` only when the `shutdown` command itself fails. A guest that ignores the request stays running |
| **Proxmox** | The PVE `shutdown` API with `timeout` set to the request's timeout (60 s) and `forceStop=1`: PVE shuts the guest down and stops it hard if it is still running after the timeout. The call returns a task, which the manager polls |

Power operations are idempotent: a stop of a VM that is already stopped is treated as success.

### A suspended VM

A VM the provider reports `Suspended` (a paused or suspended-to-RAM libvirt domain) cannot shut down gracefully. A request for `OffGraceful` is **not** turned into a hard power-off: the VM is held with `Ready=False`, reason `PowerStateUnmanaged`, and a message asking you to set `spec.powerState: Off` (hard power-off) or to resume the VM on the hypervisor, after which it is shut down gracefully.

## Requirements

- **vSphere:** VMware Tools (or open-vm-tools) installed and running in the guest.
- **libvirt:** a guest that responds to ACPI power-button events; the QEMU guest agent is recommended. The provider adds the agent channel to every domain it defines, and the cloud-init it injects by default installs `qemu-guest-agent`.
- **Proxmox:** the QEMU guest agent enabled and running in the guest for reliable shutdown, and a guest that responds to ACPI.

## Best practices

1. Install the guest tools and test that a manual `shutdown -h now` works.
2. Expect to wait up to 60 seconds on vSphere and Proxmox before the fallback hard power-off, and no fallback at all on libvirt: check a libvirt VM that stays running and use `Off` for it.
3. Check the provider logs to see which path was taken (`Gracefully shutting down`, `falling back to power off`).
4. Use `Off` when you want the power cut immediately.

## Troubleshooting

### The VM did not shut down gracefully

1. Check the guest tools:

    ```bash
    # VMware
    vmware-toolbox-cmd stat running
    # QEMU/KVM
    systemctl status qemu-guest-agent
    ```

2. Verify ACPI power-button handling in the guest, and test a manual `shutdown -h now`.
3. On vSphere, a VM whose tools are not `toolsOk`/`toolsOld` is powered off hard immediately; this is by design, so a VM without tools always loses the "graceful" part.

### A libvirt VM stays running after `OffGraceful`

The `virsh shutdown` request was accepted but the guest ignored it, and the provider does not time out. Set `spec.powerState: Off` to cut the power.

### Fallback to a hard power-off

The provider falls back to a hard power-off when: vSphere cannot confirm the tools are running, vSphere's `ShutdownGuest` fails or the 60 second timeout passes, the Proxmox shutdown timeout passes, or the libvirt `shutdown` command fails. The VM is then off, but the guest did not shut down cleanly.

## Examples

See [`graceful-shutdown-examples.yaml`](../../examples/graceful-shutdown-examples.yaml) for `OffGraceful` and `Off` VMs. The examples live in `default` and reference a Provider, VMClass and VMImage in `virtrigaud-system`, which must share themselves with `default` through `consumerNamespaceSelector`; the file's header shows how.
