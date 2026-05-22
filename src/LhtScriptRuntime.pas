unit LhtScriptRuntime;

{$mode objfpc}{$H+}

interface

uses
  LhtDom, LhtScript;

type
  TLjsHostHandlerKind = (lhhOutputRecord, lhhCanvasContext, lhhElementGet);
  TLjsCapability = (lcDebugOutput, lcBrowserAlert, lcCanvasBasic, lcDomVisual);
  TLjsCapabilitySet = set of TLjsCapability;

  TLjsHostBinding = record
    ObjectName: string;
    MethodName: string;
    Capability: TLjsCapability;
    HandlerKind: TLjsHostHandlerKind;
    OutputPrefix: string;
  end;

  TLjsHostBindingArray = array of TLjsHostBinding;

  TLjsRuntimeProfile = record
    Name: string;
    Capabilities: TLjsCapabilitySet;
    StepLimit: Integer;
    StackSlotLimit: Integer;
    OutputRecordLimit: Integer;
    StringLengthLimit: Integer;
    ExpressionDepthLimit: Integer;
    HostObjectLimit: Integer;
    TokenCountLimit: Integer;
    HostBindings: TLjsHostBindingArray;
    DomRoot: TNode;
  end;

function DefaultLjsHostBindings: TLjsHostBindingArray;
function DefaultLjsRuntimeProfile: TLjsRuntimeProfile;
function CliDebugLjsRuntimeProfile: TLjsRuntimeProfile;
function CliPageLjsRuntimeProfile(Root: TNode): TLjsRuntimeProfile;
function IsolatedLjsRuntimeProfile: TLjsRuntimeProfile;
function ExecuteLjsTokens(const Tokens: TLjsTokenArray): string;
function ExecuteLjsTokensWithHosts(const Tokens: TLjsTokenArray;
  const Hosts: TLjsHostBindingArray): string;
function ExecuteLjsTokensWithProfile(const Tokens: TLjsTokenArray;
  const Profile: TLjsRuntimeProfile): string;
function ExecuteLjsScriptText(const S: string): string;
function ExecuteLjsScriptTextWithHosts(const S: string;
  const Hosts: TLjsHostBindingArray): string;
function ExecuteLjsScriptTextWithProfile(const S: string;
  const Profile: TLjsRuntimeProfile): string;

implementation

uses
  SysUtils, Math, LhtValidation;

const
  LJS_DEFAULT_STEP_LIMIT = 10000;
  LJS_DEFAULT_STACK_SLOT_LIMIT = 1000;
  LJS_DEFAULT_OUTPUT_RECORD_LIMIT = 1000;
  LJS_DEFAULT_STRING_LENGTH_LIMIT = 255;
  LJS_DEFAULT_EXPRESSION_DEPTH_LIMIT = 256;
  LJS_DEFAULT_HOST_OBJECT_LIMIT = 1000;
  LJS_DEFAULT_TOKEN_COUNT_LIMIT = 4096;
  LJS_CALL_FRAME_SLOT_OVERHEAD = 1;

