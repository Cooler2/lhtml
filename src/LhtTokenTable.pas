unit LhtTokenTable;

{$mode objfpc}{$H+}

interface

type
  TTokenStreamKind = (tsDoc, tsDom, tsStyle, tsScript);
  TTokenDictKind = (tdDoc, tdDom, tdStyle, tdAttr, tdValue, tdLjs);
  TTokenKind = (tkElement, tkCommand, tkAttr, tkValue);

  TTokenDef = record
    Code: Byte;
    Name: string;
    Dict: TTokenDictKind;
    Kind: TTokenKind;
    Bare: Boolean;
    IntegerValue: Boolean;
  end;

function IsBareElement(const Name: string): Boolean;
function TokenNameForElement(const Name: string): string;
function TokenCodeForCommand(const Name: string): Byte;
function TokenNameForAttr(const Name: string): string;
function IsIntegerAttr(const Name: string): Boolean;
function IsColorAttr(const Name: string): Boolean;
function IsFontFaceAttr(const Name: string): Boolean;
function IsFontSizeAttr(const Name: string): Boolean;
function TokenCodeForValue(const TypeName, ValueName: string): Byte;
function TokenNameForValue(const Name: string): string;
function IsValueTokenInStream(Code: Byte; Stream: TTokenStreamKind): Boolean;
function ValueTypeForTokenName(const Name: string): string;
function ValueNameForTokenName(const Name: string): string;
function TokenCodeForElement(const Name: string): Byte;
function TokenCodeForAttr(const Name: string): Byte;
function ElementNameForToken(Code: Byte): string;
function AttrNameForToken(Code: Byte): string;
function IsElementToken(Code: Byte): Boolean;
function IsAttrToken(Code: Byte): Boolean;
function TokenDefForCode(Code: Byte): TTokenDef;
function TokenDefForName(const Name: string; Kind: TTokenKind): TTokenDef;
function TokenDefForCodeInStream(Code: Byte; Stream: TTokenStreamKind): TTokenDef;
function TokenDefForNameInStream(const Name: string; Kind: TTokenKind;
  Stream: TTokenStreamKind): TTokenDef;
function StreamName(Stream: TTokenStreamKind): string;
function DictName(Dict: TTokenDictKind): string;
function DictIdForKind(Dict: TTokenDictKind): Byte;
function DictKindForId(DictId: Cardinal; out Dict: TTokenDictKind): Boolean;
function TokenCountForDict(Dict: TTokenDictKind): Byte;
function MiniTokenDefCount: Integer;
function MiniTokenDefByIndex(Index: Integer): TTokenDef;
function IsElementTokenInStream(Code: Byte; Stream: TTokenStreamKind): Boolean;
function IsAttrTokenInStream(Code: Byte; Stream: TTokenStreamKind): Boolean;
function DictValidInStream(Dict: TTokenDictKind; Stream: TTokenStreamKind): Boolean;

const
  TOK_END = $00;
  TOK_START = $01;
  TOK_COMMAND = $02;
  TOK_INLINE_VALUE = $03;
  TOK_INLINE_BYTE = $04;

  CMD_IMPORT = $00;
  CMD_BODY_BEGIN = $04;
  CMD_STYLE_BEGIN = $05;
  CMD_SCRIPT_BEGIN = $06;

  DICT_DOC_MINI = $01;
  DICT_DOM_MINI = $02;
  DICT_STYLE_MINI = $03;
  DICT_ATTR_MINI = $04;
  DICT_VALUE_MINI = $05;
  DICT_LJS_MINI = $06;

  INLINE_FLAG_USE = $80;
  INLINE_TYPE_UINT = $00;
  INLINE_TYPE_COLOR = $02;
  INLINE_TYPE_STRING = $04;
  INLINE_TYPE_TEXT = $05;

implementation

uses
  SysUtils;

