unit LhtDebugFont;

{$mode objfpc}{$H+}

interface

uses
  LhtRenderTypes;

type
  TLhtDebugFont = class(TLhtTextMetrics)
  public
    function GetGlyph(C: Char; const Style: TLhtFontStyle): TLhtGlyph; override;
    function MeasureText(const S: string; const Style: TLhtFontStyle): Integer; override;
    function SpaceAdvance(const Style: TLhtFontStyle): Integer; override;
    function Ascent(const Style: TLhtFontStyle): Integer; override;
    function Descent(const Style: TLhtFontStyle): Integer; override;
    function LineHeight(const Style: TLhtFontStyle): Integer; override;
  end;

implementation

const
  GlyphW = 5;
  GlyphH = 7;

function ScaleForSize(Size: TLhtFontSize): Integer;
begin
  case Size of
    lfsTiny, lfsSmall: Result := 1;
    lfsLarge, lfsXLarge: Result := 3;
    lfsXXLarge: Result := 4;
  else
    Result := 2;
  end;
end;

function AdvanceForSize(Size: TLhtFontSize): Integer;
begin
  Result := 6 * ScaleForSize(Size);
end;

function LineHeightForSize(Size: TLhtFontSize): Integer;
begin
  case Size of
    lfsTiny: Result := 10;
    lfsSmall: Result := 12;
    lfsLarge: Result := 30;
    lfsXLarge: Result := 34;
    lfsXXLarge: Result := 44;
  else
    Result := 20;
  end;
end;

function AscentForSize(Size: TLhtFontSize): Integer;
begin
  Result := GlyphH * ScaleForSize(Size);
end;

function DescentForSize(Size: TLhtFontSize): Integer;
begin
  Result := LineHeightForSize(Size) - AscentForSize(Size);
  if Result < 0 then
    Result := 0;
end;

function GlyphRow(C: Char; Row: Integer): Byte;
const
  Digits: array['0'..'9', 0..6] of Byte = (
    (%01110, %10001, %10011, %10101, %11001, %10001, %01110),
    (%00100, %01100, %00100, %00100, %00100, %00100, %01110),
    (%01110, %10001, %00001, %00010, %00100, %01000, %11111),
    (%11110, %00001, %00001, %01110, %00001, %00001, %11110),
    (%00010, %00110, %01010, %10010, %11111, %00010, %00010),
    (%11111, %10000, %11110, %00001, %00001, %10001, %01110),
    (%00110, %01000, %10000, %11110, %10001, %10001, %01110),
    (%11111, %00001, %00010, %00100, %01000, %01000, %01000),
    (%01110, %10001, %10001, %01110, %10001, %10001, %01110),
    (%01110, %10001, %10001, %01111, %00001, %00010, %01100)
  );
  Letters: array['A'..'Z', 0..6] of Byte = (
    (%01110, %10001, %10001, %11111, %10001, %10001, %10001),
    (%11110, %10001, %10001, %11110, %10001, %10001, %11110),
    (%01110, %10001, %10000, %10000, %10000, %10001, %01110),
    (%11110, %10001, %10001, %10001, %10001, %10001, %11110),
    (%11111, %10000, %10000, %11110, %10000, %10000, %11111),
    (%11111, %10000, %10000, %11110, %10000, %10000, %10000),
    (%01110, %10001, %10000, %10111, %10001, %10001, %01110),
    (%10001, %10001, %10001, %11111, %10001, %10001, %10001),
    (%01110, %00100, %00100, %00100, %00100, %00100, %01110),
    (%00111, %00010, %00010, %00010, %00010, %10010, %01100),
    (%10001, %10010, %10100, %11000, %10100, %10010, %10001),
    (%10000, %10000, %10000, %10000, %10000, %10000, %11111),
    (%10001, %11011, %10101, %10101, %10001, %10001, %10001),
    (%10001, %11001, %10101, %10011, %10001, %10001, %10001),
    (%01110, %10001, %10001, %10001, %10001, %10001, %01110),
    (%11110, %10001, %10001, %11110, %10000, %10000, %10000),
    (%01110, %10001, %10001, %10001, %10101, %10010, %01101),
    (%11110, %10001, %10001, %11110, %10100, %10010, %10001),
    (%01111, %10000, %10000, %01110, %00001, %00001, %11110),
    (%11111, %00100, %00100, %00100, %00100, %00100, %00100),
    (%10001, %10001, %10001, %10001, %10001, %10001, %01110),
    (%10001, %10001, %10001, %10001, %10001, %01010, %00100),
    (%10001, %10001, %10001, %10101, %10101, %10101, %01010),
    (%10001, %10001, %01010, %00100, %01010, %10001, %10001),
    (%10001, %10001, %01010, %00100, %00100, %00100, %00100),
    (%11111, %00001, %00010, %00100, %01000, %10000, %11111)
  );