type
  TLjsValueKind = (lvNull, lvNumber, lvString, lvBool, lvHostObject);

  TLjsValue = record
    Kind: TLjsValueKind;
    NumberValue: Single;
    StringValue: string;
    BoolValue: Boolean;
    HostObjectId: Integer;
  end;

  TLjsHostObjectKind = (lhoCanvasContext, lhoElement);

  TLjsHostObject = record
    Kind: TLjsHostObjectKind;
    Name: string;
    Node: TNode;
  end;

  TLjsVar = record
    Name: string;
    Value: TLjsValue;
  end;

  TLjsScope = record
    Vars: array of TLjsVar;
  end;

  TLjsFunction = record
    Name: string;
    Params: array of string;
    NodeIndex: Integer;
  end;

  TLjsRuntimeHostBinding = record
    FullName: string;
    Capability: TLjsCapability;
    HandlerKind: TLjsHostHandlerKind;
    OutputPrefix: string;
  end;

  ELjsReturn = class(Exception)
  public
    Value: TLjsValue;
    constructor CreateReturn(const AValue: TLjsValue);
  end;

  TLjsRuntime = class
  private
    FTokens: TLjsTokenArray;
    FAst: TLjsScriptAst;
    FScopes: array of TLjsScope;
    FFunctions: array of TLjsFunction;
    FOutput: string;
    FOutputRecords: Integer;
    FOutputRecordLimit: Integer;
    FSteps: Integer;
    FStepLimit: Integer;
    FStackSlots: Integer;
    FStackSlotLimit: Integer;
    FStringLengthLimit: Integer;
    FExpressionDepthLimit: Integer;
    FHostObjectLimit: Integer;
    FCapabilities: TLjsCapabilitySet;
    FDomRoot: TNode;
    FHostBindings: array of TLjsRuntimeHostBinding;
    FHostObjects: array of TLjsHostObject;
    function FindVar(const Name: string): Integer;
    function FindVarInScope(ScopeIndex: Integer; const Name: string): Integer;
    function GetVar(const Name: string): TLjsValue;
    procedure DeclareVar(const Name: string; const Value: TLjsValue);
    procedure SetVar(const Name: string; const Value: TLjsValue);
    function FindFunction(const Name: string): Integer;
    procedure DeclareFunction(NodeIndex: Integer);
    procedure CollectFunctions;
    procedure CollectFunctionsFromList(const List: TLjsStatementList);
    procedure PushScope;
    procedure PopScope;
    procedure ChargeStackSlots(Count: Integer);
    procedure ReleaseStackSlots(Count: Integer);
    procedure Step;
    procedure AppendOutput(const Prefix: string; const Value: TLjsValue);
    function MakeStringValue(const Value: string): TLjsValue;
    function MakeHostObjectValue(Kind: TLjsHostObjectKind): TLjsValue;
    function RequireHostObjectId(const Value: TLjsValue;
      const OpName: string): Integer;
    function RequireHostObject(const Value: TLjsValue;
      Kind: TLjsHostObjectKind; const OpName: string): Integer;
    function FindElementById(Node: TNode; const Id: string): TNode;
    procedure RequireArgCount(const Args: array of TLjsValue; Count: Integer;
      const OpName: string);
    function EscapeOutputValue(const S: string): string;
    function FindHostCall(const FullName: string): Integer;
    procedure ExecuteHostBinding(const Binding: TLjsRuntimeHostBinding;
      const Args: array of TLjsValue; out ReturnValue: TLjsValue);
    function CallRootHost(const FullName: string;
      const Args: array of TLjsValue): TLjsValue;
    function CallCanvasMethod(const ObjectId: Integer; const AMethodName: string;
      const Args: array of TLjsValue): TLjsValue;
    function CallHostObjectMethod(const Target: TLjsValue; const AMethodName: string;
      const Args: array of TLjsValue): TLjsValue;
    procedure SetHostObjectProperty(const Target: TLjsValue;
      const PropertyName: string; const Value: TLjsValue);
    function EvalExpressionNode(const Expression: TLjsExpression;
      NodeIndex, Depth: Integer): TLjsValue;
    function EvalExpression(const Expression: TLjsExpression): TLjsValue;
    function CallFunction(const Name: string; const Args: array of TLjsValue): TLjsValue;
    procedure ExecNode(NodeIndex: Integer);
    procedure ExecList(const List: TLjsStatementList);
  public
    constructor Create(const Tokens: TLjsTokenArray;
      const Profile: TLjsRuntimeProfile);
    procedure RegisterHostCall(const ObjectName, HostMethodName,
      OutputPrefix: string; Capability: TLjsCapability;
      HandlerKind: TLjsHostHandlerKind);
    function Run: string;
  end;

function NullValue: TLjsValue;
begin
  Result.Kind := lvNull;
end;

function NumberValue(Value: Single): TLjsValue;
begin
  Result.Kind := lvNumber;
  Result.NumberValue := Value;
end;

function BoolValue(Value: Boolean): TLjsValue;
begin
  Result.Kind := lvBool;
  Result.BoolValue := Value;
end;

constructor ELjsReturn.CreateReturn(const AValue: TLjsValue);
begin
  inherited Create('Script return');
  Value := AValue;
end;

function TokenIsDict(const Token: TLjsToken; const Name: string): Boolean;
begin
  Result := (Token.Kind = ljsDict) and (Token.Name = Name);
end;

function ValueToString(const Value: TLjsValue): string;
var
  FS: TFormatSettings;
begin
  case Value.Kind of
    lvNull:
      Result := 'null';
    lvNumber:
      begin
        if SameValue(Frac(Value.NumberValue), 0.0) then
          Result := IntToStr(Round(Value.NumberValue))
        else
        begin
          FS := DefaultFormatSettings;
          FS.DecimalSeparator := '.';
          Result := FloatToStr(Value.NumberValue, FS);
        end;
      end;
    lvString:
      Result := Value.StringValue;
    lvBool:
      if Value.BoolValue then
        Result := 'true'
      else
        Result := 'false';
    lvHostObject:
      Result := '[host object]';
  else
    Result := '';
  end;
end;

function ValueTruthy(const Value: TLjsValue): Boolean;
begin
  case Value.Kind of
    lvNull: Result := False;
    lvNumber: Result := Value.NumberValue <> 0;
    lvString: Result := Value.StringValue <> '';
    lvBool: Result := Value.BoolValue;
    lvHostObject: Result := True;
  else
    Result := False;
  end;
end;

