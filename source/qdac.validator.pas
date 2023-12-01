﻿unit qdac.validator;

interface

///!!!! Dont format this unit because Delphi formator not support generics!!!!
///!!!! 不要格式化这个单元的代码，Delphi自带的格式化会将带泛型的类搞乱!!!!

uses System.Classes, System.SysUtils,System.Character, System.TypInfo, System.Generics.Defaults,
  System.Generics.Collections,System.RegularExpressionsCore, System.Rtti,qdac.common;

type
  EValidateException = class(Exception)

  end;

  TQStringPair=TPair<UnicodeString,UnicodeString>;
  // 验证器的基类，声明基础的接口和方法
  TQValidator < TQValueType >= class
  private
    FErrorMessage: UnicodeString;
  protected
    // 验证器类型标志符，子类应该重该本方法
    class function GetTypeName: UnicodeString; virtual;
    class function FormatError(const AErrorMsg: UnicodeString;const AParams: TArray <TQStringPair>): UnicodeString; static;
  public
    constructor Create(const AErrorMsg: UnicodeString); overload;
    function Accept(const AValue: TQValueType): Boolean; virtual; abstract;
    procedure Check(const AValue: TQValueType); virtual; abstract;
    function Require(const AValue: TQValueType; const ADefaultValue: TQValueType): TQValueType; virtual;abstract;
    property ErrorMessage: UnicodeString read FErrorMessage write FErrorMessage;
  end;

  TQLengthValidator<TQValueType> = class(TQValidator<TQValueType>)
  private
    FMinSize, FMaxSize: SizeInt;
  public
    constructor Create(const AMinSize, AMaxSize: SizeInt;const AErrorMsg: UnicodeString); overload;
    function Accept(const AValue: TQValueType): Boolean; overload; override;
    procedure Check(const AValue: TQValueType); overload; override;
    function Require(const AValue: TQValueType; const ADefaultValue: TQValueType): TQValueType; overload; override;
    property MinSize: SizeInt read FMinSize;
    property MaxSize: SizeInt read FMaxSize;
  // class methods
    class function LengthOf(const AValue: TQValueType): SizeInt;static;
    class function AcceptEx(const AValue: TQValueType;const AMinSize, AMaxSize: SizeInt): Boolean; overload; static;
    class procedure CheckEx(const AValue: TQValueType;const AMinSize, AMaxSize: SizeInt;
      const AErrorMsg: UnicodeString);overload;static;
    class function RequireEx(const AValue: TQValueType; const AMinSize, AMaxSize: SizeInt;
      const ADefaultValue: TQValueType): TQValueType;overload;static;
  end;

  // 边界处理规则，默认相等
  TQRangeBound = (GreatThanMin, LessThanMax);

  TQRangeBounds = set of TQRangeBound;

  TQRangeValidator<TQValueType> = class(TQValidator<TQValueType>)
  private
    FBounds: TQRangeBounds;
    FComparer: IComparer<TQValueType>;
    FMinValue, FMaxValue: TQValueType;
  protected
    class function GetTypeName: UnicodeString; override;
  public
    constructor Create(const AMinValue, AMaxValue: TQValueType;const AErrorMsg: UnicodeString;
      AComparer: IComparer<TQValueType>); overload;
    function Accept(const AValue: TQValueType): Boolean;overload;override;
    procedure Check(const AValue: TQValueType); overload; override;
    function Require(const AValue: TQValueType; const ADefaultValue: TQValueType): TQValueType; overload; override;
    property MinValue: TQValueType read FMinValue;
    property MaxValue: TQValueType read FMaxValue;
    property Bounds: TQRangeBounds read FBounds write FBounds;
  // class methods
    class function AcceptEx(const AValue: TQValueType; const AMinValue, AMaxValue: TQValueType;
      ABounds: TQRangeBounds = []; const AComparer: IComparer < TQValueType >= nil): Boolean; overload; static;
    class procedure CheckEx(const AValue: TQValueType; const AMinValue, AMaxValue: TQValueType;
      const AErrorMsg: UnicodeString; ABounds: TQRangeBounds = [];
      const AComparer: IComparer < TQValueType >= nil); overload; static;
    class function RequireEx(const AValue: TQValueType; const AMinValue, AMaxValue: TQValueType;
      const ADefaultValue: TQValueType; ABounds: TQRangeBounds = [];
      const AComparer: IComparer < TQValueType >= nil): TQValueType; overload; static;
  end;

  // 基于文本的验证规则
  TQTextValidator = class(TQValidator<UnicodeString>)
  protected 
    class function GeTQValueTypeName: UnicodeString;virtual;
  public
    function Accept(const AValue: UnicodeString): Boolean;override;
    procedure Check(const AValue: UnicodeString);override;
    function Require(const AValue: UnicodeString;const ADefaultValue: UnicodeString = ''): UnicodeString;override;
  end;

  TQChineseIdValidator = class(TQTextValidator)
  protected class
    function GeTQValueTypeName: UnicodeString;override;
  public
    function Accept(const AValue: UnicodeString): Boolean;override;
    function TryDecode(AIdNo: UnicodeString; var ACityCode: String;
      var ABirthday: TDateTime; var AIsFemale: Boolean): Boolean;
  end;

  TQEmailValidator = class(TQTextValidator)
  public
    function Accept(const AValue: UnicodeString): Boolean;override;
  end;

  TQRegexValidator = class(TQTextValidator)
  private 
    FValueTypeName: String;
    FRegex: String;
    FRegexProcessor: TPerlRegex;
  public
    function Accept(const AValue: UnicodeString): Boolean;override;
    property Regex: String read FRegex write FRegex;
    property ValueTypeName: String read FValueTypeName write FValueTypeName;
  end;

  TQChineseMobileValidator = class(TQTextValidator)
  protected 
    class function GeTQValueTypeName: UnicodeString;override;
  public
    function Accept(const AValue: UnicodeString): Boolean;override;
  end;

  TQBase64Validator = class(TQTextValidator)
  public
    function Accept(const AValue: UnicodeString): Boolean; override;
  end;

  //IPV4地址验证规则
  TQIPV4Validator=class(TQTextValidator)
  protected
    class function GeTQValueTypeName: UnicodeString;override;
  public
    function Accept(const AValue: UnicodeString): Boolean; override;
  end;


  TQUrlValidator = class(TQTextValidator)
  public
    function Accept(const AValue: UnicodeString): Boolean;override;
    function TryDecode(const AUrl: UnicodeString;
      var ASchema, AUserName, APassword, AHost, ADocPath: UnicodeString;
      var AParams: TArray<UnicodeString>; APort: Word): Boolean;
  end;


  //基于类型的规则验证实现，对特定类型的子规则都在其名下定义
  TQTypeValidator<TQValueType>=class
  public
    type
      TQValidatorType=TQValidator<TQValueType>;
  private
    FTypeInfo: PTypeInfo;
    FItems: TDictionary<string, TQValidatorType>;
  public
    constructor Create(const AValidators: TArray < TQValidator < TQValueType >> );overload;
    destructor Destroy;override;
  /// <summary> 注册一个规则验证器 </summary>
  /// <param name="AName"> 规则名称，字符串类型，同名规则后注册替换先注册 </param>
  /// <param name="AValidator"> 对应规则的验证器 </param>
  procedure Register(const AName: UnicodeString; AValidator: TQValidatorType);
  end;

  TQValidators = class sealed 
  private 
    class var
      FCurrent: TQValidators;
      FEmail: TQTextValidator;
      FChineseMobile: TQTextValidator;
      FBase64: TQTextValidator;
      FChineseId: TQChineseIdValidator;
      FUrl: TQUrlValidator;
    class function GetCurrent: TQValidators; static;
  private
    FTypeValidators: TDictionary<PTypeInfo, TObject>;
    class function GetBase64: TQTextValidator; static;
    class function GetChineseId: TQChineseIdValidator; static;
    class function GetChineseMobile: TQTextValidator; static;
    class function GetEmail: TQTextValidator; static;
    class function GetUrl: TQUrlValidator; static;
  public
    constructor Create;
    destructor Destroy; override;
    class constructor Create;
    class destructor Destroy;
    class procedure Register<TQValueType>(ATypeValidator: TQTypeValidator<TQValueType>);
    // Known validators
    class function Length<TQValueType>: TQLengthValidator<TQValueType>;
    class function Range<TQValueType>: TQRangeValidator<TQValueType>;
    class function Custom<TQValueType>(const AName: UnicodeString): TQValidator<TQValueType>;
    class property Email: TQTextValidator read GetEmail write FEmail;
    class property ChineseMobile: TQTextValidator read GetChineseMobile write FChineseMobile;
    class property ChineseId: TQChineseIdValidator read GetChineseId write FChineseId;
    class property Base64: TQTextValidator read GetBase64 write FBase64;
    class property Url: TQUrlValidator read GetUrl write FUrl;
    class property Current: TQValidators read GetCurrent;
  end;

