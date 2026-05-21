unit LhtCanvasBmp;

{$mode objfpc}{$H+}

interface

uses
  Classes, LhtRenderTypes;

type
  TLhtBmpCanvas = class(TLhtCanvas)
  private
    FWidth: Integer;
    FHeight: Integer;
    FPixels: array of TRgb;
    function Index(X, Y: Integer): Integer;
    procedure SetPixel(X, Y: Integer; Color: TRgb);
  public
    constructor Create(AWidth, AHeight: Integer);
    procedure Clear(Color: TRgb); override;
    procedure FillRect(X, Y, W, H: Integer; Color: TRgb); override;
    procedure StrokeRect(X, Y, W, H: Integer; Color: TRgb); override;
    procedure DrawGlyph(X, Y: Integer; const Glyph: TLhtGlyph; Color: TRgb); override;
    procedure SaveBmp(const FileName: string);
  end;

implementation

constructor TLhtBmpCanvas.Create(AWidth, AHeight: Integer);
begin
  inherited Create;
  FWidth := AWidth;
  FHeight := AHeight;
  SetLength(FPixels, FWidth * FHeight);
end;

function TLhtBmpCanvas.Index(X, Y: Integer): Integer;
begin
  Result := Y * FWidth + X;
end;

procedure TLhtBmpCanvas.SetPixel(X, Y: Integer; Color: TRgb);
begin
  if (X < 0) or (Y < 0) or (X >= FWidth) or (Y >= FHeight) then
    Exit;
  FPixels[Index(X, Y)] := Color;
end;

procedure TLhtBmpCanvas.Clear(Color: TRgb);
begin
  FillRect(0, 0, FWidth, FHeight, Color);
end;

procedure TLhtBmpCanvas.FillRect(X, Y, W, H: Integer; Color: TRgb);
var
  IX, IY: Integer;
begin
  for IY := Y to Y + H - 1 do
    for IX := X to X + W - 1 do
      SetPixel(IX, IY, Color);
end;

procedure TLhtBmpCanvas.StrokeRect(X, Y, W, H: Integer; Color: TRgb);
var
  I: Integer;
begin
  for I := 0 to W - 1 do
  begin
    SetPixel(X + I, Y, Color);
    SetPixel(X + I, Y + H - 1, Color);
  end;
  for I := 0 to H - 1 do
  begin
    SetPixel(X, Y + I, Color);
    SetPixel(X + W - 1, Y + I, Color);
  end;
end;

procedure TLhtBmpCanvas.DrawGlyph(X, Y: Integer; const Glyph: TLhtGlyph; Color: TRgb);
var
  Row, Col, SX, SY: Integer;
  Bits: Word;
begin
  for Row := 0 to Glyph.Height - 1 do
  begin
    Bits := Glyph.Rows[Row];
    for Col := 0 to Glyph.Width - 1 do
      if (Bits and (1 shl (Glyph.Width - 1 - Col))) <> 0 then
        for SY := 0 to Glyph.Scale - 1 do
          for SX := 0 to Glyph.Scale - 1 do
            SetPixel(X + Col * Glyph.Scale + SX, Y + Row * Glyph.Scale + SY, Color);
  end;
end;

procedure WriteWordLE(Stream: TStream; V: Word);
begin
  Stream.WriteBuffer(V, SizeOf(V));
end;

procedure WriteDWordLE(Stream: TStream; V: Cardinal);
begin
  Stream.WriteBuffer(V, SizeOf(V));
end;

procedure WriteIntLE(Stream: TStream; V: Integer);
begin
  Stream.WriteBuffer(V, SizeOf(V));
end;

procedure TLhtBmpCanvas.SaveBmp(const FileName: string);
var
  Stream: TFileStream;
  RowSize: Integer;
  ImageSize: Cardinal;
  FileSize: Cardinal;
  X, Y, Pad: Integer;
  P: TRgb;
  Zero: Byte;
begin
  RowSize := ((FWidth * 3 + 3) div 4) * 4;
  ImageSize := RowSize * FHeight;
  FileSize := 14 + 40 + ImageSize;
  Zero := 0;

  Stream := TFileStream.Create(FileName, fmCreate);
  try
    WriteWordLE(Stream, $4D42);
    WriteDWordLE(Stream, FileSize);
    WriteWordLE(Stream, 0);
    WriteWordLE(Stream, 0);
    WriteDWordLE(Stream, 14 + 40);

    WriteDWordLE(Stream, 40);
    WriteIntLE(Stream, FWidth);
    WriteIntLE(Stream, FHeight);
    WriteWordLE(Stream, 1);
    WriteWordLE(Stream, 24);
    WriteDWordLE(Stream, 0);
    WriteDWordLE(Stream, ImageSize);
    WriteIntLE(Stream, 2835);
    WriteIntLE(Stream, 2835);
    WriteDWordLE(Stream, 0);
    WriteDWordLE(Stream, 0);

    for Y := FHeight - 1 downto 0 do
    begin
      for X := 0 to FWidth - 1 do
      begin
        P := FPixels[Index(X, Y)];
        Stream.WriteBuffer(P.B, 1);
        Stream.WriteBuffer(P.G, 1);
        Stream.WriteBuffer(P.R, 1);
      end;
      for Pad := 1 to RowSize - FWidth * 3 do
        Stream.WriteBuffer(Zero, 1);
    end;
  finally
    Stream.Free;
  end;
end;

end.
