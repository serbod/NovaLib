{ Simple objects

(C) Sergey Bodrov (serbod@gmail.com)
MIT license


TSimpleLock - simple spin-lock
}
unit SimpleObj;

{$ifdef FPC}
{$mode objfpc}{$H+}
{$endif}

interface

uses
  {$ifdef MSWINDOWS}Windows, {$endif}
  Classes, SysUtils;

type
  TSimpleLock = object
  private
    LockCount: Integer;
  public
    procedure Init();
    function Acquire(ALockTryCount: Integer = 100): Boolean;
    procedure Release();
  end;

  TSimpleRWLock = object
  private
    LockCount: Integer;
    WriteThreadID: Cardinal;
  public
    procedure Init();
    function BeginRead(ALockTryCount: Integer = 1000): Boolean;
    function BeginWrite(): Boolean;
    procedure EndRead();
    procedure EndWrite();
  end;

  { Simple thread-safe file writer for log files }
  TSimpleFileWriter = object
  private
    fh: THandle;
    FUnflushedCount: Integer;
    FLock: TSimpleLock;
  public
    FileName: string;
    procedure Init();
    procedure Term();
    { Append data to file. Note! Line ending chars not auto-added! }
    procedure Write(const AStr: AnsiString = '');
  end;

  { TSimpleDataQueue }
  { Simple thread-safe data queue }
  PSimpleDataQueue = ^TSimpleDataQueue;
  TSimpleDataQueue = object
  private
    FData: AnsiString;
    FLock: TSimpleLock;
  public
    procedure Init();
    procedure Push(const AData: AnsiString);
    function Pull(ASize: Integer = MaxInt): AnsiString;
    function Peek(ASize: Integer = MaxInt): AnsiString;
  end;

  PSimpleHashItem = ^TSimpleHashItem;
  TSimpleHashItem = record
    Next: PSimpleHashItem;
    Key: string;
    Value: Integer;
  end;

  { TStringHash }
  { Simple string-to-integer hashtable }
  TSimpleStringHash = object
  private
    Buckets: array of PSimpleHashItem;
    function Find(const Key: string): PSimpleHashItem;
    function HashOf(const Key: string): Cardinal;
  public
    procedure Init(Size: Integer = 256);
    procedure Add(const Key: string; Value: Integer);
    procedure Clear;
    function Modify(const Key: string; Value: Integer): Boolean;
    { return -1 if no value for key, suitable for list index }
    function ValueOf(const Key: string): Integer;
    function FindValue(const Key: string; out Value: Integer): Boolean;
  end;

procedure SimplePause(ACount: LongWord);

implementation

const
  WR_LOCK     = $10000;
  PAUSE_COUNT = 10000;

{$ifndef FPC}
const
  fsFromEnd = 2;

procedure SimplePause(ACount: LongWord);
begin
  //Sleep(ACount);
  //SleepEx(ACount, True);
  asm
    MOV EAX, ACount
    MOV EBX, PAUSE_COUNT
    MUL EBX
    MOV ECX, EAX
  @start1:
    PAUSE
    LOOP @start1
  end;
end;

{$else}

procedure SimplePause(ACount: LongWord);
begin
  SleepEx(ACount, True);
end;
{$endif}

{ TSimpleLock }

function TSimpleLock.Acquire(ALockTryCount: Integer): Boolean;
begin
  Result := False;
  while (ALockTryCount > 0) do
  begin
    // returns LockCount before increment
    if (InterlockedExchangeAdd(LockCount, $1) = 0) then
    begin
      ALockTryCount := 0;
      Result := True;
    end
    else
    begin
      InterlockedExchangeAdd(LockCount, -$1);
      Dec(ALockTryCount);
      //SleepEx(1, True);
      SimplePause(1);
    end;
  end;
end;

procedure TSimpleLock.Init;
begin
  LockCount := 0;
end;

procedure TSimpleLock.Release;
begin
  // release exclusive lock
  InterlockedExchangeAdd(LockCount, -$1);
end;

{ TSimpleRWLock }

