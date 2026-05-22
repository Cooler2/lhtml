unit LhtValidation;

{$mode objfpc}{$H+}

interface

procedure ValidateMiniElementName(const Name: string);
procedure ValidateMiniAttributeName(const Name: string; AllowFontShorthand: Boolean);
procedure ValidateMiniAttributeValue(const Name, Value: string);
function IsMiniBareTag(const Name: string): Boolean;

implementation

uses
  SysUtils, LhtRenderTypes, LhtTokenTable;

function IsUIntLiteral(const S: string): Boolean;
var
  I: Integer;
  Value: QWord;
begin
  Result := False;
  if S = '' then
    Exit;
  Value := 0;
  for I := 1 to Length(S) do
  begin
    if not (S[I] in ['0'..'9']) then
      Exit;
    Value := Value * 10 + Ord(S[I]) - Ord('0');
    if Value > High(Cardinal) then
      Exit;
  end;
  Result := True;
end;

function IsFontFaceValue(const S: string): Boolean;
var
  L: string;
begin
  L := LowerCase(S);
  Result := (L = 'default') or (L = 'sans') or (L = 'serif') or (L = 'mono');
end;

function IsFontSizeValue(const S: string): Boolean;
var
  L: string;
begin
  L := LowerCase(S);
  Result := (L = 'tiny') or (L = 'small') or (L = 'normal') or
    (L = 'large') or (L = 'xlarge') or (L = 'xxlarge');
end;

procedure ValidateMiniElementName(const Name: string);
begin
  if (Name = 'style') or (Name = 'script') or (Name = 'library') then
    Exit;
  if (Name = 'p') or (Name = 'br') then
    TokenDefForNameInStream(Name, tkCommand, tsDom)
  else if (Name = 'body') or (Name = 'block') or (Name = 'row') or
    (Name = 'spacer') or (Name = 'span') or (Name = 'a') or
    (Name = 'table') or (Name = 'col') or (Name = 'tr') or (Name = 'td') then
    TokenDefForNameInStream(Name, tkElement, tsDom)
  else
    TokenDefForNameInStream(Name, tkElement, tsDoc);
end;

procedure ValidateMiniAttributeName(const Name: string; AllowFontShorthand: Boolean);
begin
  if AllowFontShorthand and (Name = 'font') then
    Exit;
  if Name = 'interface' then
    Exit;
  TokenDefForName(Name, tkAttr);
end;

procedure ValidateFontShorthand(const Value: string);
var
  Start: Integer;
  Pos: Integer;
  Part: string;
begin
  Pos := 1;
  while Pos <= Length(Value) + 1 do
  begin
    Start := Pos;
    while (Pos <= Length(Value)) and (Value[Pos] <> ',') do
      Inc(Pos);
    Part := Trim(Copy(Value, Start, Pos - Start));
    if (Part <> '') and (not IsFontFaceValue(Part)) and
      (not IsFontSizeValue(Part)) then
      raise Exception.CreateFmt('Attribute font got unknown font value "%s"', [Part]);
    Inc(Pos);
  end;
end;

procedure ValidateMiniAttributeValue(const Name, Value: string);
var
  Color: TRgb;
begin
  if Name = 'font' then
  begin
    ValidateFontShorthand(Value);
    Exit;
  end;
  if Name = 'interface' then
    Exit;
  if IsIntegerAttr(Name) and (not IsUIntLiteral(Value)) then
    raise Exception.CreateFmt('Attribute %s expects unsigned integer, got "%s"',
      [Name, Value]);
  if IsColorAttr(Name) and (not TryParseColor(Value, Color)) then
    raise Exception.CreateFmt('Attribute %s expects color, got "%s"', [Name, Value]);
  if IsFontFaceAttr(Name) and (not IsFontFaceValue(Value)) then
    raise Exception.CreateFmt('Attribute %s expects fontFace enum, got "%s"',
      [Name, Value]);
  if IsFontSizeAttr(Name) and (not IsFontSizeValue(Value)) then
    raise Exception.CreateFmt('Attribute %s expects fontSize enum, got "%s"',
      [Name, Value]);
end;

function IsMiniBareTag(const Name: string): Boolean;
begin
  Result := (Name = 'meta') or (Name = 'spacer') or
    (Name = 'p') or (Name = 'br') or (Name = 'col');
end;

end.
