(*
Variant List (C) Sergey Bodrov 2020
MIT License

Usage:

var MyList: Variant;
MyList := VarListCreate;
MyList.AddValue(1);
MyList.AddValue('test');
WriteLn(MyList.GetValue(0), MyList.GetValue(1));

Methods:
  SetCapacity(MaxCount) - allocate memory for list values
  AddValue(Value) - add value to end of list. Capacity increased if needed
  GetCount() - get stored items count
  GetValue(Index) - get item value for given index (0..GetCount()-1)
  SetValue(Index, Value) - set item value for given index (0..GetCount()-1)

Note: '+' operator can't be used because it require conversion of right-side operand to same type

*)
unit VarLists;

interface

uses Variants;

type
  TVarListType = class(TInvokeableVariantType)
  public
    procedure CastTo(var Dest: TVarData; const Source: TVarData;
      const AVarType: TVarType); override;
    procedure Clear(var V: TVarData); override;
    procedure Copy(var Dest: TVarData; const Source: TVarData; const Indirect: Boolean); override;
    function DoFunction(var Dest: TVarData; const V: TVarData;
      const Name: string; const Arguments: TVarDataArray): Boolean; override;
    function DoProcedure(const V: TVarData; const Name: string;
      const Arguments: TVarDataArray): Boolean; override;
  end;

  function VarListCreate(): Variant;
  function VarTypeList(): TVarType;

implementation

type
  TVariantListItemArray = array of TVarData;

  TVariantList = class
  private
    FItems: TVariantListItemArray;
    FItemsCount: Integer;
  public
    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;

    procedure SetCapacity(AValue: Integer);
    function GetValue(AIndex: Integer; var AValue: TVarData): Boolean;
    procedure SetValue(AIndex: Integer; const AValue: TVarData);
    procedure AddValue(const AValue: TVarData);
    procedure CopyTo(ADest: TVariantList);

    function GetCount(): Integer;
    function AsString(): string;
    property Items: TVariantListItemArray read FItems;
  end;

  TVarListData = packed record
    VType: TVarType;
    Reserved1, Reserved2, Reserved3: Word;
    VList: TVariantList;
    Reserved4: {$ifdef FPC}PtrInt{$else}LongInt{$endif};
  end;

var
  VarListType: TVarListType = nil;

function VarTypeList(): TVarType;
begin
  Result := VarListType.VarType;
end;

function VarListCreate(): Variant;
begin
  VarClear(Result);
  TVarListData(Result).VType := VarTypeList;
  TVarListData(Result).VList := TVariantList.Create();
end;

{ TVarListType }

procedure TVarListType.CastTo(var Dest: TVarData; const Source: TVarData;
  const AVarType: TVarType);
var
  LTemp: TVarData;
begin
  if Source.VType = VarType then
  begin
    case AVarType of
      varOleStr:
        VarDataFromOleStr(Dest, TVarListData(Source).VList.AsString);
      varString:
        VarDataFromStr(Dest, TVarListData(Source).VList.AsString);
    else
      VarDataInit(LTemp);
      try
        LTemp.VType := varInteger;
        LTemp.VInteger := TVarListData(Source).VList.GetCount();
        VarDataCastTo(Dest, LTemp, AVarType);
      finally
        VarDataClear(LTemp);
      end;
    end;
  end
  else
    RaiseCastError;
end;

procedure TVarListType.Clear(var V: TVarData);
var
  i: Integer;
begin
  V.VType := varEmpty;
  if TVarListData(V).VList <> nil then
  begin
    for i := TVarListData(V).VList.GetCount()-1 downto 0 do
      VarDataClear(TVarListData(V).VList.Items[i]);

    TVarListData(V).VList.Free();
    TVarListData(V).VList := nil;
  end;
end;

procedure TVarListType.Copy(var Dest: TVarData;
  const Source: TVarData; const Indirect: Boolean);
begin
  if Indirect and VarDataIsByRef(Source) then
    VarDataCopyNoInd(Dest, Source)
  else
  begin
    TVarListData(Dest).VType := VarType;
    TVarListData(Dest).VList := TVariantList.Create();
    TVarListData(Source).VList.CopyTo(TVarListData(Dest).VList)
  end;
end;

function TVarListType.DoFunction(var Dest: TVarData;
  const V: TVarData; const Name: string;
  const Arguments: TVarDataArray): Boolean;
var
  sName: string;
begin
  Result := False;
 
  sName := UpCase(Name);
  if (sName = 'GETCOUNT') then
  begin
    Variant(Dest) := TVarListData(V).VList.GetCount();
    Result := True;
  end
  else
  if (sName = 'GETVALUE') and (Length(Arguments) = 1) then
  begin
    // GetValue(Index)
    TVarListData(V).VList.GetValue(Variant(Arguments[0]), Dest);
    Result := True;
  end;

end;

function TVarListType.DoProcedure(const V: TVarData; const Name: string;
  const Arguments: TVarDataArray): Boolean;
var
  sName: string;
begin
  sName := UpCase(Name);
  if (sName = 'SETVALUE') and (Length(Arguments) = 2) then
  begin
    // SetValue(Index, Value)
    TVarListData(V).VList.SetValue(Variant(Arguments[0]), Arguments[1]);
    Result := True;
  end
  else
  if (sName = 'ADDVALUE') and (Length(Arguments) = 1) then
  begin
    // AddValue(Value)
    TVarListData(V).VList.AddValue(Arguments[0]);
    Result := True;
  end
  else
  if (sName = 'SETCAPACITY') and (Length(Arguments) = 1) then
  begin
    // SetCapacity(MaxCount)
    TVarListData(V).VList.SetCapacity(Variant(Arguments[0]));
    Result := True;
  end
  else
    Result := False;
end;

{ TVariantList }

procedure TVariantList.AddValue(const AValue: TVarData);
begin
  Inc(FItemsCount);
  if Length(FItems) < FItemsCount then
    SetCapacity(FItemsCount + 1);
  Variant(FItems[FItemsCount-1]) := Variant(AValue);
end;

procedure TVariantList.AfterConstruction;
begin
  inherited;
  SetCapacity(0);
end;

function TVariantList.AsString: string;
var
  i: Integer;
begin
  Result := '[';
  for i := 0 to FItemsCount-1 do
  begin
    if i > 0 then
      Result := Result + ',';
    Result := Result + VarToStr(Variant(Items[i]));
  end;
  Result := Result + ']';
end;

procedure TVariantList.BeforeDestruction;
begin
  inherited;

end;

procedure TVariantList.CopyTo(ADest: TVariantList);
var
  i: Integer;
begin
  ADest.SetCapacity(FItemsCount);
  for i := 0 to FItemsCount-1 do
  begin
    ADest.SetValue(i, FItems[i]);
  end;
end;

function TVariantList.GetCount: Integer;
begin
  Result := FItemsCount;
end;

function TVariantList.GetValue(AIndex: Integer; var AValue: TVarData): Boolean;
begin
  if AIndex < FItemsCount then
  begin
    Variant(AValue) := Variant(FItems[AIndex]);
    Result := True;
  end
  else
    Result := False;
end;

procedure TVariantList.SetCapacity(AValue: Integer);
begin
  SetLength(FItems, AValue);
  if FItemsCount > AValue then
    FItemsCount := AValue;
end;

procedure TVariantList.SetValue(AIndex: Integer; const AValue: TVarData);
begin
  if (AIndex >= 0) and (AIndex < FItemsCount) then
  begin
    Variant(FItems[AIndex]) := Variant(AValue);
  end;
end;

initialization

VarListType := TVarListType.Create();

finalization

VarListType.Free();

end.
