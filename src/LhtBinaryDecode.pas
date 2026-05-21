unit LhtBinaryDecode;

{$mode objfpc}{$H+}

interface

uses
  Classes, LhtDom;

function DecodeMiniBinary(Stream: TStream): TNode;

implementation

uses
  SysUtils, LhtTokenTable, LhtRenderTypes, LhtStyle, LhtScript;

type
  TDictSet = set of TTokenDictKind;
  TImportState = array[TTokenStreamKind] of TDictSet;

  TByteReader = class
  private
    FStream: TStream;
    FHasPeek: Boolean;
    FPeek: Byte;
  public
    constructor Create(AStream: TStream);
    function Eof: Boolean;
    function ReadByte: Byte;
    function PeekByte: Byte;
  end;

constructor TByteReader.Create(AStream: TStream);
begin
  inherited Create;
  FStream := AStream;
end;

function TByteReader.Eof: Boolean;
begin
  Result := (not FHasPeek) and (FStream.Position >= FStream.Size);
end;

function TByteReader.ReadByte: Byte;
begin
  if FHasPeek then
  begin
    Result := FPeek;
    FHasPeek := False;
    Exit;
  end;
  if FStream.Read(Result, SizeOf(Result)) <> SizeOf(Result) then
    raise Exception.Create('Unexpected EOF');
end;

function TByteReader.PeekByte: Byte;
begin
  if not FHasPeek then
  begin
    if FStream.Read(FPeek, SizeOf(FPeek)) <> SizeOf(FPeek) then
      raise Exception.Create('Unexpected EOF');
    FHasPeek := True;
  end;
  Result := FPeek;
end;

function ReadVarUInt(R: TByteReader): Cardinal;
var
  B: Byte;
  Shift: Integer;
begin
  Result := 0;
  Shift := 0;
  repeat
    B := R.ReadByte;
    if (Shift > 28) or ((Shift = 28) and ((B and $F0) <> 0)) then
      raise Exception.Create('Varuint too large');
    Result := Result or (Cardinal(B and $7F) shl Shift);
    Inc(Shift, 7);
  until (B and $80) = 0;
end;

procedure ValidateInlineAttrValue(const AttrName: string; const Value: string;
  ValueType: Byte);
var
  Family: TLhtFontFamily;
  Size: TLhtFontSize;
begin
  if IsIntegerAttr(AttrName) then
  begin
    if ValueType <> INLINE_TYPE_UINT then
      raise Exception.CreateFmt('Attribute %s expects uint inline value, got type %d',
        [AttrName, ValueType]);
    Exit;
  end;

  if IsColorAttr(AttrName) then
  begin
    if ValueType <> INLINE_TYPE_COLOR then
      raise Exception.CreateFmt('Attribute %s expects color inline value, got type %d',
        [AttrName, ValueType]);
    Exit;
  end;

  if IsFontFaceAttr(AttrName) or IsFontSizeAttr(AttrName) then
  begin
    if ValueType <> INLINE_TYPE_STRING then
      raise Exception.CreateFmt('Attribute %s expects string inline value, got type %d',
        [AttrName, ValueType]);
    if IsFontFaceAttr(AttrName) then
    begin
      Family := FontFamilyFromString(Value, lffDefault);
      if FontFamilyToString(Family) <> LowerCase(Value) then
        raise Exception.CreateFmt('Attribute %s expects fontFace enum, got "%s"',
          [AttrName, Value]);
    end
    else
    begin
      Size := FontSizeFromString(Value, lfsNormal);
      if FontSizeToString(Size) <> LowerCase(Value) then
        raise Exception.CreateFmt('Attribute %s expects fontSize enum, got "%s"',
          [AttrName, Value]);
    end;
    Exit;
  end;

  if ValueType <> INLINE_TYPE_STRING then
    raise Exception.CreateFmt('Attribute %s expects string inline value, got type %d',
      [AttrName, ValueType]);
end;

procedure ExpectImport(R: TByteReader; Stream: TTokenStreamKind;
  ExpectedDict: TTokenDictKind; var State: TImportState);
var
  Command: Byte;
  DictId: Cardinal;
  Count: Cardinal;
  Dict: TTokenDictKind;
