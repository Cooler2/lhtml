unit LhtRender;

{$mode objfpc}{$H+}

interface

uses
  LhtDom, LhtRenderTypes, LhtDisplayList;

procedure BuildMiniDisplayList(Root: TNode; DisplayList: TLhtDisplayList;
  Text: TLhtTextMetrics; Width, Height: Integer);
procedure RenderMini(Root: TNode; Canvas: TLhtCanvas; Text: TLhtTextMetrics;
  Width, Height: Integer);
procedure RenderMiniToBmp(Root: TNode; const FileName: string);
procedure RenderMiniToGdiBmp(Root: TNode; const FileName: string);

implementation

uses
  SysUtils, LhtCanvasBmp, LhtDebugFont, LhtCanvasGdi, LhtStyle;

const
  CanvasW = 640;
  CanvasH = 720;
  PageMargin = 16;

type
  TInlineRun = record
    X: Integer;
    Text: string;
    Style: TLhtFontStyle;
    Color: TRgb;
  end;

  TInlineLine = record
    Runs: array of TInlineRun;
    Width: Integer;
    Ascent: Integer;
    Descent: Integer;
  end;

  TLhtBoxStyle = record
    Padding: Integer;
    BorderWidth: Integer;
    BorderColor: TRgb;
    HasBackground: Boolean;
    BackgroundColor: TRgb;
  end;

  TLhtResolvedAttrs = record
    ClassName: string;
    Width: Integer;
    Height: Integer;
    TextStyle: TLhtFontStyle;
    TextColor: TRgb;
    BoxStyle: TLhtBoxStyle;
  end;

function AttrValue(Node: TNode; const Name, Default: string): string;
var
  I: Integer;
begin
  for I := 0 to High(Node.Attrs) do
    if Node.Attrs[I].Name = Name then
      Exit(Node.Attrs[I].Value);
  Result := Default;
end;

function AttrInt(Node: TNode; const Name: string; Default: Integer): Integer;
var
  Code: Integer;
  S: string;
begin
  S := AttrValue(Node, Name, '');
  if S = '' then
    Exit(Default);
  Val(S, Result, Code);
  if Code <> 0 then
    Result := Default;
end;

function AttrColor(Node: TNode; const Name: string; Default: TRgb): TRgb;
var
  S: string;
begin
  S := AttrValue(Node, Name, '');
  if (S = '') or (not TryParseColor(S, Result)) then
    Result := Default;
end;

function HasAttr(Node: TNode; const Name: string): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(Node.Attrs) do
    if Node.Attrs[I].Name = Name then
      Exit(True);
  Result := False;
end;

function ClampAvailWidth(Width: Integer): Integer;
begin
  if Width < 0 then
    Result := 0
  else
    Result := Width;
end;

function ClampBoxWidth(DeclaredWidth, AvailW: Integer): Integer;
begin
  AvailW := ClampAvailWidth(AvailW);
  Result := DeclaredWidth;
  if Result < 40 then
    Result := 40;
  if Result > AvailW then
    Result := AvailW;
end;

function NonNegativeAttrInt(Node: TNode; const Name: string; Default: Integer): Integer;
begin
  Result := AttrInt(Node, Name, Default);
  if Result < 0 then
    Result := 0;
end;

function DefaultBoxStyle: TLhtBoxStyle;
begin
  Result.Padding := 8;
  Result.BorderWidth := 1;
  Result.BorderColor := Rgb(216, 220, 225);
  Result.HasBackground := False;
  Result.BackgroundColor := Rgb(250, 250, 248);
end;

procedure ApplyAttrToResolved(const Attr: TAttr; var Resolved: TLhtResolvedAttrs);
var
  ParentFamily: TLhtFontFamily;
