unit LhtDom;

{$mode objfpc}{$H+}

interface

type
  TAttr = record
    Name: string;
    Value: string;
  end;

  TNodeKind = (nkElement, nkText);

  TNode = class
  public
    Kind: TNodeKind;
    Name: string;
    Text: string;
    Attrs: array of TAttr;
    Children: array of TNode;
    constructor CreateElement(const AName: string);
    constructor CreateText(const AText: string);
    destructor Destroy; override;
    procedure AddAttr(const AName, AValue: string);
    procedure AddChild(AChild: TNode);
    function TextContent: string;
  end;

implementation

constructor TNode.CreateElement(const AName: string);
begin
  inherited Create;
  Kind := nkElement;
  Name := AName;
end;

constructor TNode.CreateText(const AText: string);
begin
  inherited Create;
  Kind := nkText;
  Text := AText;
end;

destructor TNode.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(Children) do
    Children[I].Free;
  inherited Destroy;
end;

procedure TNode.AddAttr(const AName, AValue: string);
var
  N: Integer;
begin
  N := Length(Attrs);
  SetLength(Attrs, N + 1);
  Attrs[N].Name := AName;
  Attrs[N].Value := AValue;
end;

procedure TNode.AddChild(AChild: TNode);
var
  N: Integer;
begin
  N := Length(Children);
  SetLength(Children, N + 1);
  Children[N] := AChild;
end;

function TNode.TextContent: string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(Children) do
    if Children[I].Kind = nkText then
    begin
      if Result <> '' then
        Result := Result + ' ';
      Result := Result + Children[I].Text;
    end;
end;

end.