const
  MiniTokens: array[0..73] of TTokenDef = (
    (Code: $05; Name: 'lhtml';  Dict: tdDoc; Kind: tkElement; Bare: False; IntegerValue: False),
    (Code: $06; Name: 'head';   Dict: tdDoc; Kind: tkElement; Bare: False; IntegerValue: False),
    (Code: $07; Name: 'title';  Dict: tdDoc; Kind: tkElement; Bare: False; IntegerValue: False),
    (Code: $08; Name: 'meta';   Dict: tdDoc; Kind: tkElement; Bare: True;  IntegerValue: False),
    (Code: $09; Name: 'script'; Dict: tdDoc; Kind: tkElement; Bare: False; IntegerValue: False),
    (Code: $05; Name: 'body';   Dict: tdDom; Kind: tkElement; Bare: False; IntegerValue: False),
    (Code: $06; Name: 'block';  Dict: tdDom; Kind: tkElement; Bare: False; IntegerValue: False),
    (Code: $07; Name: 'row';    Dict: tdDom; Kind: tkElement; Bare: False; IntegerValue: False),
    (Code: $08; Name: 'spacer'; Dict: tdDom; Kind: tkElement; Bare: True;  IntegerValue: False),
    (Code: $09; Name: 'p';      Dict: tdDom; Kind: tkCommand; Bare: True;  IntegerValue: False),
    (Code: $0A; Name: 'br';     Dict: tdDom; Kind: tkCommand; Bare: True;  IntegerValue: False),
    (Code: $0B; Name: 'span';   Dict: tdDom; Kind: tkElement; Bare: False; IntegerValue: False),
    (Code: $0C; Name: 'a';      Dict: tdDom; Kind: tkElement; Bare: False; IntegerValue: False),
    (Code: $0D; Name: 'table';  Dict: tdDom; Kind: tkElement; Bare: False; IntegerValue: False),
    (Code: $0E; Name: 'col';    Dict: tdDom; Kind: tkElement; Bare: True;  IntegerValue: False),
    (Code: $0F; Name: 'tr';     Dict: tdDom; Kind: tkElement; Bare: False; IntegerValue: False),
    (Code: $10; Name: 'td';     Dict: tdDom; Kind: tkElement; Bare: False; IntegerValue: False),
    (Code: $05; Name: 'classDecl'; Dict: tdStyle; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $06; Name: 'set';    Dict: tdStyle; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $05; Name: 'kw:let'; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $06; Name: 'kw:if'; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $07; Name: 'kw:else'; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $08; Name: 'kw:while'; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $09; Name: 'kw:true'; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $0A; Name: 'kw:false'; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $0B; Name: 'kw:null'; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $0C; Name: 'op:='; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $0D; Name: 'op:+'; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $0E; Name: 'op:-'; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $0F; Name: 'op:*'; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $10; Name: 'op:/'; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $11; Name: 'op:=='; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $12; Name: 'op:!='; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $13; Name: 'op:<'; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $14; Name: 'op:>'; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $15; Name: 'op:<='; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $16; Name: 'op:>='; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $17; Name: 'punct:('; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $18; Name: 'punct:)'; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $19; Name: 'punct:{'; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $1A; Name: 'punct:}'; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $1B; Name: 'punct:;'; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $1C; Name: 'punct:,'; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $1F; Name: 'literal:identifier'; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $30; Name: 'literal:string'; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $31; Name: 'literal:number'; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $32; Name: 'kw:function'; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $33; Name: 'kw:return'; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $34; Name: 'punct:.'; Dict: tdLjs; Kind: tkCommand; Bare: False; IntegerValue: False),
    (Code: $20; Name: 'version'; Dict: tdAttr; Kind: tkAttr; Bare: False; IntegerValue: True),
    (Code: $21; Name: 'name';    Dict: tdAttr; Kind: tkAttr; Bare: False; IntegerValue: False),
    (Code: $22; Name: 'content'; Dict: tdAttr; Kind: tkAttr; Bare: False; IntegerValue: False),
    (Code: $23; Name: 'id';      Dict: tdAttr; Kind: tkAttr; Bare: False; IntegerValue: False),
    (Code: $24; Name: 'width';   Dict: tdAttr; Kind: tkAttr; Bare: False; IntegerValue: True),
    (Code: $25; Name: 'height';  Dict: tdAttr; Kind: tkAttr; Bare: False; IntegerValue: True),
    (Code: $26; Name: 'href';    Dict: tdAttr; Kind: tkAttr; Bare: False; IntegerValue: False),
    (Code: $27; Name: 'fontFace'; Dict: tdAttr; Kind: tkAttr; Bare: False; IntegerValue: False),
    (Code: $28; Name: 'fontSize'; Dict: tdAttr; Kind: tkAttr; Bare: False; IntegerValue: False),
    (Code: $29; Name: 'color'; Dict: tdAttr; Kind: tkAttr; Bare: False; IntegerValue: False),
    (Code: $2A; Name: 'background'; Dict: tdAttr; Kind: tkAttr; Bare: False; IntegerValue: False),
    (Code: $2B; Name: 'border'; Dict: tdAttr; Kind: tkAttr; Bare: False; IntegerValue: False),
    (Code: $2C; Name: 'padding'; Dict: tdAttr; Kind: tkAttr; Bare: False; IntegerValue: True),
    (Code: $2D; Name: 'borderWidth'; Dict: tdAttr; Kind: tkAttr; Bare: False; IntegerValue: True),
    (Code: $2E; Name: 'class'; Dict: tdAttr; Kind: tkAttr; Bare: False; IntegerValue: False),
    (Code: $40; Name: 'TFontFace:default'; Dict: tdValue; Kind: tkValue; Bare: False; IntegerValue: False),
    (Code: $41; Name: 'TFontFace:sans'; Dict: tdValue; Kind: tkValue; Bare: False; IntegerValue: False),
    (Code: $42; Name: 'TFontFace:serif'; Dict: tdValue; Kind: tkValue; Bare: False; IntegerValue: False),
    (Code: $43; Name: 'TFontFace:mono'; Dict: tdValue; Kind: tkValue; Bare: False; IntegerValue: False),
    (Code: $44; Name: 'TFontSize:tiny'; Dict: tdValue; Kind: tkValue; Bare: False; IntegerValue: False),
    (Code: $45; Name: 'TFontSize:small'; Dict: tdValue; Kind: tkValue; Bare: False; IntegerValue: False),
    (Code: $46; Name: 'TFontSize:normal'; Dict: tdValue; Kind: tkValue; Bare: False; IntegerValue: False),
    (Code: $47; Name: 'TFontSize:large'; Dict: tdValue; Kind: tkValue; Bare: False; IntegerValue: False),
    (Code: $48; Name: 'TFontSize:xlarge'; Dict: tdValue; Kind: tkValue; Bare: False; IntegerValue: False),
    (Code: $49; Name: 'TFontSize:xxlarge'; Dict: tdValue; Kind: tkValue; Bare: False; IntegerValue: False)
  );

