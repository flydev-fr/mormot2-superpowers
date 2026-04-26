program smoke;
{$IFDEF FPC}{$mode objfpc}{$H+}{$ELSE}{$APPTYPE CONSOLE}{$ENDIF}
{$I mormot.defines.inc}
uses
  mormot.core.base;
begin
  if SYNOPSE_FRAMEWORK_VERSION = '' then
    Halt(1);
  Halt(0);
end.
