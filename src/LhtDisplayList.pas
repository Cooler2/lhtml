unit LhtDisplayList;

{$mode objfpc}{$H+}

interface

uses
  LhtDom, LhtRenderTypes;

type
  TLhtDisplayCommandKind = (dckFillRect, dckStrokeRect, dckTextRun);

  TLhtDisplayCommand = record
    Kind: TLhtDisplayCommandKind;
    Owner: TNode;
    OriginX: Integer;
    OriginY: Integer;
    X: Integer;
    Y: Integer;
    W: Integer;
    H: Integer;
    Color: TRgb;
    Text: string;
    Style: TLhtFontStyle;
    BaselineY: Integer;
  end;

  TLhtDisplayList = class
  private
    FCommands: array of TLhtDisplayCommand;
    function AddCommand(Kind: TLhtDisplayCommandKind): Integer;
    function InsertCommand(Index: Integer; Kind: TLhtDisplayCommandKind): Integer;
  public
    procedure Clear;
    procedure AddFillRect(Owner: TNode; OriginX, OriginY, X, Y, W, H: Integer;
      Color: TRgb);
    procedure InsertFillRect(Index: Integer; Owner: TNode; OriginX, OriginY, X,
      Y, W, H: Integer; Color: TRgb);
    procedure AddStrokeRect(Owner: TNode; OriginX, OriginY, X, Y, W, H: Integer;
      Color: TRgb);
    procedure AddTextRun(Owner: TNode; OriginX, OriginY, X, BaselineY: Integer;
      const S: string;
      const Style: TLhtFontStyle; Color: TRgb);
    procedure StretchOwnerHeight(Owner: TNode; Height: Integer);
    procedure Paint(Canvas: TLhtCanvas; Text: TLhtTextMetrics);
    procedure PaintOwner(Canvas: TLhtCanvas; Text: TLhtTextMetrics; Owner: TNode);
    function Count: Integer;
    function Command(Index: Integer): TLhtDisplayCommand;
  end;

implementation

uses
  SysUtils;

function TLhtDisplayList.AddCommand(Kind: TLhtDisplayCommandKind): Integer;
begin
  Result := Length(FCommands);
  SetLength(FCommands, Result + 1);
  FillChar(FCommands[Result], SizeOf(FCommands[Result]), 0);
  FCommands[Result].Kind := Kind;
end;

function TLhtDisplayList.InsertCommand(Index: Integer;
  Kind: TLhtDisplayCommandKind): Integer;
var
  I, N: Integer;
begin
  N := Length(FCommands);
  if (Index < 0) or (Index > N) then
    raise Exception.Create('Display command insert index out of range');
  SetLength(FCommands, N + 1);
  for I := N downto Index + 1 do
    FCommands[I] := FCommands[I - 1];
  FillChar(FCommands[Index], SizeOf(FCommands[Index]), 0);
  FCommands[Index].Kind := Kind;
  Result := Index;
end;

procedure TLhtDisplayList.Clear;
begin
  SetLength(FCommands, 0);
end;

procedure TLhtDisplayList.AddFillRect(Owner: TNode; OriginX, OriginY, X, Y, W,
  H: Integer; Color: TRgb);
var
  I: Integer;
begin
  I := AddCommand(dckFillRect);
  FCommands[I].Owner := Owner;
  FCommands[I].OriginX := OriginX;
  FCommands[I].OriginY := OriginY;
  FCommands[I].X := X;
  FCommands[I].Y := Y;
  FCommands[I].W := W;
  FCommands[I].H := H;
  FCommands[I].Color := Color;
end;

procedure TLhtDisplayList.InsertFillRect(Index: Integer; Owner: TNode; OriginX,
  OriginY, X, Y, W, H: Integer; Color: TRgb);
var
  I: Integer;
