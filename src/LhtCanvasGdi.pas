unit LhtCanvasGdi;

{$mode objfpc}{$H+}

interface

uses
  Windows, Classes, LhtRenderTypes;

type
  TLhtGdiCanvas = class(TLhtCanvas)
  private
    FWidth: Integer;
    FHeight: Integer;
    FDC: HDC;
    FBitmap: HBITMAP;
    FOldBitmap: HGDIOBJ;
    FBits: Pointer;
    procedure SelectFontForStyle(const Style: TLhtFontStyle; out OldFont: HGDIOBJ;
      out Font: HFONT);
  public
    constructor Create(AWidth, AHeight: Integer);
    destructor Destroy; override;

    procedure Clear(Color: TRgb); override;
    procedure FillRect(X, Y, W, H: Integer; Color: TRgb); override;
    procedure StrokeRect(X, Y, W, H: Integer; Color: TRgb); override;
    procedure DrawGlyph(X, Y: Integer; const Glyph: TLhtGlyph; Color: TRgb); override;
    procedure DrawTextRun(X, BaselineY: Integer; const S: string;
      const Style: TLhtFontStyle; Color: TRgb; Text: TLhtTextMetrics); override;

    procedure SaveBmp(const FileName: string);
  end;

  TLhtGdiTextMetrics = class(TLhtTextMetrics)
  private
    FDC: HDC;
    procedure SelectFontForStyle(const Style: TLhtFontStyle; out OldFont: HGDIOBJ;
      out Font: HFONT);
  public
    constructor Create;
    destructor Destroy; override;

    function GetGlyph(C: Char; const Style: TLhtFontStyle): TLhtGlyph; override;
    function MeasureText(const S: string; const Style: TLhtFontStyle): Integer; override;
    function SpaceAdvance(const Style: TLhtFontStyle): Integer; override;
    function Ascent(const Style: TLhtFontStyle): Integer; override;
    function Descent(const Style: TLhtFontStyle): Integer; override;
    function LineHeight(const Style: TLhtFontStyle): Integer; override;
  end;

implementation

uses
  SysUtils;

function ColorRef(Color: TRgb): COLORREF;
begin
  Result := Windows.RGB(Color.R, Color.G, Color.B);
end;

function GdiFontName(const Style: TLhtFontStyle): string;
begin
  case Style.Family of
    lffSerif: Result := 'Times New Roman';
    lffMono: Result := 'Consolas';
  else
    Result := 'Arial';
  end;
end;

function GdiFontHeight(const Style: TLhtFontStyle): Integer;
begin
  case Style.Size of
    lfsTiny: Result := -8;
    lfsSmall: Result := -10;
    lfsLarge: Result := -24;
    lfsXLarge: Result := -32;
    lfsXXLarge: Result := -44;
  else
    Result := -16;
  end;
end;

function CreateFontForStyle(const Style: TLhtFontStyle): HFONT;
begin
  Result := CreateFont(GdiFontHeight(Style), 0, 0, 0, FW_NORMAL, 0, 0, 0,
    DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, ANTIALIASED_QUALITY,
    DEFAULT_PITCH or FF_DONTCARE, PChar(GdiFontName(Style)));
  if Result = 0 then
    raise Exception.Create('CreateFont failed');
end;

constructor TLhtGdiCanvas.Create(AWidth, AHeight: Integer);
var
  Info: BITMAPINFO;
begin
  inherited Create;
  FWidth := AWidth;
  FHeight := AHeight;

  FillChar(Info, SizeOf(Info), 0);
  Info.bmiHeader.biSize := SizeOf(BITMAPINFOHEADER);
  Info.bmiHeader.biWidth := FWidth;
  Info.bmiHeader.biHeight := -FHeight;
  Info.bmiHeader.biPlanes := 1;
  Info.bmiHeader.biBitCount := 32;
  Info.bmiHeader.biCompression := BI_RGB;

  FDC := CreateCompatibleDC(0);
  if FDC = 0 then
    raise Exception.Create('CreateCompatibleDC failed');

  FBitmap := CreateDIBSection(FDC, Info, DIB_RGB_COLORS, FBits, 0, 0);
  if FBitmap = 0 then
    raise Exception.Create('CreateDIBSection failed');

  FOldBitmap := SelectObject(FDC, FBitmap);
  SetBkMode(FDC, TRANSPARENT);
end;

destructor TLhtGdiCanvas.Destroy;
begin
  if FDC <> 0 then
  begin
    if FOldBitmap <> 0 then
      SelectObject(FDC, FOldBitmap);
    if FBitmap <> 0 then
      DeleteObject(FBitmap);
    DeleteDC(FDC);
  end;
  inherited Destroy;
end;

procedure TLhtGdiCanvas.SelectFontForStyle(const Style: TLhtFontStyle;
  out OldFont: HGDIOBJ; out Font: HFONT);
begin
  Font := CreateFontForStyle(Style);
  OldFont := SelectObject(FDC, Font);
end;

procedure TLhtGdiCanvas.Clear(Color: TRgb);
begin
  FillRect(0, 0, FWidth, FHeight, Color);
end;

procedure TLhtGdiCanvas.FillRect(X, Y, W, H: Integer; Color: TRgb);
var
  R: TRect;
  Brush: HBRUSH;
begin
  R.Left := X;
  R.Top := Y;
  R.Right := X + W;
  R.Bottom := Y + H;
  Brush := CreateSolidBrush(ColorRef(Color));
  try
    Windows.FillRect(FDC, R, Brush);
  finally
    DeleteObject(Brush);
  end;
end;

procedure TLhtGdiCanvas.StrokeRect(X, Y, W, H: Integer; Color: TRgb);
var
  Pen, OldPen: HGDIOBJ;
  OldBrush: HGDIOBJ;
