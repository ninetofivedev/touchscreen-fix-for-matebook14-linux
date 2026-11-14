# Touchscreen Fix for Huawei MateBook 14 (2025) on Linux

A small workaround for intermittent touchscreen initialization on the **Huawei MateBook 14 (2025), model FLMH-X**, using the **FTSC1000** I²C-HID touchscreen controller.

The fix reloads the `i2c_hid_acpi` kernel module after a short delay during boot. This repository includes an **interactive installer** so you do not need to create the script and systemd service manually after reinstalling Linux.

> **Compatibility:** Tested with a Matebook14 (2025), model FLMH-X with CachyOS, Linux Mint, Manjaro and Zorin OS. Other hardware models, kernel versions and distributions are not guaranteed to work. A Linux system running **systemd** is required.

## Quick start: automatic installation (recommended)

1. Clone or download this repository, then open a terminal in its directory:

   ```bash
   git clone https://github.com/ninetofivedev/touchscreen-fix-for-matebook14-linux.git
   cd touchscreen-fix-for-matebook14-linux
   ```

   If you downloaded the ZIP instead, extract it and open a terminal in the extracted folder.

2. Run the installer:

   ```bash
   sudo bash install-touchscreen-fix.sh
   ```

3. Select **`1`** to install the fix, then confirm with **`Y`** (or press Enter). The installer prints the progress and checks that the files and systemd service were created and enabled successfully.

4. **Reboot** and test the touchscreen:

   ```bash
   sudo reboot
   ```

The installer **does not reload the driver immediately**. It enables the fix for the next boot.

### Installer menu

```text
=============================================
 FTSC1000 Touchscreen Fix – MateBook 14 2025
=============================================

1) Install / reinstall touchscreen fix
2) Uninstall touchscreen fix
3) Exit

Select an option [1-3]:
```

The installer interface and its status messages are in English. Before installing or uninstalling, it asks for confirmation (`[Y/n]`). The default when pressing Enter is **Yes**; enter `n` to cancel.

### Remove the fix

Run the same installer again:

```bash
sudo bash install-touchscreen-fix.sh
```

Choose **`2`** and confirm. The installer disables `ftsc1000-touch.service`, removes the two installer-managed files, and reloads systemd. It does not delete unrelated files. If no installer-managed files are found, it reports that there is nothing to remove.

> **Existing manual installation:** If you already followed the original instructions and created the files manually, the installer will **not overwrite or remove them**. It only modifies files marked as managed by this installer. Back up and remove the manually created files first if you want to switch to the automatic method. The installer also refuses to overwrite symbolic links at either target path.

## How it works

The MateBook 14 (2025) touchscreen is connected through an internal I²C-HID controller. On some Linux boots, the controller may not be ready when the driver first initializes, leaving touchscreen input unavailable.

The workaround uses a systemd oneshot service to reload the kernel module after the standard module-loading and local filesystem startup targets:

```bash
modprobe -r i2c_hid_acpi
sleep 2
modprobe i2c_hid_acpi
sleep 2
```

These commands briefly remove and reload the **shared `i2c_hid_acpi` driver**, potentially affecting other I²C-HID input devices while the module is unloaded. They should only be used on suitable hardware.

## Verify the installation

Check whether the service is enabled for startup:

```bash
systemctl is-enabled ftsc1000-touch.service
```

Expected output after installation: `enabled`.

After reboot, check the last boot's service log:

```bash
journalctl -b -u ftsc1000-touch.service --no-pager
```

You can also inspect the service:

```bash
systemctl status ftsc1000-touch.service
```

Because the unit uses `Type=oneshot` without `RemainAfterExit=yes`, **`inactive (dead)` can be normal after a successful run**. Look for a successful exit in the journal rather than relying on the active/inactive label alone.

## Manual installation (alternative)

If you prefer to install the workaround manually, follow these steps instead of using the installer.

### 1. Create the initialization script

```bash
sudo nano /usr/local/bin/ftsc1000-touch-init.sh
```

Paste:

```bash
#!/bin/bash
modprobe -r i2c_hid_acpi
sleep 2
modprobe i2c_hid_acpi
sleep 2
```

Make it executable:

```bash
sudo chmod +x /usr/local/bin/ftsc1000-touch-init.sh
```

### 2. Create the systemd service

```bash
sudo nano /etc/systemd/system/ftsc1000-touch.service
```

Paste:

```ini
[Unit]
Description=FTSC1000 Touchscreen Init Delay Fix
After=systemd-modules-load.service
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ftsc1000-touch-init.sh
TimeoutStartSec=10

[Install]
WantedBy=multi-user.target
```

### 3. Enable the service

```bash
sudo systemctl daemon-reload
sudo systemctl enable ftsc1000-touch.service
sudo reboot
```

### Manually undo the manual installation

Only do this if these are the files you created specifically for this workaround:

```bash
sudo systemctl disable ftsc1000-touch.service
sudo rm /etc/systemd/system/ftsc1000-touch.service
sudo rm /usr/local/bin/ftsc1000-touch-init.sh
sudo systemctl daemon-reload
```

Reboot afterward if you want to test startup without the fix.

## Requirements and notes

- Linux with **systemd** running as the init system.
- Root privileges (`sudo`) to install or remove system files.
- The `modprobe` utility (usually provided by the `kmod` package).
- The `i2c_hid_acpi` driver supported by your kernel. The installer warns if `modinfo` cannot find it; this warning is not a guarantee the hardware is supported or unsupported.
- The automatic installer uses the paths `/usr/local/bin/ftsc1000-touch-init.sh` and `/etc/systemd/system/ftsc1000-touch.service`.
- The installer checks the module with `modinfo`, validates the generated Bash script and systemd unit, and verifies that the unit is enabled. It does not automatically test touchscreen input.
- Review scripts before executing them with root privileges. A successful installation does not by itself prove that the touchscreen is working; always test it after reboot.

## License

See [LICENSE](LICENSE).