begin
  I := InsertCommand(Index, dckFillRect);
  FCommands[I].Owner := Owner;
  FCommands[I].OriginX := OriginX;
  FCommands[I].OriginY := OriginY;
  FCommands[I].X := X;
  FCommands[I].Y := Y;
  FCommands[I].W := W;
  FCommands[I].H := H;
  FCommands[I].Color := Color;
end;

procedure TLhtDisplayList.AddStrokeRect(Owner: TNode; OriginX, OriginY, X, Y, W,
  H: Integer; Color: TRgb);
var
  I: Integer;
begin
  I := AddCommand(dckStrokeRect);
  FCommands[I].Owner := Owner;
  FCommands[I].OriginX := OriginX;
  FCommands[I].OriginY := OriginY;
  FCommands[I].X := X;
  FCommands[I].Y := Y;
  FCommands[I].W := W;
  FCommands[I].H := H;
  FCommands[I].Color := Color;
end;

procedure TLhtDisplayList.AddTextRun(Owner: TNode; OriginX, OriginY, X,
  BaselineY: Integer; const S: string; const Style: TLhtFontStyle; Color: TRgb);
var
  I: Integer;
begin
  if S = '' then
    Exit;
  I := AddCommand(dckTextRun);
  FCommands[I].Owner := Owner;
  FCommands[I].OriginX := OriginX;
  FCommands[I].OriginY := OriginY;
  FCommands[I].X := X;
  FCommands[I].BaselineY := BaselineY;
  FCommands[I].Text := S;
  FCommands[I].Style := Style;
  FCommands[I].Color := Color;
end;

procedure TLhtDisplayList.StretchOwnerHeight(Owner: TNode; Height: Integer);
var
  I: Integer;
begin
  for I := 0 to High(FCommands) do
    if FCommands[I].Owner = Owner then
      case FCommands[I].Kind of
        dckFillRect:
          FCommands[I].H := Height;
        dckStrokeRect:
          begin
            FCommands[I].H := Height - FCommands[I].Y * 2;
            if FCommands[I].H < 0 then
              FCommands[I].H := 0;
          end;
      end;
end;

procedure PaintCommand(Canvas: TLhtCanvas; Text: TLhtTextMetrics;
  const Cmd: TLhtDisplayCommand);
begin
  case Cmd.Kind of
    dckFillRect:
      Canvas.FillRect(Cmd.OriginX + Cmd.X, Cmd.OriginY + Cmd.Y,
        Cmd.W, Cmd.H, Cmd.Color);
    dckStrokeRect:
      Canvas.StrokeRect(Cmd.OriginX + Cmd.X, Cmd.OriginY + Cmd.Y,
        Cmd.W, Cmd.H, Cmd.Color);
    dckTextRun:
      Canvas.DrawTextRun(Cmd.OriginX + Cmd.X,
        Cmd.OriginY + Cmd.BaselineY, Cmd.Text, Cmd.Style, Cmd.Color, Text);
  else
    raise Exception.Create('Unknown display command');
  end;
end;

procedure TLhtDisplayList.Paint(Canvas: TLhtCanvas; Text: TLhtTextMetrics);
var
  I: Integer;
begin
  for I := 0 to High(FCommands) do
    PaintCommand(Canvas, Text, FCommands[I]);
end;

procedure TLhtDisplayList.PaintOwner(Canvas: TLhtCanvas; Text: TLhtTextMetrics;
  Owner: TNode);
var
  I: Integer;
begin
  for I := 0 to High(FCommands) do
    if FCommands[I].Owner = Owner then
      PaintCommand(Canvas, Text, FCommands[I]);
end;

function TLhtDisplayList.Count: Integer;
begin
  Result := Length(FCommands);
end;

function TLhtDisplayList.Command(Index: Integer): TLhtDisplayCommand;
begin
  if (Index < 0) or (Index >= Length(FCommands)) then
    raise Exception.Create('Display command index out of range');
  Result := FCommands[Index];
end;

end.
