# FPC modes and command-line flags

`fpc` is the Free Pascal Compiler. It accepts dozens of single-letter flag families that toggle language mode, output type, search paths, optimisations, and target platform. mORMot 2 only uses a small subset, but getting the wrong member of that subset produces unhelpful errors. This reference enumerates the flags this skill recommends, what each does, and what defaults you must override.

## Language modes (`-M<mode>`)

The `-M` flag selects the source dialect FPC parses. mORMot 2 is written for `objfpc`, with C-style operators enabled.

| Mode        | Meaning                                                          | mORMot 2 status |
|-------------|------------------------------------------------------------------|-----------------|
| `-Mfpc`     | FPC's native dialect (closest to old Turbo Pascal extensions)    | Not supported   |
| `-Mobjfpc`  | Object Pascal, FPC's enhanced flavour                            | **Required**    |
| `-Mdelphi`  | Maximum Delphi compatibility (no operator overloading)           | Not supported   |
| `-Mtp`      | Turbo Pascal 7 dialect                                            | Not supported   |
| `-Mmacpas`  | Mac Pascal dialect                                                | Not supported   |

Pair `-Mobjfpc` with `-Sci` so C-style operators (`+=`, `-=`, `*=`, `/=`, `^=`) parse. Without `-Sci`, mORMot source breaks at the first compound assignment.

```bash
fpc -Mobjfpc -Sci myunit.pas
```

In an `.lpi`, set this under `Project Options | Compiler Options | Parsing | Syntax mode` to `ObjFPC` and check `C-style operators (*=, +=, /= and -=)`.

## Search-path flags

| Flag      | Meaning                                                    | Notes                          |
|-----------|------------------------------------------------------------|--------------------------------|
| `-Fu<dir>`| Add to **unit** search path (looks for `.ppu` and `.pas`)  | Repeat for each dir            |
| `-Fi<dir>`| Add to **include** search path (`{$I file.inc}`)           | Repeat for each dir            |
| `-Fl<dir>`| Add to **library** search path (`-llibname`, `cwstring`)   | Linux dynamic linker hint      |
| `-Fr<file>`| Use a **resource string** file                             | Internationalisation           |
| `-Fo<file>`| Set the **output object** file (rare, prefer `-FE`)        |                                |
| `-Fd`     | Disable inheriting search paths from `fpc.cfg`             | Useful in CI sandboxes         |

For mORMot 2:

```bash
SRC="$MORMOT2_PATH/src"
fpc -Mobjfpc -Sci \
  -Fu"$SRC" -Fu"$SRC/core" -Fu"$SRC/orm" -Fu"$SRC/rest" -Fu"$SRC/soa" \
  -Fu"$SRC/db" -Fu"$SRC/crypt" -Fu"$SRC/net" -Fu"$SRC/app" -Fu"$SRC/lib" \
  -Fi"$SRC" -Fi"$SRC/core" \
  myproject.lpr
```

`scripts/fpc-build.sh` constructs this exact list, dropping any directory that does not exist on disk so a partial mORMot checkout still builds.

## Output-directory flags

| Flag      | Meaning                                                       |
|-----------|---------------------------------------------------------------|
| `-FE<dir>`| Place the **executable** in `<dir>`                           |
| `-FU<dir>`| Place **unit output** (`.ppu`, `.o`) in `<dir>`               |
| `-FW<file>`| Write a **whole-program** info file (for cross-unit dead-code elimination, paired with `-Fw`) |

Always partition `-FU` per target when cross-compiling: `-FU./lib/$(fpc -PB)-$(fpc -TB)` or, in `.lpi`, `lib/$(TargetCPU)-$(TargetOS)`. A shared `lib/` mixes incompatible `.ppu` files from prior targets and the linker silently picks wrong.

## Optimisation flags

| Flag      | Meaning                                                                |
|-----------|------------------------------------------------------------------------|
| `-O-`     | Disable optimisations (default for debug builds)                       |
| `-O1`     | Quick optimisations, fast compile                                      |
| `-O2`     | Standard release optimisations                                          |
| `-O3`     | Aggressive: register variables, inlining (mORMot release default)       |
| `-O4`     | Even more aggressive (alias analysis); occasional miscompiles, test it |
| `-OoREGVAR` | Specific opt sub-flag: register variables (already in `-O3`)         |
| `-OpPENTIUMM` | CPU-specific tuning (rarely worth the loss of portability)         |
| `-CX`     | Smartlink units (smaller binaries, slower link)                        |
| `-XX`     | Smartlink the executable                                                |

