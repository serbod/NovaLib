(*
Variant Dictionary (C) Sergey Bodrov 2020
Auto-sorted by names, binary search used to get value by name

MIT License

Usage:

var MyDict: Variant;
MyDict := VarDictCreate();
MyDict.Field1 := 1;
MyDict.Field2 := 'test';

Methods:
  GetCount() - get stored items count
  GetValue(Index) - get item value for given Index (0..GetCount()-1)
  GetName(Index) - get item name for given Index (0..GetCount()-1)
  GetNameIndex(Name) - get index of item Name, or <0 if Name not found
  SetValue(Name, Value) - set value for Name

*)
unit VarDicts;

{$IFDEF fpc}
{$mode objfpc}
{$ENDIF}
{$h+}

interface

uses Variants, VarUtils;

type

  { TVarDictType }

  TVarDictType = class(TInvokeableVariantType)
  private
    procedure VarDerefAndCopy(const V: TVarData);
    function InternalSetProperty(const V: TVarData; const Name: string; const Value: TVarData): Boolean;
  public
    function IsClear(const V: TVarData): Boolean; override;
    procedure Cast(var Dest: TVarData; const Source: TVarData); override;
    procedure CastTo(var Dest: TVarData; const Source: TVarData;
      const AVarType: TVarType); override;
    procedure BinaryOp(var Left: TVarData; const Right: TVarData; const Operation: TVarOp); override;
    procedure Clear(var V: TVarData); override;
    procedure Copy(var Dest: TVarData; const Source: TVarData; const Indirect: Boolean); override;
    function GetProperty(var Dest: TVarData; const V: TVarData; const Name: string): Boolean; override;
    function SetProperty(var V: TVarData; const Name: string; const Value: TVarData): Boolean; override;
    function DoFunction(var Dest: TVarData; const V: TVarData;
      const Name: string; const Arguments: TVarDataArray): Boolean; override;
    function DoProcedure(const V: TVarData; const Name: string;
      const Arguments: TVarDataArray): Boolean; override;
  end;

  function VarDictCreate(): Variant;
  function VarTypeDict(): TVarType;

var
  VarDictCaseSensitive: Boolean;

implementation

uses SysUtils;

type
  TVariantDictionaryItem = record
    Name: string;
    Value: TVarData;
  end;
  TVariantDictionaryItemArray = array of TVariantDictionaryItem;

  TVariantDictionary = class
  public
    Items: TVariantDictionaryItemArray;
    ItemsCount: Integer;

    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;

    { if >= 0 then index of found name
      if < 0 then 1-based index for name (can be > Count)
      IsAddItem - add named item }
    function GetNameIndex(const AName: string; IsAddItem: Boolean = False): Integer;

    function GetCount(): Integer;
    function AsString(): string;
  end;

  TVarDictData = packed record
    VType: TVarType;
    Reserved1, Reserved2, Reserved3: Word;
    VDict: TVariantDictionary;
    Reserved4: {$ifdef FPC}PtrInt{$else}LongInt{$endif};
  end;
  PVarDictData = ^TVarDictData;

var
  VarDictType: TVarDictType = nil;

function VarTypeDict(): TVarType;
begin
  Result := VarDictType.VarType;
end;

function VarDictCreate(): Variant;
begin
  VarClear(Result);
  TVarDictData(Result).VType := VarTypeDict;
  TVarDictData(Result).VDict := TVariantDictionary.Create();
end;

{ TVariantDictionaryType }

procedure TVarDictType.Clear(var V: TVarData);
var
  i: Integer;
  pVarDict: PVarDictData;
begin
  V.VType := varEmpty;
  pVarDict := Addr(V);
  if pVarDict^.VDict <> nil then
  begin
    for i := pVarDict^.VDict.ItemsCount-1 downto 0 do
      VarDataClear(pVarDict^.VDict.Items[i].Value);

    pVarDict^.VDict.Free();
    pVarDict^.VDict := nil;
  end;
