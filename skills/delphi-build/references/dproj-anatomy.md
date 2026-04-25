# `.dproj` anatomy

A `.dproj` is MSBuild XML. The IDE writes it; MSBuild and the standalone compilers consume it. Understanding the structure means you can edit it by hand, generate it from a template, or merge it across IDE versions without losing toggles.

## Top-level shape

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <ProjectGuid>{12345678-...}</ProjectGuid>
    <MainSource>myserver.dpr</MainSource>
    <Base>True</Base>
    <Config Condition="'$(Config)'==''">Debug</Config>
    <Platform Condition="'$(Platform)'==''">Win64</Platform>
    <ProjectVersion>20.2</ProjectVersion>             <!-- IDE version that saved -->
    <FrameworkType>VCL</FrameworkType>
    <AppType>Console</AppType>
  </PropertyGroup>

  <PropertyGroup Condition="'$(Base)'!=''">
    <!-- shared across all configs -->
    <DCC_UnitSearchPath>...;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>
    <DCC_Namespace>System;Winapi;Data.DB;$(DCC_Namespace)</DCC_Namespace>
    <DCC_Define>$(DCC_Define)</DCC_Define>
  </PropertyGroup>

  <PropertyGroup Condition="'$(Cfg_1)'!=''">
    <Cfg_1>true</Cfg_1>
    <CfgParent>Base</CfgParent>
    <Base>true</Base>
    <DCC_Define>DEBUG;$(DCC_Define)</DCC_Define>
    <DCC_DcuOutput>.\$(Platform)\$(Config)</DCC_DcuOutput>
    <DCC_ExeOutput>.\$(Platform)\$(Config)</DCC_ExeOutput>
  </PropertyGroup>

  <PropertyGroup Condition="'$(Cfg_2)'!=''">
    <Cfg_2>true</Cfg_2>
    <CfgParent>Base</CfgParent>
    <Base>true</Base>
    <DCC_Define>RELEASE;$(DCC_Define)</DCC_Define>
    <DCC_Optimize>true</DCC_Optimize>
  </PropertyGroup>

  <ItemGroup>
    <DelphiCompile Include="$(MainSource)"><MainSource>MainSource</MainSource></DelphiCompile>
    <DCCReference Include="myserver.rest.pas"/>
    <BuildConfiguration Include="Base"><Key>Base</Key></BuildConfiguration>
    <BuildConfiguration Include="Debug"><Key>Cfg_1</Key><CfgParent>Base</CfgParent></BuildConfiguration>
    <BuildConfiguration Include="Release"><Key>Cfg_2</Key><CfgParent>Base</CfgParent></BuildConfiguration>
  </ItemGroup>

  <ProjectExtensions>
    <Borland.Personality>Delphi.Personality.12</Borland.Personality>
    <Borland.ProjectType>VCLApplication</Borland.ProjectType>
    <BorlandProject>...</BorlandProject>
  </ProjectExtensions>

  <Import Project="$(BDS)\Bin\CodeGear.Delphi.Targets" Condition="Exists('$(BDS)\Bin\CodeGear.Delphi.Targets')"/>