function TSimpleRWLock.BeginRead(ALockTryCount: Integer): Boolean;
var
  LockTryCount: Integer;
begin
  Result := False;
  // try to acquire permissive lock
  LockTryCount := ALockTryCount;
  while (LockTryCount > 0) do
  begin
    if (InterlockedExchangeAdd(LockCount, $1) < WR_LOCK) then
    begin
      Result := True;
      LockTryCount := 0;
    end
    else
    begin
      InterlockedExchangeAdd(LockCount, -$1);
      Dec(LockTryCount);
      //SleepEx(1, True);
      SimplePause(1);
    end;
  end;
end;

function TSimpleRWLock.BeginWrite: Boolean;
var
  LockTryCount, LockWaitCount: Integer;
  n: Integer;
begin
  LockTryCount := 10;
  LockWaitCount := 100;
  Result := False;
  // set lock to prevent new readers, return LockCount before
  n := InterlockedExchangeAdd(LockCount, WR_LOCK);
  while (LockTryCount > 0) do
  begin
    if (n = 0) then
    begin
      Result := True;
      WriteThreadID := GetCurrentThreadId();
      Exit;
    end
    else
    begin
      if (n < WR_LOCK) and (LockWaitCount > 0) then
      begin
        // was locked by reader, unlock after pause
        Dec(LockWaitCount);
        SimplePause(1);
        InterlockedExchangeAdd(LockCount, -WR_LOCK);
      end
      else
      begin
        // was locked by other writer
        if WriteThreadID = GetCurrentThreadId() then
        begin
          // writer in same thread, recursive
          Result := True;
          Exit;
        end
        else
        begin
          // writer in other thread, unlock before pause
          InterlockedExchangeAdd(LockCount, -WR_LOCK);
          Dec(LockTryCount);
          //SleepEx(1, True);
          SimplePause(1);
        end;
      end;
      // try lock again
      if LockTryCount > 0 then
        n := InterlockedExchangeAdd(LockCount, WR_LOCK);
    end;
  end;
end;

procedure TSimpleRWLock.EndRead;
var
  n: Integer;
begin
  // release read lock
  n := InterlockedExchangeAdd(LockCount, -$1);
  Assert(n > $0, 'TSimpleRWLock.EndRead() was not locked =' + IntToStr(n));
end;

procedure TSimpleRWLock.EndWrite;
begin
  // release exclusive write lock
  if InterlockedExchangeAdd(LockCount, -WR_LOCK) < WR_LOCK then
  begin
    Assert(False, 'TSimpleRWLock.EndWrite() was not locked');
    // was not locked
    //InterlockedExchangeAdd(LockCount, WR_LOCK);
  end;
  WriteThreadID := 0;
end;

procedure TSimpleRWLock.Init;
begin
  LockCount := 0;
end;

{ TSimpleFileWriter }

procedure TSimpleFileWriter.Init();
begin
  FUnflushedCount := 0;
  fh := 0;
  FLock.Init();
end;

procedure TSimpleFileWriter.Write(const AStr: AnsiString);
var
  {$IFDEF FPC}
  Res: THandle;
  {$ELSE}
  Res: Integer;
  {$ENDIF}
begin
  if not FLock.Acquire then Exit;
  if FUnflushedCount = 0 then
  begin
    Res := FileOpen(FileName, (fmOpenReadWrite or fmShareDenyNone));
    {$IFDEF FPC}
    if Res <> feInvalidHandle then
    {$ELSE}
    if Res > 0 then
    {$ENDIF}
    begin
      fh := Res;
      FileSeek(fh, 0, fsFromEnd);
    end
    else
    begin
      // file not exists? try to create new
      // Just created file not shared, despite to access flags
      Res := FileCreate(FileName, 438);
      {$IFDEF FPC}
      if Res <> feInvalidHandle then
      {$ELSE}
      if Res > 0 then
      {$ENDIF}
      begin
        FileClose(Res);
        Res := FileOpen(FileName, (fmOpenReadWrite or fmShareDenyNone));
        {$IFDEF FPC}
        if Res <> feInvalidHandle then
        {$ELSE}
        if Res > 0 then
        {$ENDIF}
          fh := Res;
      end;
    end;
  end;

  if fh <> 0 then
  begin
    if AStr <> '' then
      FileWrite(fh, AStr[1], Length(AStr));
    //Flush(f); // forced flush data from buffer to file
    Inc(FUnflushedCount);
    if FUnflushedCount > 10 then
    begin
      // another forced flush
      FUnflushedCount := 0;
      //CloseFile(f);
      FileClose(fh);
      fh := 0;
    end;
  end;
  FLock.Release();