end;

function TVarDictType.IsClear(const V: TVarData): Boolean;
begin
  Result := (TVarDictData(V).VDict = nil) or (TVarDictData(V).VDict.GetCount() = 0);
end;

procedure TVarDictType.Copy(var Dest: TVarData;
  const Source: TVarData; const Indirect: Boolean);
var
  i: Integer;
begin
  if Indirect and VarDataIsByRef(Source) then
    VarDataCopyNoInd(Dest, Source)
  else
  begin
    TVarDictData(Dest).VType := VarType;
    TVarDictData(Dest).VDict := TVariantDictionary.Create();
    for i := 0 to TVarDictData(Source).VDict.ItemsCount - 1 do
    begin
      InternalSetProperty(Dest, TVarDictData(Source).VDict.Items[i].Name, TVarDictData(Source).VDict.Items[i].Value);
    end;
  end;
end;

function TVarDictType.DoFunction(var Dest: TVarData;
  const V: TVarData; const Name: string;
  const Arguments: TVarDataArray): Boolean;
var
  i: Integer;
  sName: string;
begin
  Result := False;

  sName := UpperCase(Name);
  if (sName = 'GETCOUNT') then
  begin
    Variant(Dest) := TVarDictData(V).VDict.GetCount();
    Result := True;
  end
  else
  if (sName = 'GETVALUE') and (Length(Arguments) = 1) then
  begin
    i := Variant(Arguments[0]);
    if (i >= 0) and (i < TVarDictData(V).VDict.ItemsCount) then
    begin
      VarDataCopy(Dest, TVarDictData(V).VDict.Items[i].Value);
      Result := True;
    end;
  end
  else
  if (sName = 'GETNAME') and (Length(Arguments) = 1) then
  begin
    i := Variant(Arguments[0]);
    if (i >= 0) and (i < TVarDictData(V).VDict.ItemsCount) then
    begin
      VarDataFromStr(Dest, TVarDictData(V).VDict.Items[i].Name);
      Result := True;
    end;
  end
  else
  if (sName = 'GETNAMEINDEX') and (Length(Arguments) = 1) then
  begin
    Variant(Dest) := TVarDictData(V).VDict.GetNameIndex(Variant(Arguments[0]));
    Result := True;
  end;
end;

function TVarDictType.DoProcedure(const V: TVarData; const Name: string;
  const Arguments: TVarDataArray): Boolean;
begin
  if (UpperCase(Name) = 'SETVALUE') and (Length(Arguments) = 2) then
  begin
    Result := InternalSetProperty(V, Variant(Arguments[0]), Arguments[1]);
  end
  else
    Result := False;
end;

function TVarDictType.GetProperty(var Dest: TVarData;
  const V: TVarData; const Name: string): Boolean;
var
  i: Integer;
begin
  i := TVarDictData(V).VDict.GetNameIndex(Name);
  if i >= 0 then
  begin
    Result := True;
    {$ifdef FPC}
    VarDataCopy(Dest, TVarDictData(V).VDict.Items[i].Value);
    {$else}
    VariantCopy(Dest, TVarDictData(V).VDict.Items[i].Value);
    {$endif}
  end
  else
    Result := False;
end;

function TVarDictType.SetProperty(var V: TVarData;
  const Name: string; const Value: TVarData): Boolean;
begin
  Result := InternalSetProperty(V, Name, Value);
end;

function TVarDictType.InternalSetProperty(const V: TVarData;
  const Name: string; const Value: TVarData): Boolean;
var
  i: Integer;
begin
  Result := True;

  if (TVarData(V).VType and varByRef) <> 0 then
    VarDerefAndCopy(V);

  i := TVarDictData(V).VDict.GetNameIndex(Name, True);
  {$ifdef FPC}
  VarDataCopy(TVarDictData(V).VDict.Items[i].Value, Value);
  {$else}
  VariantCopy(TVarDictData(V).VDict.Items[i].Value, Value);
  {$endif}
end;

