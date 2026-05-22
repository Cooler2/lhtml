unit LhtCli;

{$mode objfpc}{$H+}

interface

procedure RunLhtC;

implementation

uses
  SysUtils, Classes, LhtDom, LhtParser, LhtDump, LhtTokenDump, LhtBinaryEncode,
  LhtBinaryDecode, LhtBinaryDump, LhtRender, LhtDisplayList, LhtRenderTypes,
  LhtDebugFont, LhtTokenTable, LhtScript, LhtScriptRuntime;

function LoadTextFile(const FileName: string): string;
var
  S: TStringList;
begin
  S := TStringList.Create;
  try
    S.LoadFromFile(FileName);
    Result := S.Text;
  finally
    S.Free;
  end;
end;

procedure Usage;
begin
  WriteLn('Usage: lhtc <command> <file.lht>');
  WriteLn;
  WriteLn('Commands:');
  WriteLn('  parse    Parse and report success');
  WriteLn('  dump     Parse and print normalized tree');
  WriteLn('  tokendump Parse and print mini token stream');
  WriteLn('  tokendumpfile Write mini token stream: lhtc tokendumpfile <input.lht> <output.dump>');
  WriteLn('  encode   Encode mini binary: lhtc encode <input.lht> <output.lhb>');
  WriteLn('  decode   Decode mini binary and print normalized tree');
  WriteLn('  decodedump Decode mini binary to dump file');
  WriteLn('  bintokendump Decode mini binary and print token stream');
  WriteLn('  bindump  Disassemble mini binary byte stream');
  WriteLn('  bindumpfile Disassemble mini binary: lhtc bindumpfile <input.lhb> <output.dump>');
  WriteLn('  render   Execute scripts, then render mini DOM to BMP: lhtc render <input.lht> <output.bmp>');
  WriteLn('  rendergdi Execute scripts, then render mini DOM through GDI: lhtc rendergdi <input.lht> <output.bmp>');
  WriteLn('  runscript Execute document <script> sections: lhtc runscript <input.lht>');
  WriteLn('  dictdump Print current mini dictionaries as markdown');
  WriteLn('  dictdumpfile Write current mini dictionaries: lhtc dictdumpfile <output.md>');
  WriteLn('  checkminimal Check examples/minimal fixtures');
  WriteLn('  checkexample Check one fixture directory: lhtc checkexample <examples/name>');
  WriteLn('  checkvalidation Check parser validation failures');
  WriteLn('  checkall Check all maintained example fixtures');
end;

function ParseFile(const FileName: string): TNode;
var
  Parser: TLhtParser;
begin
  Parser := TLhtParser.Create(LoadTextFile(FileName));
  try
    Result := Parser.Parse;
  finally
    Parser.Free;
  end;
end;

function ExecuteDocumentScripts(Root: TNode): string; forward;

procedure RunReadCommand(const Command, FileName: string);
var
  Root: TNode;
begin
  Root := ParseFile(FileName);
  try
    if Command = 'parse' then
      WriteLn('OK: ', FileName)
    else if Command = 'dump' then
      DumpNode(Root, 0)
    else if Command = 'tokendump' then
      DumpTokens(Root, 0)
    else
      raise Exception.CreateFmt('Unknown command: %s', [Command]);
  finally
    Root.Free;
  end;
end;

procedure RunEncode(const InputName, OutputName: string);
var
  Root: TNode;
  Stream: TFileStream;
begin
  Root := ParseFile(InputName);
  try
    Stream := TFileStream.Create(OutputName, fmCreate);
    try
      EncodeMiniBinary(Root, Stream);
    finally
      Stream.Free;
    end;
  finally
    Root.Free;
  end;
  WriteLn('Wrote ', OutputName);
end;

procedure RunRender(const InputName, OutputName: string);
var
  Root: TNode;
begin
  Root := ParseFile(InputName);
  try
    ExecuteDocumentScripts(Root);
    RenderMiniToBmp(Root, OutputName);
  finally
    Root.Free;
  end;
  WriteLn('Wrote ', OutputName);
end;

procedure RunRenderGdi(const InputName, OutputName: string);
var
  Root: TNode;
begin
  Root := ParseFile(InputName);
  try
    ExecuteDocumentScripts(Root);
    RenderMiniToGdiBmp(Root, OutputName);
  finally
    Root.Free;
  end;
  WriteLn('Wrote ', OutputName);
end;

procedure RunDecodeCommand(const Command, FileName: string);
var
  Stream: TFileStream;
  Root: TNode;
begin
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    Root := DecodeMiniBinary(Stream);
  finally
    Stream.Free;
  end;

  try
    if Command = 'decode' then
      DumpNode(Root, 0)
    else if Command = 'bintokendump' then
      DumpTokens(Root, 0)
    else
      raise Exception.CreateFmt('Unknown decode command: %s', [Command]);
  finally
    Root.Free;
  end;
end;

procedure AppendLibraryBinding(var Libraries: TLjsLibraryBindingArray;
  const InterfaceName, FunctionName, SourceText: string);
var
  N: Integer;
begin
  N := Length(Libraries);
  SetLength(Libraries, N + 1);
  Libraries[N].InterfaceName := InterfaceName;
  Libraries[N].FunctionName := FunctionName;
  Libraries[N].SourceText := SourceText;
end;

procedure AppendSourceLibraryBindings(Node: TNode;
  var Libraries: TLjsLibraryBindingArray);
var
  I: Integer;
  Tokens: TLjsTokenArray;
  Ast: TLjsScriptAst;
  InterfaceName, SourceText: string;
begin
  InterfaceName := Node.AttrValue('interface', '');
  if InterfaceName = '' then
    raise Exception.Create('Element <library> requires interface attribute');
  SourceText := Node.TextContent;
  Tokens := ParseLjsLibraryScriptText(SourceText);
  Ast := ParseLjsLibraryProgram(Tokens);
  if Length(Ast.PublicNames) = 0 then
    raise Exception.CreateFmt('Library %s declares no public interface',
      [InterfaceName]);
  for I := 0 to High(Ast.PublicNames) do
    AppendLibraryBinding(Libraries, InterfaceName, Ast.PublicNames[I],
      SourceText);
