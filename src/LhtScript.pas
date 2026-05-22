unit LhtScript;

{$mode objfpc}{$H+}

interface

type
  TLjsTokenKind = (ljsDict, ljsIdentifier, ljsString, ljsNumber);
  TLjsExprNodeKind = (lenToken, lenBinary, lenCall, lenMemberCall);
  TLjsStatementKind = (lskLet, lskAssign, lskSetMember, lskCall, lskIf,
    lskWhile, lskFunction, lskReturn, lskPublic);

  TLjsToken = record
    Kind: TLjsTokenKind;
    Name: string;
    Value: string;
  end;

  TLjsTokenArray = array of TLjsToken;

  TLjsExprNode = record
    Kind: TLjsExprNodeKind;
    TokenIndex: Integer;
    Name: string;
    Left: Integer;
    Right: Integer;
    Args: array of Integer;
  end;

  TLjsExpression = record
    Nodes: array of TLjsExprNode;
    Root: Integer;
  end;

  TLjsStatementList = array of Integer;

  TLjsStatementNode = record
    Kind: TLjsStatementKind;
    TokenIndex: Integer;
    Name: string;
    MemberName: string;
    Params: array of string;
    Expr: TLjsExpression;
    Body: TLjsStatementList;
    ElseBody: TLjsStatementList;
  end;

  TLjsScriptAst = record
    Nodes: array of TLjsStatementNode;
    Root: TLjsStatementList;
    PublicNames: array of string;
  end;

function ParseLjsScriptText(const S: string): TLjsTokenArray;
function ParseLjsLibraryScriptText(const S: string): TLjsTokenArray;
procedure ValidateLjsTokens(const Tokens: TLjsTokenArray);
procedure ValidateLjsLibraryTokens(const Tokens: TLjsTokenArray);
function ParseLjsExpressionRange(const Tokens: TLjsTokenArray;
  StartIndex, EndIndex: Integer): TLjsExpression;
function ParseLjsProgram(const Tokens: TLjsTokenArray): TLjsScriptAst;
function ParseLjsLibraryProgram(const Tokens: TLjsTokenArray): TLjsScriptAst;
function LjsTokensToText(const Tokens: TLjsTokenArray): string;
function LjsTokenDebugName(const Token: TLjsToken): string;

implementation

uses
  SysUtils;

type
  TLjsExprParser = class
  private
    FTokens: TLjsTokenArray;
    FIndex: Integer;
    FEndIndex: Integer;
    FExpression: TLjsExpression;
    function IsDict(Index: Integer; const Name: string): Boolean;
    function AddNode(Kind: TLjsExprNodeKind; TokenIndex, Left, Right: Integer): Integer;
    function AddCallNode(TokenIndex: Integer; const Args: array of Integer): Integer;
    function AddMemberCallNode(TargetIndex, MethodTokenIndex: Integer;
      const Args: array of Integer): Integer;
    procedure ParseCallArgs(var Args: TLjsStatementList);
    function ParseExpression: Integer;
    function ParseEquality: Integer;
    function ParseComparison: Integer;
    function ParseTerm: Integer;
    function ParseFactor: Integer;
    function ParsePrimary: Integer;
  public
    function Parse(const Tokens: TLjsTokenArray; StartIndex, EndIndex: Integer): TLjsExpression;
  end;

  TLjsStatementParser = class
  private
    FTokens: TLjsTokenArray;
    FIndex: Integer;
    FLibraryMode: Boolean;
    FAst: TLjsScriptAst;
    function AddNode(Kind: TLjsStatementKind; TokenIndex: Integer): Integer;
    function IsDict(Index: Integer; const Name: string): Boolean;
    function ParseExpressionUntil(const EndPuncts: string): TLjsExpression;
    function ParseStatementList(StopAtBrace, AllowReturn,
      AllowFunction, AllowPublic: Boolean): TLjsStatementList;
    function ParseStatement(AllowReturn, AllowFunction,
      AllowPublic: Boolean): Integer;
    function ParseStatementBody(AllowReturn: Boolean): TLjsStatementList;
    function ParseLet: Integer;
    function ParseAssign: Integer;
    function ParseMemberAssign: Integer;
    function ParseHostObjectCall: Integer;
    function ParseReturn(AllowReturn: Boolean): Integer;
    function ParseWhile(AllowReturn: Boolean): Integer;
    function ParseIf(AllowReturn: Boolean): Integer;
    function ParseFunction: Integer;
    function ParsePublic: Integer;
    procedure ValidatePublicInterface;
  public
    function Parse(const Tokens: TLjsTokenArray;
      LibraryMode: Boolean): TLjsScriptAst;
  end;

procedure AddDictToken(var Tokens: TLjsTokenArray; const Name: string);
var
  N: Integer;
begin
  N := Length(Tokens);
  SetLength(Tokens, N + 1);
  Tokens[N].Kind := ljsDict;
  Tokens[N].Name := Name;
end;

