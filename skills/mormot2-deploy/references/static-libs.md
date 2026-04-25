# Static libraries

mORMot 2 ships precompiled C dependencies as `.o` (POSIX) and `.obj` (Windows) archives in `mORMot2/static/`. The framework links them with `{$L ...}` directives gated on per-platform conditional defines from `mormot.defines.inc`. Once the conditional is set and the archive is on the linker search path, the binary has no runtime dependency on the corresponding shared library.

## Where the binaries come from

The static archive is NOT in the git checkout. Download it once after cloning:

```
https://synopse.info/files/mormot2static.7z   # Windows
https://synopse.info/files/mormot2static.tgz  # POSIX
```

Extract under `mORMot2/static/`. The layout is one folder per `<cpu>-<os>` triplet (e.g. `x86_64-linux`, `i386-win32`, `aarch64-darwin`). Each triplet has the C runtime shims plus the per-library archives. The defines in `mormot.defines.inc` already match the triplets that ship binaries; if you target a triplet without binaries, the static define is auto-undefined and the framework falls back to dynamic loading or pure Pascal.

## Library matrix

| Library    | Conditional define   | Default on Delphi              | Default on FPC                 | Pascal unit pulled                       | Notes                                                   |
|------------|----------------------|--------------------------------|--------------------------------|------------------------------------------|---------------------------------------------------------|
| SQLite3    | `STATICSQLITE` (set when `NOSQLITE3STATIC` is undefined) | Win32, Win64                  | Linux x86_64, Win32/64, Darwin | `mormot.db.raw.sqlite3.static`           | Disabled on aarch64-win64 and Win-ARM by default        |
| OpenSSL    | `OPENSSLSTATIC`      | Win32, Win64 (in 2.x defaults) | Linux x86_64, Win32/64         | `mormot.lib.openssl11`                   | When undef, OpenSSL is loaded dynamically at runtime    |
| Zstd       | (sets `Zstd := TSynZstdStatic`) | Win32/64 with archive            | Linux x86_64, Win32/64         | `mormot.lib.zstd`                        | Static is the default; `TSynZstdDynamic` is the fallback|
| libdeflate | `LIBDEFLATESTATIC`   | Intel Win                      | Intel Linux, Intel Win         | `mormot.core.zip`                        | Faster zlib for in-memory only; on-disk uses zlib       |
| zlib       | `ZLIBSTATIC` / `ZLIBPAS` / `ZLIBEXT` / `ZLIBRTL` | varies          | varies                          | `mormot.lib.z` -> `mormot.core.zip`     | Static on FPC Win, RTL on Delphi Win64, paszlib on ARM  |
| QuickJS    | `LIBQUICKJSSTATIC`   | Win32; Win64 partial           | Linux x86_64, Win32/64         | `mormot.lib.quickjs`                     | Marked unstable on Delphi Win64 10.4+; check defines    |
| libcurl    | `LIBCURLSTATIC`      | n/a                            | Mainly Android                 | `mormot.lib.curl`                        | Desktop targets keep dynamic libcurl                    |
| libgss     | (POSIX only)         | n/a                            | Linux                          | `mormot.lib.gssapi`                      | GSSAPI is dynamic-only; Kerberos libs ship via OS pkgs  |

Bare minimum for a "single binary" REST/HTTPS server: `STATICSQLITE` + `OPENSSLSTATIC` + `LIBDEFLATESTATIC`. That eliminates the SQLite library, the OpenSSL libcrypto/libssl pair, and the libdeflate runtime, which together account for almost all the runtime DLL/.so dependencies a typical mORMot binary would otherwise carry.

## Compiler flag reminders

The static units consume `.o` / `.obj` via `{$L name.o}` directives that are already inside the framework. You do NOT pass `-l...` or `gcc -static`. The deployment-time inputs are:

- `mORMot2/static/<triplet>/` is on the linker search path. Delphi reads it from the project's library path, FPC from `-Fl<dir>`.
- The conditional define is active. Inspect with a one-liner: `grep -n 'STATICSQLITE\|OPENSSLSTATIC\|LIBDEFLATESTATIC\|LIBQUICKJSSTATIC' mormot.defines.inc | head` and confirm the active branch matches your target.
- For Delphi/Win32, the static linker pulls `msvcrt.dll` shims via `mormot.lib.static`. That is fine; it is `msvcrt.dll`, not `vcruntime140.dll`. You do not need to ship a VC++ redistributable.

## Verification

A binary built with the right statics exposes only OS libraries to the runtime loader:

```
# POSIX
$ ldd ./myserver
  linux-vdso.so.1
  libc.so.6
  libpthread.so.0
  libdl.so.2
  /lib64/ld-linux-x86-64.so.2

# Windows
> dumpbin /dependents myserver.exe
  KERNEL32.dll  ADVAPI32.dll  WS2_32.dll  WINMM.dll  msvcrt.dll
```

If `libssl.so.3`, `libcrypto.so.3`, `libsqlite3.so.0`, or `libcurl.so.4` show up, the static define did not apply. Re-check the conditional, then verify the archive matches the target triplet.

## Trade-offs

Static linking gives a single binary, lower attack surface (no PATH-search hijack), and consistent versions across hosts. The cost is binary size (a stripped Linux x86_64 mORMot REST binary with `STATICSQLITE` + `OPENSSLSTATIC` + `LIBDEFLATESTATIC` lands around 8 to 12 MB) and longer link times. For a microservice, the trade is almost always worth it. For a desktop tool that the user runs from a folder of mixed binaries, dynamic loading lets multiple programs share one OpenSSL.

The one library you should NEVER static-link: `libgss` (GSSAPI). Kerberos depends on the host's `/etc/krb5.conf` and the OS-managed credential cache. Statically linking GSSAPI breaks against newer KDCs the moment the admin upgrades the OS package. Keep `mormot.lib.gssapi` dynamic and let the OS manage Kerberos.