end;

procedure AppendScriptOutput(Root, Node: TNode;
  var Libraries: TLjsLibraryBindingArray; var Output: string);
var
  I: Integer;
  Profile: TLjsRuntimeProfile;
begin
  if (Node.Kind = nkElement) and (Node.Name = 'library') then
  begin
    AppendSourceLibraryBindings(Node, Libraries);
    Exit;
  end;

  if (Node.Kind = nkElement) and (Node.Name = 'script') then
  begin
    Profile := CliPageLjsRuntimeProfile(Root);
    Profile.Libraries := Libraries;
    Output := Output + ExecuteLjsScriptTextWithProfile(Node.TextContent, Profile);
  end;
  for I := 0 to High(Node.Children) do
    AppendScriptOutput(Root, Node.Children[I], Libraries, Output);
end;

function ExecuteDocumentScripts(Root: TNode): string;
var
  Libraries: TLjsLibraryBindingArray;
begin
  SetLength(Libraries, 0);
  Result := '';
  AppendScriptOutput(Root, Root, Libraries, Result);
end;

procedure RunScript(const InputName: string);
var
  Root: TNode;
  Output: string;
begin
  Root := ParseFile(InputName);
  try
    Output := ExecuteDocumentScripts(Root);
  finally
    Root.Free;
  end;
  if Output <> '' then
    Write(Output);
end;

procedure RunBinDump(FileName: string);
var
  Stream: TFileStream;
  OutStream: THandleStream;
begin
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    OutStream := THandleStream.Create(TTextRec(Output).Handle);
    try
      DumpMiniBinaryDisasm(Stream, OutStream);
    finally
      OutStream.Free;
    end;
  finally
    Stream.Free;
  end;
end;

procedure RunTokenDumpFile(const InputName, OutputName: string);
var
  Root: TNode;
  OutStream: TFileStream;
begin
  Root := ParseFile(InputName);
  try
    OutStream := TFileStream.Create(OutputName, fmCreate);
    try
      DumpTokensToStream(Root, 0, OutStream);
    finally
      OutStream.Free;
    end;
  finally
    Root.Free;
  end;
  WriteLn('Wrote ', OutputName);
end;

procedure RunBinDumpFile(const InputName, OutputName: string);
var
  InStream: TFileStream;
  OutStream: TFileStream;
begin
  InStream := TFileStream.Create(InputName, fmOpenRead or fmShareDenyWrite);
  try
    OutStream := TFileStream.Create(OutputName, fmCreate);
    try
      DumpMiniBinaryDisasm(InStream, OutStream);
    finally
      OutStream.Free;
    end;
  finally
    InStream.Free;
  end;
  WriteLn('Wrote ', OutputName);
end;

procedure RunDecodeDump(const InputName, OutputName: string);
var
  InStream: TFileStream;
  OutStream: TFileStream;
  Root: TNode;
begin
  InStream := TFileStream.Create(InputName, fmOpenRead or fmShareDenyWrite);
  try
    Root := DecodeMiniBinary(InStream);
  finally
    InStream.Free;
  end;

  try
    OutStream := TFileStream.Create(OutputName, fmCreate);
    try
      DumpNodeToStream(Root, 0, OutStream);
    finally
      OutStream.Free;
    end;
  finally
    Root.Free;
  end;
  WriteLn('Wrote ', OutputName);
end;

function TokenKindName(Kind: TTokenKind): string;
begin
  case Kind of
    tkElement: Result := 'element';
    tkCommand: Result := 'command';
    tkAttr: Result := 'attr';
    tkValue: Result := 'value';
  else
    Result := 'unknown';
  end;
end;

procedure WriteMdLine(Stream: TStream; const S: string);
begin
  if S <> '' then
    Stream.WriteBuffer(S[1], Length(S));
  Stream.WriteBuffer(LineEnding[1], Length(LineEnding));
end;

procedure DumpDictionaryToStream(Stream: TStream; Dict: TTokenDictKind);
var
  I, Entry: Integer;
  Def: TTokenDef;
begin
  WriteMdLine(Stream, '## ' + DictName(Dict));
  WriteMdLine(Stream, '');
  WriteMdLine(Stream, '| Entry | Code | Kind | Name | Bare | Integer |');
  WriteMdLine(Stream, '|---:|---:|---|---|---|---|');
  Entry := 0;
  for I := 0 to MiniTokenDefCount - 1 do
  begin
    Def := MiniTokenDefByIndex(I);
    if Def.Dict <> Dict then
      Continue;
    WriteMdLine(Stream, Format('| `%d` | `%s` | `%s` | `%s` | `%s` | `%s` |',
      [Entry, IntToHex(Def.Code, 2), TokenKindName(Def.Kind), Def.Name,
       BoolToStr(Def.Bare, True), BoolToStr(Def.IntegerValue, True)]));
    Inc(Entry);
  end;
  WriteMdLine(Stream, '');
end;

