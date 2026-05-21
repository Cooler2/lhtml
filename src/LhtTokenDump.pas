unit LhtTokenDump;

{$mode objfpc}{$H+}

interface

uses
  Classes, LhtDom;

procedure DumpTokens(Node: TNode; Indent: Integer);
procedure DumpTokensToStream(Node: TNode; Indent: Integer; Stream: TStream);

implementation

uses
  SysUtils, LhtTokenTable, LhtScript;

procedure WriteString(Stream: TStream; const S: string);
begin
  if S <> '' then
    Stream.WriteBuffer(S[1], Length(S));
end;

procedure WriteLine(Stream: TStream; const S: string);
begin
  WriteString(Stream, S);
  WriteString(Stream, LineEnding);
end;

function IsUInt8Literal(const S: string; out Value: Integer): Boolean;
var
  Code: Integer;
begin
  Val(S, Value, Code);
  Result := (Code = 0) and (Value >= 0) and (Value <= 255);
end;

procedure DumpAttrToStream(const Attr: TAttr; Indent: Integer; Stream: TStream);
var
  Pad: string;
  IntValue: Integer;
begin
  Pad := StringOfChar(' ', Indent);

  if IsIntegerAttr(Attr.Name) and IsUInt8Literal(Attr.Value, IntValue) then
    WriteLine(Stream, Pad + 'ATTR ' + TokenNameForAttr(Attr.Name) +
      ' INLINE_BYTE ' + IntToStr(IntValue))
  else if IsIntegerAttr(Attr.Name) then
    WriteLine(Stream, Pad + 'ATTR ' + TokenNameForAttr(Attr.Name) +
      ' INLINE_VALUE uint "' + Attr.Value + '"')
  else if IsColorAttr(Attr.Name) then
    WriteLine(Stream, Pad + 'ATTR ' + TokenNameForAttr(Attr.Name) +
      ' INLINE_VALUE color "' + Attr.Value + '"')
  else if IsFontFaceAttr(Attr.Name) then
    WriteLine(Stream, Pad + 'ATTR ' + TokenNameForAttr(Attr.Name) +
      ' TOKEN value:TFontFace:' + Attr.Value)
  else if IsFontSizeAttr(Attr.Name) then
    WriteLine(Stream, Pad + 'ATTR ' + TokenNameForAttr(Attr.Name) +
      ' TOKEN value:TFontSize:' + Attr.Value)
  else
    WriteLine(Stream, Pad + 'ATTR ' + TokenNameForAttr(Attr.Name) +
      ' INLINE_VALUE string "' + Attr.Value + '"');
end;

procedure DumpTextToStream(Node: TNode; Indent: Integer; Stream: TStream);
begin
  WriteLine(Stream, StringOfChar(' ', Indent) + 'TEXT "' + Node.Text + '"');
end;

procedure DumpScriptToStream(Node: TNode; Indent: Integer; Stream: TStream);
var
  Tokens: TLjsTokenArray;
  I: Integer;
  Pad: string;
begin
  Pad := StringOfChar(' ', Indent);
  WriteLine(Stream, Pad + 'COMMAND SCRIPT_BEGIN');
  Tokens := ParseLjsScriptText(Node.TextContent);
  for I := 0 to High(Tokens) do
  begin
    if (Tokens[I].Kind = ljsDict) and (Tokens[I].Name = 'punct:{') then
      WriteLine(Stream, Pad + '  LJS START')
    else if (Tokens[I].Kind = ljsDict) and (Tokens[I].Name = 'punct:}') then
      WriteLine(Stream, Pad + '  LJS END')
    else
      WriteLine(Stream, Pad + '  LJS ' + LjsTokenDebugName(Tokens[I]));
  end;
  WriteLine(Stream, Pad + 'END SCRIPT');
end;

procedure DumpElementToStream(Node: TNode; Indent: Integer; Stream: TStream);
var
  I: Integer;
  Pad: string;
  Bare: Boolean;
begin
  if Node.Name = '#document' then
  begin
    for I := 0 to High(Node.Children) do
      DumpTokensToStream(Node.Children[I], Indent, Stream);
    Exit;
  end;

  Pad := StringOfChar(' ', Indent);
  if Node.Name = 'style' then
  begin
    WriteLine(Stream, Pad + 'COMMAND STYLE_BEGIN');
    for I := 0 to High(Node.Children) do
      DumpTokensToStream(Node.Children[I], Indent + 2, Stream);
    WriteLine(Stream, Pad + 'END STYLE');
    Exit;
  end;

  if Node.Name = 'script' then
  begin
    DumpScriptToStream(Node, Indent, Stream);
    Exit;
  end;

  if Node.Name = 'body' then
    WriteLine(Stream, Pad + 'COMMAND BODY_BEGIN');

  Bare := IsBareElement(Node.Name);

  if Bare then
    WriteLine(Stream, Pad + TokenNameForElement(Node.Name))
  else
    WriteLine(Stream, Pad + 'START ' + TokenNameForElement(Node.Name));

  for I := 0 to High(Node.Attrs) do
    DumpAttrToStream(Node.Attrs[I], Indent + 2, Stream);

  for I := 0 to High(Node.Children) do
    DumpTokensToStream(Node.Children[I], Indent + 2, Stream);

  if not Bare then
    WriteLine(Stream, Pad + 'END ' + TokenNameForElement(Node.Name));
end;

procedure DumpTokensToStream(Node: TNode; Indent: Integer; Stream: TStream);
begin
  case Node.Kind of
    nkElement: DumpElementToStream(Node, Indent, Stream);
    nkText: DumpTextToStream(Node, Indent, Stream);
  end;
end;

procedure DumpTokens(Node: TNode; Indent: Integer);
var
  Stream: THandleStream;
begin
  Stream := THandleStream.Create(TTextRec(Output).Handle);
  try
    DumpTokensToStream(Node, Indent, Stream);
  finally
    Stream.Free;
  end;
end;

end.