begin
  if R.ReadByte <> TOK_COMMAND then
    raise Exception.CreateFmt('Expected IMPORT command for %s dictionary',
      [DictName(ExpectedDict)]);
  Command := R.ReadByte;
  if Command <> CMD_IMPORT then
    raise Exception.CreateFmt('Expected IMPORT command, got %.2x', [Command]);
  DictId := ReadVarUInt(R);
  Count := ReadVarUInt(R);
  if (not DictKindForId(DictId, Dict)) or (Dict <> ExpectedDict) then
    raise Exception.CreateFmt('Expected %s dictionary in %s stream, got dict %d',
      [DictName(ExpectedDict), StreamName(Stream), DictId]);
  if not DictValidInStream(Dict, Stream) then
    raise Exception.CreateFmt('Dictionary %s is not valid in %s stream',
      [DictName(Dict), StreamName(Stream)]);
  if Count <> TokenCountForDict(Dict) then
    raise Exception.CreateFmt('Expected %d imported tokens for %s dictionary, got %d',
      [TokenCountForDict(Dict), DictName(Dict), Count]);
  Include(State[Stream], Dict);
end;

procedure RequireImport(Stream: TTokenStreamKind; Dict: TTokenDictKind;
  const State: TImportState);
begin
  if not (Dict in State[Stream]) then
    raise Exception.CreateFmt('Missing %s import in %s stream',
      [DictName(Dict), StreamName(Stream)]);
end;

function ReadUtf8Bytes(R: TByteReader; Len: Cardinal): string;
var
  I: Cardinal;
begin
  SetLength(Result, Len);
  for I := 1 to Len do
    Result[I] := Char(R.ReadByte);
end;

function ReadInlineValue(R: TByteReader; out ValueType: Byte): string;
var
  Marker: Byte;
  Header: Byte;
  UIntValue: Cardinal;
  ColorValue: Word;
  Len: Cardinal;
begin
  Marker := R.ReadByte;
  if Marker = TOK_INLINE_BYTE then
  begin
    ValueType := INLINE_TYPE_UINT;
    Result := IntToStr(R.ReadByte);
    Exit;
  end;

  if Marker <> TOK_INLINE_VALUE then
    raise Exception.CreateFmt('Expected inline value, got %.2x', [Marker]);

  Header := R.ReadByte;
  if (Header and INLINE_FLAG_USE) = 0 then
    raise Exception.Create('Mini decoder only supports USE inline values');

  ValueType := Header and $0F;
  case ValueType of
    INLINE_TYPE_UINT:
      begin
        UIntValue := ReadVarUInt(R);
        Result := IntToStr(UIntValue);
      end;
    INLINE_TYPE_COLOR:
      begin
        ColorValue := R.ReadByte;
        ColorValue := ColorValue or (Word(R.ReadByte) shl 8);
        Result := ColorToHex(Rgb565ToRgb(ColorValue));
      end;
    INLINE_TYPE_STRING, INLINE_TYPE_TEXT:
      begin
        Len := ReadVarUInt(R);
        Result := ReadUtf8Bytes(R, Len);
      end;
  else
    raise Exception.CreateFmt('Unsupported inline value type: %d', [ValueType]);
  end;
end;

function ReadAttrValue(R: TByteReader; const AttrName: string;
  TokenStream: TTokenStreamKind): string;
var
  Code: Byte;
  Def: TTokenDef;
  ValueType: Byte;
begin
  Code := R.PeekByte;
  if IsValueTokenInStream(Code, TokenStream) then
  begin
    R.ReadByte;
    Def := TokenDefForCodeInStream(Code, TokenStream);
    if IsFontFaceAttr(AttrName) then
    begin
      if ValueTypeForTokenName(Def.Name) <> 'TFontFace' then
        raise Exception.CreateFmt('Attribute %s got incompatible value token %s',
          [AttrName, Def.Name]);
      Exit(ValueNameForTokenName(Def.Name));
    end;
    if IsFontSizeAttr(AttrName) then
    begin
      if ValueTypeForTokenName(Def.Name) <> 'TFontSize' then
        raise Exception.CreateFmt('Attribute %s got incompatible value token %s',
          [AttrName, Def.Name]);
      Exit(ValueNameForTokenName(Def.Name));
    end;
    raise Exception.CreateFmt('Attribute %s does not accept value token %s',
      [AttrName, Def.Name]);
  end;

  Result := ReadInlineValue(R, ValueType);
  ValidateInlineAttrValue(AttrName, Result, ValueType);
end;

procedure ReadStyleSet(R: TByteReader; Sheet: TLhtStyleSheet; RuleIndex: Integer);
var
  Code: Byte;
  AttrName: string;
  Value: string;
begin
  Code := R.ReadByte;
  if not IsAttrTokenInStream(Code, tsStyle) then
    raise Exception.CreateFmt('Expected style attr token, got %.2x', [Code]);
  AttrName := AttrNameForToken(Code);
  Value := ReadAttrValue(R, AttrName, tsStyle);
  Sheet.AddAttr(RuleIndex, AttrName, Value);
end;

function ReadStyleStream(R: TByteReader; var State: TImportState): TNode;
var
  Sheet: TLhtStyleSheet;
  Code: Byte;
  ClassName: string;
  ValueType: Byte;
  Rule: Integer;
