# v10 snapshot artifacts (matching node_v21 / node4 22.23.4-1)

These are the device-generated V8 startup snapshot + embedded blob that
node_v21 (the packaged node.real) was linked against. Generated on the
device by the fixed mksnapshot (mks_fixed2, wall #12 machinery), 2026-11-11.

- snapshot_v10_wrapper.cc: byte-array wrapper, v8_Default_snapshot_blob
  (293,463-byte compressed startup blob)
- embedded_code_v10.bin: raw embedded code blob (1,920,160 B,
  md5 1857cff92832de5db510e3d49864b56e; contains the 11,415 finalised
  builtin fixups -- the wall #12 deliverable)
- embedded_data_v10.bin: EmbeddedData metadata table (88,408 B)
- embedded_S_v10.txt: the .byte-array assembly wrapper compiled into
  geni/embedded.o (the .S form of embedded_code_v10.bin)

## Regeneration procedure (if V8 builtins change)

1. Device: cd /var/mobile/scratch/snapgen && ../mks_fixed2
   --target_os=ios --target_arch=arm --startup_src snapshot.cc
   --startup_blob Default --embedded_variant Default
   (device mksnapshot now finalises fixups before dumping -- wall #12
   fix in embedded-data.cc; call1 dumps embedded, PHASE writes
   startup, call2 exits)
2. Pull embedded_code.bin / embedded_data.bin / snapshot.cc back
3. Rebuild geni/{embedded.o,snapshot.o} from the wrappers
   (see /tmp/rebuild-geni.sh pattern: .byte arrays + the four
   _v8_Default_embedded_blob_{code,data,_size_} symbols)
4. Swap into libv8_snapshot.flat.a, relink node
5. Verify: --jitless -e "console.log(40+2)" -> 42, then http roundtrip

The wrappers exist because the cctools ld64 link needs the blobs as
plain data symbols; upstream uses its own embedded.S emitter which is
tied to the snapshot-embedder flow we replaced.