function TokenDefForCode(Code: Byte): TTokenDef;
var
  I: Integer;
begin
  for I := 0 to High(MiniTokens) do
    if MiniTokens[I].Code = Code then
      Exit(MiniTokens[I]);
  raise Exception.CreateFmt('Unknown mini token code: %.2x', [Code]);
end;

function TokenDefForName(const Name: string; Kind: TTokenKind): TTokenDef;
var
  I: Integer;
begin
  for I := 0 to High(MiniTokens) do
    if (MiniTokens[I].Name = Name) and (MiniTokens[I].Kind = Kind) then
      Exit(MiniTokens[I]);
  raise Exception.CreateFmt('Unknown mini token name: %s', [Name]);
end;

function TokenDefForCodeInStream(Code: Byte; Stream: TTokenStreamKind): TTokenDef;
var
  I: Integer;
begin
  for I := 0 to High(MiniTokens) do
    if (MiniTokens[I].Code = Code) and DictValidInStream(MiniTokens[I].Dict, Stream) then
      Exit(MiniTokens[I]);
  raise Exception.CreateFmt('Token %.2x is not valid in %s stream',
    [Code, StreamName(Stream)]);
end;

function TokenDefForNameInStream(const Name: string; Kind: TTokenKind;
  Stream: TTokenStreamKind): TTokenDef;