begin
  if not (tdStyle in State[tsStyle]) then
    ExpectImport(R, tsStyle, tdStyle, State);
  if not (tdAttr in State[tsStyle]) then
    ExpectImport(R, tsStyle, tdAttr, State);
  if not (tdValue in State[tsStyle]) then
    ExpectImport(R, tsStyle, tdValue, State);
  RequireImport(tsStyle, tdStyle, State);
  RequireImport(tsStyle, tdAttr, State);
  RequireImport(tsStyle, tdValue, State);

  Sheet := TLhtStyleSheet.Create;
  try
    while not R.Eof do
    begin
      Code := R.ReadByte;
      if Code = TOK_END then
        Break;
      if Code <> TokenCodeForCommand('classDecl') then
        raise Exception.CreateFmt('Expected style classDecl, got %.2x', [Code]);
      ClassName := ReadInlineValue(R, ValueType);
      if ValueType <> INLINE_TYPE_STRING then
        raise Exception.Create('Style class name must be a string');
      Rule := Sheet.AddRule(ClassName);
      while not R.Eof do
      begin
        Code := R.PeekByte;
        if Code = TOK_END then
        begin
          R.ReadByte;
          Break;
        end;
        if R.ReadByte <> TokenCodeForCommand('set') then
          raise Exception.CreateFmt('Expected style set, got %.2x', [Code]);
        ReadStyleSet(R, Sheet, Rule);
      end;
    end;

    Result := TNode.CreateElement('style');
    Result.AddChild(TNode.CreateText(StyleSheetToText(Sheet)));
  finally
    Sheet.Free;
  end;
end;

function ReadScriptStream(R: TByteReader; var State: TImportState): TNode;
var
  Tokens: TLjsTokenArray;
  Code: Byte;
  Def: TTokenDef;
  ValueType: Byte;
  N, BlockDepth: Integer;
begin
  if not (tdLjs in State[tsScript]) then
    ExpectImport(R, tsScript, tdLjs, State);
  RequireImport(tsScript, tdLjs, State);

  SetLength(Tokens, 0);
  BlockDepth := 0;
  while not R.Eof do
  begin
    Code := R.ReadByte;
    if (Code = TOK_END) and (BlockDepth = 0) then
      Break;
    N := Length(Tokens);
    SetLength(Tokens, N + 1);
    if Code = TOK_START then
    begin
      Tokens[N].Kind := ljsDict;
      Tokens[N].Name := 'punct:{';
      Inc(BlockDepth);
      Continue;
    end;
    if Code = TOK_END then
    begin
      Tokens[N].Kind := ljsDict;
      Tokens[N].Name := 'punct:}';
      Dec(BlockDepth);
      Continue;
    end;
    Def := TokenDefForCodeInStream(Code, tsScript);
    if Def.Name = 'literal:identifier' then
    begin
      Tokens[N].Kind := ljsIdentifier;
      Tokens[N].Value := ReadInlineValue(R, ValueType);
      if ValueType <> INLINE_TYPE_STRING then
        raise Exception.Create('Script identifier literal must be a string');
    end
    else if Def.Name = 'literal:string' then
    begin
      Tokens[N].Kind := ljsString;
      Tokens[N].Value := ReadInlineValue(R, ValueType);
      if ValueType <> INLINE_TYPE_STRING then
        raise Exception.Create('Script string literal must be a string');
    end
    else if Def.Name = 'literal:number' then
    begin
      Tokens[N].Kind := ljsNumber;
      Tokens[N].Value := ReadInlineValue(R, ValueType);
      if ValueType <> INLINE_TYPE_STRING then
        raise Exception.Create('Script number literal must be a string');
    end
    else
    begin
      Tokens[N].Kind := ljsDict;
      Tokens[N].Name := Def.Name;
    end;
  end;

  ValidateLjsTokens(Tokens);
  Result := TNode.CreateElement('script');
  Result.AddChild(TNode.CreateText(LjsTokensToText(Tokens)));
end;

procedure ReadAttrs(R: TByteReader; Node: TNode; TokenStream: TTokenStreamKind);
var
  Code: Byte;
  AttrName: string;
  Value: string;
begin
  while not R.Eof do
  begin
    Code := R.PeekByte;
    if not IsAttrTokenInStream(Code, TokenStream) then
      Break;
    R.ReadByte;
    AttrName := AttrNameForToken(Code);
    Value := ReadAttrValue(R, AttrName, TokenStream);
    Node.AddAttr(AttrName, Value);
  end;
end;

function ReadElementAfterStart(R: TByteReader; TokenStream: TTokenStreamKind;
  var State: TImportState): TNode;
var
  Code: Byte;
  Child: TNode;
  ValueType: Byte;
  Value: string;
  Def: TTokenDef;
