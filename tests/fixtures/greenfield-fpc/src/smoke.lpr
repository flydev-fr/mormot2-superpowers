program smoke;
{$mode objfpc}{$H+}
{$I mormot.defines.inc}
uses
  mormot.core.base;
begin
  if SYNOPSE_FRAMEWORK_VERSION = '' then
    Halt(1);
  Halt(0);
end.