procedure AddLiteralToken(var Tokens: TLjsTokenArray; Kind: TLjsTokenKind;
  const Value: string);
var
  N: Integer;
begin
  N := Length(Tokens);
  SetLength(Tokens, N + 1);
  Tokens[N].Kind := Kind;
  Tokens[N].Value := Value;
end;

function IsIdentStart(C: Char): Boolean;
begin
  Result := (C in ['A'..'Z']) or (C in ['a'..'z']) or (C = '_');
end;

function IsIdentChar(C: Char): Boolean;
begin
  Result := IsIdentStart(C) or (C in ['0'..'9']);
end;

function KeywordOrBuiltinName(const Word: string): string;
begin
  if (Word = 'let') or (Word = 'if') or (Word = 'else') or
     (Word = 'while') or (Word = 'function') or (Word = 'return') or
     (Word = 'public') or (Word = 'true') or (Word = 'false') or
     (Word = 'null') then
    Result := 'kw:' + Word
  else
    Result := '';
end;

function ReadStringLiteral(const S: string; var Pos: Integer): string;
var
  Quote: Char;
  Escaped: Boolean;
begin
  Result := '';
  Quote := S[Pos];
  Inc(Pos);
  Escaped := False;
  while Pos <= Length(S) do
  begin
    if Escaped then
    begin
      case S[Pos] of
        'n': Result := Result + #10;
        'r': Result := Result + #13;
        't': Result := Result + #9;
        '\', '"', '''': Result := Result + S[Pos];
      else
        Result := Result + S[Pos];
      end;
      Escaped := False;
    end
    else if S[Pos] = '\' then
      Escaped := True
    else if S[Pos] = Quote then
    begin
      Inc(Pos);
      Exit;
    end
    else
      Result := Result + S[Pos];
    Inc(Pos);
  end;
  raise Exception.Create('Unterminated script string literal');
end;

function ReadNumberLiteral(const S: string; var Pos: Integer): string;
var
  Start: Integer;
  SeenDot: Boolean;
begin
  Start := Pos;
  SeenDot := False;
  while Pos <= Length(S) do
  begin
    if S[Pos] in ['0'..'9'] then
      Inc(Pos)
    else if (S[Pos] = '.') and (not SeenDot) then
    begin
      SeenDot := True;
      Inc(Pos);
    end
    else
      Break;
  end;
  Result := Copy(S, Start, Pos - Start);
  if Result = '.' then
    raise Exception.CreateFmt('Invalid script number at byte %d', [Start]);
end;

procedure SkipBlockComment(const S: string; var Pos: Integer);
begin
  Inc(Pos, 2);
  while Pos < Length(S) do
  begin
    if (S[Pos] = '*') and (S[Pos + 1] = '/') then
    begin
      Inc(Pos, 2);
      Exit;
    end;
    Inc(Pos);
  end;
  raise Exception.Create('Unterminated script block comment');
end;

function TokenizeLjsScriptText(const S: string): TLjsTokenArray;
var
  Pos, Start: Integer;
  Word, Name: string;