function ValuesEqual(const A, B: TLjsValue): Boolean;
begin
  if A.Kind <> B.Kind then
    Exit(False);
  case A.Kind of
    lvNull: Result := True;
    lvNumber: Result := SameValue(A.NumberValue, B.NumberValue);
    lvString: Result := A.StringValue = B.StringValue;
    lvBool: Result := A.BoolValue = B.BoolValue;
    lvHostObject: Result := A.HostObjectId = B.HostObjectId;
  else
    Result := False;
  end;
end;

function RequireNumber(const Value: TLjsValue; const OpName: string): Single;
begin
  if Value.Kind <> lvNumber then
    raise Exception.CreateFmt('Script operator %s expects number, got %s',
      [OpName, ValueToString(Value)]);
  Result := Value.NumberValue;
end;

function DefaultLjsHostBindings: TLjsHostBindingArray;
begin
  Result := nil;
  SetLength(Result, 4);
  Result[0].ObjectName := 'Debug';
  Result[0].MethodName := 'log';
  Result[0].Capability := lcDebugOutput;
  Result[0].HandlerKind := lhhOutputRecord;
  Result[0].OutputPrefix := 'LOG';
  Result[1].ObjectName := 'Browser';
  Result[1].MethodName := 'alert';
  Result[1].Capability := lcBrowserAlert;
  Result[1].HandlerKind := lhhOutputRecord;
  Result[1].OutputPrefix := 'ALERT';
  Result[2].ObjectName := 'Canvas';
  Result[2].MethodName := 'context';
  Result[2].Capability := lcCanvasBasic;
  Result[2].HandlerKind := lhhCanvasContext;
  Result[2].OutputPrefix := '';
  Result[3].ObjectName := 'Document';
  Result[3].MethodName := 'getElement';
  Result[3].Capability := lcDomVisual;
  Result[3].HandlerKind := lhhElementGet;
  Result[3].OutputPrefix := '';
end;

function IsolatedLjsRuntimeProfile: TLjsRuntimeProfile;
begin
  Result.Name := 'isolated';
  Result.Capabilities := [];
  Result.HostBindings := nil;
  Result.StepLimit := LJS_DEFAULT_STEP_LIMIT;
  Result.StackSlotLimit := LJS_DEFAULT_STACK_SLOT_LIMIT;
  Result.OutputRecordLimit := LJS_DEFAULT_OUTPUT_RECORD_LIMIT;
  Result.StringLengthLimit := LJS_DEFAULT_STRING_LENGTH_LIMIT;
  Result.ExpressionDepthLimit := LJS_DEFAULT_EXPRESSION_DEPTH_LIMIT;
  Result.HostObjectLimit := LJS_DEFAULT_HOST_OBJECT_LIMIT;
  Result.TokenCountLimit := LJS_DEFAULT_TOKEN_COUNT_LIMIT;
  Result.DomRoot := nil;
end;

function CliDebugLjsRuntimeProfile: TLjsRuntimeProfile;
begin
  Result := IsolatedLjsRuntimeProfile;
  Result.Name := 'cli-debug';
  Result.Capabilities := [lcDebugOutput, lcBrowserAlert];
  Result.HostBindings := DefaultLjsHostBindings;
end;

function DefaultLjsRuntimeProfile: TLjsRuntimeProfile;
begin
  Result := CliDebugLjsRuntimeProfile;
end;

function CliPageLjsRuntimeProfile(Root: TNode): TLjsRuntimeProfile;
begin
  Result := CliDebugLjsRuntimeProfile;
  Result.Name := 'cli-page';
  Result.Capabilities := Result.Capabilities + [lcDomVisual];
  Result.DomRoot := Root;
end;

constructor TLjsRuntime.Create(const Tokens: TLjsTokenArray;
  const Profile: TLjsRuntimeProfile);
begin
  inherited Create;
  FTokens := Tokens;
  FOutput := '';
  FOutputRecords := 0;
  FOutputRecordLimit := Profile.OutputRecordLimit;
  FSteps := 0;
  FStepLimit := Profile.StepLimit;
  FStackSlots := 0;
  FStackSlotLimit := Profile.StackSlotLimit;
  FStringLengthLimit := Profile.StringLengthLimit;
  FExpressionDepthLimit := Profile.ExpressionDepthLimit;
  FHostObjectLimit := Profile.HostObjectLimit;
  FCapabilities := Profile.Capabilities;
  FDomRoot := Profile.DomRoot;
  SetLength(FScopes, 1);
  ChargeStackSlots(LJS_CALL_FRAME_SLOT_OVERHEAD);
end;

function TLjsRuntime.FindVar(const Name: string): Integer;
var
  I: Integer;
begin
  for I := High(FScopes) downto 0 do
    if FindVarInScope(I, Name) >= 0 then
      Exit(I);
  Result := -1;
end;

function TLjsRuntime.FindVarInScope(ScopeIndex: Integer; const Name: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FScopes[ScopeIndex].Vars) do
    if FScopes[ScopeIndex].Vars[I].Name = Name then
      Exit(I);
  Result := -1;
end;