begin
  if Attr.Name = 'fontFace' then
  begin
    ParentFamily := Resolved.TextStyle.Family;
    Resolved.TextStyle.Family := FontFamilyFromString(Attr.Value, Resolved.TextStyle.Family);
    if Resolved.TextStyle.Family = lffDefault then
      Resolved.TextStyle.Family := ParentFamily;
  end
  else if Attr.Name = 'fontSize' then
    Resolved.TextStyle.Size := FontSizeFromString(Attr.Value, Resolved.TextStyle.Size)
  else if Attr.Name = 'color' then
    TryParseColor(Attr.Value, Resolved.TextColor)
  else if Attr.Name = 'padding' then
  begin
    Resolved.BoxStyle.Padding := StrToIntDef(Attr.Value, Resolved.BoxStyle.Padding);
    if Resolved.BoxStyle.Padding < 0 then
      Resolved.BoxStyle.Padding := 0;
  end
  else if Attr.Name = 'borderWidth' then
  begin
    Resolved.BoxStyle.BorderWidth := StrToIntDef(Attr.Value,
      Resolved.BoxStyle.BorderWidth);
    if Resolved.BoxStyle.BorderWidth < 0 then
      Resolved.BoxStyle.BorderWidth := 0;
  end
  else if Attr.Name = 'border' then
    TryParseColor(Attr.Value, Resolved.BoxStyle.BorderColor)
  else if Attr.Name = 'background' then
  begin
    Resolved.BoxStyle.HasBackground := True;
    TryParseColor(Attr.Value, Resolved.BoxStyle.BackgroundColor);
  end
  else if Attr.Name = 'width' then
    Resolved.Width := StrToIntDef(Attr.Value, Resolved.Width)
  else if Attr.Name = 'height' then
    Resolved.Height := StrToIntDef(Attr.Value, Resolved.Height);
end;

procedure ApplyClassAttrs(const ClassName: string; Sheet: TLhtStyleSheet;
  var Resolved: TLhtResolvedAttrs);
var
  Pos: Integer;
  Start: Integer;
  Name: string;
  Rule: Integer;
  I: Integer;
begin
  if Sheet = nil then
    Exit;
  Pos := 1;
  while Pos <= Length(ClassName) do
  begin
    while (Pos <= Length(ClassName)) and (ClassName[Pos] = ' ') do
      Inc(Pos);
    Start := Pos;
    while (Pos <= Length(ClassName)) and (ClassName[Pos] <> ' ') do
      Inc(Pos);
    Name := Copy(ClassName, Start, Pos - Start);
    if Name <> '' then
    begin
      Rule := Sheet.FindRule(Name);
      if Rule >= 0 then
        for I := 0 to High(Sheet.Rules[Rule].Attrs) do
          ApplyAttrToResolved(Sheet.Rules[Rule].Attrs[I], Resolved);
    end;
  end;
end;

function ResolveAttrs(Node: TNode; const ParentStyle: TLhtFontStyle;
  ParentColor: TRgb; Sheet: TLhtStyleSheet): TLhtResolvedAttrs;
var
  I: Integer;
begin
  Result.ClassName := AttrValue(Node, 'class', '');
  Result.Width := -1;
  Result.Height := -1;
  Result.TextStyle := ParentStyle;
  Result.TextColor := ParentColor;
  Result.BoxStyle := DefaultBoxStyle;

  if Result.ClassName <> '' then
    ApplyClassAttrs(Result.ClassName, Sheet, Result);

  for I := 0 to High(Node.Attrs) do
    ApplyAttrToResolved(Node.Attrs[I], Result);
end;

function ResolveAttrsFromBase(Node: TNode; const Base: TLhtResolvedAttrs;
  Sheet: TLhtStyleSheet): TLhtResolvedAttrs;
var
  I: Integer;
begin
  Result := Base;
  Result.ClassName := AttrValue(Node, 'class', '');
  Result.Width := -1;
  Result.Height := -1;

  if Result.ClassName <> '' then
    ApplyClassAttrs(Result.ClassName, Sheet, Result);

  for I := 0 to High(Node.Attrs) do
    ApplyAttrToResolved(Node.Attrs[I], Result);
end;

function InnerBoxSize(OuterSize: Integer; const BoxStyle: TLhtBoxStyle): Integer;
begin
  Result := OuterSize - 2 * (BoxStyle.Padding + BoxStyle.BorderWidth);
  if Result < 0 then
    Result := 0;
end;

