# Goldenmate UPS + DGX Spark

Graceful shutdown of an NVIDIA DGX Spark when a Goldenmate 1000VA lithium UPS runs low on battery.
The UPS talks to the Spark over USB (HID), [Network UPS Tools](https://networkupstools.org/) (NUT)
reads it, and a small watcher stops all Docker containers and powers the machine off at a
battery-charge threshold (default 40%).

## Hardware and software

- Goldenmate 1000VA/800W lithium UPS (LiFePO4, 230Wh, USB communication port)
- NVIDIA DGX Spark, Ubuntu 24.04 (DGX OS), aarch64
- NUT 2.8.1 with the `usbhid-ups` driver (USB ID `06da:ffff`)

## How it works

1. `upsmon` (NUT) runs `ups-notify` when the UPS goes on battery or returns to mains.
2. On battery, `ups-battery-watch.service` polls `battery.charge` every 10 seconds.
3. At or below the threshold it runs `upsmon -c fsd`, and `upsmon` runs `ups-graceful-shutdown`.
4. `ups-graceful-shutdown` stops all Docker containers (30 s timeout), syncs, and runs `shutdown -h now`.

The UPS does not expose load or writable low-battery thresholds, so the policy uses
`battery.charge` rather than the drifting `battery.runtime` estimate.

## Quick start

Requires `sudo` on the Spark, with the UPS cabled to an open USB-C port (not the power-input port).

```zsh
sudo apt install nut nut-client nut-server
sudo zsh scripts/ups-nut-setup.zsh
sudo zsh scripts/ups-shutdown-install.zsh
upsc goldenmate
```

Change the threshold in `/etc/nut/ups-shutdown.env` (`THRESHOLD=40`). Set `DRY_RUN=1` to run
`ups-graceful-shutdown` without acting.

## Layout

| Path | Purpose |
|---|---|
| `scripts/ups-nut-setup.zsh` | Configure NUT (standalone, `usbhid-ups`, localhost only, local monitor user) |
| `scripts/ups-shutdown-install.zsh` | Install the shutdown hooks and systemd watcher unit |
| `scripts/ups-battery-watch.zsh` | Poll charge on battery, force shutdown at the threshold |
| `scripts/ups-graceful-shutdown.zsh` | Stop Docker containers, sync, power off |
| `scripts/ups-notify.zsh` | `upsmon` NOTIFYCMD hook |
| `scripts/spark-power-log.zsh` | User service that logs GPU watts, CPU, and UPS state every 10 s (see `docs/process/spark-power-sampler.md`) |
| `docs/process/dgx-spark-ups-setup.md` | Setup guide, baseline readings, troubleshooting |
| `docs/plans/dgx-spark-ups-graceful-shutdown.md` | Implementation plan and status |

See [docs/index.md](docs/index.md) for the full documentation set.

## Status

Setup, hooks, and a mains smoke test are done. The pull-the-plug test and the check that the
Spark powers back on after an outage are still open; see the
[plan](docs/plans/dgx-spark-ups-graceful-shutdown.md).

The scripts stop every running Docker container and power off the host. Review them before
installing, and test at a quiet moment.
