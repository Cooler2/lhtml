unit LhtParser;

{$mode objfpc}{$H+}

interface

uses
  LhtDom;

type
  TLhtParser = class
  private
    FSource: string;
    FPos: Integer;
    FRoot: TNode;
    FStack: array of TNode;
    function Current: Char;
    function Eof: Boolean;
    procedure Push(ANode: TNode);
    function Pop: TNode;
    function Top: TNode;
    procedure ParseText;
    procedure ParseRawElement(Node: TNode; const CloseTag: string);
    procedure SkipComment;
    procedure ParseTag;
    function ReadName: string;
    function ReadAttrValue: string;
    procedure SkipSpaces;
    function IsBareTag(const AName: string): Boolean;
    function IsNameChar(C: Char): Boolean;
    function NormalizeText(const S: string): string;
    procedure AddNormalizedAttr(Node: TNode; const AttrName, AttrValue: string);
    procedure ExpandFontAttr(Node: TNode; const AttrValue: string);
    procedure ValidateDocumentShape;
    procedure ValidateStyleNodes(Node: TNode);
    procedure ValidateStructure(Node: TNode);
  public
    constructor Create(const ASource: string);
    destructor Destroy; override;
    function Parse: TNode;
  end;

implementation

uses
  SysUtils, LhtStyle, LhtScript, LhtValidation;

constructor TLhtParser.Create(const ASource: string);
begin
  inherited Create;
  FSource := ASource;
  FPos := 1;
  FRoot := TNode.CreateElement('#document');
  Push(FRoot);
end;

destructor TLhtParser.Destroy;
begin
  FRoot.Free;
  inherited Destroy;
end;

function TLhtParser.Current: Char;
begin
  if Eof then
    Result := #0
  else
    Result := FSource[FPos];
end;

function TLhtParser.Eof: Boolean;
begin
  Result := FPos > Length(FSource);
end;

procedure TLhtParser.Push(ANode: TNode);
var
  N: Integer;
begin
  N := Length(FStack);
  SetLength(FStack, N + 1);
  FStack[N] := ANode;
end;

function TLhtParser.Pop: TNode;
var
  N: Integer;
begin
  N := Length(FStack);
  if N = 0 then
    raise Exception.Create('Parser stack underflow');
  Result := FStack[N - 1];
  SetLength(FStack, N - 1);
end;

function TLhtParser.Top: TNode;
begin
  if Length(FStack) = 0 then
    raise Exception.Create('Parser stack is empty');
  Result := FStack[High(FStack)];
end;

function TLhtParser.IsNameChar(C: Char): Boolean;
begin
  Result := (C in ['A'..'Z']) or (C in ['a'..'z']) or
    (C in ['0'..'9']) or (C in ['_', '-']);
end;