procedure AddBorder(DisplayList: TLhtDisplayList; Owner: TNode; X, Y, W, H: Integer;
  const BoxStyle: TLhtBoxStyle);
var
  I: Integer;
begin
  for I := 0 to BoxStyle.BorderWidth - 1 do
  begin
    if (W - I * 2 <= 0) or (H - I * 2 <= 0) then
      Exit;
    DisplayList.AddStrokeRect(Owner, X, Y, I, I, W - I * 2, H - I * 2,
      BoxStyle.BorderColor);
  end;
end;

function FindElement(Node: TNode; const Name: string): TNode;
var
  I: Integer;
begin
  if (Node.Kind = nkElement) and (Node.Name = Name) then
    Exit(Node);
  for I := 0 to High(Node.Children) do
  begin
    Result := FindElement(Node.Children[I], Name);
    if Result <> nil then
      Exit;
  end;
  Result := nil;
end;

procedure ClearLine(var Line: TInlineLine);
begin
  SetLength(Line.Runs, 0);
  Line.Width := 0;
  Line.Ascent := 0;
  Line.Descent := 0;
end;

procedure AddRun(var Line: TInlineLine; TextMetrics: TLhtTextMetrics;
  const S: string; const Style: TLhtFontStyle; Color: TRgb; X: Integer);
var
  N: Integer;
  A, D: Integer;
begin
  if S = '' then
    Exit;
  N := Length(Line.Runs);
  SetLength(Line.Runs, N + 1);
  Line.Runs[N].X := X;
  Line.Runs[N].Text := S;
  Line.Runs[N].Style := Style;
  Line.Runs[N].Color := Color;
  Line.Width := X + TextMetrics.MeasureText(S, Style);

  A := TextMetrics.Ascent(Style);
  D := TextMetrics.Descent(Style);
  if A > Line.Ascent then
    Line.Ascent := A;
  if D > Line.Descent then
    Line.Descent := D;
end;

procedure FlushLine(DisplayList: TLhtDisplayList; TextMetrics: TLhtTextMetrics;
  Owner: TNode; OriginX, OriginY: Integer; var Line: TInlineLine;
  BaseX: Integer; var CY: Integer);
var
  I: Integer;
  BaselineY: Integer;
begin
  if Length(Line.Runs) = 0 then
    Exit;

  BaselineY := CY + Line.Ascent;
  for I := 0 to High(Line.Runs) do
    DisplayList.AddTextRun(Owner, OriginX, OriginY, BaseX + Line.Runs[I].X,
      BaselineY,
      Line.Runs[I].Text, Line.Runs[I].Style, Line.Runs[I].Color);

  Inc(CY, Line.Ascent + Line.Descent);
  ClearLine(Line);
end;

function NextWord(const S: string; var Pos: Integer): string;
var
  Start: Integer;
begin
  while (Pos <= Length(S)) and (S[Pos] = ' ') do
    Inc(Pos);
  Start := Pos;
  while (Pos <= Length(S)) and (S[Pos] <> ' ') do
    Inc(Pos);
  Result := Copy(S, Start, Pos - Start);
end;

function NoSpaceBefore(const S: string): Boolean;
begin
  Result := (Length(S) > 0) and (S[1] in ['.', ',', ':', ';', '!', '?', ')', ']']);
end;

procedure NewLine(DisplayList: TLhtDisplayList; Text: TLhtTextMetrics;
  Owner: TNode; OriginX, OriginY: Integer; var Line: TInlineLine;
  BaseX: Integer; var CX, CY: Integer; Extra: Integer);
begin
  FlushLine(DisplayList, Text, Owner, OriginX, OriginY, Line, BaseX, CY);
  CX := 0;
  Inc(CY, Extra);
end;

procedure RenderInlineNode(DisplayList: TLhtDisplayList; Text: TLhtTextMetrics; Node: TNode;
  Owner: TNode; OriginX, OriginY, BaseX, MaxW: Integer; var CX, CY: Integer;
  var NeedSpace: Boolean; var Line: TInlineLine;
  const Style: TLhtFontStyle; Color: TRgb; Sheet: TLhtStyleSheet); forward;

