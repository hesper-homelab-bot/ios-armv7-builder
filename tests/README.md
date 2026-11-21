# tests/ -- device acceptance suite

Executable form of the README's "Verified on an iPad 4" table.  Each
`<pkg>.sh` runs read-only probes over ssh and prints PASS/FAIL/SKIP per case.

```sh
tests/run-all.sh            # everything, writes tests/REPORT.md (gitignored)
tests/run-all.sh curl jq    # just these packages
IPAD_HOST=other tests/run-all.sh
```

Connection target: `IPAD_HOST` (default `ipad`, see DEVICE.md).  The device
being unreachable makes cases SKIP, not FAIL.

Rules for new cases:

* read-only on the device -- no writes, no service (re)starts, nothing that
  can break the production ssh path;
* binaries are called by absolute path (our packages install under
  /var/mobile/tools, /var/mobile/openssl4, /usr/bin; PATH on the device is
  not guaranteed to include the tool prefixes);
* every assertion must correspond to behaviour already verified in the README
  table or the package's docs/<pkg>.md -- this suite is a regression net, not
  a place to invent new claims.

The README table stays hand-written for now (it carries richer context than a
PASS/FAIL row); REPORT.md is the machine-readable sibling.  If the two ever
drift, this suite wins -- fix the device, then the table.