begin
  Result := TokenDefForName(Name, Kind);
  if not DictValidInStream(Result.Dict, Stream) then
    raise Exception.CreateFmt('Token %s is not valid in %s stream',
      [Name, StreamName(Stream)]);
end;

function StreamName(Stream: TTokenStreamKind): string;
begin
  case Stream of
    tsDoc: Result := 'DOC';
    tsDom: Result := 'DOM';
    tsStyle: Result := 'STYLE';
    tsScript: Result := 'SCRIPT';
  else
    Result := 'unknown';
  end;
end;

function DictName(Dict: TTokenDictKind): string;
begin
  case Dict of
    tdDoc: Result := 'DOC';
    tdDom: Result := 'DOM';
    tdStyle: Result := 'STYLE';
    tdAttr: Result := 'ATTR';
    tdValue: Result := 'VALUE';
    tdLjs: Result := 'LJS';
  else
    Result := 'unknown';
  end;
end;

function DictIdForKind(Dict: TTokenDictKind): Byte;
begin
  case Dict of
    tdDoc: Result := DICT_DOC_MINI;
    tdDom: Result := DICT_DOM_MINI;
    tdStyle: Result := DICT_STYLE_MINI;
    tdAttr: Result := DICT_ATTR_MINI;
    tdValue: Result := DICT_VALUE_MINI;
    tdLjs: Result := DICT_LJS_MINI;
  else
    Result := 0;
  end;
end;

function DictKindForId(DictId: Cardinal; out Dict: TTokenDictKind): Boolean;
begin
  Result := True;
  case DictId of
    DICT_DOC_MINI: Dict := tdDoc;
    DICT_DOM_MINI: Dict := tdDom;
    DICT_STYLE_MINI: Dict := tdStyle;
    DICT_ATTR_MINI: Dict := tdAttr;
    DICT_VALUE_MINI: Dict := tdValue;
    DICT_LJS_MINI: Dict := tdLjs;
  else
    Result := False;
  end;
end;

function TokenCountForDict(Dict: TTokenDictKind): Byte;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(MiniTokens) do
    if MiniTokens[I].Dict = Dict then
      Inc(Result);
end;

function DictValidInStream(Dict: TTokenDictKind; Stream: TTokenStreamKind): Boolean;
begin
  case Dict of
    tdDoc: Result := Stream = tsDoc;
    tdDom: Result := Stream = tsDom;
    tdStyle: Result := Stream = tsStyle;
    tdLjs: Result := Stream = tsScript;
    tdAttr, tdValue: Result := True;
  else
    Result := False;
  end;
end;

function MiniTokenDefCount: Integer;
begin
  Result := Length(MiniTokens);
end;

function MiniTokenDefByIndex(Index: Integer): TTokenDef;
begin
  if (Index < 0) or (Index >= Length(MiniTokens)) then
    raise Exception.Create('Mini token index out of range');
  Result := MiniTokens[Index];
end;

function IsBareElement(const Name: string): Boolean;
begin
  if (Name = 'p') or (Name = 'br') then
    Result := TokenDefForName(Name, tkCommand).Bare
  else
    Result := TokenDefForName(Name, tkElement).Bare;
end;

function TokenNameForElement(const Name: string): string;
var
  Def: TTokenDef;
begin
  try
    Def := TokenDefForName(Name, tkCommand);
    if Def.Name = Name then
      Exit('command:' + Name);
  except
  end;
  Result := 'element:' + Name;
end;

function TokenCodeForCommand(const Name: string): Byte;
begin
  Result := TokenDefForName(Name, tkCommand).Code;