procedure RenderInlineText(DisplayList: TLhtDisplayList; Text: TLhtTextMetrics;
  const S: string; Owner: TNode; OriginX, OriginY, BaseX, MaxW: Integer;
  var CX, CY: Integer; var NeedSpace: Boolean; var Line: TInlineLine;
  const Style: TLhtFontStyle; Color: TRgb);
var
  Pos: Integer;
  Word: string;
  W: Integer;
  SpaceW: Integer;
begin
  Pos := 1;
  while Pos <= Length(S) do
  begin
    Word := NextWord(S, Pos);
    if Word = '' then
      Break;
    W := Text.MeasureText(Word, Style);
    SpaceW := 0;
    if NeedSpace and (not NoSpaceBefore(Word)) then
    begin
      SpaceW := Text.SpaceAdvance(Style);
      if CX + SpaceW + W > MaxW then
      begin
        NewLine(DisplayList, Text, Owner, OriginX, OriginY, Line, BaseX, CX,
          CY, 0);
        SpaceW := 0;
      end
      else
        Inc(CX, SpaceW);
    end;
    if (CX > 0) and (CX + W > MaxW) then
      NewLine(DisplayList, Text, Owner, OriginX, OriginY, Line, BaseX, CX,
        CY, 0);
    AddRun(Line, Text, Word, Style, Color, CX);
    Inc(CX, W);
    NeedSpace := True;
  end;
end;

procedure RenderInlineChildren(DisplayList: TLhtDisplayList; Text: TLhtTextMetrics;
  Node: TNode; OriginX, OriginY, BaseX, BaseY, MaxX: Integer;
  const Style: TLhtFontStyle; Color: TRgb; Sheet: TLhtStyleSheet;
  var UsedH: Integer);
var
  I: Integer;
  CX, CY: Integer;
  NeedSpace: Boolean;
  Line: TInlineLine;
begin
  CX := 0;
  CY := BaseY;
  NeedSpace := False;
  ClearLine(Line);
  for I := 0 to High(Node.Children) do
    RenderInlineNode(DisplayList, Text, Node.Children[I], Node, OriginX, OriginY,
      BaseX, MaxX, CX, CY, NeedSpace, Line, Style, Color, Sheet);
  FlushLine(DisplayList, Text, Node, OriginX, OriginY, Line, BaseX, CY);
  UsedH := CY - BaseY;
  if UsedH = 0 then
    UsedH := Text.LineHeight(Style);
end;

procedure RenderInlineNode(DisplayList: TLhtDisplayList; Text: TLhtTextMetrics; Node: TNode;
  Owner: TNode; OriginX, OriginY, BaseX, MaxW: Integer; var CX, CY: Integer;
  var NeedSpace: Boolean; var Line: TInlineLine;
  const Style: TLhtFontStyle; Color: TRgb; Sheet: TLhtStyleSheet);
var
  I: Integer;
  LinkColor: TRgb;
  Resolved: TLhtResolvedAttrs;
begin
  if Node.Kind = nkText then
  begin
    RenderInlineText(DisplayList, Text, Node.Text, Owner, OriginX, OriginY,
      BaseX, MaxW, CX, CY, NeedSpace, Line, Style, Color);
    Exit;
  end;

  Resolved := ResolveAttrs(Node, Style, Color, Sheet);

  if Node.Name = 'p' then
  begin
    NewLine(DisplayList, Text, Owner, OriginX, OriginY, Line, BaseX, CX, CY,
      12);
    NeedSpace := False;
    Exit;
  end;
  if Node.Name = 'br' then
  begin
    NewLine(DisplayList, Text, Owner, OriginX, OriginY, Line, BaseX, CX, CY,
      0);
    NeedSpace := False;
    Exit;
  end;

  LinkColor := Resolved.TextColor;
  if Node.Name = 'a' then
    LinkColor := AttrColor(Node, 'color', Rgb(0, 72, 180));

  for I := 0 to High(Node.Children) do
    RenderInlineNode(DisplayList, Text, Node.Children[I], Owner, OriginX,
      OriginY, BaseX, MaxW, CX, CY, NeedSpace, Line, Resolved.TextStyle,
      LinkColor, Sheet);
