﻿// JCL_DEBUG_EXPERT_GENERATEJDBG OFF
program multilogfiles;

uses
  Vcl.Forms,
  main in 'main.pas' {Form4};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm4, Form4);
  Application.Run;
end.