begin
  Pen := CreatePen(PS_SOLID, 1, ColorRef(Color));
  OldPen := SelectObject(FDC, Pen);
  OldBrush := SelectObject(FDC, GetStockObject(NULL_BRUSH));
  Rectangle(FDC, X, Y, X + W, Y + H);
  SelectObject(FDC, OldBrush);
  SelectObject(FDC, OldPen);
  DeleteObject(Pen);
end;

procedure TLhtGdiCanvas.DrawGlyph(X, Y: Integer; const Glyph: TLhtGlyph; Color: TRgb);
var
  OldFont: HGDIOBJ;
  Font: HFONT;
  S: string;
begin
  if Glyph.Ch = ' ' then
    Exit;
  SelectFontForStyle(Glyph.Style, OldFont, Font);
  try
    SetTextColor(FDC, ColorRef(Color));
    S := Glyph.Ch;
    TextOut(FDC, X, Y, PChar(S), Length(S));
  finally
    SelectObject(FDC, OldFont);
    DeleteObject(Font);
  end;
end;

procedure TLhtGdiCanvas.DrawTextRun(X, BaselineY: Integer; const S: string;
  const Style: TLhtFontStyle; Color: TRgb; Text: TLhtTextMetrics);
var
  OldFont: HGDIOBJ;
  Font: HFONT;
  OldAlign: UINT;
begin
  if S = '' then
    Exit;
  SelectFontForStyle(Style, OldFont, Font);
  try
    SetTextColor(FDC, ColorRef(Color));
    OldAlign := SetTextAlign(FDC, TA_LEFT or TA_BASELINE);
    TextOut(FDC, X, BaselineY, PChar(S), Length(S));
    SetTextAlign(FDC, OldAlign);
  finally
    SelectObject(FDC, OldFont);
    DeleteObject(Font);
  end;
end;

constructor TLhtGdiTextMetrics.Create;
begin
  inherited Create;
  FDC := CreateCompatibleDC(0);
  if FDC = 0 then
    raise Exception.Create('CreateCompatibleDC failed');
end;

destructor TLhtGdiTextMetrics.Destroy;
begin
  if FDC <> 0 then
    DeleteDC(FDC);
  inherited Destroy;
end;

procedure TLhtGdiTextMetrics.SelectFontForStyle(const Style: TLhtFontStyle;
  out OldFont: HGDIOBJ; out Font: HFONT);
begin
  Font := CreateFontForStyle(Style);
  OldFont := SelectObject(FDC, Font);
end;

function TLhtGdiTextMetrics.GetGlyph(C: Char; const Style: TLhtFontStyle): TLhtGlyph;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Ch := C;
  Result.Style := Style;
  Result.Advance := MeasureText(C, Style);
end;

function TLhtGdiTextMetrics.MeasureText(const S: string; const Style: TLhtFontStyle): Integer;
var
  Size: TSize;
  OldFont: HGDIOBJ;
  Font: HFONT;
begin
  if S = '' then
    Exit(0);
  SelectFontForStyle(Style, OldFont, Font);
  try
    if not GetTextExtentPoint32(FDC, PChar(S), Length(S), Size) then
      raise Exception.Create('GetTextExtentPoint32 failed');
    Result := Size.cx;
  finally
    SelectObject(FDC, OldFont);
    DeleteObject(Font);
  end;
end;

function TLhtGdiTextMetrics.SpaceAdvance(const Style: TLhtFontStyle): Integer;
begin
  Result := MeasureText(' ', Style);
end;

function TLhtGdiTextMetrics.Ascent(const Style: TLhtFontStyle): Integer;
var
  M: TEXTMETRIC;
  OldFont: HGDIOBJ;
  Font: HFONT;
begin
  SelectFontForStyle(Style, OldFont, Font);
  try
    if not GetTextMetrics(FDC, M) then
      raise Exception.Create('GetTextMetrics failed');
    Result := M.tmAscent;
  finally
    SelectObject(FDC, OldFont);
    DeleteObject(Font);
  end;
end;

function TLhtGdiTextMetrics.Descent(const Style: TLhtFontStyle): Integer;
var
  M: TEXTMETRIC;
  OldFont: HGDIOBJ;
  Font: HFONT;
begin
  SelectFontForStyle(Style, OldFont, Font);
  try
    if not GetTextMetrics(FDC, M) then
      raise Exception.Create('GetTextMetrics failed');
    Result := M.tmDescent + M.tmExternalLeading;
  finally
    SelectObject(FDC, OldFont);
    DeleteObject(Font);
  end;
end;

function TLhtGdiTextMetrics.LineHeight(const Style: TLhtFontStyle): Integer;
begin
  Result := Ascent(Style) + Descent(Style);
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

procedure TLhtGdiCanvas.SaveBmp(const FileName: string);
var
  Stream: TFileStream;
  RowSize: Integer;
  ImageSize: Cardinal;
  FileSize: Cardinal;
  X, Y, Pad: Integer;
  Src: PByte;
  B, G, R, Zero: Byte;
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
      Src := PByte(FBits) + Y * FWidth * 4;
      for X := 0 to FWidth - 1 do
      begin
        B := Src^; Inc(Src);
        G := Src^; Inc(Src);
        R := Src^; Inc(Src, 2);
        Stream.WriteBuffer(B, 1);
        Stream.WriteBuffer(G, 1);
        Stream.WriteBuffer(R, 1);
      end;
      for Pad := 1 to RowSize - FWidth * 3 do
        Stream.WriteBuffer(Zero, 1);
    end;
  finally
    Stream.Free;
  end;
end;

end.
