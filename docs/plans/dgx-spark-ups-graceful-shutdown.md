# DGX Spark UPS Graceful Shutdown Implementation Plan

## Goal

Connect the Goldenmate 1000VA UPS to the DGX Spark over USB so that,
on power loss, the Spark stops its services cleanly and powers off based on remaining
battery, before the UPS cuts out.

## Context

- **Hardware:** GOLDENMATE 1000VA/800W Lithium UPS, sine wave, LiFePO4 (230Wh),
  "Updated Pro Ver. with USB Communication Port", 8 outlets, LCD. Amazon ASIN
  `B0DZ2L9HN4`, ordered 2026-05-26.
- **Host:** DGX Spark, aarch64, Ubuntu 24.04.4 (DGX OS), kernel 6.17.0-1029-nvidia.
- **Software:** Network UPS Tools (NUT). `apt-cache` on the Spark offers `nut-server`
  2.8.1-3.1ubuntu2; nothing is installed yet.
- **Current state (checked 2026-09-25):** UPS now cabled and enumerates as
  `06da:ffff` (Phoenixtec "Smart-Battery", USB HID). NUT is not installed yet.
- **Source:** the initial setup outline came from an AI-generated summary
  (unverified claim). Treat it as a hypothesis. Known gaps in it: it omits
  `upsd.conf`, `upsd.users`, and `upsmon.conf` (`MONITOR` line), without which
  `upsmon` does nothing; it asserts `usbhid-ups` compatibility without a
  VID:PID check; and it relies only on the UPS firmware's `LB` flag, which is not
  a user-chosen battery threshold.

## Tasks

### Phase 0: verify premises

- [x] Verify premise: cable UPS to Spark, run `lsusb`, record the UPS VID:PID (2026-09-25: `06da:ffff` Phoenixtec "Smart-Battery", HID class, iSerial ends `M251`, manufacturer string `-BMS-`)
- [x] Confirm Spark USB-C port: power-input port is clearly marked; the other 3 USB-C ports are open and any works (UPS confirmed enumerating over USB 2.0 HID on the port in use)
- [x] Check the VID:PID against NUT: `06da:ffff` is listed in the packaged `62-nut-usbups.rules` (nut-server 2.8.1-3.1ubuntu2) as "PROTECT B / NAS - usbhid-ups", so `usbhid-ups` is the right driver. Still confirm live with `nut-scanner -U` after install
- [ ] Confirm Spark power draw under load vs. UPS 800W / 230Wh limit; estimate runtime at idle and at full GPU load

### Phase 1: NUT install and driver

- [x] `sudo apt install nut nut-client nut-server`
- [x] Run `sudo nut-scanner -U` to detect the UPS (skipped: nut-scanner lacks libusb here; driver match came from the udev rules and the live driver start confirmed it)
- [x] Add `[goldenmate]` block to `/etc/nut/ups.conf` (`driver = usbhid-ups`, `port = auto`; add vendorid/productid or `pollonly`/override options if the generic driver needs them) (pinned `vendorid = 06da`, `productid = ffff`; applied via `scripts/ups-nut-setup.zsh`)
- [x] Set `MODE=standalone` in `/etc/nut/nut.conf`
- [x] Ensure udev rule grants the `nut` user access to the USB device; replug and confirm
- [x] Start `nut-driver@goldenmate` and `nut-server`; confirm `upsc goldenmate` returns `battery.charge`, `battery.runtime`, `ups.status` (2026-09-25: `battery.charge` 100, `battery.runtime` 9720-11400 s and drifting, `ups.status` OL)

### Phase 2: monitoring config

- [x] Add a local monitor user in `/etc/nut/upsd.users` (with `upsmon primary`)
- [x] Ensure `/etc/nut/upsd.conf` listens on `127.0.0.1` only
- [x] Add `MONITOR goldenmate@localhost 1 <user> <password> primary` to `/etc/nut/upsmon.conf`
- [x] Set `SHUTDOWNCMD`, `NOTIFYCMD`, and `NOTIFYFLAG` entries for `ONBATT` and `ONLINE` (applied 2026-09-25 via `scripts/ups-shutdown-install.zsh`; `nut-monitor` restarted cleanly; `LOWBATT` already forces shutdown natively via upsmon)
- [x] Store the password out of the repo (file mode 0640, root:nut); do not commit it (random password, `/etc/nut` files root:nut 0640)
- [x] Enable and start `nut-monitor`

### Phase 3: battery-based shutdown policy

- [x] Decide thresholds: shut down at `battery.charge` <= 40% (default, tunable in `/etc/nut/ups-shutdown.env`); revisit after the pull-the-plug test
- [x] Check writable thresholds: `upsrw goldenmate` exposes only `ups.delay.shutdown`/`ups.delay.start`; no `battery.charge.low`/`battery.runtime.low`, and no `ups.load`. Thresholds must be implemented in our own logic (`upssched` or a polling script)
- [x] Write `scripts/ups-graceful-shutdown.zsh` (stops all Docker containers with a 30 s timeout, syncs, then `shutdown -h now`; `DRY_RUN=1` supported and dry-run verified 2026-09-25)
- [x] Install and wire (done 2026-09-25): run `sudo zsh scripts/ups-shutdown-install.zsh` (sets `SHUTDOWNCMD`, `NOTIFYCMD`/`NOTIFYFLAG`; `ups-notify` starts `ups-battery-watch.service` on ONBATT, which polls charge and calls `upsmon -c fsd` at the threshold)

### Phase 4: test

- [x] Smoke test watcher on mains (2026-09-25): first run failed on zsh read-only `status` variable; fixed (`ups_status`), reinstalled, journal shows "on battery; watching" then "back on mains (status=OL); stopping watch"
- [ ] Dry run: invoke the shutdown script with power connected and confirm services stop cleanly
- [ ] Simulate with `upsmon -c fsd` only after confirming nothing critical is running
- [ ] Pull-the-plug test (record results in the baseline section of `docs/process/dgx-spark-ups-setup.md`) with a light workload; log battery charge/runtime vs. time
- [ ] Confirm the Spark powers back on / recovers after mains returns (BIOS/UPS auto-restart behavior)

### Phase 5: docs and alerting

- [x] Write `docs/process/dgx-spark-ups-setup.md` (prerequisites, steps, troubleshooting) and link it from `docs/index.md`
- [ ] Optional: email/Slack alert on `ONBATT` and `LOWBATT`

## Notes

- Observed 2026-09-25: driver `usbhid-ups` (Phoenixtec/Liebert HID 0.41) works, but
  `battery.runtime` is a firmware estimate that drifted 9720 -> 11400 s while idle on
  mains. Base the policy primarily on `battery.charge`, and validate against the
  pull-the-plug test rather than trusting the runtime figure.
- Only these commands are exposed: `load.off`, `load.off.delay`, `load.on`, `load.on.delay`,
  `driver.killpower` (gated by `driver.flag.allow_killpower`, currently 0). Cutting UPS
  output after the OS halts is optional and not enabled.

- Do not rely on the UPS `LB` flag alone; firmware thresholds on consumer units are
  often set very late for a 230Wh battery. Measure actual shutdown time on the Spark.
- LiFePO4 units can cut off abruptly at low state of charge; leave generous margin.
- Only the Spark (and its network gear, if desired) should be on battery outlets;
  keep other loads off to preserve runtime.
