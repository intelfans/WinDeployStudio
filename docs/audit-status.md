STATUS AFTER 2026-11 AUDIT ROUND

VERIFIED TODAY

  flutter analyze .......... no issues
  flutter test ............. 424 passed (86 test files)
  flutter pub get .......... restored 56 missing packages

The package cache had been pruned since the last session: 56 of 115
resolved packages were missing from C:/Users/bob_0/AppData/Local/Pub/Cache,
so the analyzer reported 1554 phantom errors. Not a code regression.

FIXED AND RE-VERIFIED IN SOURCE

  update signature gate ........ if (!signatureTrusted) return false
  download URL policy .......... https only, no loopback/RFC1918
  AI default model ............. mimo-v2.6-pro + retired-id migration
  mirror route ref.watch ....... moved into MirrorDetailRoute
  WTG file probe ............... inside the guarded region
  benchmark telemetry .......... inside try, no permanent running state
  erase dialog controller ...... disposed via whenComplete
  geo lookup ................... gated by the privacy policy
  privacy policy ............... HKLM value plus marker file
  tools load failure ........... error state, no endless spinner
  log clear confirmation ....... messenger captured before pop
  build-time state mutation .... read-only effective mode
  tool locale fallback ......... locale -> language -> base -> en
  raw write verification ....... GPT header excluded, post-mount recheck
  disk safety seam ............. DiskSafetyProcessRunner + 7 behaviour tests

STILL OPEN

  P1  WebView has no navigation allow-list. loadUrl runs unchecked and
      scripts are injected into any origin. Requires a per-caller origin
      policy, which is a product decision.

  P1  Plain downloads carry no digest. A file with no expected hash is
      accepted on length alone.

  P1  Search sends the raw user message to Bing/DuckDuckGo; the only
      guard is a five-word regex deny-list.

  P2  Mirror identity accepts an MD5 match on its own.

  P2  Four declared dependencies are never imported: logger, collection,
      filesize, fluentui_system_icons.

  P3  Installer and both binaries remain unsigned, so SmartScreen shows
      an unknown publisher and the in-app updater has no identity anchor.

  P3  isSystem is null on the USB disk and the native helper maps it to
      false. Today the target is still rejected because a USB bus is not
      external-and-safe, but the null default is the wrong direction.

NOT YET CONFIRMED ON HARDWARE

  The reworked raw-write verification has not been run against a physical
  disk since the change. The USB stick is no longer attached. Until that
  run happens, the post-mount check is verified only by contract tests and
  by an independent digest cross-check on the image file.
