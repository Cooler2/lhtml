unit LhtBinaryEncode;

{$mode objfpc}{$H+}

interface

uses
  Classes, LhtDom;

procedure EncodeMiniBinary(Root: TNode; Stream: TStream);

implementation

uses
  SysUtils, LhtTokenTable, LhtRenderTypes, LhtStyle, LhtScript;

type
  TDictSet = set of TTokenDictKind;
  TImportState = array[TTokenStreamKind] of TDictSet;

procedure WriteByte(Stream: TStream; B: Byte);
begin
  Stream.WriteBuffer(B, SizeOf(B));
end;

procedure WriteBytes(Stream: TStream; const S: string);
begin
  if Length(S) > 0 then
    Stream.WriteBuffer(S[1], Length(S));
end;

procedure WriteVarUInt(Stream: TStream; Value: Cardinal);
var
  B: Byte;
begin
  repeat
    B := Value and $7F;
    Value := Value shr 7;
    if Value <> 0 then
      B := B or $80;
    WriteByte(Stream, B);
  until Value = 0;
end;

function ParseUInt(const S: string; out Value: Cardinal): Boolean;
var
  I: Integer;
  Digit: Cardinal;
begin
  Result := S <> '';
  Value := 0;
  for I := 1 to Length(S) do
  begin
    if not (S[I] in ['0'..'9']) then
      Exit(False);
    Digit := Ord(S[I]) - Ord('0');
    if Value > (High(Cardinal) - Digit) div 10 then
      Exit(False);
    Value := Value * 10 + Digit;
  end;
end;

procedure WriteInlineString(Stream: TStream; ValueType: Byte; const S: string);
begin
  WriteByte(Stream, TOK_INLINE_VALUE);
  WriteByte(Stream, INLINE_FLAG_USE or ValueType);
  WriteVarUInt(Stream, Length(S));
  WriteBytes(Stream, S);
end;

procedure WriteInlineUInt(Stream: TStream; Value: Cardinal);
begin
  if Value <= 255 then
  begin
    WriteByte(Stream, TOK_INLINE_BYTE);
    WriteByte(Stream, Value);
  end
  else
  begin
    WriteByte(Stream, TOK_INLINE_VALUE);
    WriteByte(Stream, INLINE_FLAG_USE or INLINE_TYPE_UINT);
    WriteVarUInt(Stream, Value);
  end;
end;

procedure WriteInlineColor(Stream: TStream; const S: string);
var
  Color: TRgb;
  PackedColor: Word;
begin
  if not TryParseColor(S, Color) then
    raise Exception.CreateFmt('Attribute expects color, got "%s"', [S]);
  PackedColor := RgbTo565(Color);
  WriteByte(Stream, TOK_INLINE_VALUE);
  WriteByte(Stream, INLINE_FLAG_USE or INLINE_TYPE_COLOR);
  WriteByte(Stream, PackedColor and $FF);
  WriteByte(Stream, PackedColor shr 8);
end;

procedure WriteFontFaceValue(Stream: TStream; const S: string);
var
  Family: TLhtFontFamily;
  ValueName: string;
begin
  Family := FontFamilyFromString(S, lffDefault);
  ValueName := FontFamilyToString(Family);
  if ValueName <> LowerCase(S) then
    raise Exception.CreateFmt('Attribute expects fontFace enum, got "%s"', [S]);
  WriteByte(Stream, TokenCodeForValue('TFontFace', ValueName));
end;

procedure WriteFontSizeValue(Stream: TStream; const S: string);
var
  Size: TLhtFontSize;
  ValueName: string;
begin
  Size := FontSizeFromString(S, lfsNormal);
  ValueName := FontSizeToString(Size);
  if ValueName <> LowerCase(S) then
    raise Exception.CreateFmt('Attribute expects fontSize enum, got "%s"', [S]);
  WriteByte(Stream, TokenCodeForValue('TFontSize', ValueName));
end;

procedure WriteCommand(Stream: TStream; Command: Byte);
begin
  WriteByte(Stream, TOK_COMMAND);
  WriteByte(Stream, Command);
end;

procedure WriteImport(Stream: TStream; Dict: TTokenDictKind);
begin
  WriteCommand(Stream, CMD_IMPORT);
  WriteVarUInt(Stream, DictIdForKind(Dict));
  WriteVarUInt(Stream, TokenCountForDict(Dict));
end;

procedure WriteImportOnce(Stream: TStream; ActiveStream: TTokenStreamKind;
  Dict: TTokenDictKind; var State: TImportState);
begin
  if Dict in State[ActiveStream] then
    Exit;
  WriteImport(Stream, Dict);
  Include(State[ActiveStream], Dict);
end;

procedure EncodeAttr(Stream: TStream; const Attr: TAttr; TokenStream: TTokenStreamKind);
var
  UIntValue: Cardinal;
begin
  TokenDefForNameInStream(Attr.Name, tkAttr, TokenStream);
  WriteByte(Stream, TokenCodeForAttr(Attr.Name));
  if IsIntegerAttr(Attr.Name) then
  begin
    if not ParseUInt(Attr.Value, UIntValue) then
      raise Exception.CreateFmt('Attribute %s expects unsigned integer, got "%s"',
        [Attr.Name, Attr.Value]);
    WriteInlineUInt(Stream, UIntValue);
  end
  else
  if IsColorAttr(Attr.Name) then
    WriteInlineColor(Stream, Attr.Value)
  else
  if IsFontFaceAttr(Attr.Name) then
    WriteFontFaceValue(Stream, Attr.Value)
  else
  if IsFontSizeAttr(Attr.Name) then
    WriteFontSizeValue(Stream, Attr.Value)
  else
    WriteInlineString(Stream, INLINE_TYPE_STRING, Attr.Value);
