# Cross-compilation with FPC

Free Pascal supports cross-compilation natively: one host (e.g. Windows x86_64) produces binaries for any combination of supported target OS and CPU (e.g. Linux AArch64). The host invokes the same `fpc` binary it always uses; `-T<os> -P<cpu>` flags switch the target. FPC then calls the matching cross-assembler and cross-linker (`<target>-as`, `<target>-ld`) found on `PATH` or under `$FPCDIR/bin/<target>`.

## Host triplets

The standard FPC notation is `<cpu>-<os>` (note: CPU first, OS second; the opposite of the GNU triplet convention).

| Host                 | `-iSP` reports | `-iSO` reports |
|----------------------|----------------|----------------|
| Windows 64           | `x86_64`       | `win64`        |
| Windows 32           | `i386`         | `win32`        |
| Linux x86_64         | `x86_64`       | `linux`        |
| Linux ARM            | `arm`          | `linux`        |
| Linux AArch64        | `aarch64`      | `linux`        |
| macOS Intel          | `x86_64`       | `darwin`       |
| macOS Apple Silicon  | `aarch64`      | `darwin`       |
| FreeBSD x86_64       | `x86_64`       | `freebsd`      |

Print the running compiler's host triplet:

```bash
fpc -iSP -iSO   # prints "x86_64\nwin64" on a Windows 64-bit FPC
```

## Common target combinations

| Goal                                   | Flags                                  |
|----------------------------------------|----------------------------------------|
| Win64 host -> Linux x86_64             | `-Tlinux -Px86_64`                     |
| Win64 host -> Linux AArch64 (RPi 4/5)  | `-Tlinux -Paarch64`                    |
| Win64 host -> Linux ARM v7 (RPi 2/3)   | `-Tlinux -Parm -CpARMV7A`              |
| Win64 host -> 32-bit Linux             | `-Tlinux -Pi386`                       |
| Linux x86_64 host -> Win64             | `-Twin64 -Px86_64`                     |
| Linux x86_64 host -> Win32             | `-Twin32 -Pi386`                       |
| macOS Intel -> macOS Apple Silicon     | `-Tdarwin -Paarch64`                   |
| Win64 host -> Android ARM64            | `-Tandroid -Paarch64`                  |
| Win64 host -> iOS device (AArch64)     | `-Tdarwin -Paarch64 -XR<sysroot>`      |

## Bootstrapping a cross toolchain

FPC ships per-host installers, not per-target. To cross-compile, you need:

1. A native FPC for the **host** (the one in `$PATH`).
2. The cross-binutils for the **target**: `<target>-as` and `<target>-ld` (and on Linux targets, `<target>-objcopy`, `<target>-strip`).
3. Optionally, the FPC RTL `.ppu` files for the target, pre-built and dropped under `$FPCDIR/units/<target>-<cpu>/`.