function TLjsRuntime.GetVar(const Name: string): TLjsValue;
var
  ScopeIndex, VarIndex: Integer;
begin
  ScopeIndex := FindVar(Name);
  if ScopeIndex < 0 then
    raise Exception.CreateFmt('Unknown script variable: %s', [Name]);
  VarIndex := FindVarInScope(ScopeIndex, Name);
  Result := FScopes[ScopeIndex].Vars[VarIndex].Value;
end;

procedure TLjsRuntime.DeclareVar(const Name: string; const Value: TLjsValue);
var
  ScopeIndex, N: Integer;
begin
  ScopeIndex := High(FScopes);
  if FindVarInScope(ScopeIndex, Name) >= 0 then
    raise Exception.CreateFmt('Duplicate script variable: %s', [Name]);
  N := Length(FScopes[ScopeIndex].Vars);
  ChargeStackSlots(1);
  SetLength(FScopes[ScopeIndex].Vars, N + 1);
  FScopes[ScopeIndex].Vars[N].Name := Name;
  FScopes[ScopeIndex].Vars[N].Value := Value;
end;

procedure TLjsRuntime.SetVar(const Name: string; const Value: TLjsValue);
var
  ScopeIndex, VarIndex: Integer;
begin
  ScopeIndex := FindVar(Name);
  if ScopeIndex < 0 then
    raise Exception.CreateFmt('Unknown script variable: %s', [Name]);
  VarIndex := FindVarInScope(ScopeIndex, Name);
  FScopes[ScopeIndex].Vars[VarIndex].Value := Value;
end;

function TLjsRuntime.FindFunction(const Name: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FFunctions) do
    if FFunctions[I].Name = Name then
      Exit(I);
  Result := -1;
end;

procedure TLjsRuntime.DeclareFunction(NodeIndex: Integer);
var
  I, N: Integer;
  Node: TLjsStatementNode;
begin
  Node := FAst.Nodes[NodeIndex];
  if FindFunction(Node.Name) >= 0 then
    raise Exception.CreateFmt('Duplicate script function: %s', [Node.Name]);
  N := Length(FFunctions);
  SetLength(FFunctions, N + 1);
  FFunctions[N].Name := Node.Name;
  SetLength(FFunctions[N].Params, Length(Node.Params));
  for I := 0 to High(Node.Params) do
    FFunctions[N].Params[I] := Node.Params[I];
  FFunctions[N].NodeIndex := NodeIndex;
end;

procedure TLjsRuntime.CollectFunctions;
begin
  CollectFunctionsFromList(FAst.Root);
end;

procedure TLjsRuntime.CollectFunctionsFromList(const List: TLjsStatementList);
var
  I, NodeIndex: Integer;
begin
  for I := 0 to High(List) do
  begin
    NodeIndex := List[I];
    if FAst.Nodes[NodeIndex].Kind = lskFunction then
      DeclareFunction(NodeIndex);
    CollectFunctionsFromList(FAst.Nodes[NodeIndex].Body);
    CollectFunctionsFromList(FAst.Nodes[NodeIndex].ElseBody);
  end;
end;

procedure TLjsRuntime.PushScope;
begin
  ChargeStackSlots(LJS_CALL_FRAME_SLOT_OVERHEAD);
  SetLength(FScopes, Length(FScopes) + 1);
end;

procedure TLjsRuntime.PopScope;
var
  ScopeSlots: Integer;
begin
  if Length(FScopes) <= 1 then
    raise Exception.Create('Cannot pop global script scope');
  ScopeSlots := LJS_CALL_FRAME_SLOT_OVERHEAD + Length(FScopes[High(FScopes)].Vars);
  SetLength(FScopes, Length(FScopes) - 1);
  ReleaseStackSlots(ScopeSlots);
end;

procedure TLjsRuntime.ChargeStackSlots(Count: Integer);
begin
  if Count <= 0 then
    Exit;
  if FStackSlots + Count > FStackSlotLimit then
    raise Exception.CreateFmt('Script runtime stack slot limit exceeded: %d > %d',
      [FStackSlots + Count, FStackSlotLimit]);
  Inc(FStackSlots, Count);
end;

procedure TLjsRuntime.ReleaseStackSlots(Count: Integer);
begin
  if Count <= 0 then
    Exit;
  Dec(FStackSlots, Count);
  if FStackSlots < 0 then
    raise Exception.Create('Script runtime stack slot accounting underflow');
end;

procedure TLjsRuntime.Step;
begin
  Inc(FSteps);
  if FSteps > FStepLimit then
    raise Exception.Create('Script runtime step limit exceeded');
end;

procedure TLjsRuntime.AppendOutput(const Prefix: string; const Value: TLjsValue);
begin
  if FOutputRecords + 1 > FOutputRecordLimit then
    raise Exception.CreateFmt('Script runtime output record limit exceeded: %d > %d',
      [FOutputRecords + 1, FOutputRecordLimit]);
  Inc(FOutputRecords);
  FOutput := FOutput + Prefix + ': ' + ValueToString(Value) + #10;