procedure DumpDictionariesToStream(Stream: TStream);
begin
  WriteMdLine(Stream, '# Current Mini Dictionary Snapshot');
  WriteMdLine(Stream, '');
  WriteMdLine(Stream, 'Generated from `src/LhtTokenTable.pas` by `lhtc dictdumpfile`.');
  WriteMdLine(Stream, 'This is a point-in-time snapshot, not a normative maintained reference.');
  WriteMdLine(Stream, '');
  WriteMdLine(Stream, '| Dict ID | Dictionary | Import count |');
  WriteMdLine(Stream, '|---:|---|---:|');
  WriteMdLine(Stream, Format('| `%d` | `%s` | `%d` |',
    [DictIdForKind(tdDoc), DictName(tdDoc), TokenCountForDict(tdDoc)]));
  WriteMdLine(Stream, Format('| `%d` | `%s` | `%d` |',
    [DictIdForKind(tdDom), DictName(tdDom), TokenCountForDict(tdDom)]));
  WriteMdLine(Stream, Format('| `%d` | `%s` | `%d` |',
    [DictIdForKind(tdStyle), DictName(tdStyle), TokenCountForDict(tdStyle)]));
  WriteMdLine(Stream, Format('| `%d` | `%s` | `%d` |',
    [DictIdForKind(tdAttr), DictName(tdAttr), TokenCountForDict(tdAttr)]));
  WriteMdLine(Stream, Format('| `%d` | `%s` | `%d` |',
    [DictIdForKind(tdValue), DictName(tdValue), TokenCountForDict(tdValue)]));
  WriteMdLine(Stream, Format('| `%d` | `%s` | `%d` |',
    [DictIdForKind(tdLjs), DictName(tdLjs), TokenCountForDict(tdLjs)]));
  WriteMdLine(Stream, '');
  DumpDictionaryToStream(Stream, tdDoc);
  DumpDictionaryToStream(Stream, tdDom);
  DumpDictionaryToStream(Stream, tdStyle);
  DumpDictionaryToStream(Stream, tdAttr);
  DumpDictionaryToStream(Stream, tdValue);
  DumpDictionaryToStream(Stream, tdLjs);
end;

procedure RunDictDump;
var
  OutStream: THandleStream;
begin
  OutStream := THandleStream.Create(TTextRec(Output).Handle);
  try
    DumpDictionariesToStream(OutStream);
  finally
    OutStream.Free;
  end;
end;

procedure RunDictDumpFile(const OutputName: string);
var
  OutStream: TFileStream;
begin
  OutStream := TFileStream.Create(OutputName, fmCreate);
  try
    DumpDictionariesToStream(OutStream);
  finally
    OutStream.Free;
  end;
  WriteLn('Wrote ', OutputName);
end;

function StreamAsString(Stream: TStream): string;
begin
  SetLength(Result, Stream.Size);
  if Stream.Size = 0 then
    Exit;
  Stream.Position := 0;
  Stream.ReadBuffer(Result[1], Length(Result));
end;

function FileAsString(const FileName: string): string;
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    Result := StreamAsString(Stream);
  finally
    Stream.Free;
  end;
end;

procedure RequireSameString(const Name, ExpectedFile, Actual: string);
var
  Expected: string;
begin
  Expected := FileAsString(ExpectedFile);
  if Expected <> Actual then
    raise Exception.CreateFmt('%s fixture mismatch: %s', [Name, ExpectedFile]);
  WriteLn('OK ', Name);
end;

procedure RunCheckExample(const DirName: string);
var
  SourceName: string;
  BinaryName: string;
  DecodedDumpName: string;
  TokenDumpName: string;
  BinaryDumpName: string;
  RuntimeDumpName: string;
  Root: TNode;
  DecodedRoot: TNode;
  Binary: TMemoryStream;
  Dump: TStringStream;
begin
  SourceName := IncludeTrailingPathDelimiter(DirName) + 'index.lht';
  BinaryName := IncludeTrailingPathDelimiter(DirName) + 'index.lhb';
  DecodedDumpName := IncludeTrailingPathDelimiter(DirName) + 'decoded.dump';
  TokenDumpName := IncludeTrailingPathDelimiter(DirName) + 'token.dump';
  BinaryDumpName := IncludeTrailingPathDelimiter(DirName) + 'binary.dump';
  RuntimeDumpName := IncludeTrailingPathDelimiter(DirName) + 'runtime.dump';

  Root := ParseFile(SourceName);
  try
    Binary := TMemoryStream.Create;
    try
      EncodeMiniBinary(Root, Binary);
      RequireSameString('binary', BinaryName, StreamAsString(Binary));

      Dump := TStringStream.Create('');
      try
        DumpTokensToStream(Root, 0, Dump);
        RequireSameString('token dump', TokenDumpName, Dump.DataString);
      finally
        Dump.Free;
      end;

      Binary.Position := 0;
      DecodedRoot := DecodeMiniBinary(Binary);
      try
        Dump := TStringStream.Create('');
        try
          DumpNodeToStream(DecodedRoot, 0, Dump);
          RequireSameString('decoded dump', DecodedDumpName, Dump.DataString);
        finally
          Dump.Free;
        end;
      finally
        DecodedRoot.Free;
      end;

      Binary.Position := 0;
      Dump := TStringStream.Create('');
      try
        DumpMiniBinaryDisasm(Binary, Dump);
        RequireSameString('binary dump', BinaryDumpName, Dump.DataString);
      finally
        Dump.Free;
      end;

      if FileExists(RuntimeDumpName) then
        RequireSameString('runtime dump', RuntimeDumpName,
          ExecuteDocumentScripts(Root));
    finally
      Binary.Free;
    end;
  finally
    Root.Free;
  end;
end;

procedure RunCheckMinimal;
begin
  RunCheckExample('examples\minimal');
end;

procedure RunCheckValidation; forward;
procedure RunCheckScriptRuntime; forward;

procedure RunCheckAll;
begin
  RunCheckExample('examples\minimal');
  RunCheckExample('examples\font-basic');
  RunCheckExample('examples\color-basic');
  RunCheckExample('examples\visual-box');
  RunCheckExample('examples\class-basic');
  RunCheckExample('examples\style-class-basic');
  RunCheckExample('examples\table-basic');
  RunCheckExample('examples\script-basic');
  RunCheckExample('examples\script-visual-dom');
  RunCheckValidation;
  RunCheckScriptRuntime;
end;

procedure ExpectParseFail(const Name, Source, MessagePart: string);
var
  Parser: TLhtParser;
  Root: TNode;