end;

function TokenNameForAttr(const Name: string): string;
begin
  Result := 'attr:' + Name;
end;

function IsIntegerAttr(const Name: string): Boolean;
begin
  Result := TokenDefForName(Name, tkAttr).IntegerValue;
end;

function IsColorAttr(const Name: string): Boolean;
begin
  Result := (Name = 'color') or (Name = 'background') or (Name = 'border');
end;

function IsFontFaceAttr(const Name: string): Boolean;
begin
  Result := Name = 'fontFace';
end;

function IsFontSizeAttr(const Name: string): Boolean;
begin
  Result := Name = 'fontSize';
end;

function TokenCodeForValue(const TypeName, ValueName: string): Byte;
begin
  Result := TokenDefForName(TypeName + ':' + ValueName, tkValue).Code;
end;

function TokenNameForValue(const Name: string): string;
begin
  Result := 'value:' + Name;
end;

function ValueTypeForTokenName(const Name: string): string;
var
  P: Integer;
begin
  P := Pos(':', Name);
  if P = 0 then
    raise Exception.CreateFmt('Value token has no type: %s', [Name]);
  Result := Copy(Name, 1, P - 1);
end;

function ValueNameForTokenName(const Name: string): string;
var
  P: Integer;
begin
  P := Pos(':', Name);
  if P = 0 then
    raise Exception.CreateFmt('Value token has no value: %s', [Name]);
  Result := Copy(Name, P + 1, MaxInt);
end;
 
function IsValueTokenInStream(Code: Byte; Stream: TTokenStreamKind): Boolean;
var
  Def: TTokenDef;
begin
  try
    Def := TokenDefForCodeInStream(Code, Stream);
    Result := Def.Kind = tkValue;
  except
    Result := False;
  end;
end;

function TokenCodeForElement(const Name: string): Byte;
begin
  if (Name = 'p') or (Name = 'br') then
    Result := TokenDefForName(Name, tkCommand).Code
  else
    Result := TokenDefForName(Name, tkElement).Code;
end;

function IsElementTokenInStream(Code: Byte; Stream: TTokenStreamKind): Boolean;
var
  Def: TTokenDef;
begin
  try
    Def := TokenDefForCodeInStream(Code, Stream);
    Result := Def.Kind in [tkElement, tkCommand];
  except
    Result := False;
  end;
end;

function IsAttrTokenInStream(Code: Byte; Stream: TTokenStreamKind): Boolean;
var
  Def: TTokenDef;
begin
  try
    Def := TokenDefForCodeInStream(Code, Stream);
    Result := Def.Kind = tkAttr;
  except
    Result := False;
  end;
end;

function TokenCodeForAttr(const Name: string): Byte;
begin
  Result := TokenDefForName(Name, tkAttr).Code;
end;

function ElementNameForToken(Code: Byte): string;
var
  Def: TTokenDef;
begin
  Def := TokenDefForCode(Code);
  if not (Def.Kind in [tkElement, tkCommand]) then
    raise Exception.CreateFmt('Token %.2x is not an element/command', [Code]);
  Result := Def.Name;
end;

function AttrNameForToken(Code: Byte): string;
var
  Def: TTokenDef;
begin
  Def := TokenDefForCode(Code);
  if Def.Kind <> tkAttr then
    raise Exception.CreateFmt('Token %.2x is not an attribute', [Code]);
  Result := Def.Name;
end;

function IsElementToken(Code: Byte): Boolean;
var
  Def: TTokenDef;
begin
  try
    Def := TokenDefForCode(Code);
    Result := Def.Kind in [tkElement, tkCommand];
  except
    Result := False;
  end;
end;

function IsAttrToken(Code: Byte): Boolean;
var
  Def: TTokenDef;
begin
  try
    Def := TokenDefForCode(Code);
    Result := Def.Kind = tkAttr;
  except
    Result := False;
  end;
end;

end.
