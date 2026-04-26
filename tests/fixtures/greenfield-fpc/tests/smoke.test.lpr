program smoketest;
{$mode objfpc}{$H+}
{$I mormot.defines.inc}
uses
  mormot.core.base,
  mormot.core.test,
  smoke.test;

begin
  with TSynTestsLogged.Create do
    try
      TestCase('Smoke', TTestSmoke);
      Run;
    finally
      Free;
    end;
end.