end;

procedure TSimpleFileWriter.Term();
begin
  if FUnflushedCount > 0 then
  begin
    FUnflushedCount := 0;
    FileClose(fh);
    fh := 0;
  end;
end;

{ TSimpleDataQueue }

procedure TSimpleDataQueue.Init();
begin
  FData := '';
  FLock.Init();
end;

procedure TSimpleDataQueue.Push(const AData: AnsiString);
begin
  if FLock.Acquire() then
  begin
    FData := FData + AData;
    FLock.Release();
  end;
end;

function TSimpleDataQueue.Pull(ASize: Integer): AnsiString;
begin
  if FLock.Acquire() then
  begin
    Result := Copy(FData, 1, ASize);
    Delete(FData, 1, ASize);
    FLock.Release();
  end
  else
    Result := '';
end;

function TSimpleDataQueue.Peek(ASize: Integer): AnsiString;
begin
  if FLock.Acquire() then
  begin
    Result := Copy(FData, 1, ASize);
    FLock.Release();
  end
  else
    Result := '';
end;

{ TSimpleStringHash }

function TSimpleStringHash.Find(const Key: string): PSimpleHashItem;
var
  Hash: Cardinal;
begin
  Hash := (HashOf(Key)) mod Cardinal(Length(Buckets));
  Result := Buckets[Hash];
  while Result <> nil do
  begin
    if Result^.Key = Key then
      Exit
    else
    begin
      Result := Result^.Next;
    end;
  end;
end;

function TSimpleStringHash.HashOf(const Key: string): Cardinal;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Length(Key) do
    Result := ((Result shl 2) or (Result shr (SizeOf(Result) * 8 - 2))) xor Ord(Key[I]);
end;

procedure TSimpleStringHash.Init(Size: Integer);
var
  i: Integer;
begin
  if Length(Buckets) > 0 then
    Clear();
  if Size < 0 then
    Size := 0;
  SetLength(Buckets, Size);
  for i := 0 to Size-1 do
    Buckets[i] := nil;
end;

procedure TSimpleStringHash.Add(const Key: string; Value: Integer);
var
  Hash: Integer;
  Bucket: PSimpleHashItem;
begin
  Hash := HashOf(Key) mod Cardinal(Length(Buckets));
  New(Bucket);
  Bucket^.Key := Key;
  Bucket^.Value := Value;
  Bucket^.Next := Buckets[Hash];
  Buckets[Hash] := Bucket;
end;

procedure TSimpleStringHash.Clear;
var
  I: Integer;
  P, N: PSimpleHashItem;
begin
  for I := 0 to Length(Buckets) - 1 do
  begin
    P := Buckets[I];
    while P <> nil do
    begin
      N := P^.Next;
      Dispose(P);
      P := N;
    end;
    Buckets[I] := nil;
  end;
end;

function TSimpleStringHash.Modify(const Key: string; Value: Integer): Boolean;
var
  P: PSimpleHashItem;
begin
  P := Find(Key);
  if P <> nil then
  begin
    Result := True;
    P^.Value := Value;
  end
  else
    Result := False;
end;

function TSimpleStringHash.ValueOf(const Key: string): Integer;
var
  P: PSimpleHashItem;
begin
  P := Find(Key);
  if P <> nil then
    Result := P^.Value
  else
    Result := -1;
end;

function TSimpleStringHash.FindValue(const Key: string; out Value: Integer): Boolean;
var
  P: PSimpleHashItem;
begin
  P := Find(Key);
  Result := (P <> nil);
  if Result then
    Value := P^.Value;
end;

end.

