{
Механизм "слабых ссылок", позволяет проверять, жив ли объект или нет
Sergey Bodrov (serbod@gmail.com) 2016
}
unit WeakRefs;

interface

type
  IWeakRef = interface
    ['{4C4419E1-7ADB-47A4-826A-61E03FBB4C84}']
    procedure _Clean;
    function IsAlive: Boolean;
    function GetOwner(): TObject;
  end;

  { Слабая ссылка, которая хранит ссылку на какой-то объект и висит в памяти,
    пока ее кто-то использует. Позволяет проверять, жив ли объект или нет. }
  TWeakRef = class(TInterfacedObject, IWeakRef)
  private
    FOwner: TObject;
  public
    constructor Create(AOwner: TObject); virtual;
    procedure _Clean;
    function IsAlive: Boolean;
    function GetOwner(): TObject;
  end;

  { Пример класса объекта, который может дать слабую ссылку на себя }
  TWeakObject = class(TObject)
  protected
    FWeakRef: IWeakRef;
    function GetWeakRef(): IWeakRef; virtual;
  public
    procedure BeforeDestruction(); override;
    property WeakRef: IWeakRef read GetWeakRef;
  end;

implementation

{ TWeakRef }

constructor TWeakRef.Create(AOwner: TObject);
begin
  FOwner := AOwner;
end;

procedure TWeakRef._Clean();
begin
  FOwner := nil;
end;

function TWeakRef.GetOwner(): TObject;
begin
  Result := FOwner;
end;

function TWeakRef.IsAlive(): Boolean;
begin
  Result := Assigned(FOwner);
end;


{ TWeakObject }

procedure TWeakObject.BeforeDestruction;
begin
  if Assigned(FWeakRef) then
    FWeakRef._Clean();
  inherited;
end;

function TWeakObject.GetWeakRef: IWeakRef;
begin
  if FWeakRef = nil then
  begin
    FWeakRef := TWeakRef.Create(Self);
  end;
  Result := FWeakRef;
end;

end.