begin
  Result := nil;
  Pos := 1;
  while Pos <= Length(S) do
  begin
    if S[Pos] in [' ', #9, #10, #13] then
    begin
      Inc(Pos);
      Continue;
    end;

    if (S[Pos] = '/') and (Pos < Length(S)) and (S[Pos + 1] = '/') then
    begin
      Inc(Pos, 2);
      while (Pos <= Length(S)) and not (S[Pos] in [#10, #13]) do
        Inc(Pos);
      Continue;
    end;

    if (S[Pos] = '/') and (Pos < Length(S)) and (S[Pos + 1] = '*') then
    begin
      SkipBlockComment(S, Pos);
      Continue;
    end;

    if IsIdentStart(S[Pos]) then
    begin
      Start := Pos;
      while (Pos <= Length(S)) and IsIdentChar(S[Pos]) do
        Inc(Pos);
      Word := Copy(S, Start, Pos - Start);
      Name := KeywordOrBuiltinName(Word);
      if Name <> '' then
        AddDictToken(Result, Name)
      else
        AddLiteralToken(Result, ljsIdentifier, Word);
      Continue;
    end;

    if S[Pos] in ['0'..'9'] then
    begin
      AddLiteralToken(Result, ljsNumber, ReadNumberLiteral(S, Pos));
      Continue;
    end;

    if S[Pos] in ['"', ''''] then
    begin
      AddLiteralToken(Result, ljsString, ReadStringLiteral(S, Pos));
      Continue;
    end;

    if Pos < Length(S) then
    begin
      Word := Copy(S, Pos, 2);
      if (Word = '==') or (Word = '!=') or (Word = '<=') or (Word = '>=') then
      begin
        AddDictToken(Result, 'op:' + Word);
        Inc(Pos, 2);
        Continue;
      end;
    end;

    case S[Pos] of
      '=', '+', '-', '*', '/', '<', '>':
        AddDictToken(Result, 'op:' + S[Pos]);
      '(', ')', '{', '}', ';', ',', '.':
        AddDictToken(Result, 'punct:' + S[Pos]);
    else
      raise Exception.CreateFmt('Unexpected script character "%s" at byte %d',
        [S[Pos], Pos]);
    end;
    Inc(Pos);
  end;
end;

function ParseLjsScriptText(const S: string): TLjsTokenArray;
begin
  Result := TokenizeLjsScriptText(S);
  ValidateLjsTokens(Result);
end;

function ParseLjsLibraryScriptText(const S: string): TLjsTokenArray;
begin
  Result := TokenizeLjsScriptText(S);
  ValidateLjsLibraryTokens(Result);
end;

function TokenIsDict(const Token: TLjsToken; const Name: string): Boolean;
begin
  Result := (Token.Kind = ljsDict) and (Token.Name = Name);
end;

function TokenIsPunct(const Token: TLjsToken; const Punct: string): Boolean;
begin
  Result := TokenIsDict(Token, 'punct:' + Punct);
end;

function TokenIsOperator(const Token: TLjsToken): Boolean;
begin
  Result := (Token.Kind = ljsDict) and (Pos('op:', Token.Name) = 1);
end;

function TokenIsValue(const Token: TLjsToken): Boolean;
begin
  Result := (Token.Kind in [ljsIdentifier, ljsString, ljsNumber]) or
    TokenIsDict(Token, 'kw:true') or TokenIsDict(Token, 'kw:false') or
    TokenIsDict(Token, 'kw:null');
end;

function TokenLabel(const Tokens: TLjsTokenArray; Index: Integer): string;
begin
  if (Index < 0) or (Index > High(Tokens)) then
    Result := '<eof>'
  else
    Result := LjsTokenDebugName(Tokens[Index]);
end;

function TLjsExprParser.IsDict(Index: Integer; const Name: string): Boolean;
begin
  Result := (Index >= 0) and (Index <= High(FTokens)) and
    (FTokens[Index].Kind = ljsDict) and (FTokens[Index].Name = Name);
end;

function TLjsExprParser.AddNode(Kind: TLjsExprNodeKind; TokenIndex, Left,
  Right: Integer): Integer;
begin
  Result := Length(FExpression.Nodes);
  SetLength(FExpression.Nodes, Result + 1);
  FExpression.Nodes[Result].Kind := Kind;
  FExpression.Nodes[Result].TokenIndex := TokenIndex;
  FExpression.Nodes[Result].Name := '';
  FExpression.Nodes[Result].Left := Left;
  FExpression.Nodes[Result].Right := Right;
  SetLength(FExpression.Nodes[Result].Args, 0);
end;

function TLjsExprParser.AddCallNode(TokenIndex: Integer;
  const Args: array of Integer): Integer;
var
  I: Integer;
begin
  Result := AddNode(lenCall, TokenIndex, -1, -1);
  SetLength(FExpression.Nodes[Result].Args, Length(Args));
  for I := 0 to High(Args) do
    FExpression.Nodes[Result].Args[I] := Args[I];
end;

function TLjsExprParser.AddMemberCallNode(TargetIndex,
  MethodTokenIndex: Integer; const Args: array of Integer): Integer;
var
  I: Integer;
begin
  Result := AddNode(lenMemberCall, MethodTokenIndex, TargetIndex, -1);
  FExpression.Nodes[Result].Name := FTokens[MethodTokenIndex].Value;
  SetLength(FExpression.Nodes[Result].Args, Length(Args));
  for I := 0 to High(Args) do
    FExpression.Nodes[Result].Args[I] := Args[I];
end;

procedure TLjsExprParser.ParseCallArgs(var Args: TLjsStatementList);
var
  Arg, ArgStart, ArgEnd, DelimIndex, Depth, OldEnd: Integer;
begin
  SetLength(Args, 0);
  if not IsDict(FIndex, 'punct:(') then
    raise Exception.CreateFmt('Expected "(" after script call target, got %s',
      [TokenLabel(FTokens, FIndex)]);
  Inc(FIndex);

  if not IsDict(FIndex, 'punct:)') then
  begin
    while True do
    begin
      ArgStart := FIndex;
      Depth := 0;
      DelimIndex := FIndex;
      while DelimIndex <= FEndIndex do
      begin
        if IsDict(DelimIndex, 'punct:(') then
          Inc(Depth)
        else if IsDict(DelimIndex, 'punct:)') then
        begin
          if Depth = 0 then
            Break;
          Dec(Depth);
        end;
        if (Depth = 0) and IsDict(DelimIndex, 'punct:,') then
          Break;
        Inc(DelimIndex);
      end;
      if DelimIndex > FEndIndex then
        raise Exception.CreateFmt('Expected ")" after script call expression, got %s',
          [TokenLabel(FTokens, DelimIndex)]);
      ArgEnd := DelimIndex - 1;
      if ArgStart > ArgEnd then
        raise Exception.Create('Expected script call argument expression');
      OldEnd := FEndIndex;
      FEndIndex := ArgEnd;
      Arg := ParseExpression;
      if FIndex <= FEndIndex then
        raise Exception.CreateFmt('Unexpected trailing script expression token: %s',
          [TokenLabel(FTokens, FIndex)]);
      FEndIndex := OldEnd;
      FIndex := DelimIndex;
      SetLength(Args, Length(Args) + 1);
      Args[High(Args)] := Arg;
      if IsDict(FIndex, 'punct:,') then
      begin
        Inc(FIndex);
        Continue;
      end;
      Break;
    end;
  end;

  if not IsDict(FIndex, 'punct:)') then
    raise Exception.CreateFmt('Expected ")" after script call expression, got %s',
      [TokenLabel(FTokens, FIndex)]);
  Inc(FIndex);
end;

function TLjsExprParser.ParsePrimary: Integer;
var
  OpenIndex, MethodIndex: Integer;
  Args: array of Integer;
begin
  if FIndex > FEndIndex then
    raise Exception.Create('Expected script expression');

  if TokenIsValue(FTokens[FIndex]) then
  begin
    OpenIndex := FIndex;
    Result := AddNode(lenToken, FIndex, -1, -1);
    Inc(FIndex);
    if (FTokens[OpenIndex].Kind = ljsIdentifier) and IsDict(FIndex, 'punct:(') then
    begin
      ParseCallArgs(Args);
      Result := AddCallNode(OpenIndex, Args);
    end;
  end
  else if IsDict(FIndex, 'punct:(') then
  begin
    OpenIndex := FIndex;
    Inc(FIndex);
    Result := ParseExpression;
    if not IsDict(FIndex, 'punct:)') then
      raise Exception.CreateFmt('Expected ")" in script expression after %s, got %s',
        [TokenLabel(FTokens, OpenIndex), TokenLabel(FTokens, FIndex)]);
    Inc(FIndex);
  end
  else
    raise Exception.CreateFmt('Unexpected script token in expression: %s',
      [TokenLabel(FTokens, FIndex)]);

  while IsDict(FIndex, 'punct:.') do
  begin
    Inc(FIndex);
    if (FIndex > FEndIndex) or (FTokens[FIndex].Kind <> ljsIdentifier) then
      raise Exception.CreateFmt('Expected script member method identifier, got %s',
        [TokenLabel(FTokens, FIndex)]);
    MethodIndex := FIndex;
    Inc(FIndex);
    ParseCallArgs(Args);
    Result := AddMemberCallNode(Result, MethodIndex, Args);
  end;
end;

function TLjsExprParser.ParseFactor: Integer;
var
  OpIndex, Right: Integer;
begin
  Result := ParsePrimary;
  while (FIndex <= FEndIndex) and
    (IsDict(FIndex, 'op:*') or IsDict(FIndex, 'op:/')) do
  begin
    OpIndex := FIndex;
    Inc(FIndex);
    Right := ParsePrimary;
    Result := AddNode(lenBinary, OpIndex, Result, Right);
  end;
end;

function TLjsExprParser.ParseTerm: Integer;
var
  OpIndex, Right: Integer;
begin
  Result := ParseFactor;
  while (FIndex <= FEndIndex) and
    (IsDict(FIndex, 'op:+') or IsDict(FIndex, 'op:-')) do
  begin
    OpIndex := FIndex;
    Inc(FIndex);
    Right := ParseFactor;
    Result := AddNode(lenBinary, OpIndex, Result, Right);
  end;
end;

function TLjsExprParser.ParseComparison: Integer;
var
  OpIndex, Right: Integer;
begin
  Result := ParseTerm;
  while (FIndex <= FEndIndex) and
    (IsDict(FIndex, 'op:<') or IsDict(FIndex, 'op:>') or
     IsDict(FIndex, 'op:<=') or IsDict(FIndex, 'op:>=')) do
  begin
    OpIndex := FIndex;
    Inc(FIndex);
    Right := ParseTerm;
    Result := AddNode(lenBinary, OpIndex, Result, Right);
  end;
end;

function TLjsExprParser.ParseEquality: Integer;
var
  OpIndex, Right: Integer;
begin
  Result := ParseComparison;
  while (FIndex <= FEndIndex) and
    (IsDict(FIndex, 'op:==') or IsDict(FIndex, 'op:!=')) do
  begin
    OpIndex := FIndex;
    Inc(FIndex);
    Right := ParseComparison;
    Result := AddNode(lenBinary, OpIndex, Result, Right);
  end;
end;

function TLjsExprParser.ParseExpression: Integer;
begin
  Result := ParseEquality;
end;

function TLjsExprParser.Parse(const Tokens: TLjsTokenArray; StartIndex,
  EndIndex: Integer): TLjsExpression;
begin
  FTokens := Tokens;
  FIndex := StartIndex;
  FEndIndex := EndIndex;
  SetLength(FExpression.Nodes, 0);
  FExpression.Root := -1;
  if StartIndex > EndIndex then
    raise Exception.Create('Expected script expression');
  FExpression.Root := ParseExpression;
  if FIndex <= FEndIndex then
    raise Exception.CreateFmt('Unexpected trailing script expression token: %s',
      [TokenLabel(FTokens, FIndex)]);
  Result := FExpression;
end;

function ParseLjsExpressionRange(const Tokens: TLjsTokenArray; StartIndex,
  EndIndex: Integer): TLjsExpression;
var
  Parser: TLjsExprParser;
begin
  Parser := TLjsExprParser.Create;
  try
    Result := Parser.Parse(Tokens, StartIndex, EndIndex);
  finally
    Parser.Free;
  end;
end;

procedure ExpectToken(const Tokens: TLjsTokenArray; var Index: Integer;
  const Name, Message: string);
begin
  if (Index > High(Tokens)) or (not TokenIsDict(Tokens[Index], Name)) then
    raise Exception.CreateFmt('%s, got %s', [Message, TokenLabel(Tokens, Index)]);
  Inc(Index);
end;

function FindExpressionEnd(const Tokens: TLjsTokenArray; StartIndex: Integer;
  const EndPuncts: string): Integer;
var
  I, ParenDepth: Integer;
  P: string;
begin
  I := StartIndex;
  ParenDepth := 0;
  while I <= High(Tokens) do
  begin
    if (Tokens[I].Kind = ljsDict) and (Pos('punct:', Tokens[I].Name) = 1) then
    begin
      P := Copy(Tokens[I].Name, 7, MaxInt);
      if (ParenDepth = 0) and (Pos(P, EndPuncts) > 0) then
        Exit(I - 1);
      if P = '(' then
        Inc(ParenDepth)
      else if P = ')' then
      begin
        if ParenDepth <= 0 then
          raise Exception.Create('Unbalanced script ")"');
        Dec(ParenDepth);
      end
      else if (P = ',') and (ParenDepth > 0) then
      begin
      end
      else if P = '.' then
      begin
      end
      else
        raise Exception.CreateFmt('Unexpected script punctuation in expression: %s',
          [TokenLabel(Tokens, I)]);
    end;
    Inc(I);
  end;

  if ParenDepth <> 0 then
    raise Exception.Create('Unbalanced script "("');
  Result := High(Tokens);
end;

procedure ValidateExpression(const Tokens: TLjsTokenArray; var Index: Integer;
  const EndPuncts: string);
var
  EndIndex: Integer;
begin
  EndIndex := FindExpressionEnd(Tokens, Index, EndPuncts);
  ParseLjsExpressionRange(Tokens, Index, EndIndex);
  Index := EndIndex + 1;
end;

function TLjsStatementParser.IsDict(Index: Integer; const Name: string): Boolean;
begin
  Result := (Index >= 0) and (Index <= High(FTokens)) and
    TokenIsDict(FTokens[Index], Name);
end;

function TLjsStatementParser.AddNode(Kind: TLjsStatementKind;
  TokenIndex: Integer): Integer;
begin
  Result := Length(FAst.Nodes);
  SetLength(FAst.Nodes, Result + 1);
  FAst.Nodes[Result].Kind := Kind;
  FAst.Nodes[Result].TokenIndex := TokenIndex;
  FAst.Nodes[Result].Name := '';
  FAst.Nodes[Result].MemberName := '';
  SetLength(FAst.Nodes[Result].Params, 0);
  SetLength(FAst.Nodes[Result].Body, 0);
  SetLength(FAst.Nodes[Result].ElseBody, 0);
  FAst.Nodes[Result].Expr.Root := -1;
  SetLength(FAst.Nodes[Result].Expr.Nodes, 0);
end;

function TLjsStatementParser.ParseExpressionUntil(
  const EndPuncts: string): TLjsExpression;
var
  StartIndex, EndIndex: Integer;
begin
  StartIndex := FIndex;
  EndIndex := FindExpressionEnd(FTokens, StartIndex, EndPuncts);
  Result := ParseLjsExpressionRange(FTokens, StartIndex, EndIndex);
  FIndex := EndIndex + 1;
end;

function TLjsStatementParser.ParseStatementBody(
  AllowReturn: Boolean): TLjsStatementList;
begin
  if IsDict(FIndex, 'punct:{') then
  begin
    Inc(FIndex);
    Result := ParseStatementList(True, AllowReturn, False, False);
    ExpectToken(FTokens, FIndex, 'punct:}', 'Expected script block "}"');
  end
  else
  begin
    SetLength(Result, 1);
    Result[0] := ParseStatement(AllowReturn, False, False);
  end;
end;

function TLjsStatementParser.ParseLet: Integer;
begin
  Result := AddNode(lskLet, FIndex);
  Inc(FIndex);
  if (FIndex > High(FTokens)) or (FTokens[FIndex].Kind <> ljsIdentifier) then
    raise Exception.CreateFmt('Expected identifier after let, got %s',
      [TokenLabel(FTokens, FIndex)]);
  FAst.Nodes[Result].Name := FTokens[FIndex].Value;
  Inc(FIndex);
  ExpectToken(FTokens, FIndex, 'op:=', 'Expected "=" in let statement');
  FAst.Nodes[Result].Expr := ParseExpressionUntil(';');
  ExpectToken(FTokens, FIndex, 'punct:;', 'Expected ";" after let statement');
end;

function TLjsStatementParser.ParseAssign: Integer;
begin
  Result := AddNode(lskAssign, FIndex);
  FAst.Nodes[Result].Name := FTokens[FIndex].Value;
  Inc(FIndex);
  ExpectToken(FTokens, FIndex, 'op:=', 'Expected "=" in assignment');
  FAst.Nodes[Result].Expr := ParseExpressionUntil(';');
  ExpectToken(FTokens, FIndex, 'punct:;', 'Expected ";" after assignment');
end;

function TLjsStatementParser.ParseMemberAssign: Integer;
begin
  Result := AddNode(lskSetMember, FIndex);
  FAst.Nodes[Result].Name := FTokens[FIndex].Value;
  Inc(FIndex);
  ExpectToken(FTokens, FIndex, 'punct:.', 'Expected "." in member assignment');
  if (FIndex > High(FTokens)) or (FTokens[FIndex].Kind <> ljsIdentifier) then
    raise Exception.CreateFmt('Expected member property identifier, got %s',
      [TokenLabel(FTokens, FIndex)]);
  FAst.Nodes[Result].MemberName := FTokens[FIndex].Value;
  Inc(FIndex);
  ExpectToken(FTokens, FIndex, 'op:=', 'Expected "=" in member assignment');
  FAst.Nodes[Result].Expr := ParseExpressionUntil(';');
  ExpectToken(FTokens, FIndex, 'punct:;', 'Expected ";" after member assignment');
end;

function TLjsStatementParser.ParseHostObjectCall: Integer;
begin
  Result := AddNode(lskCall, FIndex);
  FAst.Nodes[Result].Expr := ParseExpressionUntil(';');
  ExpectToken(FTokens, FIndex, 'punct:;', 'Expected ";" after host object call');
end;

function TLjsStatementParser.ParseReturn(AllowReturn: Boolean): Integer;
begin
  if not AllowReturn then
    raise Exception.Create('Unexpected script return outside function');
  Result := AddNode(lskReturn, FIndex);
  Inc(FIndex);
  FAst.Nodes[Result].Expr := ParseExpressionUntil(';');
  ExpectToken(FTokens, FIndex, 'punct:;', 'Expected ";" after return statement');
end;

function TLjsStatementParser.ParseWhile(AllowReturn: Boolean): Integer;
begin
  Result := AddNode(lskWhile, FIndex);
  Inc(FIndex);
  ExpectToken(FTokens, FIndex, 'punct:(', 'Expected "(" after while');
  FAst.Nodes[Result].Expr := ParseExpressionUntil(')');
  ExpectToken(FTokens, FIndex, 'punct:)', 'Expected ")" after while condition');
  FAst.Nodes[Result].Body := ParseStatementBody(AllowReturn);
end;

function TLjsStatementParser.ParseIf(AllowReturn: Boolean): Integer;
begin
  Result := AddNode(lskIf, FIndex);
  Inc(FIndex);
  ExpectToken(FTokens, FIndex, 'punct:(', 'Expected "(" after if');
  FAst.Nodes[Result].Expr := ParseExpressionUntil(')');
  ExpectToken(FTokens, FIndex, 'punct:)', 'Expected ")" after if condition');
  FAst.Nodes[Result].Body := ParseStatementBody(AllowReturn);
  if IsDict(FIndex, 'kw:else') then
  begin
    Inc(FIndex);
    FAst.Nodes[Result].ElseBody := ParseStatementBody(AllowReturn);
  end;
end;

function TLjsStatementParser.ParseFunction: Integer;
begin
  Result := AddNode(lskFunction, FIndex);
  Inc(FIndex);
  if (FIndex > High(FTokens)) or (FTokens[FIndex].Kind <> ljsIdentifier) then
    raise Exception.CreateFmt('Expected identifier after function, got %s',
      [TokenLabel(FTokens, FIndex)]);
  FAst.Nodes[Result].Name := FTokens[FIndex].Value;
  Inc(FIndex);
  ExpectToken(FTokens, FIndex, 'punct:(', 'Expected "(" after function name');
  if not IsDict(FIndex, 'punct:)') then
  begin
    while True do
    begin
      if (FIndex > High(FTokens)) or (FTokens[FIndex].Kind <> ljsIdentifier) then
        raise Exception.CreateFmt('Expected function parameter identifier, got %s',
          [TokenLabel(FTokens, FIndex)]);
      SetLength(FAst.Nodes[Result].Params, Length(FAst.Nodes[Result].Params) + 1);
      FAst.Nodes[Result].Params[High(FAst.Nodes[Result].Params)] :=
        FTokens[FIndex].Value;
      Inc(FIndex);
      if IsDict(FIndex, 'punct:,') then
      begin
        Inc(FIndex);
        Continue;
      end;
      Break;
    end;
  end;
  ExpectToken(FTokens, FIndex, 'punct:)', 'Expected ")" after function parameters');
  ExpectToken(FTokens, FIndex, 'punct:{', 'Expected script block "{"');
  FAst.Nodes[Result].Body := ParseStatementList(True, True, False, False);
  ExpectToken(FTokens, FIndex, 'punct:}', 'Expected script block "}"');
end;

function TLjsStatementParser.ParsePublic: Integer;
begin
  Result := AddNode(lskPublic, FIndex);
  Inc(FIndex);
  ExpectToken(FTokens, FIndex, 'punct:{', 'Expected "{" after public');
  if not IsDict(FIndex, 'punct:}') then
  begin
    while True do
    begin
      if (FIndex > High(FTokens)) or (FTokens[FIndex].Kind <> ljsIdentifier) then
        raise Exception.CreateFmt('Expected public function identifier, got %s',
          [TokenLabel(FTokens, FIndex)]);
      SetLength(FAst.Nodes[Result].Params, Length(FAst.Nodes[Result].Params) + 1);
      FAst.Nodes[Result].Params[High(FAst.Nodes[Result].Params)] :=
        FTokens[FIndex].Value;
      Inc(FIndex);
      if IsDict(FIndex, 'punct:,') then
      begin
        Inc(FIndex);
        Continue;
      end;
      Break;
    end;
  end;
  ExpectToken(FTokens, FIndex, 'punct:}', 'Expected "}" after public names');
end;

function TLjsStatementParser.ParseStatement(AllowReturn,
  AllowFunction, AllowPublic: Boolean): Integer;
begin
  if FIndex > High(FTokens) then
    raise Exception.Create('Unexpected end of script statement');
  if IsDict(FIndex, 'kw:let') then
    Result := ParseLet
  else if IsDict(FIndex, 'kw:while') then
    Result := ParseWhile(AllowReturn)
  else if IsDict(FIndex, 'kw:if') then
    Result := ParseIf(AllowReturn)
  else if IsDict(FIndex, 'kw:return') then
    Result := ParseReturn(AllowReturn)
  else if FTokens[FIndex].Kind = ljsIdentifier then
  begin
    if IsDict(FIndex + 1, 'punct:.') then
    begin
      if (FIndex + 3 <= High(FTokens)) and
         (FTokens[FIndex + 2].Kind = ljsIdentifier) and
         IsDict(FIndex + 3, 'op:=') then
        Result := ParseMemberAssign
      else
        Result := ParseHostObjectCall;
    end
    else
      Result := ParseAssign;
  end
  else if IsDict(FIndex, 'kw:function') then
  begin
    if not AllowFunction then
      raise Exception.Create('Function declaration requires a script block context');
    Result := ParseFunction;
  end
  else if IsDict(FIndex, 'kw:public') then
  begin
    if not FLibraryMode then
      raise Exception.Create('Public declaration requires a library script context');
    if not AllowPublic then
      raise Exception.Create('Public declaration requires a library script block context');
    Result := ParsePublic;
  end
  else if IsDict(FIndex, 'kw:else') then
    raise Exception.Create('Unexpected script else without matching if')
  else
    raise Exception.CreateFmt('Unexpected script statement token: %s',
      [TokenLabel(FTokens, FIndex)]);
end;

function TLjsStatementParser.ParseStatementList(StopAtBrace, AllowReturn,
  AllowFunction, AllowPublic: Boolean): TLjsStatementList;
var
  N: Integer;
  List: TLjsStatementList;
begin
  SetLength(List, 0);
  while FIndex <= High(FTokens) do
  begin
    if IsDict(FIndex, 'punct:}') then
    begin
      if StopAtBrace then
      begin
        Result := List;
        Exit;
      end;
      raise Exception.Create('Unexpected script block "}"');
    end;

    N := Length(List);
    SetLength(List, N + 1);
    List[N] := ParseStatement(AllowReturn, AllowFunction, AllowPublic);
  end;

  if StopAtBrace then
    raise Exception.Create('Unterminated script block');
  Result := List;
end;

procedure TLjsStatementParser.ValidatePublicInterface;
var
  I, J, PublicNode: Integer;
  Name: string;
  Found: Boolean;
begin
  PublicNode := -1;
  for I := 0 to High(FAst.Root) do
    if FAst.Nodes[FAst.Root[I]].Kind = lskPublic then
    begin
      if PublicNode >= 0 then
        raise Exception.Create('Duplicate public declaration in library script');
      PublicNode := FAst.Root[I];
    end;

  if PublicNode < 0 then
    Exit;

  SetLength(FAst.PublicNames, Length(FAst.Nodes[PublicNode].Params));
  for I := 0 to High(FAst.Nodes[PublicNode].Params) do
  begin
    Name := FAst.Nodes[PublicNode].Params[I];
    for J := 0 to I - 1 do
      if FAst.Nodes[PublicNode].Params[J] = Name then
        raise Exception.CreateFmt('Duplicate public function: %s', [Name]);

    Found := False;
    for J := 0 to High(FAst.Root) do
      if (FAst.Nodes[FAst.Root[J]].Kind = lskFunction) and
         (FAst.Nodes[FAst.Root[J]].Name = Name) then
      begin
        Found := True;
        Break;
      end;
    if not Found then
      raise Exception.CreateFmt('Unknown public function: %s', [Name]);

    FAst.PublicNames[I] := Name;
  end;
end;

function TLjsStatementParser.Parse(const Tokens: TLjsTokenArray;
  LibraryMode: Boolean): TLjsScriptAst;
begin
  FTokens := Tokens;
  FIndex := 0;
  FLibraryMode := LibraryMode;
  SetLength(FAst.Nodes, 0);
  SetLength(FAst.Root, 0);
  SetLength(FAst.PublicNames, 0);
  FAst.Root := ParseStatementList(False, False, True, LibraryMode);
  if LibraryMode then
    ValidatePublicInterface;
  Result := FAst;
end;

function ParseLjsProgram(const Tokens: TLjsTokenArray): TLjsScriptAst;
var
  Parser: TLjsStatementParser;
begin
  Parser := TLjsStatementParser.Create;
  try
    Result := Parser.Parse(Tokens, False);
  finally
    Parser.Free;
  end;
end;

function ParseLjsLibraryProgram(const Tokens: TLjsTokenArray): TLjsScriptAst;
var
  Parser: TLjsStatementParser;
begin
  Parser := TLjsStatementParser.Create;
  try
    Result := Parser.Parse(Tokens, True);
  finally
    Parser.Free;
  end;
end;

procedure ValidateLjsTokens(const Tokens: TLjsTokenArray);
begin
  ParseLjsProgram(Tokens);
end;

procedure ValidateLjsLibraryTokens(const Tokens: TLjsTokenArray);
begin
  ParseLjsLibraryProgram(Tokens);
end;

function EscapeStringLiteral(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    case S[I] of
      '\': Result := Result + '\\';
      '"': Result := Result + '\"';
      #9: Result := Result + '\t';
      #10: Result := Result + '\n';
      #13: Result := Result + '\r';
    else
      Result := Result + S[I];
    end;
  end;
end;

function TokenText(const Token: TLjsToken): string;
begin
  case Token.Kind of
    ljsDict:
      begin
        if Pos('kw:', Token.Name) = 1 then
          Result := Copy(Token.Name, 4, MaxInt)
        else if Pos('op:', Token.Name) = 1 then
          Result := Copy(Token.Name, 4, MaxInt)
        else if Pos('punct:', Token.Name) = 1 then
          Result := Copy(Token.Name, 7, MaxInt)
        else if Pos('builtin:', Token.Name) = 1 then
          Result := Copy(Token.Name, 9, MaxInt)
        else
          Result := Token.Name;
      end;
    ljsIdentifier, ljsNumber:
      Result := Token.Value;
    ljsString:
      Result := '"' + EscapeStringLiteral(Token.Value) + '"';
  else
    Result := '';
  end;
end;

function IsNoSpaceBefore(const S: string): Boolean;
begin
  Result := (S = ')') or (S = '}') or (S = ';') or (S = ',') or (S = '.');
end;

function IsNoSpaceAfter(const S: string): Boolean;
begin
  Result := (S = '(') or (S = '{') or (S = '.');
end;

function IsCallOpen(const Tokens: TLjsTokenArray; Index: Integer;
  const Part: string): Boolean;
begin
  Result := False;
  if (Part <> '(') or (Index <= 0) then
    Exit;
  Result := (Tokens[Index - 1].Kind = ljsIdentifier) or
    ((Tokens[Index - 1].Kind = ljsDict) and
     (Pos('builtin:', Tokens[Index - 1].Name) = 1));
end;

function LjsTokensToText(const Tokens: TLjsTokenArray): string;
var
  I: Integer;
  Part, Prev: string;
begin
  Result := '';
  Prev := '';
  for I := 0 to High(Tokens) do
  begin
    Part := TokenText(Tokens[I]);
    if Result <> '' then
    begin
      if Prev = ';' then
        Result := Result + LineEnding
      else if IsCallOpen(Tokens, I, Part) then
      begin
      end
      else if (not IsNoSpaceBefore(Part)) and (not IsNoSpaceAfter(Prev)) then
        Result := Result + ' ';
    end;
    Result := Result + Part;
    Prev := Part;
  end;
  if Result <> '' then
    Result := Result + LineEnding;
end;

function LjsTokenDebugName(const Token: TLjsToken): string;
begin
  case Token.Kind of
    ljsDict: Result := Token.Name;
    ljsIdentifier: Result := 'identifier:' + Token.Value;
    ljsString: Result := 'string:"' + EscapeStringLiteral(Token.Value) + '"';
    ljsNumber: Result := 'number:' + Token.Value;
  else
    Result := 'unknown';
  end;
end;

end.