end;

function TLjsRuntime.MakeStringValue(const Value: string): TLjsValue;
begin
  if Length(Value) > FStringLengthLimit then
    raise Exception.CreateFmt('Script runtime string length limit exceeded: %d > %d',
      [Length(Value), FStringLengthLimit]);
  Result.Kind := lvString;
  Result.StringValue := Value;
end;

function TLjsRuntime.MakeHostObjectValue(Kind: TLjsHostObjectKind): TLjsValue;
var
  N: Integer;
begin
  N := Length(FHostObjects);
  if N + 1 > FHostObjectLimit then
    raise Exception.CreateFmt('Script runtime host object limit exceeded: %d > %d',
      [N + 1, FHostObjectLimit]);
  SetLength(FHostObjects, N + 1);
  FHostObjects[N].Kind := Kind;
  FHostObjects[N].Name := '';
  FHostObjects[N].Node := nil;
  Result.Kind := lvHostObject;
  Result.HostObjectId := N;
end;

function TLjsRuntime.RequireHostObjectId(const Value: TLjsValue;
  const OpName: string): Integer;
begin
  if Value.Kind <> lvHostObject then
    raise Exception.CreateFmt('Script host method %s expects host object, got %s',
      [OpName, ValueToString(Value)]);
  if (Value.HostObjectId < 0) or (Value.HostObjectId > High(FHostObjects)) then
    raise Exception.CreateFmt('Script host method %s got invalid host object',
      [OpName]);
  Result := Value.HostObjectId;
end;

function TLjsRuntime.RequireHostObject(const Value: TLjsValue;
  Kind: TLjsHostObjectKind; const OpName: string): Integer;
begin
  Result := RequireHostObjectId(Value, OpName);
  if FHostObjects[Result].Kind <> Kind then
    raise Exception.CreateFmt('Script host method %s got incompatible host object',
      [OpName]);
end;

function TLjsRuntime.FindElementById(Node: TNode; const Id: string): TNode;
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
    Result := FindElementById(Node.Children[I], Id);
    if Result <> nil then
      Exit;
  end;
end;

procedure TLjsRuntime.RequireArgCount(const Args: array of TLjsValue;
  Count: Integer; const OpName: string);
var
  ArgLabel: string;
begin
  if Length(Args) <> Count then
  begin
    if Count = 1 then
      ArgLabel := 'argument'
    else
      ArgLabel := 'arguments';
    raise Exception.CreateFmt('Script host method %s expects %d %s, got %d',
      [OpName, Count, ArgLabel, Length(Args)]);
  end;
end;