begin
  if (C >= 'a') and (C <= 'z') then
    C := Chr(Ord(C) - Ord('a') + Ord('A'));
  if (C >= 'A') and (C <= 'Z') then
    Exit(Letters[C, Row]);
  if (C >= '0') and (C <= '9') then
    Exit(Digits[C, Row]);
  case C of
    '.': if Row = 6 then Exit(%00100);
    ',': if Row in [5, 6] then Exit(%00100);
    ':': if Row in [2, 5] then Exit(%00100);
    ';': if Row in [2, 5, 6] then Exit(%00100);
    '-': if Row = 3 then Exit(%11111);
    '/': Exit(1 shl (4 - Row * 5 div 7));
    '(': if Row in [1..5] then Exit(%01000) else Exit(%00100);
    ')': if Row in [1..5] then Exit(%00010) else Exit(%00100);
    '[': if Row in [0, 6] then Exit(%01100) else Exit(%01000);
    ']': if Row in [0, 6] then Exit(%00110) else Exit(%00010);
    '_': if Row = 6 then Exit(%11111);
    '''': if Row in [0, 1] then Exit(%00100);
    '"': if Row in [0, 1] then Exit(%01010);
    '!': if Row <= 4 then Exit(%00100) else if Row = 6 then Exit(%00100);
    '?':
      case Row of
        0: Exit(%01110);
        1: Exit(%10001);
        2: Exit(%00001);
        3: Exit(%00010);
        4: Exit(%00100);
        6: Exit(%00100);
      end;
  end;
  Result := 0;
end;

function TLhtDebugFont.GetGlyph(C: Char; const Style: TLhtFontStyle): TLhtGlyph;
var
  I: Integer;
begin
  Result.Ch := C;
  Result.Style := Style;
  Result.Width := GlyphW;
  Result.Height := GlyphH;
  Result.Advance := AdvanceForSize(Style.Size);
  Result.Scale := ScaleForSize(Style.Size);
  for I := 0 to High(Result.Rows) do
    Result.Rows[I] := 0;
  if C = ' ' then
    Exit;
  for I := 0 to GlyphH - 1 do
    Result.Rows[I] := GlyphRow(C, I);
end;

function TLhtDebugFont.MeasureText(const S: string; const Style: TLhtFontStyle): Integer;
begin
  Result := Length(S) * AdvanceForSize(Style.Size);
end;

function TLhtDebugFont.SpaceAdvance(const Style: TLhtFontStyle): Integer;
begin
  Result := AdvanceForSize(Style.Size);
end;

function TLhtDebugFont.Ascent(const Style: TLhtFontStyle): Integer;
begin
  Result := AscentForSize(Style.Size);
end;

function TLhtDebugFont.Descent(const Style: TLhtFontStyle): Integer;
begin
  Result := DescentForSize(Style.Size);
end;

function TLhtDebugFont.LineHeight(const Style: TLhtFontStyle): Integer;
begin
  Result := LineHeightForSize(Style.Size);
end;

end.
