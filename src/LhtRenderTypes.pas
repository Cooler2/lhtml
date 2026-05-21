unit LhtRenderTypes;

{$mode objfpc}{$H+}

interface

type
  TLhtTextMetrics = class;

  TLhtFontFamily = (lffDefault, lffSans, lffSerif, lffMono);
  TLhtFontSize = (lfsTiny, lfsSmall, lfsNormal, lfsLarge, lfsXLarge, lfsXXLarge);

  TLhtFontStyle = record
    Family: TLhtFontFamily;
    Size: TLhtFontSize;
  end;

  TRgb = record
    R, G, B: Byte;
  end;

  TLhtGlyph = record
    Ch: Char;
    Style: TLhtFontStyle;
    Width: Integer;
    Height: Integer;
    Advance: Integer;
    Scale: Integer;
    Rows: array[0..15] of Word;
  end;

  TLhtCanvas = class
  public
    procedure Clear(Color: TRgb); virtual; abstract;
    procedure FillRect(X, Y, W, H: Integer; Color: TRgb); virtual; abstract;
    procedure StrokeRect(X, Y, W, H: Integer; Color: TRgb); virtual; abstract;
    procedure DrawGlyph(X, Y: Integer; const Glyph: TLhtGlyph; Color: TRgb); virtual; abstract;
    procedure DrawTextRun(X, BaselineY: Integer; const S: string;
      const Style: TLhtFontStyle; Color: TRgb; Text: TLhtTextMetrics); virtual;
  end;

  TLhtTextMetrics = class
  public
    function GetGlyph(C: Char; const Style: TLhtFontStyle): TLhtGlyph; virtual; abstract;
    function MeasureText(const S: string; const Style: TLhtFontStyle): Integer; virtual; abstract;
    function SpaceAdvance(const Style: TLhtFontStyle): Integer; virtual; abstract;
    function Ascent(const Style: TLhtFontStyle): Integer; virtual; abstract;
    function Descent(const Style: TLhtFontStyle): Integer; virtual; abstract;
    function LineHeight(const Style: TLhtFontStyle): Integer; virtual; abstract;
  end;

function Rgb(R, G, B: Byte): TRgb;
function TryParseColor(const S: string; out Color: TRgb): Boolean;
function ColorToHex(const Color: TRgb): string;
function RgbTo565(const Color: TRgb): Word;
function Rgb565ToRgb(Value: Word): TRgb;
function DefaultFontStyle: TLhtFontStyle;
function FontFamilyFromString(const S: string; Default: TLhtFontFamily): TLhtFontFamily;
function FontSizeFromString(const S: string; Default: TLhtFontSize): TLhtFontSize;
function FontFamilyToString(Family: TLhtFontFamily): string;
function FontSizeToString(Size: TLhtFontSize): string;

implementation

uses
  SysUtils;

procedure TLhtCanvas.DrawTextRun(X, BaselineY: Integer; const S: string;
  const Style: TLhtFontStyle; Color: TRgb; Text: TLhtTextMetrics);
var
  I, CX, TopY: Integer;
  Glyph: TLhtGlyph;
begin
  CX := X;
  TopY := BaselineY - Text.Ascent(Style);
  for I := 1 to Length(S) do
  begin
    Glyph := Text.GetGlyph(S[I], Style);
    if S[I] <> ' ' then
      DrawGlyph(CX, TopY, Glyph, Color);
    Inc(CX, Glyph.Advance);
  end;
end;

function Rgb(R, G, B: Byte): TRgb;
begin
  Result.R := R;
  Result.G := G;
  Result.B := B;
end;

function HexValue(C: Char; out Value: Byte): Boolean;
begin
  if C in ['0'..'9'] then
  begin
    Value := Ord(C) - Ord('0');
    Exit(True);
  end;
  if C in ['a'..'f'] then
  begin
    Value := Ord(C) - Ord('a') + 10;
    Exit(True);
  end;
  if C in ['A'..'F'] then
  begin
    Value := Ord(C) - Ord('A') + 10;
    Exit(True);
  end;
  Result := False;
end;

function ParseHexByte(const S: string; Pos: Integer; out Value: Byte): Boolean;
var
  Hi, Lo: Byte;