On Windows, the canonical layout (under any FPC install root, e.g. `%FPCUP_ROOT%\fpc\`) is:

```
$FPCDIR/
  bin/
    x86_64-win64/         # host compiler
      fpc.exe
      ppcx64.exe
    arm-linux/            # cross binutils for ARM Linux
      arm-linux-as.exe
      arm-linux-ld.exe
      arm-linux-strip.exe
    aarch64-linux\        # cross binutils for AArch64 Linux
      ...
  units\
    x86_64-win64\         # host RTL ppu files
    arm-linux\            # cross RTL ppu files
    aarch64-linux\
    ...
```

`fpcup` (or the official Lazarus cross-installer) sets all this up. Without the cross binutils on `PATH`, FPC errors out with `Error: Can't open file: <target>-ld`.

## Output-directory partitioning

The single most common cross-compile mistake is letting `.ppu` files from different targets share one directory. FPC writes per-unit `.ppu` plus a per-unit `.o` into `-FU`, and a Linux/AArch64 `.o` cannot link into a Win64 binary. The linker eventually catches it ("Wrong symbol size" or "Object format not understood"), but the error message rarely names the offender.

Always partition:

```bash
# Hand-rolled fpc:
fpc -Tlinux -Paarch64 -FU./lib/aarch64-linux ...

# Lazarus .lpi:
<UnitOutputDirectory Value="lib/$(TargetCPU)-$(TargetOS)"/>

# CI: nuke lib/ between targets if you cannot partition.
rm -rf ./lib
fpc -Tlinux -Paarch64 ...
```

The same applies to `-FE` (executable output): partition by target so a `bin/` directory with a Windows `.exe` and a Linux ELF side by side does not confuse the deploy step.

## CPU sub-target tuning

Some `-P<cpu>` values accept `-Cp<subtype>` to refine instruction selection.

| `-P` | `-Cp` values                                                  | Notes                              |
|------|---------------------------------------------------------------|------------------------------------|
| `arm` | `ARMV5T`, `ARMV6`, `ARMV7A`, `ARMV7M`                       | RPi 2/3 = `ARMV7A`; RPi Zero = `ARMV6` |
| `i386` | `PENTIUM2`, `PENTIUM3`, `PENTIUM4`, `PENTIUMM`, `COREI`     | Default fits most x86 machines     |
| `x86_64` | `COREI`, `COREAVX`, `COREAVX2`, `COREAVX512`               | Default `COREI` is portable         |
| `aarch64` | (no widely used sub-type)                                   |                                    |

On ARM, also pair with `-Cf<fpu>`:

| `-Cf` | Meaning                                              |
|-------|------------------------------------------------------|
| `SOFT`     | Software float (most compatible, slowest)        |
| `VFPV2`    | RPi 1 / older ARMv6                              |
| `VFPV3`    | RPi 2/3, most ARMv7                              |
| `VFPV4`    | Newer ARMv7 with SIMD                            |
| `NEON`     | Use NEON SIMD where available                    |

For RPi 4/5 (AArch64), no `-Cf` is needed: `aarch64` always has hardware FP.

## Runtime DLL/SO requirements

FPC binaries are mostly statically linked, but a few targets need runtime artefacts:

- **Linux** — `libc`, `libpthread`, optionally `libdl` and `libcwstring` (Unicode). The target host MUST have these; cross-compiled binaries do NOT bundle them. mORMot 2 also pulls in `libssl` and `libcrypto` if you build with `OPENSSLSTATIC` undefined.
- **Windows** — typically self-contained; `MSVCRT.dll` is on every Windows. mORMot 2 may pull in `wininet.dll` and `winhttp.dll` for the HTTP client.
- **macOS** — `libSystem.dylib` (always present), plus signing on Apple Silicon (`codesign -s -`).
- **Android** — Bionic libc; the binary must be packaged into an `.apk` with the right architecture in `lib/`.

For mORMot 2 specifically, when bundling shared libs (SQLite, OpenSSL) is not desired, build with `STATICSQLITE` and `OPENSSLSTATIC` defined and link against `static/<target>/`. See `mormot2-deploy` for the runtime-bundling decisions; this skill only covers the *build flags* that produce the binary.

## `-XR<sysroot>` for offline cross-builds

When the build host does NOT have the target's headers and runtime libs installed, point FPC at a sysroot (a copy of the target's `/`):

```bash
fpc -Tlinux -Paarch64 -XR/opt/aarch64-linux-sysroot myproject.lpr
```

The sysroot must contain at least `usr/lib`, `usr/include` (for any `cdecl` calls), and `lib/ld-linux-aarch64.so.1`. The Raspberry Pi project ships such sysroots; for AArch64 Linux Docker images, `multiarch/qemu-user-static` chroots are a quick way to materialise one.

## `lazbuild` cross-compile shortcuts

`lazbuild` accepts the same target overrides:

```bash
lazbuild myproject.lpi --os=linux --cpu=aarch64 --build-mode=Release
```

The `.lpi` does not need a per-target build mode; the override flags rewrite `<TargetOS>` and `<TargetCPU>` for the duration of the invocation. Pair with a target-partitioned `<UnitOutputDirectory>` and one `.lpi` covers every cross-target the project ships.

## Asserting the right target was built

After a cross-build, verify the binary's actual format before shipping:

```bash
# Linux ELF, AArch64
file ./bin/aarch64-linux/myserver
# expects: ELF 64-bit LSB executable, ARM aarch64 ...

# Windows PE, x86_64
file ./bin/x86_64-win64/myserver.exe
# expects: PE32+ executable (console) x86-64

# Linux ELF, ARMv7 (RPi 3)
file ./bin/arm-linux/myserver
# expects: ELF 32-bit LSB executable, ARM, EABI5 ...
```

`file` on Windows ships with Git Bash and MSYS2; on Linux/macOS it is part of the base image. Make this assertion part of the CI pipeline so a misconfigured host triplet fails loudly rather than producing a binary that silently runs only on the build machine.