begin
  Parser := TLhtParser.Create(Source);
  Root := nil;
  try
    try
      Root := Parser.Parse;
      raise Exception.CreateFmt('validation case did not fail: %s', [Name]);
    except
      on E: Exception do
      begin
        if Pos(MessagePart, E.Message) = 0 then
          raise Exception.CreateFmt('validation case %s failed with unexpected message: %s',
            [Name, E.Message]);
        WriteLn('OK validation ', Name);
      end;
    end;
  finally
    Root.Free;
    Parser.Free;
  end;
end;

procedure ExpectLibraryParseOk(const Name, Source: string);
begin
  ParseLjsLibraryScriptText(Source);
  WriteLn('OK validation ', Name);
end;

procedure ExpectLibraryParseFail(const Name, Source, MessagePart: string);
begin
  try
    ParseLjsLibraryScriptText(Source);
    raise Exception.CreateFmt('validation case did not fail: %s', [Name]);
  except
    on E: Exception do
    begin
      if Pos(MessagePart, E.Message) = 0 then
        raise Exception.CreateFmt('validation case %s failed with unexpected message: %s',
          [Name, E.Message]);
      WriteLn('OK validation ', Name);
    end;
  end;
end;

procedure RunCheckValidation;
begin
  ExpectParseFail('unknown tag',
    '<lhtml><body><img></body></lhtml>',
    'Unknown mini token name');
  ExpectParseFail('unknown attr',
    '<lhtml version=1><body bogus=1></body></lhtml>',
    'Unknown mini token name');
  ExpectParseFail('bad uint',
    '<lhtml version=no><body></body></lhtml>',
    'expects unsigned integer');
  ExpectParseFail('bad color',
    '<lhtml><body color=#GGG></body></lhtml>',
    'expects color');
  ExpectParseFail('closing bare',
    '<lhtml><body><br></br></body></lhtml>',
    'must not have a closing tag');
  ExpectParseFail('bad style property',
    '<lhtml><style>.x { bogus=1 }</style><body></body></lhtml>',
    'Unknown mini token name');
  ExpectParseFail('table child',
    '<lhtml><body><table><td>Bad</td></table></body></lhtml>',
    'is not allowed inside <table>');
  ExpectParseFail('late col',
    '<lhtml><body><table><tr><td>Ok</td></tr><col></table></body></lhtml>',
    'must appear before the first <tr>');
  ExpectParseFail('tr child',
    '<lhtml><body><table><tr><block>Bad</block></tr></table></body></lhtml>',
    'Element <tr> only allows <td> children');
  ExpectParseFail('td block child',
    '<lhtml><body><table><tr><td><block>Bad</block></td></tr></table></body></lhtml>',
    'is not allowed inside <td>');
  ExpectParseFail('unterminated lht comment',
    '<lhtml><!-- nope<body></body></lhtml>',
    'Unterminated LHT comment');
  ExpectParseFail('bad script char',
    '<lhtml><script>let x = @;</script><body></body></lhtml>',
    'Unexpected script character');
  ExpectParseFail('bad script string',
    '<lhtml><script>Browser.alert("oops);</script><body></body></lhtml>',
    'Unterminated script string literal');
  ExpectParseFail('script let missing ident',
    '<lhtml><script>let = 1;</script><body></body></lhtml>',
    'Expected identifier after let');
  ExpectParseFail('script missing semicolon',
    '<lhtml><script>let x = 1</script><body></body></lhtml>',
    'Expected ";" after let statement');
  ExpectParseFail('script bad call',
    '<lhtml><script>Debug.log(;);</script><body></body></lhtml>',
    'Unexpected script punctuation in expression');
  ExpectParseFail('script bare host alias rejected',
    '<lhtml><script>log(1);</script><body></body></lhtml>',
    'Expected "=" in assignment');
  ExpectParseFail('script unbalanced paren',
    '<lhtml><script>while (x < 4 { Debug.log(x); }</script><body></body></lhtml>',
    'Unexpected script punctuation in expression');
  ExpectParseFail('script stray else',
    '<lhtml><script>else { Debug.log(1); }</script><body></body></lhtml>',
    'Unexpected script else');
  ExpectParseFail('script expression trailing token',
    '<lhtml><script>let x = 1 2;</script><body></body></lhtml>',
    'Unexpected trailing script expression token');
  ExpectParseFail('script return outside function',
    '<lhtml><script>return 1;</script><body></body></lhtml>',
    'Unexpected script return outside function');
  ExpectParseFail('script function inside if rejected',
    '<lhtml><script>if (true) { function hidden() { return 1; } }</script><body></body></lhtml>',
    'Function declaration requires a script block context');
  ExpectParseFail('script nested function rejected',
    '<lhtml><script>function outer() { function inner() { return 1; } return 2; }</script><body></body></lhtml>',
    'Function declaration requires a script block context');
  ExpectParseFail('script public rejected',
    '<lhtml><script>public { add } function add() { return 1; }</script><body></body></lhtml>',
    'Public declaration requires a library script context');
  ExpectParseFail('library requires interface',
    '<lhtml><library>public { add } function add() { return 1; }</library><body></body></lhtml>',
    'Element <library> requires interface attribute');
  ExpectParseFail('library inside body rejected',
    '<lhtml><body><library interface=Bad>public { add } function add() { return 1; }</library></body></lhtml>',
    'Element <library> is allowed only directly under <lhtml>');
  ExpectLibraryParseOk('library public before function',
    'public { add } function add(a, b) { return a + b; }');
  ExpectLibraryParseOk('library public after function',
    'function add(a, b) { return a + b; } public { add }');
  ExpectLibraryParseFail('library public inside if rejected',
    'if (true) { public { add } } function add() { return 1; }',
    'Public declaration requires a library script block context');
  ExpectLibraryParseFail('library public inside function rejected',
    'function outer() { public { outer } return 1; }',
    'Public declaration requires a library script block context');
  ExpectLibraryParseFail('library public unknown function rejected',
    'public { missing } function add() { return 1; }',
    'Unknown public function');
  ExpectLibraryParseFail('library public duplicate name rejected',
    'public { add, add } function add() { return 1; }',
    'Duplicate public function');
  ExpectLibraryParseFail('library duplicate public block rejected',
    'public { add } public { add } function add() { return 1; }',
    'Duplicate public declaration');