end;

procedure EncodeStyleNode(Stream: TStream; Node: TNode; var State: TImportState);
var
  Sheet: TLhtStyleSheet;
  I, J: Integer;
begin
  Sheet := TLhtStyleSheet.Create;
  try
    ParseStyleSheetText(Node.TextContent, Sheet);
    WriteCommand(Stream, CMD_STYLE_BEGIN);
    WriteImportOnce(Stream, tsStyle, tdStyle, State);
    WriteImportOnce(Stream, tsStyle, tdAttr, State);
    WriteImportOnce(Stream, tsStyle, tdValue, State);
    for I := 0 to High(Sheet.Rules) do
    begin
      WriteByte(Stream, TokenCodeForCommand('classDecl'));
      WriteInlineString(Stream, INLINE_TYPE_STRING, Sheet.Rules[I].ClassName);
      for J := 0 to High(Sheet.Rules[I].Attrs) do
      begin
        WriteByte(Stream, TokenCodeForCommand('set'));
        EncodeAttr(Stream, Sheet.Rules[I].Attrs[J], tsStyle);
      end;
      WriteByte(Stream, TOK_END);
    end;
    WriteByte(Stream, TOK_END);
  finally
    Sheet.Free;
  end;
end;

procedure EncodeScriptNode(Stream: TStream; Node: TNode; var State: TImportState);
var
  Tokens: TLjsTokenArray;
  I: Integer;
begin
  Tokens := ParseLjsScriptText(Node.TextContent);
  WriteCommand(Stream, CMD_SCRIPT_BEGIN);
  WriteImportOnce(Stream, tsScript, tdLjs, State);
  for I := 0 to High(Tokens) do
  begin
    case Tokens[I].Kind of
      ljsDict:
        begin
          if Tokens[I].Name = 'punct:{' then
            WriteByte(Stream, TOK_START)
          else if Tokens[I].Name = 'punct:}' then
            WriteByte(Stream, TOK_END)
          else
            WriteByte(Stream, TokenDefForNameInStream(Tokens[I].Name, tkCommand,
              tsScript).Code);
        end;
      ljsIdentifier:
        begin
          WriteByte(Stream, TokenDefForNameInStream('literal:identifier',
            tkCommand, tsScript).Code);
          WriteInlineString(Stream, INLINE_TYPE_STRING, Tokens[I].Value);
        end;
      ljsString:
        begin
          WriteByte(Stream, TokenDefForNameInStream('literal:string',
            tkCommand, tsScript).Code);
          WriteInlineString(Stream, INLINE_TYPE_STRING, Tokens[I].Value);
        end;
      ljsNumber:
        begin
          WriteByte(Stream, TokenDefForNameInStream('literal:number',
            tkCommand, tsScript).Code);
          WriteInlineString(Stream, INLINE_TYPE_STRING, Tokens[I].Value);
        end;
    end;
  end;
  WriteByte(Stream, TOK_END);
end;

procedure EncodeNode(Stream: TStream; Node: TNode; TokenStream: TTokenStreamKind;
  var State: TImportState);
var
  I: Integer;
  Bare: Boolean;
begin
  if Node.Kind = nkText then
  begin
    WriteInlineString(Stream, INLINE_TYPE_TEXT, Node.Text);
    Exit;
  end;

  if Node.Name = '#document' then
  begin
    for I := 0 to High(Node.Children) do
      EncodeNode(Stream, Node.Children[I], tsDoc, State);
    Exit;
  end;

  if (TokenStream = tsDoc) and (Node.Name = 'body') then
  begin
    WriteCommand(Stream, CMD_BODY_BEGIN);
    WriteImportOnce(Stream, tsDom, tdDom, State);
    WriteImportOnce(Stream, tsDom, tdAttr, State);
    WriteImportOnce(Stream, tsDom, tdValue, State);
    EncodeNode(Stream, Node, tsDom, State);
    Exit;
  end;

  if (TokenStream = tsDoc) and (Node.Name = 'style') then
  begin
    EncodeStyleNode(Stream, Node, State);
    Exit;
  end;

  if (TokenStream = tsDoc) and (Node.Name = 'script') then
  begin
    EncodeScriptNode(Stream, Node, State);
    Exit;
  end;

  if (Node.Name = 'p') or (Node.Name = 'br') then
    TokenDefForNameInStream(Node.Name, tkCommand, TokenStream)
  else
    TokenDefForNameInStream(Node.Name, tkElement, TokenStream);

  Bare := IsBareElement(Node.Name);
  if Bare then
    WriteByte(Stream, TokenCodeForElement(Node.Name))
  else
  begin
    WriteByte(Stream, TOK_START);
    WriteByte(Stream, TokenCodeForElement(Node.Name));
  end;

  for I := 0 to High(Node.Attrs) do
    EncodeAttr(Stream, Node.Attrs[I], TokenStream);

  for I := 0 to High(Node.Children) do
    EncodeNode(Stream, Node.Children[I], TokenStream, State);

  if not Bare then
    WriteByte(Stream, TOK_END);
end;

procedure EncodeMiniBinary(Root: TNode; Stream: TStream);
var
  State: TImportState;
begin
  FillChar(State, SizeOf(State), 0);
  WriteBytes(Stream, 'LHTM');
  WriteByte(Stream, 1);
  WriteImportOnce(Stream, tsDoc, tdDoc, State);
  WriteImportOnce(Stream, tsDoc, tdAttr, State);
  EncodeNode(Stream, Root, tsDoc, State);
end;

end.
