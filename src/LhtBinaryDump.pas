unit LhtBinaryDump;

{$mode objfpc}{$H+}

interface

uses
  Classes;

procedure DumpMiniBinaryDisasm(Stream: TStream; OutStream: TStream);

implementation

uses
  SysUtils, LhtTokenTable, LhtRenderTypes;

type
  TDisasmReader = class
  private
    FData: array of Byte;
    FPos: Integer;
    function ReadByteRaw: Byte;
  public
    constructor Create(Stream: TStream);
    function Eof: Boolean;
    function Pos: Integer;
    function PeekByte: Byte;
    function ReadByte: Byte;
    function ReadVarUInt(out Bytes: string): Cardinal;
    function ReadBytes(Count: Cardinal): string;
    function LastBytes(StartPos: Integer): string;
  end;

constructor TDisasmReader.Create(Stream: TStream);
begin
  inherited Create;
  SetLength(FData, Stream.Size - Stream.Position);
  if Length(FData) > 0 then
    Stream.ReadBuffer(FData[0], Length(FData));
end;

function TDisasmReader.Eof: Boolean;
begin
  Result := FPos >= Length(FData);
end;

function TDisasmReader.Pos: Integer;
begin
  Result := FPos;
end;

function TDisasmReader.ReadByteRaw: Byte;
begin
  if Eof then
    raise Exception.Create('Unexpected EOF');
  Result := FData[FPos];
  Inc(FPos);
end;

function TDisasmReader.PeekByte: Byte;
begin
  if Eof then
    raise Exception.Create('Unexpected EOF');
  Result := FData[FPos];
end;

function TDisasmReader.ReadByte: Byte;
begin
  Result := ReadByteRaw;
end;

function TDisasmReader.ReadVarUInt(out Bytes: string): Cardinal;
var
  B: Byte;
  Shift: Integer;
begin
  Result := 0;
  Shift := 0;
  Bytes := '';
  repeat
    B := ReadByteRaw;
    if Bytes <> '' then
      Bytes := Bytes + ' ';
    Bytes := Bytes + IntToHex(B, 2);
    if (Shift > 28) or ((Shift = 28) and ((B and $F0) <> 0)) then
      raise Exception.Create('Varuint too large');
    Result := Result or (Cardinal(B and $7F) shl Shift);
    Inc(Shift, 7);
  until (B and $80) = 0;
end;

function TDisasmReader.ReadBytes(Count: Cardinal): string;
var
  I: Cardinal;
begin
  SetLength(Result, Count);
  for I := 1 to Count do
    Result[I] := Char(ReadByteRaw);
end;

function TDisasmReader.LastBytes(StartPos: Integer): string;
var
  I: Integer;
begin
  Result := '';
  for I := StartPos to FPos - 1 do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + IntToHex(FData[I], 2);
  end;
end;

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