function TLjsRuntime.EscapeOutputValue(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    case S[I] of
      '\': Result := Result + '\\';
      #10: Result := Result + '\n';
      #13: Result := Result + '\r';
      #9: Result := Result + '\t';
    else
      Result := Result + S[I];
    end;
end;

function TLjsRuntime.FindHostCall(const FullName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FHostBindings) do
    if FHostBindings[I].FullName = FullName then
      Exit(I);
  Result := -1;
end;

function TLjsRuntime.CallRootHost(const FullName: string;
  const Args: array of TLjsValue): TLjsValue;
var
  BindingIndex: Integer;
begin
  BindingIndex := FindHostCall(FullName);
  if BindingIndex < 0 then
    raise Exception.CreateFmt('Unknown script host call: %s', [FullName]);
  ExecuteHostBinding(FHostBindings[BindingIndex], Args, Result);
end;

procedure TLjsRuntime.ExecuteHostBinding(const Binding: TLjsRuntimeHostBinding;
  const Args: array of TLjsValue; out ReturnValue: TLjsValue);
var
  Element: TNode;
begin
  ReturnValue := NullValue;
  case Binding.HandlerKind of
    lhhOutputRecord:
      begin
        RequireArgCount(Args, 1, Binding.FullName);
        AppendOutput(Binding.OutputPrefix, Args[0]);
      end;
    lhhCanvasContext:
      begin
        RequireArgCount(Args, 0, Binding.FullName);
        ReturnValue := MakeHostObjectValue(lhoCanvasContext);
      end;
    lhhElementGet:
      begin
        RequireArgCount(Args, 1, Binding.FullName);
        if Args[0].Kind <> lvString then
          raise Exception.CreateFmt('Script host method %s expects string id, got %s',
            [Binding.FullName, ValueToString(Args[0])]);
        if FDomRoot = nil then
          raise Exception.CreateFmt('Script host method %s requires document root',
            [Binding.FullName]);
        Element := FindElementById(FDomRoot, Args[0].StringValue);
        if Element = nil then
        begin
          ReturnValue := NullValue;
          Exit;
        end;
        ReturnValue := MakeHostObjectValue(lhoElement);
        FHostObjects[ReturnValue.HostObjectId].Name := Args[0].StringValue;
        FHostObjects[ReturnValue.HostObjectId].Node := Element;
      end;
  else
    raise Exception.CreateFmt('Unsupported script host handler for capability %d',
      [Ord(Binding.Capability)]);
  end;
end;

procedure TLjsRuntime.SetHostObjectProperty(const Target: TLjsValue;
  const PropertyName: string; const Value: TLjsValue);
var
  ObjectId: Integer;
begin
  ObjectId := RequireHostObject(Target, lhoElement, PropertyName);
  if not (lcDomVisual in FCapabilities) then
    raise Exception.CreateFmt('Unknown script host property: element.%s',
      [PropertyName]);
  if (PropertyName <> 'color') and (PropertyName <> 'background') and
     (PropertyName <> 'border') and (PropertyName <> 'borderWidth') then
    raise Exception.CreateFmt('Unknown script host property: element.%s',
      [PropertyName]);
  if FHostObjects[ObjectId].Node = nil then
    raise Exception.CreateFmt('Script host property element.%s got stale element handle',
      [PropertyName]);
  ValidateMiniAttributeValue(PropertyName, ValueToString(Value));
  FHostObjects[ObjectId].Node.SetAttr(PropertyName, ValueToString(Value));
  AppendOutput('DOM', MakeStringValue(Format('%s.%s = %s',
    [EscapeOutputValue(FHostObjects[ObjectId].Name), PropertyName,
     EscapeOutputValue(ValueToString(Value))])));
end;

function TLjsRuntime.CallCanvasMethod(const ObjectId: Integer;
  const AMethodName: string; const Args: array of TLjsValue): TLjsValue;
var
  FullName: string;
begin
  FullName := 'canvas.' + AMethodName;
  if not (lcCanvasBasic in FCapabilities) then
    raise Exception.CreateFmt('Unknown script host call: %s', [FullName]);

  Result := NullValue;
  if AMethodName = 'clear' then
  begin
    RequireArgCount(Args, 0, FullName);
    AppendOutput('CANVAS', MakeStringValue('clear'));
  end
  else if AMethodName = 'fillRect' then
  begin
    RequireArgCount(Args, 4, FullName);
    AppendOutput('CANVAS', MakeStringValue(Format('fillRect %s %s %s %s',
      [ValueToString(Args[0]), ValueToString(Args[1]),
       ValueToString(Args[2]), ValueToString(Args[3])])));
  end
  else if AMethodName = 'strokeRect' then
  begin
    RequireArgCount(Args, 4, FullName);
    AppendOutput('CANVAS', MakeStringValue(Format('strokeRect %s %s %s %s',
      [ValueToString(Args[0]), ValueToString(Args[1]),
       ValueToString(Args[2]), ValueToString(Args[3])])));
  end
  else
    raise Exception.CreateFmt('Unknown script host call: %s', [FullName]);
end;

function TLjsRuntime.CallHostObjectMethod(const Target: TLjsValue;
  const AMethodName: string; const Args: array of TLjsValue): TLjsValue;
var
  ObjectId: Integer;
begin
  ObjectId := RequireHostObjectId(Target, AMethodName);
  case FHostObjects[ObjectId].Kind of
    lhoCanvasContext:
      Result := CallCanvasMethod(ObjectId, AMethodName, Args);
    lhoElement:
      raise Exception.CreateFmt('Unknown script host call: element.%s',
        [AMethodName]);
  else
    raise Exception.CreateFmt('Script host method %s got incompatible host object',
      [AMethodName]);
  end;
end;

function TLjsRuntime.EvalExpressionNode(const Expression: TLjsExpression;
  NodeIndex, Depth: Integer): TLjsValue;
var
  I: Integer;
  FS: TFormatSettings;
  Node: TLjsExprNode;
  Token: TLjsToken;
  Left, Right: TLjsValue;
  Args: array of TLjsValue;
  TargetName: string;
begin
  if Depth > FExpressionDepthLimit then
    raise Exception.CreateFmt('Script runtime expression depth limit exceeded: %d > %d',
      [Depth, FExpressionDepthLimit]);
  if (NodeIndex < 0) or (NodeIndex > High(Expression.Nodes)) then
    raise Exception.Create('Invalid script expression node');

  Node := Expression.Nodes[NodeIndex];
  Token := FTokens[Node.TokenIndex];
  if Node.Kind = lenToken then
  begin
    if Token.Kind = ljsNumber then
    begin
      FS := DefaultFormatSettings;
      FS.DecimalSeparator := '.';
      Result := NumberValue(StrToFloat(Token.Value, FS));
    end
    else if Token.Kind = ljsString then
      Result := MakeStringValue(Token.Value)
    else if Token.Kind = ljsIdentifier then
      Result := GetVar(Token.Value)
    else if TokenIsDict(Token, 'kw:true') then
      Result := BoolValue(True)
    else if TokenIsDict(Token, 'kw:false') then
      Result := BoolValue(False)
    else if TokenIsDict(Token, 'kw:null') then
      Result := NullValue
    else
      raise Exception.CreateFmt('Unexpected script runtime value token: %s',
        [LjsTokenDebugName(Token)]);
    Exit;
  end;

  if Node.Kind = lenCall then
  begin
    if Token.Kind <> ljsIdentifier then
      raise Exception.CreateFmt('Unexpected script runtime call target: %s',
        [LjsTokenDebugName(Token)]);
    SetLength(Args, Length(Node.Args));
    for I := 0 to High(Node.Args) do
      Args[I] := EvalExpressionNode(Expression, Node.Args[I], Depth + 1);
    Result := CallFunction(Token.Value, Args);
    Exit;
  end;

  if Node.Kind = lenMemberCall then
  begin
    SetLength(Args, Length(Node.Args));
    for I := 0 to High(Node.Args) do
      Args[I] := EvalExpressionNode(Expression, Node.Args[I], Depth + 1);
    if (Node.Left >= 0) and
       (Expression.Nodes[Node.Left].Kind = lenToken) and
       (FTokens[Expression.Nodes[Node.Left].TokenIndex].Kind = ljsIdentifier) then
    begin
      TargetName := FTokens[Expression.Nodes[Node.Left].TokenIndex].Value;
      if FindVar(TargetName) < 0 then
      begin
        if FindHostCall(TargetName + '.' + Node.Name) >= 0 then
        begin
          Result := CallRootHost(TargetName + '.' + Node.Name, Args);
          Exit;
        end;
        raise Exception.CreateFmt('Unknown script host call: %s.%s',
          [TargetName, Node.Name]);
      end;
    end;

    Left := EvalExpressionNode(Expression, Node.Left, Depth + 1);
    Result := CallHostObjectMethod(Left, Node.Name, Args);
    Exit;
  end;

  Left := EvalExpressionNode(Expression, Node.Left, Depth + 1);
  Right := EvalExpressionNode(Expression, Node.Right, Depth + 1);
  if TokenIsDict(Token, 'op:*') then
    Result := NumberValue(RequireNumber(Left, '*') * RequireNumber(Right, '*'))
  else if TokenIsDict(Token, 'op:/') then
    Result := NumberValue(RequireNumber(Left, '/') / RequireNumber(Right, '/'))
  else if TokenIsDict(Token, 'op:+') then
  begin
    if (Left.Kind = lvString) or (Right.Kind = lvString) then
      Result := MakeStringValue(ValueToString(Left) + ValueToString(Right))
    else
      Result := NumberValue(RequireNumber(Left, '+') + RequireNumber(Right, '+'));
  end
  else if TokenIsDict(Token, 'op:-') then
    Result := NumberValue(RequireNumber(Left, '-') - RequireNumber(Right, '-'))
  else if TokenIsDict(Token, 'op:<') then
    Result := BoolValue(RequireNumber(Left, '<') < RequireNumber(Right, '<'))
  else if TokenIsDict(Token, 'op:>') then
    Result := BoolValue(RequireNumber(Left, '>') > RequireNumber(Right, '>'))
  else if TokenIsDict(Token, 'op:<=') then
    Result := BoolValue(RequireNumber(Left, '<=') <= RequireNumber(Right, '<='))
  else if TokenIsDict(Token, 'op:>=') then
    Result := BoolValue(RequireNumber(Left, '>=') >= RequireNumber(Right, '>='))
  else if TokenIsDict(Token, 'op:==') then
    Result := BoolValue(ValuesEqual(Left, Right))
  else if TokenIsDict(Token, 'op:!=') then
    Result := BoolValue(not ValuesEqual(Left, Right))
  else
    raise Exception.CreateFmt('Unexpected script runtime operator: %s',
      [LjsTokenDebugName(Token)]);
end;

function TLjsRuntime.EvalExpression(const Expression: TLjsExpression): TLjsValue;
begin
  Result := EvalExpressionNode(Expression, Expression.Root, 1);
end;

function TLjsRuntime.CallFunction(const Name: string;
  const Args: array of TLjsValue): TLjsValue;
var
  I, FunctionIndex: Integer;
begin
  Step;
  FunctionIndex := FindFunction(Name);
  if FunctionIndex < 0 then
    raise Exception.CreateFmt('Unknown script function: %s', [Name]);

  PushScope;
  try
    for I := 0 to High(FFunctions[FunctionIndex].Params) do
    begin
      if I <= High(Args) then
        DeclareVar(FFunctions[FunctionIndex].Params[I], Args[I])
      else
        DeclareVar(FFunctions[FunctionIndex].Params[I], NullValue);
    end;
    try
      ExecList(FAst.Nodes[FFunctions[FunctionIndex].NodeIndex].Body);
    except
      on R: ELjsReturn do
      begin
        Result := R.Value;
        Exit;
      end;
    end;
    Result := NullValue;
  finally
    PopScope;
  end;
end;

procedure TLjsRuntime.ExecNode(NodeIndex: Integer);
var
  Node: TLjsStatementNode;
  CondValue: TLjsValue;
begin
  Step;
  Node := FAst.Nodes[NodeIndex];
  case Node.Kind of
    lskLet:
      DeclareVar(Node.Name, EvalExpression(Node.Expr));
    lskAssign:
      SetVar(Node.Name, EvalExpression(Node.Expr));
    lskSetMember:
      SetHostObjectProperty(GetVar(Node.Name), Node.MemberName,
        EvalExpression(Node.Expr));
    lskCall:
      EvalExpression(Node.Expr);
    lskIf:
      begin
        CondValue := EvalExpression(Node.Expr);
        if ValueTruthy(CondValue) then
          ExecList(Node.Body)
        else
          ExecList(Node.ElseBody);
      end;
    lskWhile:
      while ValueTruthy(EvalExpression(Node.Expr)) do
      begin
        Step;
        ExecList(Node.Body);
      end;
    lskFunction:
      begin
      end;
    lskReturn:
      raise ELjsReturn.CreateReturn(EvalExpression(Node.Expr));
  else
    raise Exception.Create('Unknown script AST node');
  end;
end;

procedure TLjsRuntime.ExecList(const List: TLjsStatementList);
var
  I: Integer;
begin
  for I := 0 to High(List) do
    ExecNode(List[I]);
end;

function TLjsRuntime.Run: string;
begin
  FAst := ParseLjsProgram(FTokens);
  CollectFunctions;
  ExecList(FAst.Root);
  Result := FOutput;
end;

procedure TLjsRuntime.RegisterHostCall(const ObjectName, HostMethodName,
  OutputPrefix: string; Capability: TLjsCapability;
  HandlerKind: TLjsHostHandlerKind);
var
  N: Integer;
begin
  if (ObjectName = '') or (HostMethodName = '') then
    raise Exception.Create('Script host binding requires object and method names');
  N := Length(FHostBindings);
  SetLength(FHostBindings, N + 1);
  FHostBindings[N].FullName := ObjectName + '.' + HostMethodName;
  FHostBindings[N].Capability := Capability;
  FHostBindings[N].HandlerKind := HandlerKind;
  FHostBindings[N].OutputPrefix := OutputPrefix;
end;

function ExecuteLjsTokensWithProfile(const Tokens: TLjsTokenArray;
  const Profile: TLjsRuntimeProfile): string;
var
  I: Integer;
  Runtime: TLjsRuntime;
begin
  if Length(Tokens) > Profile.TokenCountLimit then
    raise Exception.CreateFmt('Script runtime token count limit exceeded: %d > %d',
      [Length(Tokens), Profile.TokenCountLimit]);

  Runtime := TLjsRuntime.Create(Tokens, Profile);
  try
    for I := 0 to High(Profile.HostBindings) do
      if Profile.HostBindings[I].Capability in Profile.Capabilities then
        Runtime.RegisterHostCall(Profile.HostBindings[I].ObjectName,
          Profile.HostBindings[I].MethodName, Profile.HostBindings[I].OutputPrefix,
          Profile.HostBindings[I].Capability, Profile.HostBindings[I].HandlerKind);
    Result := Runtime.Run;
  finally
    Runtime.Free;
  end;
end;

function ExecuteLjsTokensWithHosts(const Tokens: TLjsTokenArray;
  const Hosts: TLjsHostBindingArray): string;
var
  Profile: TLjsRuntimeProfile;
begin
  Profile := IsolatedLjsRuntimeProfile;
  Profile.HostBindings := Hosts;
  Profile.Capabilities := [lcDebugOutput, lcBrowserAlert];
  Result := ExecuteLjsTokensWithProfile(Tokens, Profile);
end;

function ExecuteLjsTokens(const Tokens: TLjsTokenArray): string;
begin
  Result := ExecuteLjsTokensWithProfile(Tokens, DefaultLjsRuntimeProfile);
end;

function ExecuteLjsScriptTextWithProfile(const S: string;
  const Profile: TLjsRuntimeProfile): string;
begin
  Result := ExecuteLjsTokensWithProfile(ParseLjsScriptText(S), Profile);
end;

function ExecuteLjsScriptTextWithHosts(const S: string;
  const Hosts: TLjsHostBindingArray): string;
var
  Profile: TLjsRuntimeProfile;
begin
  Profile := IsolatedLjsRuntimeProfile;
  Profile.HostBindings := Hosts;
  Result := ExecuteLjsScriptTextWithProfile(S, Profile);
end;

function ExecuteLjsScriptText(const S: string): string;
begin
  Result := ExecuteLjsScriptTextWithProfile(S, DefaultLjsRuntimeProfile);
end;

end.