procedure TLhtParser.SkipSpaces;
begin
  while (not Eof) and (Current in [' ', #9, #10, #13]) do
    Inc(FPos);
end;

function TLhtParser.ReadName: string;
var
  Start: Integer;
begin
  Start := FPos;
  while (not Eof) and IsNameChar(Current) do
    Inc(FPos);
  Result := Copy(FSource, Start, FPos - Start);
  if Result = '' then
    raise Exception.CreateFmt('Expected name at byte %d', [FPos]);
end;

function TLhtParser.ReadAttrValue: string;
var
  Quote: Char;
  Start: Integer;
begin
  SkipSpaces;
  if Eof then
    raise Exception.Create('Unexpected EOF in attribute value');

  if Current in ['"', ''''] then
  begin
    Quote := Current;
    Inc(FPos);
    Start := FPos;
    while (not Eof) and (Current <> Quote) do
      Inc(FPos);
    if Eof then
      raise Exception.Create('Unterminated quoted attribute value');
    Result := Copy(FSource, Start, FPos - Start);
    Inc(FPos);
  end
  else
  begin
    Start := FPos;
    while (not Eof) and not (Current in [' ', #9, #10, #13, '>']) do
      Inc(FPos);
    Result := Copy(FSource, Start, FPos - Start);
  end;
end;

function TLhtParser.IsBareTag(const AName: string): Boolean;
begin
  Result := IsMiniBareTag(AName);
end;

function TLhtParser.NormalizeText(const S: string): string;
var
  I: Integer;
  C: Char;
  InSpace: Boolean;
begin
  Result := '';
  InSpace := True;
  for I := 1 to Length(S) do
  begin
    C := S[I];
    if C in [' ', #9, #10, #13] then
    begin
      if not InSpace then
      begin
        Result := Result + ' ';
        InSpace := True;
      end;
    end
    else
    begin
      Result := Result + C;
      InSpace := False;
    end;
  end;
  Result := Trim(Result);
end;

procedure TLhtParser.ExpandFontAttr(Node: TNode; const AttrValue: string);
var
  Start: Integer;
  Pos: Integer;
  Part: string;
begin
  Pos := 1;
  while Pos <= Length(AttrValue) + 1 do
  begin
    Start := Pos;
    while (Pos <= Length(AttrValue)) and (AttrValue[Pos] <> ',') do
      Inc(Pos);
    Part := Trim(Copy(AttrValue, Start, Pos - Start));
    if Part <> '' then
    begin
      if (LowerCase(Part) = 'tiny') or (LowerCase(Part) = 'small') or
        (LowerCase(Part) = 'normal') or (LowerCase(Part) = 'large') or
        (LowerCase(Part) = 'xlarge') or (LowerCase(Part) = 'xxlarge') then
        Node.AddAttr('fontSize', Part)
      else
        Node.AddAttr('fontFace', Part);
    end;
    Inc(Pos);
  end;
end;

procedure TLhtParser.AddNormalizedAttr(Node: TNode; const AttrName, AttrValue: string);
begin
  ValidateMiniAttributeName(AttrName, True);
  ValidateMiniAttributeValue(AttrName, AttrValue);
  if AttrName = 'font' then
    ExpandFontAttr(Node, AttrValue)
  else
    Node.AddAttr(AttrName, AttrValue);
end;

procedure TLhtParser.ParseText;
var
  Start: Integer;
  S: string;
begin
  Start := FPos;
  while (not Eof) and (Current <> '<') do
    Inc(FPos);
  S := NormalizeText(Copy(FSource, Start, FPos - Start));
  if S <> '' then
    Top.AddChild(TNode.CreateText(S));
end;

procedure TLhtParser.ParseRawElement(Node: TNode; const CloseTag: string);
var
  ClosePos: SizeInt;
  RawText: string;
begin
  ClosePos := Pos(CloseTag, LowerCase(Copy(FSource, FPos, MaxInt)));
  if ClosePos = 0 then
    raise Exception.CreateFmt('Unterminated <%s> element', [Node.Name]);
  RawText := Copy(FSource, FPos, ClosePos - 1);
  Node.AddChild(TNode.CreateText(RawText));
  Inc(FPos, ClosePos - 1 + Length(CloseTag));
end;

procedure TLhtParser.SkipComment;
var
  ClosePos: SizeInt;
begin
  if Copy(FSource, FPos, Length('<!--')) <> '<!--' then
    raise Exception.CreateFmt('Expected "<!--" at byte %d', [FPos]);
  ClosePos := Pos('-->', Copy(FSource, FPos + Length('<!--'), MaxInt));
  if ClosePos = 0 then
    raise Exception.Create('Unterminated LHT comment');
  Inc(FPos, Length('<!--') + ClosePos - 1 + Length('-->'));
end;

procedure TLhtParser.ParseTag;
var
  Closing: Boolean;
  SelfClose: Boolean;
  Name: string;
  AttrName: string;
  AttrValue: string;
  Node: TNode;
  Closed: TNode;
begin
  if Current <> '<' then
    raise Exception.CreateFmt('Expected "<" at byte %d', [FPos]);

  if Copy(FSource, FPos, Length('<!--')) = '<!--' then
  begin
    SkipComment;
    Exit;
  end;

  Inc(FPos);

  Closing := False;
  if Current = '/' then
  begin
    Closing := True;
    Inc(FPos);
  end;

  SkipSpaces;
  Name := ReadName;
  ValidateMiniElementName(Name);
  if (not Closing) and (Name = 'library') and (Top.Name <> 'lhtml') then
    raise Exception.Create('Element <library> is allowed only directly under <lhtml>');

  if Closing then
  begin
    if IsBareTag(Name) then
      raise Exception.CreateFmt('Bare tag <%s> must not have a closing tag', [Name]);
    SkipSpaces;
    if Current <> '>' then
      raise Exception.CreateFmt('Expected ">" after closing tag %s', [Name]);
    Inc(FPos);
    Closed := Pop;
    if Closed.Name <> Name then
      raise Exception.CreateFmt('Mismatched closing tag: expected </%s>, got </%s>',
        [Closed.Name, Name]);
    Exit;
  end;

  Node := TNode.CreateElement(Name);
  Top.AddChild(Node);
  SelfClose := False;

  while not Eof do
  begin
    SkipSpaces;
    if Current = '>' then
    begin
      Inc(FPos);
      Break;
    end;
    if Current = '/' then
    begin
      Inc(FPos);
      if Current <> '>' then
        raise Exception.CreateFmt('Expected ">" after "/" in tag %s', [Name]);
      Inc(FPos);
      SelfClose := True;
      Break;
    end;

    AttrName := ReadName;
    SkipSpaces;
    if Current = '=' then
    begin
      Inc(FPos);
      AttrValue := ReadAttrValue;
    end
    else
      AttrValue := 'true';
    AddNormalizedAttr(Node, AttrName, AttrValue);
  end;

  if (not SelfClose) and (not IsBareTag(Name)) then
  begin
    if Name = 'script' then
      ParseRawElement(Node, '</script>')
    else if Name = 'library' then
      ParseRawElement(Node, '</library>')
    else
      Push(Node);
  end;
end;

procedure TLhtParser.ValidateDocumentShape;
var
  I, BodyCount, HeadCount: Integer;
  Doc: TNode;
begin
  if Length(FRoot.Children) <> 1 then
    raise Exception.Create('Mini document expects exactly one <lhtml> root element');
  Doc := FRoot.Children[0];
  if (Doc.Kind <> nkElement) or (Doc.Name <> 'lhtml') then
    raise Exception.Create('Mini document root must be <lhtml>');

  BodyCount := 0;
  HeadCount := 0;
  for I := 0 to High(Doc.Children) do
  begin
    if Doc.Children[I].Kind <> nkElement then
      Continue;
    if Doc.Children[I].Name = 'head' then
      Inc(HeadCount)
    else if Doc.Children[I].Name = 'body' then
      Inc(BodyCount)
    else if (Doc.Children[I].Name <> 'style') and
      (Doc.Children[I].Name <> 'script') and
      (Doc.Children[I].Name <> 'library') then
      raise Exception.CreateFmt('Element <%s> is not allowed directly under <lhtml>',
        [Doc.Children[I].Name]);
  end;

  if HeadCount > 1 then
    raise Exception.Create('Mini document allows at most one <head>');
  if BodyCount <> 1 then
    raise Exception.Create('Mini document expects exactly one <body>');
end;

procedure TLhtParser.ValidateStyleNodes(Node: TNode);
var
  I: Integer;
  Sheet: TLhtStyleSheet;
begin
  if (Node.Kind = nkElement) and (Node.Name = 'style') then
  begin
    Sheet := TLhtStyleSheet.Create;
    try
      ParseStyleSheetText(Node.TextContent, Sheet);
    finally
      Sheet.Free;
    end;
    Exit;
  end;

  for I := 0 to High(Node.Children) do
    ValidateStyleNodes(Node.Children[I]);
end;

procedure ValidateScriptNodes(Node: TNode);
var
  I: Integer;
begin
  if (Node.Kind = nkElement) and (Node.Name = 'script') then
  begin
    ParseLjsScriptText(Node.TextContent);
    Exit;
  end;
  if (Node.Kind = nkElement) and (Node.Name = 'library') then
  begin
    if Node.AttrValue('interface', '') = '' then
      raise Exception.Create('Element <library> requires interface attribute');
    ParseLjsLibraryScriptText(Node.TextContent);
    Exit;
  end;
  for I := 0 to High(Node.Children) do
    ValidateScriptNodes(Node.Children[I]);
end;

function IsInlineContentNode(Node: TNode): Boolean;
begin
  if Node.Kind = nkText then
    Exit(True);
  Result := (Node.Kind = nkElement) and
    ((Node.Name = 'span') or (Node.Name = 'a') or
     (Node.Name = 'p') or (Node.Name = 'br'));
end;

procedure TLhtParser.ValidateStructure(Node: TNode);
var
  I: Integer;
  SeenTableRow: Boolean;
  Child: TNode;
begin
  if Node.Kind <> nkElement then
    Exit;

  if Node.Name = 'table' then
  begin
    SeenTableRow := False;
    for I := 0 to High(Node.Children) do
    begin
      Child := Node.Children[I];
      if Child.Kind <> nkElement then
        raise Exception.Create('Element <table> only allows <col> and <tr> children');
      if Child.Name = 'col' then
      begin
        if SeenTableRow then
          raise Exception.Create('Element <col> must appear before the first <tr>');
      end
      else if Child.Name = 'tr' then
        SeenTableRow := True
      else
        raise Exception.CreateFmt('Element <%s> is not allowed inside <table>',
          [Child.Name]);
    end;
  end
  else if Node.Name = 'tr' then
  begin
    for I := 0 to High(Node.Children) do
    begin
      Child := Node.Children[I];
      if (Child.Kind <> nkElement) or (Child.Name <> 'td') then
        raise Exception.Create('Element <tr> only allows <td> children');
    end;
  end
  else if Node.Name = 'td' then
  begin
    for I := 0 to High(Node.Children) do
      if not IsInlineContentNode(Node.Children[I]) then
        raise Exception.CreateFmt('Element <%s> is not allowed inside <td>',
          [Node.Children[I].Name]);
  end
  else if Node.Name = 'col' then
  begin
    if Length(Node.Children) <> 0 then
      raise Exception.Create('Element <col> must be bare');
  end;

  for I := 0 to High(Node.Children) do
    ValidateStructure(Node.Children[I]);
end;

function TLhtParser.Parse: TNode;
begin
  while not Eof do
  begin
    if Current = '<' then
      ParseTag
    else
      ParseText;
  end;

  if Length(FStack) <> 1 then
    raise Exception.CreateFmt('Unclosed tag <%s>', [Top.Name]);

  ValidateDocumentShape;
  ValidateStyleNodes(FRoot);
  ValidateScriptNodes(FRoot);
  ValidateStructure(FRoot);

  Result := FRoot;
  FRoot := nil;
end;

end.