procedure TVarDictType.Cast(var Dest: TVarData; const Source: TVarData);
begin
  //inherited;
  VariantInit(Dest);
  TVarDictData(Dest).VType := VarType;
  TVarDictData(Dest).VDict := TVariantDictionary.Create();
end;

procedure TVarDictType.CastTo(var Dest: TVarData; const Source: TVarData;
  const AVarType: TVarType);
var
  LTemp: TVarData;
begin
  if Source.VType = VarType then
  begin
    case AVarType of
      varOleStr:
        VarDataFromOleStr(Dest, TVarDictData(Source).VDict.AsString);
      varString:
        VarDataFromStr(Dest, TVarDictData(Source).VDict.AsString);
    else
      VarDataInit(LTemp);
      try
        LTemp.VType := varInteger;
        LTemp.VInteger := TVarDictData(Source).VDict.ItemsCount;
        VarDataCastTo(Dest, LTemp, AVarType);
      finally
        VarDataClear(LTemp);
      end;
    end;
  end
  else
    RaiseCastError;
end;

procedure TVarDictType.BinaryOp(var Left: TVarData; const Right: TVarData;
  const Operation: TVarOp);
var
  i: Integer;
begin
  case Operation of
    opAdd:
    begin
      if (Left.VType = VarTypeDict) and (Right.VType = VarTypeDict) then
      begin
        for i := 0 to TVarDictData(Right).VDict.ItemsCount - 1 do
        begin
          InternalSetProperty(Left, TVarDictData(Right).VDict.Items[i].Name, TVarDictData(Right).VDict.Items[i].Value);
        end;
      end
      else
        inherited BinaryOp(Left, Right, Operation);
    end;
  else
    inherited BinaryOp(Left, Right, Operation);
  end;
end;

{ TVariantDictionary }

procedure TVariantDictionary.AfterConstruction;
begin
  inherited;
  ItemsCount := 0;
  SetLength(Items, ItemsCount);
end;

procedure TVariantDictionary.BeforeDestruction;
begin
  inherited;

end;

function TVariantDictionary.GetCount: Integer;
begin
  Result := ItemsCount;
end;

function TVariantDictionary.GetNameIndex(const AName: string; IsAddItem: Boolean): Integer;
var
  i, iCompResult, iL, iR, iM: Integer;
  sName: string;
begin
  if not VarDictCaseSensitive then
    sName := LowerCase(AName)
  else
    sName := AName;
  // binary search
  Result := -1;
  iL := 0;
  iR := ItemsCount-1;
  while iL <= iR do
  begin
    iM := (iL + iR) div 2;
    iCompResult := CompareText(sName, Items[iM].Name);
    if iCompResult > 0 then
    begin
      iL := iM + 1;
      Result := -(iM + 2);
    end
    else
    if iCompResult < 0 then
    begin
      iR := iM - 1;
      Result := -(iM + 1);
    end
    else
    begin
      Result := iM;
      Break;
    end;
  end;

  // insert name if needed
  if (Result < 0) and IsAddItem then
  begin
    Result := -Result - 1;
    Inc(ItemsCount);
    SetLength(Items, ItemsCount);
    // shift elements
    for i := ItemsCount-1 downto Result + 1 do
      Items[i] := Items[i-1];

    Items[Result].Name := sName;
    VariantInit(Items[Result].Value);
  end;
end;

function TVariantDictionary.AsString: string;
var
  i: Integer;
begin
  Result := '{';
  for i := 0 to ItemsCount-1 do
  begin
    if i > 0 then
      Result := Result + ',';
    Result := Result + Items[i].Name + ':' + VarToStr(Variant(Items[i].Value));
  end;
  Result := Result + '}';
end;

procedure TVarDictType.VarDerefAndCopy(const V: TVarData);
begin
// todo: write-on-copy
end;

initialization

VarDictType := TVarDictType.Create();
VarDictCaseSensitive := False;

finalization

VarDictType.Free();

end.
