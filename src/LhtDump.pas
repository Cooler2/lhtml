unit LhtDump;

{$mode objfpc}{$H+}

interface

uses
  Classes, LhtDom;

procedure DumpNode(Node: TNode; Indent: Integer);
procedure DumpNodeToStream(Node: TNode; Indent: Integer; Stream: TStream);

implementation

uses
  SysUtils, LhtTokenTable;

procedure WriteIndent(Stream: TStream; Indent: Integer);
var
  S: string;
begin
  S := StringOfChar(' ', Indent);
  if S <> '' then
    Stream.WriteBuffer(S[1], Length(S));
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

procedure DumpNodeToStream(Node: TNode; Indent: Integer; Stream: TStream);
var
  I: Integer;
begin
  if Node.Kind = nkText then
  begin
    WriteIndent(Stream, Indent);
    WriteLine(Stream, '"' + Node.Text + '"');
    Exit;
  end;

  WriteIndent(Stream, Indent);
  WriteString(Stream, '<' + Node.Name);
  for I := 0 to High(Node.Attrs) do
    WriteString(Stream, ' ' + Node.Attrs[I].Name + '="' + Node.Attrs[I].Value + '"');
  WriteLine(Stream, '>');

  for I := 0 to High(Node.Children) do
    DumpNodeToStream(Node.Children[I], Indent + 2, Stream);

  if (Node.Name <> '#document') and
    ((Node.Name = 'style') or (not IsBareElement(Node.Name))) then
  begin
    WriteIndent(Stream, Indent);
    WriteLine(Stream, '</' + Node.Name + '>');
  end;
end;

procedure DumpNode(Node: TNode; Indent: Integer);
var
  Stream: THandleStream;
begin
  Stream := THandleStream.Create(TTextRec(Output).Handle);
  try
    DumpNodeToStream(Node, Indent, Stream);
  finally
    Stream.Free;
  end;
end;

end.