end;

procedure ExpectScriptOutput(const Name, Source, Expected: string);
var
  Actual: string;
begin
  Actual := ExecuteLjsScriptText(Source);
  if Actual <> Expected then
    raise Exception.CreateFmt('script runtime case %s output mismatch: got "%s"',
      [Name, Actual]);
  WriteLn('OK script runtime ', Name);
end;

procedure ExpectDocumentScriptOutput(const Name, Source, Expected: string);
var
  Parser: TLhtParser;
  Root: TNode;
  Actual: string;
begin
  Parser := TLhtParser.Create(Source);
  Root := nil;
  try
    Root := Parser.Parse;
    Actual := ExecuteDocumentScripts(Root);
    if Actual <> Expected then
      raise Exception.CreateFmt('script runtime case %s output mismatch: got "%s"',
        [Name, Actual]);
    WriteLn('OK script runtime ', Name);
  finally
    Root.Free;
    Parser.Free;
  end;
end;

procedure ExpectDocumentScriptFail(const Name, Source, MessagePart: string);
var
  Parser: TLhtParser;
  Root: TNode;
begin
  Parser := TLhtParser.Create(Source);
  Root := nil;
  try
    try
      Root := Parser.Parse;
      ExecuteDocumentScripts(Root);
      raise Exception.CreateFmt('script runtime case did not fail: %s', [Name]);
    except
      on E: Exception do
      begin
        if Pos(MessagePart, E.Message) = 0 then
          raise Exception.CreateFmt('script runtime case %s failed with unexpected message: %s',
            [Name, E.Message]);
        WriteLn('OK script runtime ', Name);
      end;
    end;
  finally
    Root.Free;
    Parser.Free;
  end;
end;

procedure ExpectScriptOutputWithProfile(const Name, Source, Expected: string;
  const Profile: TLjsRuntimeProfile);
var
  Actual: string;
begin
  Actual := ExecuteLjsScriptTextWithProfile(Source, Profile);
  if Actual <> Expected then
    raise Exception.CreateFmt('script runtime case %s output mismatch: got "%s"',
      [Name, Actual]);
  WriteLn('OK script runtime ', Name);
end;

procedure ExpectScriptRuntimeFail(const Name, Source, MessagePart: string);
begin
  try
    ExecuteLjsScriptText(Source);
    raise Exception.CreateFmt('script runtime case did not fail: %s', [Name]);
  except
    on E: Exception do
    begin
      if Pos(MessagePart, E.Message) = 0 then
        raise Exception.CreateFmt('script runtime case %s failed with unexpected message: %s',
          [Name, E.Message]);
      WriteLn('OK script runtime ', Name);
    end;
  end;
end;

procedure ExpectScriptRuntimeNoHostsFail(const Name, Source, MessagePart: string);
var
  Profile: TLjsRuntimeProfile;
begin
  Profile := IsolatedLjsRuntimeProfile;
  try
    ExecuteLjsScriptTextWithProfile(Source, Profile);
    raise Exception.CreateFmt('script runtime case did not fail: %s', [Name]);
  except
    on E: Exception do
    begin
      if Pos(MessagePart, E.Message) = 0 then
        raise Exception.CreateFmt('script runtime case %s failed with unexpected message: %s',
          [Name, E.Message]);
      WriteLn('OK script runtime ', Name);
    end;
  end;
end;

procedure ExpectScriptRuntimeProfileFail(const Name, Source,
  MessagePart: string; const Profile: TLjsRuntimeProfile);
begin
  try
    ExecuteLjsScriptTextWithProfile(Source, Profile);
    raise Exception.CreateFmt('script runtime case did not fail: %s', [Name]);
  except
    on E: Exception do
    begin
      if Pos(MessagePart, E.Message) = 0 then
        raise Exception.CreateFmt('script runtime case %s failed with unexpected message: %s',
          [Name, E.Message]);
      WriteLn('OK script runtime ', Name);
    end;
  end;
end;

procedure ExpectScriptLibraryOutput(const Name, Source, InterfaceName,
  LibrarySource, FunctionName, Expected: string);
var
  Actual: string;
begin
  Actual := ExecuteLjsScriptTextWithLibrary(Source, InterfaceName, LibrarySource,
    FunctionName);
  if Actual <> Expected then
    raise Exception.CreateFmt('script runtime case %s output mismatch: got "%s"',
      [Name, Actual]);
  WriteLn('OK script runtime ', Name);
end;

procedure ExpectScriptLibraryFail(const Name, Source, InterfaceName,
  LibrarySource, FunctionName, MessagePart: string);
begin
  try
    ExecuteLjsScriptTextWithLibrary(Source, InterfaceName, LibrarySource,
      FunctionName);
    raise Exception.CreateFmt('script runtime case did not fail: %s', [Name]);
  except
    on E: Exception do
    begin
      if Pos(MessagePart, E.Message) = 0 then
        raise Exception.CreateFmt('script runtime case %s failed with unexpected message: %s',
          [Name, E.Message]);
      WriteLn('OK script runtime ', Name);
    end;
  end;
end;

procedure ExpectDomVisualMutation;
var
  Profile: TLjsRuntimeProfile;
  Root, Body, Block, EscapedBlock: TNode;
  Actual: string;