function PrintableString(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    case S[I] of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #9: Result := Result + '\t';
      #10: Result := Result + '\n';
      #13: Result := Result + '\r';
    else
      if Ord(S[I]) < 32 then
        Result := Result + '\x' + IntToHex(Ord(S[I]), 2)
      else
        Result := Result + S[I];
    end;
  end;
end;

function CommandName(Code: Byte): string;
begin
  case Code of
    CMD_IMPORT: Result := 'IMPORT';
    CMD_BODY_BEGIN: Result := 'BODY_BEGIN';
    CMD_STYLE_BEGIN: Result := 'STYLE_BEGIN';
    CMD_SCRIPT_BEGIN: Result := 'SCRIPT_BEGIN';
  else
    Result := 'UNKNOWN_COMMAND';
  end;
end;

procedure Emit(OutStream: TStream; Offset: Integer; const Bytes, Text: string);
begin
  WriteLine(OutStream, IntToHex(Offset, 4) + '  ' +
    Bytes + StringOfChar(' ', 18 - Length(Bytes)) + '  ' + Text);
end;

procedure DumpInlineValue(R: TDisasmReader; OutStream: TStream; Offset: Integer);
var
  Marker: Byte;
  Header: Byte;
  ValueType: Byte;
  UIntValue: Cardinal;
  ColorValue: Word;
  Len: Cardinal;
  VarBytes: string;
  S: string;
  TypeName: string;
begin
  Marker := R.ReadByte;
  if Marker = TOK_INLINE_BYTE then
  begin
    Emit(OutStream, Offset, R.LastBytes(Offset), 'INLINE_BYTE ' + IntToStr(R.ReadByte));
    Exit;
  end;

  if Marker <> TOK_INLINE_VALUE then
    raise Exception.CreateFmt('Expected inline value at %.4x, got %.2x',
      [Offset, Marker]);

  Header := R.ReadByte;
  ValueType := Header and $0F;

  case ValueType of
    INLINE_TYPE_UINT:
      begin
        UIntValue := R.ReadVarUInt(VarBytes);
        Emit(OutStream, Offset, R.LastBytes(Offset),
          'INLINE_VALUE uint ' + IntToStr(UIntValue));
      end;
    INLINE_TYPE_COLOR:
      begin
        ColorValue := R.ReadByte;
        ColorValue := ColorValue or (Word(R.ReadByte) shl 8);
        Emit(OutStream, Offset, R.LastBytes(Offset),
          'INLINE_VALUE color ' + ColorToHex(Rgb565ToRgb(ColorValue)));
      end;
    INLINE_TYPE_STRING, INLINE_TYPE_TEXT:
      begin
        Len := R.ReadVarUInt(VarBytes);
        S := R.ReadBytes(Len);
        if ValueType = INLINE_TYPE_TEXT then
          TypeName := 'text'
        else
          TypeName := 'string';
        Emit(OutStream, Offset, R.LastBytes(Offset),
          'INLINE_VALUE ' + TypeName + ' "' + PrintableString(S) + '"');
      end;
  else
    raise Exception.CreateFmt('Unsupported inline value type at %.4x: %d',
      [Offset, ValueType]);
  end;
end;

procedure DumpMiniBinaryDisasm(Stream: TStream; OutStream: TStream);
var
  R: TDisasmReader;
  Offset: Integer;
  Code: Byte;
  B: Byte;
  Magic: string;
  CurrentStream: TTokenStreamKind;
  DictId: Cardinal;
  Count: Cardinal;
  VarBytes: string;
  Def: TTokenDef;
  Dict: TTokenDictKind;
  ImportName: string;
  ScriptBlockDepth: Integer;
begin
  R := TDisasmReader.Create(Stream);
  try
    CurrentStream := tsDoc;
    ScriptBlockDepth := 0;
    Offset := R.Pos;
    Magic := R.ReadBytes(4);
    Emit(OutStream, Offset, R.LastBytes(Offset), 'MAGIC "' + Magic + '"');
    if Magic <> 'LHTM' then
      raise Exception.Create('Invalid mini binary magic');

    Offset := R.Pos;
    B := R.ReadByte;
    Emit(OutStream, Offset, R.LastBytes(Offset), 'MINI_VERSION ' + IntToStr(B));
    if B <> 1 then
      raise Exception.CreateFmt('Unsupported mini binary version: %d', [B]);

    while not R.Eof do
    begin
      Offset := R.Pos;
      Code := R.PeekByte;

      if (Code = TOK_INLINE_VALUE) or (Code = TOK_INLINE_BYTE) then
      begin
        DumpInlineValue(R, OutStream, Offset);
        Continue;
      end;

      R.ReadByte;
      case Code of
        TOK_END:
          begin
            if CurrentStream = tsScript then
            begin
              if ScriptBlockDepth > 0 then
              begin
                Dec(ScriptBlockDepth);
                Emit(OutStream, Offset, R.LastBytes(Offset), 'LJS END');
              end
              else
                Emit(OutStream, Offset, R.LastBytes(Offset), 'END SCRIPT');
            end
            else
              Emit(OutStream, Offset, R.LastBytes(Offset), 'END');
          end;
        TOK_START:
          begin
            if CurrentStream = tsScript then
            begin
              Inc(ScriptBlockDepth);
              Emit(OutStream, Offset, R.LastBytes(Offset), 'LJS START');
            end
            else
              Emit(OutStream, Offset, R.LastBytes(Offset), 'START');
          end;
        TOK_COMMAND:
          begin
            B := R.ReadByte;
            if B = CMD_IMPORT then
            begin
              DictId := R.ReadVarUInt(VarBytes);
              Count := R.ReadVarUInt(VarBytes);
              if DictKindForId(DictId, Dict) then
              begin
                ImportName := DictName(Dict);
                if Dict = tdDoc then
                  CurrentStream := tsDoc
                else if Dict = tdDom then
                  CurrentStream := tsDom
                else if Dict = tdStyle then
                  CurrentStream := tsStyle
                else if Dict = tdLjs then
                  CurrentStream := tsScript;
              end
              else
                ImportName := 'unknown';
              Emit(OutStream, Offset, R.LastBytes(Offset),
                'COMMAND IMPORT dict=' + IntToStr(DictId) +
                ' count=' + IntToStr(Count) + ' ; ' + ImportName +
                ' in ' + StreamName(CurrentStream));
            end
            else
            begin
              if B = CMD_BODY_BEGIN then
                CurrentStream := tsDom
              else if B = CMD_STYLE_BEGIN then
                CurrentStream := tsStyle
              else if B = CMD_SCRIPT_BEGIN then
                CurrentStream := tsScript;
              Emit(OutStream, Offset, R.LastBytes(Offset),
                'COMMAND ' + CommandName(B));
            end;
          end;
      else
        if IsElementTokenInStream(Code, CurrentStream) then
        begin
          Def := TokenDefForCodeInStream(Code, CurrentStream);
          if CurrentStream = tsScript then
            Emit(OutStream, Offset, R.LastBytes(Offset), 'LJS ' + Def.Name)
          else
            Emit(OutStream, Offset, R.LastBytes(Offset),
              TokenNameForElement(Def.Name));
        end
        else if IsAttrTokenInStream(Code, CurrentStream) then
        begin
          Def := TokenDefForCodeInStream(Code, CurrentStream);
          Emit(OutStream, Offset, R.LastBytes(Offset),
            TokenNameForAttr(Def.Name));
        end
        else if IsValueTokenInStream(Code, CurrentStream) then
        begin
          Def := TokenDefForCodeInStream(Code, CurrentStream);
          Emit(OutStream, Offset, R.LastBytes(Offset),
            TokenNameForValue(Def.Name));
        end
        else
          Emit(OutStream, Offset, R.LastBytes(Offset),
            Format('UNKNOWN %.2x', [Code]));
      end;
    end;
  finally
    R.Free;
  end;
end;

end.
