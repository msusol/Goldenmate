# TODO

## DGX Spark UPS graceful shutdown

Plan: [dgx-spark-ups-graceful-shutdown.md](dgx-spark-ups-graceful-shutdown.md)

- [ ] Phase 0: verify premises (cable UPS, VID:PID, port/cable, power draw)
- [x] Phase 1: NUT install and driver
- [x] Phase 2: monitoring config
- [ ] Phase 3: battery-based shutdown policy
- [ ] Phase 4: test
- [ ] Phase 5: docs and alerting (process doc done; optional alerts open)

## Next steps

### DGX Spark UPS graceful shutdown

1. Phase 4: pull-the-plug test (quiet moment; stops all containers and powers off), then check Spark power-on after mains returns.
