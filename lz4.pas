unit LZ4;

////////////////////////////////////////////////////////////////////////////////
//                                                                            //
// Description:	LZ4 decompressor in pure Pascal                               //
// Version:	0.1                                                           //
// Date:	22-MAR-2025                                                   //
// License:     MIT                                                           //
// Target:	Win64, Free Pascal, Delphi                                    //
// Base on:     PHP code by Stephan J. Müller                                 //
// Copyright:	(c) 2025 Xelitan.com.                                         //
//		All rights reserved.                                          //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

interface

uses Classes, SysUtils;

function LZ4Decode(const InData: TBytes; Offset: Integer = 0): TBytes;
procedure LZ4DecodeStream(InputStream, OutputStream: TStream);

implementation

function LZ4Decode(const InData: TBytes; Offset: Integer = 0): TBytes;

var Len, Token, nLiterals, MatchOffset, MatchLength: Integer;
    i,j: Integer;
    OutData: TBytes;
    OutPos: Integer;

  procedure AddOverflow(var Sum: Integer);
  var Summand: Integer;
  begin
    repeat
      Summand := InData[i];
      Inc(i);
      Inc(Sum, Summand);
    until Summand <> $FF;
  end;

  procedure CopyLiterals(Count: Integer);
  begin
    if (i + Count) > Len then raise Exception.Create('Literals exceed input length');
    SetLength(OutData, OutPos + Count);
    Move(InData[I], OutData[OutPos], Count);
    Inc(i, Count);
    Inc(OutPos, Count);
  end;

  procedure CopyMatch(MatchOffset, MatchLength: Integer);
  var MatchPos, k: Integer;
  begin
    MatchPos := OutPos - MatchOffset;
    if MatchPos < 0 then raise Exception.Create('Invalid match offset');
    SetLength(OutData, OutPos + MatchLength);
    for k := 0 to MatchLength - 1 do begin
      OutData[OutPos] := OutData[MatchPos];
      Inc(OutPos);
      Inc(MatchPos);
    end;
  end;

begin
  Len := Length(InData);
  i := Offset;
  OutPos := 0;
  SetLength(OutData, 0);

  while i < Len do begin
    Token := InData[i];
    Inc(i);
    nLiterals := Token shr 4;
    if nLiterals = $F then AddOverflow(nLiterals);
    CopyLiterals(nLiterals);

    if i >= Len then Break;

    MatchOffset := InData[i] or (InData[i+1] shl 8);
    Inc(i, 2);
    if MatchOffset = 0 then raise Exception.Create('Invalid match offset (zero)');

    MatchLength := Token and $F;
    if MatchLength = $F then AddOverflow(MatchLength);
    Inc(MatchLength, 4);

    CopyMatch(MatchOffset, MatchLength);
  end;

  Result := OutData;
end;

procedure LZ4DecodeStream(InputStream, OutputStream: TStream);
var  Token: Byte;
     nLiterals, MatchOffset, MatchLength: Integer;

  function ReadByte: Byte;
  begin
    if InputStream.Read(Result, 1) <> 1 then raise Exception.Create('Unexpected end of input');
  end;

  procedure AddOverflow(var Sum: Integer);
  var  B: Byte;
  begin
    repeat
      B := ReadByte;
      Inc(Sum, B);
    until B <> $FF;
  end;

  procedure CopyLiterals(Count: Integer);
  var  Buffer: TBytes;
  begin
    if Count = 0 then Exit;
    SetLength(Buffer, Count);
    if InputStream.Read(Buffer[0], Count) <> Count then raise Exception.Create('Failed to read literals');
    OutputStream.WriteBuffer(Buffer[0], Count);
  end;

  procedure CopyMatch(MatchOffset, MatchLength: Integer);
  var CurrentPos, MatchPos, k: Int64;
      Buffer: TBytes;
      B: Byte;
  begin
    CurrentPos := OutputStream.Position;
    MatchPos := CurrentPos - MatchOffset;
    if MatchPos < 0 then raise Exception.Create('Invalid match offset');

    for k := 0 to MatchLength - 1 do begin
      OutputStream.Position := MatchPos + k;
      if OutputStream.Read(B, 1) <> 1 then
        raise Exception.Create('Failed to read match byte');
      OutputStream.Position := CurrentPos + k;
      OutputStream.Write(B, 1);
    end;
    OutputStream.Position := CurrentPos + MatchLength;
  end;

begin
  while InputStream.Position < InputStream.Size do begin
    Token := ReadByte;

    // Process literals
    nLiterals := Token shr 4;
    if nLiterals = $F then AddOverflow(nLiterals);
    CopyLiterals(nLiterals);

    if InputStream.Position >= InputStream.Size then Break;

    // Read match offset (2 bytes)
    MatchOffset := ReadByte or (ReadByte shl 8);
    if MatchOffset = 0 then raise Exception.Create('Invalid match offset (zero)');

    // Match length
    MatchLength := Token and $F;
    if MatchLength = $F then AddOverflow(MatchLength);
    Inc(MatchLength, 4);

    // Copy match
    CopyMatch(MatchOffset, MatchLength);
  end;
end;    

end.
