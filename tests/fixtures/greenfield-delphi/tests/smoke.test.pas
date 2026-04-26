unit smoke.test;

interface

uses
  mormot.core.base,
  mormot.core.test;

type
  TTestSmoke = class(TSynTestCase)
  published
    procedure FrameworkVersionPresent;
  end;

implementation

procedure TTestSmoke.FrameworkVersionPresent;
begin
  CheckUtf8(SYNOPSE_FRAMEWORK_VERSION <> '', 'mORMot framework version is set');
end;

end.