begin
  Result := HexValue(S[Pos], Hi) and HexValue(S[Pos + 1], Lo);
  if Result then
    Value := Hi * 16 + Lo;
end;

function TryParseColor(const S: string; out Color: TRgb): Boolean;
var
  L: string;
  R, G, B: Byte;
begin
  L := LowerCase(Trim(S));
  if L = '' then
    Exit(False);

  if L[1] = '#' then
  begin
    if Length(L) = 4 then
    begin
      Result := HexValue(L[2], R) and HexValue(L[3], G) and HexValue(L[4], B);
      if Result then
        Color := Rgb(R * 17, G * 17, B * 17);
      Exit;
    end;
    if Length(L) = 7 then
    begin
      Result := ParseHexByte(L, 2, R) and ParseHexByte(L, 4, G) and
        ParseHexByte(L, 6, B);
      if Result then
        Color := Rgb(R, G, B);
      Exit;
    end;
    Exit(False);
  end;

  Result := True;
  if L = 'black' then
    Color := Rgb(0, 0, 0)
  else if L = 'white' then
    Color := Rgb(255, 255, 255)
  else if L = 'red' then
    Color := Rgb(192, 32, 32)
  else if L = 'green' then
    Color := Rgb(32, 144, 64)
  else if L = 'blue' then
    Color := Rgb(32, 80, 192)
  else if L = 'navy' then
    Color := Rgb(0, 48, 128)
  else if L = 'gray' then
    Color := Rgb(128, 128, 128)
  else if L = 'silver' then
    Color := Rgb(192, 192, 192)
  else if L = 'yellow' then
    Color := Rgb(232, 192, 48)
  else
    Result := False;
end;

function ColorToHex(const Color: TRgb): string;
begin
  Result := '#' + IntToHex(Color.R, 2) + IntToHex(Color.G, 2) +
    IntToHex(Color.B, 2);
end;

function RgbTo565(const Color: TRgb): Word;
begin
  Result := ((Word(Color.R) shr 3) shl 11) or
    ((Word(Color.G) shr 2) shl 5) or (Word(Color.B) shr 3);
end;

function Rgb565ToRgb(Value: Word): TRgb;
begin
  Result.R := ((Value shr 11) and $1F) * 255 div 31;
  Result.G := ((Value shr 5) and $3F) * 255 div 63;
  Result.B := (Value and $1F) * 255 div 31;
end;

function DefaultFontStyle: TLhtFontStyle;
begin
  Result.Family := lffSans;
  Result.Size := lfsNormal;
end;

function FontFamilyFromString(const S: string; Default: TLhtFontFamily): TLhtFontFamily;
var
  L: string;
begin
  L := LowerCase(S);
  if (L = '') or (L = 'default') then
    Result := lffDefault
  else if L = 'sans' then
    Result := lffSans
  else if L = 'serif' then
    Result := lffSerif
  else if L = 'mono' then
    Result := lffMono
  else
    Result := Default;
end;

function FontFamilyToString(Family: TLhtFontFamily): string;
begin
  case Family of
    lffDefault: Result := 'default';
    lffSerif: Result := 'serif';
    lffMono: Result := 'mono';
  else
    Result := 'sans';
  end;
end;

function FontSizeFromString(const S: string; Default: TLhtFontSize): TLhtFontSize;
var
  L: string;
begin
  L := LowerCase(S);
  if L = 'tiny' then
    Result := lfsTiny
  else if L = 'small' then
    Result := lfsSmall
  else if (L = '') or (L = 'normal') then
    Result := lfsNormal
  else if L = 'large' then
    Result := lfsLarge
  else if L = 'xlarge' then
    Result := lfsXLarge
  else if L = 'xxlarge' then
    Result := lfsXXLarge
  else
    Result := Default;
end;

function FontSizeToString(Size: TLhtFontSize): string;
begin
  case Size of
    lfsTiny: Result := 'tiny';
    lfsSmall: Result := 'small';
    lfsLarge: Result := 'large';
    lfsXLarge: Result := 'xlarge';
    lfsXXLarge: Result := 'xxlarge';
  else
    Result := 'normal';
  end;
end;

end.