end;

function RenderBox(DisplayList: TLhtDisplayList; Text: TLhtTextMetrics; Node: TNode;
  X, Y, AvailW: Integer; const Style: TLhtFontStyle; Color: TRgb;
  Sheet: TLhtStyleSheet; out UsedW: Integer): Integer; forward;

function RenderBlockResolved(DisplayList: TLhtDisplayList; Text: TLhtTextMetrics;
  Node: TNode; X, Y, AvailW: Integer; const Resolved: TLhtResolvedAttrs;
  Sheet: TLhtStyleSheet; out UsedW: Integer): Integer; forward;

function RenderBlock(DisplayList: TLhtDisplayList; Text: TLhtTextMetrics; Node: TNode;
  X, Y, AvailW: Integer; const Style: TLhtFontStyle; Color: TRgb;
  Sheet: TLhtStyleSheet; out UsedW: Integer): Integer;
var
  Resolved: TLhtResolvedAttrs;
begin
  Resolved := ResolveAttrs(Node, Style, Color, Sheet);
  Result := RenderBlockResolved(DisplayList, Text, Node, X, Y, AvailW,
    Resolved, Sheet, UsedW);
end;

function RenderBlockResolved(DisplayList: TLhtDisplayList; Text: TLhtTextMetrics;
  Node: TNode; X, Y, AvailW: Integer; const Resolved: TLhtResolvedAttrs;
  Sheet: TLhtStyleSheet; out UsedW: Integer): Integer;
var
  W, TextH: Integer;
  TextW: Integer;
  TextOffset: Integer;
  StartIndex: Integer;
begin
  if Resolved.Width >= 0 then
    W := ClampBoxWidth(Resolved.Width, AvailW)
  else
    W := ClampBoxWidth(AvailW, AvailW);
  UsedW := W;
  if W <= 0 then
    Exit(0);
  StartIndex := DisplayList.Count;
  TextOffset := Resolved.BoxStyle.Padding + Resolved.BoxStyle.BorderWidth;
  TextW := InnerBoxSize(W, Resolved.BoxStyle);
  RenderInlineChildren(DisplayList, Text, Node, X, Y, TextOffset, TextOffset, TextW,
    Resolved.TextStyle, Resolved.TextColor, Sheet, TextH);
  Result := TextH + TextOffset * 2;
  if Result < 16 + TextOffset * 2 then
    Result := 16 + TextOffset * 2;
  if Resolved.BoxStyle.HasBackground then
    DisplayList.InsertFillRect(StartIndex, Node, X, Y, 0, 0, W, Result,
      Resolved.BoxStyle.BackgroundColor);
  AddBorder(DisplayList, Node, X, Y, W, Result, Resolved.BoxStyle);
end;

function CountRowCells(Node: TNode): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Node.Children) do
    if (Node.Children[I].Kind = nkElement) and (Node.Children[I].Name = 'td') then
      Inc(Result);
end;

function TableColumnCount(Node: TNode): Integer;
var
  I, Cells: Integer;
begin
  Result := 0;
  for I := 0 to High(Node.Children) do
  begin
    if (Node.Children[I].Kind = nkElement) and (Node.Children[I].Name = 'col') then
    begin
      Inc(Result);
      Continue;
    end;
    if (Node.Children[I].Kind = nkElement) and (Node.Children[I].Name = 'tr') then
    begin
      Cells := CountRowCells(Node.Children[I]);
      if Cells > Result then
        Result := Cells;
    end;
  end;
end;

function RenderTable(DisplayList: TLhtDisplayList; Text: TLhtTextMetrics; Node: TNode;
  X, Y, AvailW: Integer; const Style: TLhtFontStyle; Color: TRgb;
  Sheet: TLhtStyleSheet; out UsedW: Integer): Integer;
var
  I, J: Integer;
  W, Cols, ColW, LastColW: Integer;
  CX, CY, RowH, CellH, CellW, ActualCellW: Integer;
  Resolved, RowResolved, CellResolved: TLhtResolvedAttrs;
  Row: TNode;
  RowCells: array of TNode;
  CellCount: Integer;