For a Release mORMot build: `-O3 -CX -XX -Xs` (strip symbols). For Debug: `-O- -gw3 -gl -godwarfsets`.

## Debug-info flags

| Flag        | Meaning                                                            |
|-------------|--------------------------------------------------------------------|
| `-g`        | Debug info, default format                                         |
| `-gl`       | Add **line-number** info (cheap, always include)                   |
| `-gw3`      | DWARFv3 debug info (the format `gdb`, `lldb`, and `pprof` understand) |
| `-godwarfsets` | DWARF for sets/enums (mORMot logs read these)                   |
| `-gh`       | Use **heaptrc** unit (leak detector at process exit)               |
| `-gv`       | Generate Valgrind-compatible info                                   |

For stack-trace logging via `TSynLog`, build with `-gw3 -gl -godwarfsets`. Without DWARF, FPC binaries do not carry the symbol/line metadata `mormot.core.log` needs to map a raw address back to source.

## Linking and binary-shape flags

| Flag      | Meaning                                                                       |
|-----------|-------------------------------------------------------------------------------|
| `-XS`     | Link statically (default on most targets)                                      |
| `-XD`     | Link dynamically (uses libc/cwstring at runtime)                               |
| `-Xs`     | Strip symbols from the final binary                                            |
| `-XX`     | Smartlink the executable (drop unused code)                                    |
| `-Xe`     | Use the GNU linker explicitly                                                  |
| `-WG`     | Mark the binary as **GUI** (Windows only; default is console)                  |
| `-WC`     | Mark the binary as **console** (Windows only)                                  |
| `-Cn`     | Skip the link step (compile only)                                              |
| `-Tlinux -Px86_64` | Cross-compile target OS / CPU                                       |

## Conditional defines

| Flag           | Meaning                                                              |
|----------------|----------------------------------------------------------------------|
| `-d<symbol>`   | Define a conditional symbol (equivalent to `{$DEFINE symbol}`)       |
| `-u<symbol>`   | Undefine a conditional symbol                                         |
| `-Sa`          | Enable assertions (`Assert(...)`)                                     |
| `-Sg`          | Allow `goto`                                                          |

mORMot 2 FPC-only defines worth knowing:

| Define             | Effect                                                          |
|--------------------|-----------------------------------------------------------------|
| `FPC_X64MM`        | Use mORMot's `mormot.core.fpcx64mm` instead of FPC's heap        |
| `FPCMM_BOOST`      | Aggressive small-block allocator on top of `FPC_X64MM`           |
| `FPCMM_DEBUG`      | Leak detection (development only, not production)                |
| `FPCMM_NOASSEMBLER`| Pure-Pascal allocator (slow but portable)                        |
| `FPC_HAS_SETJMP`   | Set automatically on platforms with `setjmp`                     |
| `MORMOT2TESTS`     | Compile the mORMot 2 test suite alongside your code              |
| `STATICSQLITE`     | Link SQLite statically (build-time half of `mormot2-deploy`)     |

## `-i*` info flags (no compile)

| Flag    | Effect                                                             |
|---------|--------------------------------------------------------------------|
| `-iV`   | Print FPC version (`3.2.2`)                                        |
| `-iSO`  | Print target OS (`linux`, `win64`)                                 |
| `-iSP`  | Print target CPU (`x86_64`, `aarch64`)                             |
| `-iTO`  | List supported target OSes                                          |
| `-iTP`  | List supported target CPUs                                          |
| `-h`    | Full help (the canonical reference is the binary itself)            |

Asserting the FPC version in CI:

```bash
fpc -iV | grep -qE '^3\.2\.[2-9]' || { echo "FPC >= 3.2.2 required"; exit 1; }
```

## Configuration files

FPC reads, in order: `$FPCDIR/etc/fpc.cfg`, `~/.fpc.cfg`, `./fpc.cfg`. Each line is a flag (no leading dash needed; `#` starts a comment). On a shared CI runner, prefer `-n` to ignore all `fpc.cfg` files and rely entirely on the script's explicit flags. `scripts/fpc-build.sh` does NOT pass `-n`, but the project can opt in by adding it under `Custom Options` in the `.lpi` or by editing the wrapper.
