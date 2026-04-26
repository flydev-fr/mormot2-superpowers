program smoketest;
{$APPTYPE CONSOLE}
{$I mormot.defines.inc}
uses
  mormot.core.base,
  mormot.core.test,
  smoke.test in 'smoke.test.pas';

begin
  with TSynTestsLogged.Create do
    try
      TestCase('Smoke', TTestSmoke);
      Run;
    finally
      Free;
    end;
end.