begin
  Resolved := ResolveAttrs(Node, Style, Color, Sheet);
  if Resolved.Width >= 0 then
    W := ClampBoxWidth(Resolved.Width, AvailW)
  else
    W := ClampBoxWidth(AvailW, AvailW);
  UsedW := W;
  if W <= 0 then
    Exit(0);

  Cols := TableColumnCount(Node);
  if Cols <= 0 then
    Cols := 1;
  ColW := W div Cols;
  if ColW <= 0 then
    ColW := 1;

  CY := Y;
  for I := 0 to High(Node.Children) do
  begin
    Row := Node.Children[I];
    if (Row.Kind <> nkElement) or (Row.Name <> 'tr') then
      Continue;

    RowResolved := ResolveAttrsFromBase(Row, Resolved, Sheet);
    CX := X;
    RowH := 0;
    CellCount := 0;
    SetLength(RowCells, 0);
    for J := 0 to High(Row.Children) do
    begin
      if (Row.Children[J].Kind <> nkElement) or (Row.Children[J].Name <> 'td') then
        Continue;
      SetLength(RowCells, CellCount + 1);
      RowCells[CellCount] := Row.Children[J];
      Inc(CellCount);
      LastColW := X + W - CX;
      CellW := ColW;
      if CellW > LastColW then
        CellW := LastColW;
      CellResolved := ResolveAttrsFromBase(Row.Children[J], RowResolved, Sheet);
      CellH := RenderBlockResolved(DisplayList, Text, Row.Children[J], CX, CY,
        CellW, CellResolved, Sheet, ActualCellW);
      Inc(CX, CellW);
      if CellH > RowH then
        RowH := CellH;
    end;

    if RowH = 0 then
      RowH := Text.LineHeight(Resolved.TextStyle);
    for J := 0 to CellCount - 1 do
      DisplayList.StretchOwnerHeight(RowCells[J], RowH);
    Inc(CY, RowH);
  end;

  Result := CY - Y;
end;

function RenderRow(DisplayList: TLhtDisplayList; Text: TLhtTextMetrics; Node: TNode;
  X, Y, AvailW: Integer; const Style: TLhtFontStyle; Color: TRgb;
  Sheet: TLhtStyleSheet; out UsedW: Integer): Integer;
var
  I, CX, H, ChildW, ChildH: Integer;
  Resolved: TLhtResolvedAttrs;
begin
  Resolved := ResolveAttrs(Node, Style, Color, Sheet);
  CX := X;
  H := 0;
  for I := 0 to High(Node.Children) do
  begin
    ChildH := RenderBox(DisplayList, Text, Node.Children[I], CX, Y,
      AvailW - (CX - X), Resolved.TextStyle, Resolved.TextColor, Sheet, ChildW);
    Inc(CX, ChildW);
    if ChildH > H then
      H := ChildH;
  end;
  UsedW := CX - X;
  if H = 0 then
    H := Text.LineHeight(Resolved.TextStyle);
  Result := H;
end;

function RenderBox(DisplayList: TLhtDisplayList; Text: TLhtTextMetrics; Node: TNode;
  X, Y, AvailW: Integer; const Style: TLhtFontStyle; Color: TRgb;
  Sheet: TLhtStyleSheet; out UsedW: Integer): Integer;
begin
  UsedW := AvailW;
  if Node.Kind = nkText then
    Exit(0);

  if Node.Name = 'block' then
    Exit(RenderBlock(DisplayList, Text, Node, X, Y, AvailW, Style, Color, Sheet,
      UsedW));
  if Node.Name = 'row' then
    Exit(RenderRow(DisplayList, Text, Node, X, Y, AvailW, Style, Color, Sheet,
      UsedW));
  if Node.Name = 'table' then
    Exit(RenderTable(DisplayList, Text, Node, X, Y, AvailW, Style, Color, Sheet,
      UsedW));
  if Node.Name = 'spacer' then
  begin
    with ResolveAttrs(Node, Style, Color, Sheet) do
    begin
      if Width >= 0 then
        UsedW := ClampAvailWidth(Width)
      else
        UsedW := ClampAvailWidth(AvailW);
      if Height >= 0 then
        Result := Height
      else
        Result := AttrInt(Node, 'height', 0);
    end;
    if UsedW > ClampAvailWidth(AvailW) then
      UsedW := ClampAvailWidth(AvailW);
    Exit;
  end;
  Result := 0;
