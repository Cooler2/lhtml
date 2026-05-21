unit LhtStyle;

{$mode objfpc}{$H+}

interface

uses
  LhtDom;

type
  TLhtStyleRule = record
    ClassName: string;
    Attrs: array of TAttr;
  end;

  TLhtStyleSheet = class
  public
    Rules: array of TLhtStyleRule;
    procedure Clear;
    function AddRule(const AClassName: string): Integer;
    procedure AddAttr(RuleIndex: Integer; const Name, Value: string);
    function FindRule(const AClassName: string): Integer;
  end;

procedure ParseStyleSheetText(const S: string; Sheet: TLhtStyleSheet);
procedure CollectStyleSheets(Root: TNode; Sheet: TLhtStyleSheet);
function StyleSheetToText(Sheet: TLhtStyleSheet): string;

implementation

uses
  SysUtils, LhtValidation;

procedure TLhtStyleSheet.Clear;
begin
  SetLength(Rules, 0);
end;

function TLhtStyleSheet.AddRule(const AClassName: string): Integer;
begin
  Result := Length(Rules);
  SetLength(Rules, Result + 1);
  Rules[Result].ClassName := AClassName;
  SetLength(Rules[Result].Attrs, 0);
end;

procedure TLhtStyleSheet.AddAttr(RuleIndex: Integer; const Name, Value: string);
var
  N: Integer;
begin
  if (RuleIndex < 0) or (RuleIndex > High(Rules)) then
    raise Exception.Create('Style rule index out of range');
  N := Length(Rules[RuleIndex].Attrs);
  SetLength(Rules[RuleIndex].Attrs, N + 1);
  Rules[RuleIndex].Attrs[N].Name := Name;
  Rules[RuleIndex].Attrs[N].Value := Value;
end;

function TLhtStyleSheet.FindRule(const AClassName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Rules) do
    if Rules[I].ClassName = AClassName then
      Exit(I);
  Result := -1;
end;

function IsNameChar(C: Char): Boolean;
begin
  Result := (C in ['A'..'Z']) or (C in ['a'..'z']) or
    (C in ['0'..'9']) or (C in ['_', '-']);
end;

procedure SkipSpaces(const S: string; var Pos: Integer);
begin
  while (Pos <= Length(S)) and (S[Pos] in [' ', #9, #10, #13]) do
    Inc(Pos);
end;

function ReadName(const S: string; var Pos: Integer): string;
var
  Start: Integer;
begin
  Start := Pos;
  while (Pos <= Length(S)) and IsNameChar(S[Pos]) do
    Inc(Pos);
  Result := Copy(S, Start, Pos - Start);
end;

function ReadValue(const S: string; var Pos: Integer): string;
var
  Start: Integer;
  Quote: Char;
begin
  SkipSpaces(S, Pos);
  if (Pos <= Length(S)) and (S[Pos] in ['"', '''']) then
  begin
    Quote := S[Pos];
    Inc(Pos);
    Start := Pos;
    while (Pos <= Length(S)) and (S[Pos] <> Quote) do
      Inc(Pos);
    if Pos > Length(S) then
      raise Exception.Create('Unterminated quoted style value');
    Result := Copy(S, Start, Pos - Start);
    Inc(Pos);
  end
  else
  begin
    Start := Pos;
    while (Pos <= Length(S)) and not (S[Pos] in [';', '}']) do
      Inc(Pos);
    Result := Trim(Copy(S, Start, Pos - Start));
  end;
end;

procedure ParseStyleSheetText(const S: string; Sheet: TLhtStyleSheet);
var
  Pos: Integer;
  ClassName: string;
  AttrName: string;
  AttrValue: string;
  Rule: Integer;
  Closed: Boolean;
begin
  Pos := 1;
  while Pos <= Length(S) do
  begin
    SkipSpaces(S, Pos);
    if Pos > Length(S) then
      Break;
    if S[Pos] <> '.' then
      raise Exception.CreateFmt('Expected class selector at style byte %d', [Pos]);
    Inc(Pos);
    ClassName := ReadName(S, Pos);
    if ClassName = '' then
      raise Exception.CreateFmt('Expected class name at style byte %d', [Pos]);
    SkipSpaces(S, Pos);
    if (Pos > Length(S)) or (S[Pos] <> '{') then
      raise Exception.CreateFmt('Expected "{" after .%s', [ClassName]);
    Inc(Pos);
    Rule := Sheet.AddRule(ClassName);
    Closed := False;

    while Pos <= Length(S) do
    begin
      SkipSpaces(S, Pos);
      if (Pos <= Length(S)) and (S[Pos] = '}') then
      begin
        Inc(Pos);
        Closed := True;
        Break;
      end;
      AttrName := ReadName(S, Pos);
      if AttrName = '' then
        raise Exception.CreateFmt('Expected style property at byte %d', [Pos]);
      ValidateMiniAttributeName(AttrName, False);
      SkipSpaces(S, Pos);
      if (Pos > Length(S)) or not (S[Pos] in ['=', ':']) then
        raise Exception.CreateFmt('Expected "=" after style property %s', [AttrName]);
      Inc(Pos);
      AttrValue := ReadValue(S, Pos);
      ValidateMiniAttributeValue(AttrName, AttrValue);
      Sheet.AddAttr(Rule, AttrName, AttrValue);
      SkipSpaces(S, Pos);
      if (Pos <= Length(S)) and (S[Pos] = ';') then
        Inc(Pos);
    end;
    if not Closed then
      raise Exception.CreateFmt('Unterminated style rule .%s', [ClassName]);
  end;
end;

procedure CollectStyleSheets(Root: TNode; Sheet: TLhtStyleSheet);
var
  I: Integer;
begin
  if (Root.Kind = nkElement) and (Root.Name = 'style') then
  begin
    for I := 0 to High(Root.Children) do
      if Root.Children[I].Kind = nkText then
        ParseStyleSheetText(Root.Children[I].Text, Sheet);
    Exit;
  end;
  for I := 0 to High(Root.Children) do
    CollectStyleSheets(Root.Children[I], Sheet);
end;

function StyleSheetToText(Sheet: TLhtStyleSheet): string;
var
  I, J: Integer;
begin
  Result := '';
  for I := 0 to High(Sheet.Rules) do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + '.' + Sheet.Rules[I].ClassName + ' {';
    for J := 0 to High(Sheet.Rules[I].Attrs) do
    begin
      if J > 0 then
        Result := Result + ';';
      Result := Result + ' ' + Sheet.Rules[I].Attrs[J].Name + '=' +
        Sheet.Rules[I].Attrs[J].Value;
    end;
    Result := Result + ' }';
  end;
end;

end.