begin
  Root := TNode.CreateElement('lhtml');
  try
    Body := TNode.CreateElement('body');
    Root.AddChild(Body);
    Block := TNode.CreateElement('block');
    Block.AddAttr('id', 'warning');
    Body.AddChild(Block);
    EscapedBlock := TNode.CreateElement('block');
    EscapedBlock.AddAttr('id', 'line' + #10 + 'break');
    Body.AddChild(EscapedBlock);

    Profile := CliPageLjsRuntimeProfile(Root);
    Actual := ExecuteLjsScriptTextWithProfile(
      'let el = Document.getElement("warning"); el.color = "#C00000"; el.background = "#FFFFCC"; el.border = "#336699"; el.borderWidth = 1;',
      Profile);
    if Actual <> 'DOM: warning.color = #C00000' + #10 +
      'DOM: warning.background = #FFFFCC' + #10 +
      'DOM: warning.border = #336699' + #10 +
      'DOM: warning.borderWidth = 1' + #10 then
      raise Exception.CreateFmt('script runtime case dom visual mutation output mismatch: got "%s"',
        [Actual]);
    if (Block.AttrValue('color', '') <> '#C00000') or
       (Block.AttrValue('background', '') <> '#FFFFCC') or
       (Block.AttrValue('border', '') <> '#336699') or
       (Block.AttrValue('borderWidth', '') <> '1') then
      raise Exception.Create('script runtime case dom visual mutation did not update node attrs');
    Actual := ExecuteLjsScriptTextWithProfile(
      'let el = Document.getElement("line\nbreak"); el.color = "#C00000";',
      Profile);
    if Actual <> 'DOM: line\nbreak.color = #C00000' + #10 then
      raise Exception.CreateFmt('script runtime case dom visual escaped output mismatch: got "%s"',
        [Actual]);
    ExpectScriptRuntimeProfileFail('dom visual property validation',
      'let el = Document.getElement("warning"); el.borderWidth = "wide";',
      'Attribute borderWidth expects unsigned integer', Profile);
    ExpectScriptRuntimeProfileFail('element method dispatch',
      'let el = Document.getElement("warning"); el.flash();',
      'Unknown script host call: element.flash', Profile);
    Profile.HostObjectLimit := 1;
    ExpectScriptRuntimeProfileFail('host object limit',
      'let a = Document.getElement("warning"); let b = Document.getElement("warning");',
      'Script runtime host object limit exceeded', Profile);
    WriteLn('OK script runtime dom visual mutation');
  finally
    Root.Free;
  end;
end;

function FindNodeById(Node: TNode; const Id: string): TNode;
var
  I: Integer;
begin
  Result := nil;
  if Node = nil then
    Exit;
  if (Node.Kind = nkElement) and (Node.AttrValue('id', '') = Id) then
    Exit(Node);
  for I := 0 to High(Node.Children) do
  begin
    Result := FindNodeById(Node.Children[I], Id);
    if Result <> nil then
      Exit;
  end;
end;

function DisplayListHasOwnerColor(List: TLhtDisplayList; Owner: TNode;
  Kind: TLhtDisplayCommandKind; const HexColor: string): Boolean;
var
  I: Integer;
  Cmd: TLhtDisplayCommand;
begin
  for I := 0 to List.Count - 1 do
  begin
    Cmd := List.Command(I);
    if (Cmd.Owner = Owner) and (Cmd.Kind = Kind) and
       (ColorToHex(Cmd.Color) = HexColor) then
      Exit(True);
  end;
  Result := False;
end;

procedure ExpectDocumentScriptDomMutation;
var
  Parser: TLhtParser;
  Root, Block: TNode;
  Output: string;
begin
  Parser := TLhtParser.Create(
    '<lhtml><body><block id="warning">Warning</block></body>' +
    '<script>let el = Document.getElement("warning"); el.color = "#C00000"; el.background = "#FFFFCC"; el.borderWidth = 1;</script></lhtml>');
  Root := nil;
  try
    Root := Parser.Parse;
    Output := ExecuteDocumentScripts(Root);
    Block := FindNodeById(Root, 'warning');
    if Block = nil then
      raise Exception.Create('script runtime case document dom visual mutation lost test block');
    if Output <> 'DOM: warning.color = #C00000' + #10 +
      'DOM: warning.background = #FFFFCC' + #10 +
      'DOM: warning.borderWidth = 1' + #10 then
      raise Exception.CreateFmt('script runtime case document dom visual mutation output mismatch: got "%s"',
        [Output]);
    if (Block.AttrValue('color', '') <> '#C00000') or
       (Block.AttrValue('background', '') <> '#FFFFCC') or
       (Block.AttrValue('borderWidth', '') <> '1') then
      raise Exception.Create('script runtime case document dom visual mutation did not update node attrs');
    WriteLn('OK script runtime document dom visual mutation');
  finally
    Root.Free;
    Parser.Free;
  end;
end;

procedure ExpectScriptVisualDomExampleRender;
var
  Root, StatusPanel, AlertPanel: TNode;
  DisplayList: TLhtDisplayList;
  Font: TLhtDebugFont;
begin
  Root := ParseFile('examples\script-visual-dom\index.lht');
  try
    ExecuteDocumentScripts(Root);
    StatusPanel := FindNodeById(Root, 'statusPanel');
    AlertPanel := FindNodeById(Root, 'alertPanel');
    if (StatusPanel = nil) or (AlertPanel = nil) then
      raise Exception.Create('script visual DOM example lost panel node');

    DisplayList := TLhtDisplayList.Create;
    Font := TLhtDebugFont.Create;
    try
      BuildMiniDisplayList(Root, DisplayList, Font, 640, 720);
      if not DisplayListHasOwnerColor(DisplayList, StatusPanel, dckFillRect,
        '#E9F7EF') then
        raise Exception.Create('script visual DOM example render missed status background');
      if not DisplayListHasOwnerColor(DisplayList, StatusPanel, dckStrokeRect,
        '#23884A') then
        raise Exception.Create('script visual DOM example render missed status border');
      if not DisplayListHasOwnerColor(DisplayList, AlertPanel, dckFillRect,
        '#FFF4D6') then
        raise Exception.Create('script visual DOM example render missed alert background');
      if not DisplayListHasOwnerColor(DisplayList, AlertPanel, dckStrokeRect,
        '#C04A00') then
        raise Exception.Create('script visual DOM example render missed alert border');
    finally
      Font.Free;
      DisplayList.Free;
    end;
    WriteLn('OK script runtime script visual DOM example render');
  finally
    Root.Free;
  end;
end;

procedure RunCheckScriptRuntime;
var
  Profile: TLjsRuntimeProfile;
begin
  ExpectScriptOutput('if true',
    'let x = 2 + 3 * 4; if (x == 14) { Debug.log("ok"); } else { Debug.log("bad"); }',
    'LOG: ok' + #10);
  ExpectScriptOutput('if else',
    'let x = 1; if (x > 2) { Debug.log("bad"); } else { Browser.alert("else"); }',
    'ALERT: else' + #10);
  ExpectScriptOutput('if else condition once',
    'function flag() { Debug.log("cond"); return false; } if (flag()) { Debug.log("bad"); } else { Debug.log("else"); }',
    'LOG: cond' + #10 + 'LOG: else' + #10);
  ExpectScriptOutput('string concat',
    'let name = "LJS"; Debug.log("hello " + name);',
    'LOG: hello LJS' + #10);
  ExpectScriptOutput('host object calls',
    'Debug.log("debug"); Browser.alert("browser");',
    'LOG: debug' + #10 + 'ALERT: browser' + #10);
  ExpectScriptRuntimeFail('host object extra argument',
    'Debug.log(1, 2);',
    'expects 1 argument');
  ExpectScriptRuntimeFail('host root shadowed by variable',
    'let Debug = 1; Debug.log(1);',
    'expects host object');
  Profile := CliDebugLjsRuntimeProfile;
  Profile.Capabilities := [lcDebugOutput];
  ExpectScriptOutputWithProfile('host capability enabled',
    'Debug.log("debug");',
    'LOG: debug' + #10, Profile);
  ExpectScriptRuntimeProfileFail('host capability not enabled',
    'Browser.alert("browser");',
    'Unknown script host call', Profile);
  ExpectScriptRuntimeFail('unknown host object call',
    'Debug.alert("bad");',
    'Unknown script host call');
  ExpectScriptRuntimeNoHostsFail('host object not registered',
    'Debug.log("debug");',
    'Unknown script host call');
  Profile := DefaultLjsRuntimeProfile;
  Profile.Capabilities := Profile.Capabilities + [lcCanvasBasic];
  ExpectScriptOutputWithProfile('canvas basic drawing sink',
    'let ctx = Canvas.context(); ctx.clear(); ctx.fillRect(1, 2, 30, 40); ctx.strokeRect(3, 4, 50, 60);',
    'CANVAS: clear' + #10 + 'CANVAS: fillRect 1 2 30 40' + #10 +
    'CANVAS: strokeRect 3 4 50 60' + #10, Profile);
  ExpectDomVisualMutation;
  ExpectDocumentScriptDomMutation;
  ExpectScriptVisualDomExampleRender;
  Profile := DefaultLjsRuntimeProfile;
  ExpectScriptRuntimeProfileFail('dom visual capability not enabled',
    'let el = Document.getElement("warning");',
    'Unknown script host call', Profile);
  Profile := DefaultLjsRuntimeProfile;
  ExpectScriptRuntimeProfileFail('canvas capability not enabled',
    'let ctx = Canvas.context();',
    'Unknown script host call', Profile);
  ExpectScriptOutput('parenthesized precedence',
    'Debug.log((2 + 3) * 4);',
    'LOG: 20' + #10);
  ExpectScriptOutput('if single statement',
    'if (true) Debug.log("single-if");',
    'LOG: single-if' + #10);
  ExpectScriptOutput('if else single statement',
    'if (false) Debug.log("bad"); else Debug.log("single-else");',
    'LOG: single-else' + #10);
  ExpectScriptOutput('while single statement',
    'let x = 1; while (x < 4) x = x + 1; Debug.log(x);',
    'LOG: 4' + #10);
  ExpectScriptOutput('function call',
    'function inc(x) { return x + 1; } Debug.log(inc(4));',
    'LOG: 5' + #10);
  ExpectScriptOutput('function local scope',
    'let x = 10; function keepLocal(x) { let y = x + 1; return y; } Debug.log(keepLocal(2)); Debug.log(x);',
    'LOG: 3' + #10 + 'LOG: 10' + #10);
  ExpectScriptOutput('function missing argument is null',
    'function second(a, b) { return b; } Debug.log(second(1));',
    'LOG: null' + #10);
  ExpectScriptOutput('function extra arguments ignored',
    'function first(a) { return a; } Debug.log(first(1, 2, 3));',
    'LOG: 1' + #10);
  ExpectScriptLibraryOutput('library plain value call',
    'Debug.log(MathLib.add(2, 3));',
    'MathLib',
    'function add(a, b) { return a + b; }',
    'add',
    'LOG: 5' + #10);
  ExpectScriptLibraryOutput('library public value call',
    'Debug.log(MathLib.add(2, 3));',
    'MathLib',
    'public { add } function add(a, b) { return a + b; } function hidden() { return 0; }',
    'add',
    'LOG: 5' + #10);
  ExpectScriptLibraryFail('library private function rejected',
    'Debug.log(MathLib.hidden());',
    'MathLib',
    'public { add } function add() { return 1; } function hidden() { return 2; }',
    'hidden',
    'Script library function is not public');
  ExpectScriptLibraryFail('library isolated from debug host',
    'Debug.log(LogLib.tryLog(1));',
    'LogLib',
    'function tryLog(value) { Debug.log(value); return value; }',
    'tryLog',
    'Unknown script host call');
  ExpectDocumentScriptOutput('source library public call',
    '<lhtml><library interface=MathLib>public { add } function add(a, b) { return a + b; }</library>' +
    '<script>Debug.log(MathLib.add(7, 8));</script><body></body></lhtml>',
    'LOG: 15' + #10);
  ExpectDocumentScriptFail('source library private call rejected',
    '<lhtml><library interface=MathLib>public { add } function add() { return 1; } function hidden() { return 2; }</library>' +
    '<script>Debug.log(MathLib.hidden());</script><body></body></lhtml>',
    'Unknown script host call: MathLib.hidden');
  ExpectScriptRuntimeFail('unknown variable',
    'Debug.log(missing);',
    'Unknown script variable');
  ExpectScriptRuntimeFail('duplicate variable',
    'let x = 1; let x = 2;',
    'Duplicate script variable');
  ExpectScriptRuntimeFail('stack slot limit',
    'function grow(n) { return grow(n + 1); } Debug.log(grow(0));',
    'Script runtime stack slot limit exceeded');
  Profile := IsolatedLjsRuntimeProfile;
  Profile.StepLimit := 3;
  ExpectScriptRuntimeProfileFail('profile step limit',
    'let x = 0; while (x < 10) x = x + 1;',
    'Script runtime step limit exceeded', Profile);
  Profile := DefaultLjsRuntimeProfile;
  Profile.OutputRecordLimit := 1;
  ExpectScriptRuntimeProfileFail('profile output record limit',
    'Debug.log(1); Debug.log(2);',
    'Script runtime output record limit exceeded', Profile);
  Profile := DefaultLjsRuntimeProfile;
  Profile.StringLengthLimit := 5;
  ExpectScriptRuntimeProfileFail('profile string literal limit',
    'Debug.log("abcdef");',
    'Script runtime string length limit exceeded', Profile);
  ExpectScriptRuntimeProfileFail('profile string concat limit',
    'Debug.log("abc" + "def");',
    'Script runtime string length limit exceeded', Profile);
  Profile := DefaultLjsRuntimeProfile;
  Profile.StringLengthLimit := 300;
  ExpectScriptOutputWithProfile('profile string value above shortstring',
    'Debug.log("' + StringOfChar('a', 260) + '");',
    'LOG: ' + StringOfChar('a', 260) + #10, Profile);
  Profile := DefaultLjsRuntimeProfile;
  Profile.ExpressionDepthLimit := 1;
  ExpectScriptRuntimeProfileFail('profile expression depth limit',
    'Debug.log(1);',
    'Script runtime expression depth limit exceeded', Profile);
  Profile := DefaultLjsRuntimeProfile;
  Profile.TokenCountLimit := 3;
  ExpectScriptRuntimeProfileFail('profile token count limit',
    'let x = 1;',
    'Script runtime token count limit exceeded', Profile);
end;

procedure RunLhtC;
begin
  try
    if ParamCount < 1 then
    begin
      Usage;
      Halt(1);
    end;
    if ParamStr(1) = 'checkminimal' then
    begin
      if ParamCount <> 1 then
      begin
        Usage;
        Halt(1);
      end;
      RunCheckMinimal;
    end
    else if ParamStr(1) = 'checkexample' then
    begin
      if ParamCount <> 2 then
      begin
        Usage;
        Halt(1);
      end;
      RunCheckExample(ParamStr(2));
    end
    else if ParamStr(1) = 'checkall' then
    begin
      if ParamCount <> 1 then
      begin
        Usage;
        Halt(1);
      end;
      RunCheckAll;
    end
    else if ParamStr(1) = 'checkvalidation' then
    begin
      if ParamCount <> 1 then
      begin
        Usage;
        Halt(1);
      end;
      RunCheckValidation;
    end
    else if ParamStr(1) = 'dictdump' then
    begin
      if ParamCount <> 1 then
      begin
        Usage;
        Halt(1);
      end;
      RunDictDump;
    end
    else if ParamStr(1) = 'dictdumpfile' then
    begin
      if ParamCount <> 2 then
      begin
        Usage;
        Halt(1);
      end;
      RunDictDumpFile(ParamStr(2));
    end
    else if ParamStr(1) = 'encode' then
    begin
      if ParamCount <> 3 then
      begin
        Usage;
        Halt(1);
      end;
      RunEncode(ParamStr(2), ParamStr(3));
    end
    else if ParamStr(1) = 'render' then
    begin
      if ParamCount <> 3 then
      begin
        Usage;
        Halt(1);
      end;
      RunRender(ParamStr(2), ParamStr(3));
    end
    else if ParamStr(1) = 'rendergdi' then
    begin
      if ParamCount <> 3 then
      begin
        Usage;
        Halt(1);
      end;
      RunRenderGdi(ParamStr(2), ParamStr(3));
    end
    else if ParamStr(1) = 'runscript' then
    begin
      if ParamCount <> 2 then
      begin
        Usage;
        Halt(1);
      end;
      RunScript(ParamStr(2));
    end
    else if ParamStr(1) = 'tokendumpfile' then
    begin
      if ParamCount <> 3 then
      begin
        Usage;
        Halt(1);
      end;
      RunTokenDumpFile(ParamStr(2), ParamStr(3));
    end
    else if ParamStr(1) = 'decodedump' then
    begin
      if ParamCount <> 3 then
      begin
        Usage;
        Halt(1);
      end;
      RunDecodeDump(ParamStr(2), ParamStr(3));
    end
    else if (ParamStr(1) = 'decode') or (ParamStr(1) = 'bintokendump') then
    begin
      if ParamCount <> 2 then
      begin
        Usage;
        Halt(1);
      end;
      RunDecodeCommand(ParamStr(1), ParamStr(2));
    end
    else if ParamStr(1) = 'bindump' then
    begin
      if ParamCount <> 2 then
      begin
        Usage;
        Halt(1);
      end;
      RunBinDump(ParamStr(2));
    end
    else if ParamStr(1) = 'bindumpfile' then
    begin
      if ParamCount <> 3 then
      begin
        Usage;
        Halt(1);
      end;
      RunBinDumpFile(ParamStr(2), ParamStr(3));
    end
    else
    begin
      if ParamCount <> 2 then
      begin
        Usage;
        Halt(1);
      end;
      RunReadCommand(ParamStr(1), ParamStr(2));
    end;
  except
    on E: Exception do
    begin
      WriteLn(StdErr, 'lhtc: ', E.Message);
      Halt(1);
    end;
  end;
end;

end.