</Project>
```

## Property groups and the `Base` / `Cfg_N` chain

The `Base` group holds shared properties. Each configuration (`Cfg_1` = Debug, `Cfg_2` = Release by IDE convention) has `<CfgParent>Base</CfgParent>`, which makes MSBuild merge the child group on top of the parent. Anything you put in `Base` is inherited by both Debug and Release.

The `<Base>true</Base>` inside config groups looks redundant but is meaningful: it tells MSBuild this group should also apply when the special `'$(Base)'!=''` condition is true. The pattern lets you write `Base`-only properties at the top once and override them per config below.

## `<DCC_*>` property reference

| Property                 | Effect                                                           | Equivalent dcc flag |
|--------------------------|------------------------------------------------------------------|---------------------|
| `<DCC_UnitSearchPath>`   | Unit search path (semicolon-separated)                           | `-U`                |
| `<DCC_Include>`          | Include search path                                              | `-I`                |
| `<DCC_ResourcePath>`     | Resource search path                                             | `-R`                |
| `<DCC_Namespace>`        | Implicit namespaces                                              | `-NS`               |
| `<DCC_Define>`           | Conditional defines (semicolon-separated)                        | `-D`                |
| `<DCC_DcuOutput>`        | DCU output directory                                             | `-O`                |
| `<DCC_ExeOutput>`        | EXE output directory                                             | `-E`                |
| `<DCC_BplOutput>`        | BPL output directory                                             | `-LE`               |
| `<DCC_DcpOutput>`        | DCP output directory                                             | `-LN`               |
| `<DCC_HppOutput>`        | HPP output directory (C++Builder integration)                    | `-NH`               |
| `<DCC_MapFile>`          | 0=none, 1=segments, 2=publics, **3=detailed (default for trace)**| `-G[N\|S\|D]`       |
| `<DCC_DebugInformation>` | True=full, False=none                                            | `-V` / `-V-`        |
| `<DCC_LocalDebugSymbols>`| Local symbols (per-unit)                                          | `-$L+\|-$L-`        |
| `<DCC_SymbolReferenceInfo>`| Y2 reference info                                              | `-$Y+\|-$Y-`        |
| `<DCC_BuildAllUnits>`    | True triggers `-B` (rebuild)                                      | `-B`                |
| `<DCC_Quiet>`            | True triggers `-Q`                                                | `-Q`                |
| `<DCC_UnitAlias>`        | Aliases (e.g. `WinTypes=Windows`)                                 | `-AB`               |
| `<DCC_Optimize>`         | True for Release builds                                           | `-$O+`              |

## `<DCC_UnitSearchPath>` versus `<DCC_SearchPath>`

Older `.dproj` files (Delphi 2007 / 2009 era) used `<DCC_SearchPath>`. From XE onwards the property was renamed `<DCC_UnitSearchPath>` and split from `<DCC_Include>` (which earlier was conflated). Both are still accepted, but only `<DCC_UnitSearchPath>` is documented. New projects should use `<DCC_UnitSearchPath>`. If you maintain a project that supports several IDEs, set both:

```xml
<DCC_UnitSearchPath>$(MORMOT2_PATH)\src;...;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>
<DCC_SearchPath>$(MORMOT2_PATH)\src;...;$(DCC_SearchPath)</DCC_SearchPath>
```

The trailing `$(...)` self-reference preserves what the parent group set; without it you wipe inherited paths.

## `<ItemGroup>` and `DCCReference`

Each `.pas` file the project ships explicitly is listed once as `<DCCReference Include="..."/>`. mORMot 2 sources are NOT listed: they live on the search path and are pulled implicitly when the `uses` clause names them. Add a `DCCReference` only for project-local units; pulling mORMot files in by reference produces duplicate-DCU build errors.

## `<ProjectExtensions>` quirks

The IDE writes a large `<BorlandProject>` blob inside `<ProjectExtensions>` that is JSON-shaped XML and *only the IDE reads it*. MSBuild ignores it. This is where the IDE stores window positions, run-parameters, package selections, and similar UI state. Hand-edit at your peril; the IDE rewrites it on every save.

## `<ProjectVersion>`

The version of the IDE that last saved the file. MSBuild does not enforce it, but the IDE may auto-upgrade on open and rewrite the file. To keep multiple IDE versions building one branch, either:

- Pin the branch to one IDE version per developer/CI box.
- Maintain `myserver.10.4.dproj` and `myserver.12.dproj` side by side and pick from the build script.

Mixing IDE versions on a shared `.dproj` always produces a churn diff at minimum, and silently dropped properties at worst.

## `<Import Project="$(BDS)\Bin\CodeGear.Delphi.Targets"/>`

The trailing import is what makes MSBuild understand `Build`, `Rebuild`, `Make`, `Clean`, `Compile` targets. Without `$(BDS)` set (i.e. `rsvars.bat` not sourced), the import file does not exist and MSBuild errors with `error MSB4019: The imported project ... was not found`. Always source `rsvars.bat` (or set `BDS` plus `BDSCommonDir`, `BDSPlatformSDKsDir`, `BDSCOMMONDIR`, `FrameworkDir`, `FrameworkVersion`) before invoking MSBuild on a `.dproj`.