begin
  Code := R.ReadByte;
  if not IsElementTokenInStream(Code, TokenStream) then
    raise Exception.CreateFmt('Expected element token after START, got %.2x', [Code]);
  Def := TokenDefForCodeInStream(Code, TokenStream);

  Result := TNode.CreateElement(Def.Name);
  try
    ReadAttrs(R, Result, TokenStream);

    while not R.Eof do
    begin
      Code := R.PeekByte;
      if Code = TOK_END then
      begin
        R.ReadByte;
        Exit;
      end;

      if Code = TOK_START then
      begin
        R.ReadByte;
        Result.AddChild(ReadElementAfterStart(R, TokenStream, State));
      end
      else if Code = TOK_COMMAND then
      begin
        R.ReadByte;
        Code := R.ReadByte;
        if (TokenStream <> tsDoc) then
          raise Exception.CreateFmt('Unexpected command %.2x in %s stream',
            [Code, StreamName(TokenStream)]);
        if Code = CMD_STYLE_BEGIN then
        begin
          Result.AddChild(ReadStyleStream(R, State));
          Continue;
        end;
        if Code = CMD_SCRIPT_BEGIN then
        begin
          Result.AddChild(ReadScriptStream(R, State));
          Continue;
        end;
        if Code <> CMD_BODY_BEGIN then
          raise Exception.CreateFmt('Unexpected command %.2x in %s stream',
            [Code, StreamName(TokenStream)]);
        if not (tdDom in State[tsDom]) then
          ExpectImport(R, tsDom, tdDom, State);
        if not (tdAttr in State[tsDom]) then
          ExpectImport(R, tsDom, tdAttr, State);
        if not (tdValue in State[tsDom]) then
          ExpectImport(R, tsDom, tdValue, State);
        RequireImport(tsDom, tdDom, State);
        RequireImport(tsDom, tdAttr, State);
        RequireImport(tsDom, tdValue, State);
        if R.ReadByte <> TOK_START then
          raise Exception.Create('Expected START after BODY_BEGIN');
        Child := ReadElementAfterStart(R, tsDom, State);
        if Child.Name <> 'body' then
        begin
          Child.Free;
          raise Exception.Create('BODY_BEGIN must be followed by START body');
        end;
        Result.AddChild(Child);
      end
      else if IsElementTokenInStream(Code, TokenStream) then
      begin
        Def := TokenDefForCodeInStream(Code, TokenStream);
        R.ReadByte;
        Child := TNode.CreateElement(Def.Name);
        try
          if not IsBareElement(Child.Name) then
            raise Exception.CreateFmt('Bare token used for non-bare element: %s',
              [Child.Name]);
          ReadAttrs(R, Child, TokenStream);
          Result.AddChild(Child);
        except
          Child.Free;
          raise;
        end;
      end
      else if (Code = TOK_INLINE_VALUE) or (Code = TOK_INLINE_BYTE) then
      begin
        Value := ReadInlineValue(R, ValueType);
        if ValueType <> INLINE_TYPE_TEXT then
          raise Exception.CreateFmt('Unexpected inline value type in content: %d',
            [ValueType]);
        Result.AddChild(TNode.CreateText(Value));
      end
      else
        raise Exception.CreateFmt('Unexpected token in element content: %.2x', [Code]);
    end;

    raise Exception.CreateFmt('Unterminated element: %s', [Result.Name]);
  except
    Result.Free;
    raise;
  end;
end;

procedure VerifyMagic(R: TByteReader);
const
  Magic = 'LHTM';
var
  I: Integer;
  Version: Byte;
begin
  for I := 1 to Length(Magic) do
    if Char(R.ReadByte) <> Magic[I] then
      raise Exception.Create('Invalid mini binary magic');
  Version := R.ReadByte;
  if Version <> 1 then
    raise Exception.CreateFmt('Unsupported mini binary version: %d', [Version]);
end;

function DecodeMiniBinary(Stream: TStream): TNode;
var
  R: TByteReader;
  Code: Byte;
  State: TImportState;
begin
  R := TByteReader.Create(Stream);
  try
    FillChar(State, SizeOf(State), 0);
    VerifyMagic(R);
    ExpectImport(R, tsDoc, tdDoc, State);
    ExpectImport(R, tsDoc, tdAttr, State);
    Result := TNode.CreateElement('#document');
    try
      while not R.Eof do
      begin
        Code := R.ReadByte;
        if Code <> TOK_START then
          raise Exception.CreateFmt('Expected START at document level, got %.2x',
            [Code]);
        Result.AddChild(ReadElementAfterStart(R, tsDoc, State));
      end;
    except
      Result.Free;
      raise;
    end;
  finally
    R.Free;
  end;
end;

end.