implementation

uses qdac.resource;

{ TQValidator<TQValueType> }

constructor TQValidator<TQValueType>.Create(const AErrorMsg: UnicodeString);
begin
  inherited Create;
  FErrorMessage := AErrorMsg;
end;

class function TQValidator<TQValueType>.FormatError(const AErrorMsg
  : UnicodeString; const AParams: TArray < TPair < UnicodeString,
  UnicodeString >> ): UnicodeString;
var
  ps, p: PWideChar;
  ABuilder: TStringBuilder;
  AName: String;
  AFound: Boolean;
begin
  // 这里只支持简单替换，使用 \[ 可以避免 [xxx] 被解析为参数名
  ps := PWideChar(AErrorMsg);
  ABuilder := TStringBuilder.Create;
  try
    p := ps;
    while p^ <> #0 do
    begin
      if p^ = '\' then // 转义 [，其它忽略
      begin
        ABuilder.Append(ps, 0, p - ps);
        Inc(p);
        if p^ = '[' then
          ABuilder.Append(p^)
        else
          ABuilder.Append('\');
        ps := p;
      end
      else if p^ = '[' then
      begin
        ABuilder.Append(ps, 0, p - ps);
        Inc(p);
        ps := p;
        while (p^ <> #0) and (p^ <> ']') do
        begin
          Inc(p);
        end;
        if p^ = ']' then
        begin
          AName := Copy(ps, 0, p - ps);
          AFound := false;
          for var I := 0 to High(AParams) do
          begin
            if CompareText(AName, AParams[I].Key) = 0 then
            begin
              ABuilder.Append(AParams[I].Value);
              AFound := True;
              break;
            end;
          end;
          if not AFound then
          begin
            ABuilder.Append('[').Append(AName).Append(']');
          end;
        end
        else
        begin
          ABuilder.Append(ps);
        end;
      end
      else
        Inc(p);
    end;
    Result := ABuilder.ToString;
  finally
    FreeAndNil(ABuilder);
  end;
end;

class function TQValidator<TQValueType>.GetTypeName: UnicodeString;
begin
  // 默认验证器类型名称规则，去掉前面的 TQ 和后面的 Validator 后小写，如 TQLengthValidator<UnicodeString> 解析为 length
  Result := ClassName.Split(['<', '>'], TSTringSplitOptions.ExcludeEmpty)[0];
  if Result.StartsWith('TQ') and Result.EndsWith('Validator') then
    Result := Result.Substring(2, Length(Result) - 11).ToLower
  else if Result.StartsWith('T') then
    Result := Result.Substring(1, Length(Result) - 1).ToLower;
end;

{ TQLengthValidator<TQValueType> }

function TQLengthValidator<TQValueType>.Accept(const AValue: TQValueType)
  : Boolean;
begin
  Result := AcceptEx(AValue, FMinSize, FMaxSize);
end;

class function TQLengthValidator<TQValueType>.AcceptEx(
  const AValue: TQValueType; const AMinSize, AMaxSize: SizeInt): Boolean;
var
  ALen:UInt64;
begin
  Assert(AMaxSize >= AMinSize, SAssertSizeError);
  if AMaxSize > 0 then
  begin
    ALen := LengthOf(AValue);
    Result := (ALen >= AMinSize) and (ALen <= AMaxSize);
  end
  else
    Result := True;
end;

procedure TQLengthValidator<TQValueType>.Check(const AValue: TQValueType);
begin
  CheckEx(AValue, FMinSize, FMaxSize, FErrorMessage);
end;

class procedure TQLengthValidator<TQValueType>.CheckEx(
  const AValue: TQValueType; const AMinSize, AMaxSize: SizeInt;
  const AErrorMsg: UnicodeString);
begin
  if not AcceptEx(AValue, AMinSize, AMaxSize) then
    raise EValidateException.Create(FormatError(AErrorMsg,
      [TPair<UnicodeString, UnicodeString>.Create('Size',
      LengthOf(AValue).ToString),
      TPair<UnicodeString, UnicodeString>.Create('MinSize', AMinSize.ToString),
      TPair<UnicodeString, UnicodeString>.Create('MaxSize',
      AMaxSize.ToString)]));
end;

constructor TQLengthValidator<TQValueType>.Create(const AMinSize, AMaxSize: SizeInt; const AErrorMsg: UnicodeString);
begin
  Assert(AMaxSize >= AMinSize, SAssertSizeError);
  inherited Create(AErrorMsg);
  FMinSize := AMinSize;
  FMaxSize := AMaxSize;
end;

class function TQLengthValidator<TQValueType>.LengthOf(const AValue: TQValueType): SizeInt;
begin
  // 只有字符串、动态数组类型支持长度判断
  case GetTypeData(TypeInfo(TQValueType)).BaseType^.Kind of
    tkUnicodeString:
      Result := Length(PUnicodeString(@AValue)^);
    tkAnsiString:
      Result := Length(PAnsiString(@AValue)^);
    tkWideString:
      Result := Length(PWideString(@AValue)^);
    tkDynArray:
      Result := DynArraySize(@AValue)
  else
    raise EValidateException.Create(SLengthOnlySupportStringAndArray);
  end;
end;

function TQLengthValidator<TQValueType>.Require(const AValue,
  ADefaultValue: TQValueType): TQValueType;
begin
  Result := RequireEx(AValue, FMinSize, FMaxSize, ADefaultValue);
end;

class function TQLengthValidator<TQValueType>.RequireEx(const AValue: TQValueType;
  const AMinSize, AMaxSize: SizeInt;const ADefaultValue:TQValueType):TQValueType;
begin
  if AcceptEx(AValue, AMinSize, AMaxSize) then
    Result := AValue
  else
    Result := ADefaultValue;
end;

{ TQValidator }

constructor TQValidators.Create;
begin
  inherited;
  FTypeValidators := TDictionary<PTypeInfo, TObject>.Create;
  FEmail := TQEmailValidator.Create(SValueTypeError);
  FChineseMobile := TQChineseMobileValidator.Create(SValueTypeError);
  FBase64 := TQBase64Validator.Create(SValueTypeError);
  FChineseId := TQChineseIdValidator.Create(SValueTypeError);
  FUrl := TQUrlValidator.Create(SValueTypeError);
end;

class constructor TQValidators.Create;
begin
  FCurrent := TQValidators.Create;
end;

class function TQValidators.Custom<TQValueType>(const AName: UnicodeString)
  : TQValidator<TQValueType>;
var
  AValidators: TQTypeValidator<TQValueType>;
begin
  Result := nil;
  TMonitor.Enter(FCurrent.FTypeValidators);
  try
    if FCurrent.FTypeValidators.TryGetValue(TypeInfo(TQValueType),
      TObject(AValidators)) then
    begin
      AValidators.FItems.TryGetValue(AName, TQValidator<TQValueType>(Result));
    end;
  finally
    TMonitor.Exit(FCurrent.FTypeValidators);
  end;
end;

class destructor TQValidators.Destroy;
begin
  FreeAndNil(FCurrent);
end;

destructor TQValidators.Destroy;
var
  AItems: TArray<TObject>;
  I: Integer;
begin
  AItems := FTypeValidators.Values.ToArray;
  for I := 0 to High(AItems) do
  begin
    FreeAndNil(AItems[I]);
  end;
  FreeAndNil(FTypeValidators);
end;

class function TQValidators.GetBase64: TQTextValidator;
begin
  Result := FBase64;
end;

class function TQValidators.GetChineseId: TQChineseIdValidator;
begin
  Result := FChineseId;
end;

class function TQValidators.GetChineseMobile: TQTextValidator;
begin
  Result := FChineseMobile;
end;

class function TQValidators.GetCurrent: TQValidators;
begin
  Result := FCurrent;
end;

class function TQValidators.GetEmail: TQTextValidator;
begin
  Result := FEmail;
end;

class function TQValidators.GetUrl: TQUrlValidator;
begin
  Result := FUrl;
end;

class function TQValidators.Length<TQValueType>: TQLengthValidator<TQValueType>;
type
  TLengthValidator = TQLengthValidator<TQValueType>;
begin
  Result := Custom<TQValueType>(TLengthValidator.GetTypeName)
    as TLengthValidator;
end;

class function TQValidators.Range<TQValueType>: TQRangeValidator<TQValueType>;
type
  TRangeValidator = TQRangeValidator<TQValueType>;
begin
  Result := Custom<TQValueType>(TRangeValidator.GetTypeName) as TRangeValidator;
end;

class procedure TQValidators.Register<TQValueType>(ATypeValidator
  : TQTypeValidator<TQValueType>);
var
  AExists: TQTypeValidator<TQValueType>;
begin
  TMonitor.Enter(FCurrent.FTypeValidators);
  try
    if not FCurrent.FTypeValidators.TryGetValue(TypeInfo(TQValueType),
      TObject(AExists)) then
      AExists := nil;
    if AExists <> ATypeValidator then
    begin
      FCurrent.FTypeValidators.AddOrSetValue(TypeInfo(TQValueType),
        ATypeValidator);
      if Assigned(AExists) then
        FreeAndNil(AExists);
    end;
  finally
    TMonitor.Exit(FCurrent.FTypeValidators);
  end;
end;

{ TQTypeValidator<TQValueType> }

constructor TQTypeValidator<TQValueType>.Create(const AValidators: TArray <
  TQValidator < TQValueType >> );
var
  I: Integer;
begin
  inherited Create;
  FTypeInfo := TypeInfo(TQValueType);
  FItems := TDictionary < String, TQValidator < TQValueType >>.Create;
  for I := 0 to High(AValidators) do
    FItems.AddOrSetValue(AValidators[I].GetTypeName, AValidators[I]);
end;

destructor TQTypeValidator<TQValueType>.Destroy;
var
  AItems: TArray<TQValidatorType>;
  I: Integer;
begin
  AItems := FItems.Values.ToArray;
  for I := 0 to High(AItems) do
  begin
    FreeAndNil(AItems[I]);
  end;
  FreeAndNil(FItems);
  inherited;
end;

procedure TQTypeValidator<TQValueType>.Register(const AName: UnicodeString;
  AValidator: TQValidatorType);
var
  AExists: TQValidatorType;
begin
  // Register must call before any process
  if not FItems.TryGetValue(AName, AExists) then
    AExists := nil;
  if AExists <> AValidator then
  begin
    FItems.AddOrSetValue(AName, AValidator);
    if Assigned(AExists) then
    begin
      FreeAndNil(AExists);
    end;
  end;
end;

{ TQRangeValidator<TQValueType> }

function TQRangeValidator<TQValueType>.Accept(const AValue: TQValueType): Boolean;
begin
  Result := AcceptEx(AValue, FMinValue, FMaxValue, FBounds);
end;

class function TQRangeValidator<TQValueType>.AcceptEx(const AValue,
  AMinValue, AMaxValue: TQValueType; ABounds: TQRangeBounds;
  const AComparer: IComparer<TQValueType>): Boolean;
var
  AMinResult, AMaxResult: Integer;
begin
  if Assigned(AComparer) then
  begin
    AMinResult := AComparer.Compare(AValue, AMinValue);
    AMaxResult := AComparer.Compare(AValue, AMaxValue);
  end
  else
  begin
    with TComparer<TQValueType>.Default do
    begin
      AMinResult := Compare(AValue, AMinValue);
      AMaxResult := Compare(AValue, AMaxValue);
    end;
  end;
  Result := ((AMinResult > 0) or ((AMinResult = 0) and
    (not(TQRangeBound.GreatThanMin in ABounds)))) and
    ((AMaxResult < 0) or ((AMaxResult = 0) and (not(TQRangeBound.LessThanMax
    in ABounds))));
end;

procedure TQRangeValidator<TQValueType>.Check(const AValue: TQValueType);
begin
  CheckEx(AValue, FMinValue, FMaxValue, FErrorMessage, FBounds);
end;

class procedure TQRangeValidator<TQValueType>.CheckEx(const AValue,
  AMinValue, AMaxValue: TQValueType; const AErrorMsg: UnicodeString;
  ABounds: TQRangeBounds; const AComparer: IComparer<TQValueType>);
begin
  if not AcceptEx(AValue, AMinValue, AMaxValue, ABounds, AComparer)
  then
  begin
    raise EValidateException.Create(FormatError(AErrorMsg,
      [TPair<UnicodeString, UnicodeString>.Create('Value',
      TValue.From<TQValueType>(AValue).ToString),
      TPair<UnicodeString, UnicodeString>.Create('MinValue',
      TValue.From<TQValueType>(AMinValue).ToString),
      TPair<UnicodeString, UnicodeString>.Create('MaxValue',
      TValue.From<TQValueType>(AMaxValue).ToString)]));
  end;
end;

constructor TQRangeValidator<TQValueType>.Create(const AMinValue,
  AMaxValue: TQValueType; const AErrorMsg: UnicodeString;
  AComparer: IComparer<TQValueType>);
begin
  inherited Create(AErrorMsg);
  FMinValue := AMinValue;
  FMaxValue := AMaxValue;
  if Assigned(AComparer) then
    FComparer := AComparer
  else
    FComparer := TComparer<TQValueType>.Default;
end;

class function TQRangeValidator<TQValueType>.GetTypeName: UnicodeString;
begin
  Result := 'range'; // Dont localize
end;

function TQRangeValidator<TQValueType>.Require(const AValue,
  ADefaultValue: TQValueType): TQValueType;
begin
  Result := RequireEx(AValue, FMinValue, FMaxValue,
    ADefaultValue, FBounds);
end;

class function TQRangeValidator<TQValueType>.RequireEx(const AValue,
  AMinValue, AMaxValue, ADefaultValue: TQValueType; ABounds: TQRangeBounds;
  const AComparer: IComparer<TQValueType>): TQValueType;
begin
  if AcceptEx(AValue, AMinValue, AMaxValue, ABounds, AComparer) then
    Result := AValue
  else
    Result := ADefaultValue;
end;

/// <summary>注册默认的验证器</summary>

procedure RegisterDefaultValidators;
begin
  // 字符串，默认可以执行长度校验
  with TQValidators.FCurrent do
  begin
    FTypeValidators.Add(TypeInfo(UnicodeString),
      TQTypeValidator<UnicodeString>.Create
      ([TQLengthValidator<UnicodeString>.Create(0, 0, SDefaultLengthError)]));
    FTypeValidators.Add(TypeInfo(AnsiString),
      TQTypeValidator<AnsiString>.Create
      ([TQLengthValidator<AnsiString>.Create(0, 0, SDefaultLengthError)]));
    FTypeValidators.Add(TypeInfo(WideString),
      TQTypeValidator<WideString>.Create
      ([TQLengthValidator<WideString>.Create(0, 0, SDefaultLengthError)]));
    FTypeValidators.Add(TypeInfo(ShortString),
      TQTypeValidator<ShortString>.Create
      ([TQLengthValidator<ShortString>.Create(0, 0, SDefaultLengthError)]));
    // 数值类型
    FTypeValidators.Add(TypeInfo(Shortint),
      TQTypeValidator<Shortint>.Create([//
        TQRangeValidator<Shortint>.Create(-128,127, SDefaultRangeError, nil)]
      ));
    FTypeValidators.Add(TypeInfo(Smallint),
      TQTypeValidator<Smallint>.Create([
       TQRangeValidator<Smallint>.Create(-32768,32767,SDefaultRangeError,nil)
       ]
      ));
    FTypeValidators.Add(TypeInfo(Integer),
      TQTypeValidator<Integer>.Create([
       TQRangeValidator<Integer>.Create(-2147483648,2147483647,SDefaultRangeError,nil)
       ]
      ));
    FTypeValidators.Add(TypeInfo(Int64),
      TQTypeValidator<Int64>.Create([
       TQRangeValidator<Int64>.Create(-9223372036854775808, 9223372036854775807, SDefaultRangeError, nil)
       ]
      ));
    FTypeValidators.Add(TypeInfo(Byte),
      TQTypeValidator<Byte>.Create([TQRangeValidator<Byte>.Create(0, 255,
      SDefaultRangeError, nil)]));
    FTypeValidators.Add(TypeInfo(Word),
      TQTypeValidator<Word>.Create([
       TQRangeValidator<Word>.Create(0, 65535, SDefaultRangeError,nil)
       ]
      ));
    FTypeValidators.Add(TypeInfo(UINT32),
      TQTypeValidator<UInt32>.Create([
       TQRangeValidator<UINT32>.Create(0, 4294967295, SDefaultRangeError,nil)
       ]
      ));
    FTypeValidators.Add(TypeInfo(UInt64),
      TQTypeValidator<UInt64>.Create([
       TQRangeValidator<UInt64>.Create(0, 18446744073709551615, SDefaultRangeError, nil)
       ]
      ));
  end;
end;

{ TQChineseIdValidator }

function TQChineseIdValidator.Accept(const AValue: UnicodeString): Boolean;
var
  ACityCode: UnicodeString;
  ABirthday: TDateTime;
  AIsFemale: Boolean;
begin
  Result := TryDecode(AValue, ACityCode, ABirthday, AIsFemale);
end;

class function TQChineseIdValidator.GeTQValueTypeName: UnicodeString;
begin
  Result := SChineseId;
end;

function TQChineseIdValidator.TryDecode(AIdNo: UnicodeString;
  var ACityCode: UnicodeString; var ABirthday: TDateTime;
  var AIsFemale: Boolean): Boolean;
var
  ALen: Integer;
  AYear, AMonth, ADay: Word;
const
  Weight: array [1 .. 17] of Integer = (7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10,
    5, 8, 4, 2);
  Checksums: array [0 .. 10] of WideChar = ('1', '0', 'X', '9', '8', '7', '6',
    '5', '4', '3', '2');

  function CheckChineseId18: WideChar;
  var
    ASum, AIdx: Integer;
  begin
    ASum := 0;
    for AIdx := 1 to 17 do
    begin
      ASum := ASum + (Ord(AIdNo.Chars[AIdx]) - Ord('0')) * Weight[AIdx];
    end;
    Result := Checksums[ASum mod 11];
  end;
begin
  ALen := Length(AIdNo);
  Result := False;
  if ALen in [15, 18] then
  // 长度检查
  begin
    if ALen = 15 then
    begin
      AIdNo := AIdNo.Substring(0, 6) + '19' + AIdNo.Substring(Length(AIdNo)-9, 9);
      AIdNo := AIdNo + CheckChineseId18;
    end
    else if CheckChineseId18 <> AIdNo.Chars[17].ToUpper then // 身份证号校验码检查
      Exit;
    ACityCode := AIdNo.Substring(0,6);
    AYear:=StrToIntDef(AIdNo.Substring(6,4),0);
    AMonth:=StrToIntDef(AIdNo.Substring(10,2),0);
    ADay:=StrToIntDef(AIdNo.Substring(12,2),0);
    if not TryEncodeDate(AYear, AMonth, ADay, ABirthday) then
      Exit;
    if TryStrToInt(AIdNo.Substring(14,3),ALen) then
    begin
      Result := True;
      if (ALen mod 2) = 0 then
        AIsFemale := True
      else
        AIsFemale := False;
    end;
  end
  else
    Result := False;
end;

{ TQTextValidator }

function TQTextValidator.Accept(const AValue: UnicodeString): Boolean;
begin
  Result := True;
end;

procedure TQTextValidator.Check(const AValue: UnicodeString);
begin
  if not Accept(AValue) then
  begin
    raise EValidateException.Create(FormatError(FErrorMessage,
      [TPair<UnicodeString, UnicodeString>.Create('Value', AValue),
      TPair<UnicodeString, UnicodeString>.Create('ValueType', GetTypeName)]));
  end;
end;

class function TQTextValidator.GeTQValueTypeName: UnicodeString;
begin
  Result := GetTypeName;
end;

function TQTextValidator.Require(const AValue, ADefaultValue: UnicodeString)
  : UnicodeString;
begin
  if Accept(AValue) then
  begin
    Result := AValue;
  end
  else
  begin
    Result := ADefaultValue;
  end;
end;

{ TQEmailValidator }

function TQEmailValidator.Accept(const AValue: UnicodeString): Boolean;
begin
  // Todo:验证邮件地址
  Result := False;
end;

{ TQChinesseMobile }

function TQChineseMobileValidator.Accept(const AValue: UnicodeString): Boolean;
var
  p: PWideChar;
  ACount: Integer;
const
  Delimiters: PWideChar = ' -';
begin
  ACount := Length(AValue);
  Result := False;
  if ACount >= 11 then
  begin
    p := PWideChar(AValue);
    if p^ = '+' then // +86
    begin
      Inc(p);
      if p^ <> '8' then
        Exit;
      Inc(p);
      if p^ <> '6' then
        Exit;
      Inc(p);
      while p^=' ' do
        Inc(p);
      if p^='-' then
        Inc(p);
      while p^=' ' do
        Inc(p);
    end;
    if p^ = '1' then // 中国手机号以1打头，目前是 13,14,15,16,17,18,19 都已使用
    begin
      Inc(p);
      if (p^ >= '3') and (p^ <= '9') then
      begin
        ACount := 2;
        Inc(p);
        while p^ <> #0 do
        begin
          if (p^ >= '0') and (p^ <= '9') then
          begin
            Inc(p);
            Inc(ACount);
          end
          else if (p^ = '-') or (p^ = ' ') then
          begin
            if (p^ = '-') and (ACount = 11) then // 虚拟号？
              Exit(True);
            Inc(p)
          end
          else
            Exit;
        end;
        Result := (ACount = 11);
      end;
    end;
  end;
end;

{ TQBase64Validator }

function TQBase64Validator.Accept(const AValue: UnicodeString): Boolean;
begin
  Result:=false;
  // Todo:验证 Base64 编码
end;

{ TQUrlValidator }

function TQUrlValidator.Accept(const AValue: UnicodeString): Boolean;
var
  ASchema, AUserName, APassword, AHost, APath: UnicodeString;
  AParams: TArray<UnicodeString>;
  APort: Word;
begin
  APort := 0;
  Result := TryDecode(AValue, ASchema, AUserName, APassword, AHost, APath,
    AParams, APort);
end;

function TQUrlValidator.TryDecode(const AUrl: UnicodeString;
  var ASchema, AUserName, APassword, AHost, ADocPath: UnicodeString;
  var AParams: TArray<UnicodeString>; APort: Word): Boolean;
begin
  // Todo: 验证URL
  Result:=false;
end;

class function TQChineseMobileValidator.GeTQValueTypeName: UnicodeString;
begin
  Result := SChineseMobile;
end;

{ TQRegexValidator }

function TQRegexValidator.Accept(const AValue: UnicodeString): Boolean;
begin
  if Length(FRegex) = 0 then
  begin
    Exit(True);
  end;
  if not Assigned(FRegexProcessor) then
  begin
    FRegexProcessor := TPerlRegex.Create;
  end;
  if not FRegexProcessor.Compiled then  
  begin
    FRegexProcessor.RegEx := FRegex;
    FRegexProcessor.Compile;
    if not FRegexProcessor.Compiled then
    begin
      raise EValidateException.CreateFmt(SRegExpressionError,[FRegex])
    end;
  end;
  FRegexProcessor.Subject := AValue;
  Result:=FRegexProcessor.Match;
end;

{ TQIPV4Validator }

function TQIPV4Validator.Accept(const AValue: UnicodeString): Boolean;
var
  ALen,I,AIpSegCount: Integer;
  AIpByte: SmallInt;
begin
  ALen := Length(AValue);
  if (ALen < 7) or (ALen > 15) then
    exit(False);
  AIpSegCount := 0;
  AIpByte := 0;
  for I := 1 to ALen do
  begin
     if AIpSegCount > 3 then
       exit(False);
     case AValue[I] of
     '0'..'9':
       begin
         AIpByte := AIpByte*10+ Ord(AValue[I]) - 48;
         if AIpByte > 255 then
           Exit(False);
       end;
     '.':
       begin
         Inc(AIpSegCount);
         AIpByte := 0;
       end;
     else
       Exit(False);
     end;
  end;
  Result := (AIpSegCount = 3) and (AIpByte < 255);
end;

class function TQIPV4Validator.GeTQValueTypeName: UnicodeString;
begin
  Result := SIPV4;
end;

initialization

RegisterDefaultValidators;

end.