end;

procedure RenderBody(DisplayList: TLhtDisplayList; Text: TLhtTextMetrics; Body: TNode;
  Width: Integer; Sheet: TLhtStyleSheet);
var
  I, Y, UsedW, H: Integer;
  Resolved: TLhtResolvedAttrs;
begin
  Resolved := ResolveAttrs(Body, DefaultFontStyle, Rgb(20, 24, 28), Sheet);
  Y := PageMargin;
  for I := 0 to High(Body.Children) do
  begin
    H := RenderBox(DisplayList, Text, Body.Children[I], PageMargin, Y,
      Width - PageMargin * 2, Resolved.TextStyle, Resolved.TextColor, Sheet,
      UsedW);
    Inc(Y, H);
    if H > 0 then
      Inc(Y, 10);
  end;
end;

procedure BuildMiniDisplayList(Root: TNode; DisplayList: TLhtDisplayList;
  Text: TLhtTextMetrics; Width, Height: Integer);
var
  Body: TNode;
  Sheet: TLhtStyleSheet;
begin
  Body := FindElement(Root, 'body');
  if Body = nil then
    raise Exception.Create('Cannot render: body element not found');

  DisplayList.Clear;
  Sheet := TLhtStyleSheet.Create;
  try
    CollectStyleSheets(Root, Sheet);
    RenderBody(DisplayList, Text, Body, Width, Sheet);
  finally
    Sheet.Free;
  end;
end;

procedure RenderMini(Root: TNode; Canvas: TLhtCanvas; Text: TLhtTextMetrics;
  Width, Height: Integer);
var
  DisplayList: TLhtDisplayList;
  Body: TNode;
  Background: TRgb;
  Sheet: TLhtStyleSheet;
  Resolved: TLhtResolvedAttrs;
begin
  Body := FindElement(Root, 'body');
  Background := Rgb(250, 250, 248);
  if Body <> nil then
  begin
    Sheet := TLhtStyleSheet.Create;
    try
      CollectStyleSheets(Root, Sheet);
      Resolved := ResolveAttrs(Body, DefaultFontStyle, Rgb(20, 24, 28), Sheet);
      if Resolved.BoxStyle.HasBackground then
        Background := Resolved.BoxStyle.BackgroundColor;
    finally
      Sheet.Free;
    end;
  end;
  Canvas.Clear(Background);
  DisplayList := TLhtDisplayList.Create;
  try
    BuildMiniDisplayList(Root, DisplayList, Text, Width, Height);
    DisplayList.Paint(Canvas, Text);
  finally
    DisplayList.Free;
  end;
end;

procedure RenderMiniToBmp(Root: TNode; const FileName: string);
var
  Canvas: TLhtBmpCanvas;
  Font: TLhtDebugFont;
begin
  Canvas := TLhtBmpCanvas.Create(CanvasW, CanvasH);
  try
    Font := TLhtDebugFont.Create;
    try
      RenderMini(Root, Canvas, Font, CanvasW, CanvasH);
      Canvas.SaveBmp(FileName);
    finally
      Font.Free;
    end;
  finally
    Canvas.Free;
  end;
end;

procedure RenderMiniToGdiBmp(Root: TNode; const FileName: string);
var
  Canvas: TLhtGdiCanvas;
  Metrics: TLhtGdiTextMetrics;
begin
  Canvas := TLhtGdiCanvas.Create(CanvasW, CanvasH);
  try
    Metrics := TLhtGdiTextMetrics.Create;
    try
      RenderMini(Root, Canvas, Metrics, CanvasW, CanvasH);
      Canvas.SaveBmp(FileName);
    finally
      Metrics.Free;
    end;
  finally
    Canvas.Free;
  end;
end;

end.
