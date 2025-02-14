﻿unit qdac.profile;

interface

{ QDAC 4.0 性能测量工具库
  1. 使用方式
  - 在函数的开始部分，增加 TQProfile.Calc('函数名称'); 调用
  - 对于 C++ Builder，可以直接简化为 CalcPerformance();
  2. 默认情况下，如果是 Debug 编译，会自动启用性能跟踪，Release 默认不启用
  3. 可以设置 TQProfile.Enabled 为 true 强制启用
  4. IDE 集成需要将来添加插件来支持，当前未实现
  5. 在启用性能测量模式下，程序退出前会保存测试结果到 profiles.json 文件中，也可以指定 TQProfile.FileName 来指定具体的文件路径
  6. 本工具库会为每个线程建立独立的管理对象，并且仅在程序退了时才会释放，所以不建议在发布给用户的版本中，长时间运行性能跟踪库。

}
uses Classes, Sysutils, Diagnostics, SyncObjs, Generics.Defaults,
  Generics.Collections;

type

  // 这个只是用来增加和减小引用计数使用，用户层调用 TQProfile.Calc 即可
  IQProfileHelper = interface
    ['{177F55CA-2B59-440B-AA81-54AFF6AC5581}']
    function CurrentStack: Pointer;
  end;

  PQProfileStack = ^TQProfileStack;
  PQProfileReference = ^TQProfileReference;

  // 引用信息记录
  TQProfileReference = record
    // 来源引用
    Ref: PQProfileStack;
    // 前一个，下一个
    Prior, Next: PQProfileReference;
  end;

  // 调用记录
  TQProfileStack = record
    // 函数名称
    Name: String;
    // 调用地址
    InvokeSource: Pointer;
    // 上一级、前一个、下一个
    Parent, Prior, Next: PQProfileStack;
    // 嵌套级别，最大嵌套级别
    NestLevel, MaxNestLevel: Cardinal;
    //
    AddedRefCount: Integer;
    // 统计信息
    // 运行次数
    Runs: Cardinal;
    // 单个函数的最小时间、最大时间、总用时，平均时间为TotalTime/Runs的结果
    MinTime, MaxTime, TotalTime: UInt64;
    // 最后一次的开始和结束时间
    LastStartTime, LastStopTime: Int64;
    // 使用链表来管理子函数
    // 第一个子函数
    FirstChild: PQProfileStack;
    // 最后一个子函数
    LastChild: PQProfileStack;
    // 异步调用的引用管理
    FirstRef, LastRef: PQProfileReference;
  end;

  PQProfileThreadStatics = ^TQProfileThreadStatics;

  // TQProfile.GetStatics 函数返回的线程统计信息
  TQProfileThreadStatics = record
    // 线程ID
    ThreadId: TThreadId;
    // 首次进入时间，末次结束时间
    FirstTime, LatestTime: UInt64;
    // 线程关联的函数列表
    Functions: TArray<String>;
  end;

  // TQProfile.GetStatics 函数返回的函数统计信息
  TQProfileFunctionStatics = record
    // 函数名称
    Name: String;
    // 函数调用来源线程列表
    Threads: TArray<PQProfileThreadStatics>;
    // 最大递归调用嵌套层数
    MaxNestLevel: Cardinal;
    // 函数运行次数
    Runs: Cardinal;
    // 函数运行的最小时长、最大时长和总时长
    MinTime, MaxTime, TotalTime: UInt64;
  end;

  // TQProfile.GetStatics的返回值
  TQProfileStatics = record
    // 线程统计信息
    Threads: TArray<TQProfileThreadStatics>;
    // 函数统计信息
    Functions: TArray<TQProfileFunctionStatics>;
  end;

  // 导出图表时的翻译字符串
  TQProfileTranslation = record
    Start, Thread: String;
  end;

  TAddressNameProc = function(const Addr: Pointer): String;

  // 全局类，用于提供性能接口
  TQProfile = class sealed
  private
  class var
    // 是否启用
    FEnabled: Boolean;
    // 退出时保存的跟踪记录信息JSON文件名
    FFileName: String;
    // 程序启动时间戳，用来和各个时间进行运算，以获取相对时间
    FStartupTime: UInt64;
    // 多线程同步锁
    FLocker: IReadWriteSync;

  type
    TQThreadProfileHelper = class(TInterfacedObject, IInterface,
      IQProfileHelper)
    protected
      FRoot: TQProfileStack;
      FCurrent: PQProfileStack;
      FThreadId: TThreadId;
      FFirstTime, FLatestTime: UInt64;
      FThreadName: String;
    private
      function CurrentStack: Pointer;
    public
      constructor Create; overload;
      procedure Push(const AName: String; AStackRef: PQProfileStack;
        const Addr: Pointer); inline;
      function _Release: Integer; overload; stdcall;
      property ThreadId: TThreadId read FThreadId;
      property ThreadName: String read FThreadName;
      property FirstTime: UInt64 read FFirstTime;
      property LatestTime: UInt64 read FLatestTime;
    end;

    TQThreadHelperSet = class sealed
    protected
    class var
      FHelpers: TArray<TQThreadProfileHelper>;
      FCount: Integer;
    public
      class constructor Create;
      class function NeedHelper(const AThreadId: TThreadId; const AName: String;
        AStackRef: PQProfileStack; const Addr: Pointer): IQProfileHelper;
    end;

    TQProfileStackHelper = record helper for TQProfileStack
      function Push(const AName: String; AStackRef: PQProfileStack;
        const Addr: Pointer): PQProfileStack;
      function Pop: PQProfileStack;
      function ThreadHelper: TQProfile.TQThreadProfileHelper;
    end;

  protected
    class procedure SaveProfiles;
    class procedure Cleanup;
    class function StackItemName(AStack: PQProfileStack): String; inline;
  public
    class constructor Create;
    // 将跟踪记录转换为 JSON 字符串格式
    class function AsString: String;
    // 将跟踪记录转换为 mermaid 流程图格式
    class function AsDiagrams: String;
    // 对跟踪记录进行统计
    class function GetStatics: TQProfileStatics;
    // 保存跟踪记录为 mermaid 格式文件
    class procedure SaveDiagrams(const AFileName: String);
    /// <summary>记录一个锚点</summary>
    /// <param name="AName">锚点名称参数，一般为函数名</param>
    /// <param name="AStackRef">参考来源锚点，一般用于异步调用时，指向原始栈记录</param>
    /// <returns>如果 TQProfile.Enabled 为 true，返回当前线程的 IQProfileHelper 接口实例，否则返回空指针</returns>
    class function Calc(const AName: String; AStackRef: PQProfileStack = nil)
      : IQProfileHelper; overload;
{$IFDEF MSWINDOWS}
    /// <summary>记录一个锚点</summary>
    /// <param name="AStackRef">参考来源锚点，一般用于异步调用时，指向原始栈记录</param>
    /// <returns>如果 TQProfile.Enabled 为 true，返回当前线程的 IQProfileHelper 接口实例，否则返回空指针</returns>
    /// <remarks>
    /// 1.此函数仅支持 Windows 操作系统，而且只记录了地址，用户需要关联 AddressName 函数来解决地址与名称的映射问题
    /// 2.AddressName 可以使用 JclDebug 中的 GetLocationInfo 函数来做简单封装，具体参考示例
    /// </remarks>
    class function Calc(AStackRef: PQProfileStack = nil)
      : IQProfileHelper; overload;
{$ENDIF}
    /// 当前是否启用了跟踪，只读，只能通过命令行开关 EnableProfile 修改或者使用默认值
    class property Enabled: Boolean read FEnabled;
    /// 要保存的跟踪记录文件名，默认为 profiles.json
    class property FileName: String read FFileName write FFileName;
  public
  class var
    // 流程图中使用的字符串翻译
    Translation: TQProfileTranslation;
    AddressName: TAddressNameProc;
  end;

{$HPPEMIT '#define CalcPerformance() TQProfile::Calc(__FUNC__)' }

resourcestring
  SProfileDiagramStart = 'Start';
  SProfileDiagramThread = 'Thread';

implementation

{$IFDEF MSWINDOWS}

uses Windows;
function RtlCaptureStackBackTrace(FramesToSkip, FramesToCapture: DWORD;
  BackTrace: Pointer; BackTraceHash: PDWORD): Word; stdcall; external kernel32;

{$ENDIF}
{ TQProfile }

class function TQProfile.Calc(const AName: String; AStackRef: PQProfileStack)
  : IQProfileHelper;
begin
  if Enabled then
    Result := TQThreadHelperSet.NeedHelper(TThread.Current.ThreadId, AName,
      AStackRef, nil)
  else
    Result := nil;
end;
{$IFDEF MSWINDOWS}

class function TQProfile.Calc(AStackRef: PQProfileStack): IQProfileHelper;
var
  Addr: Pointer;
begin
  Addr := nil;
  RtlCaptureStackBackTrace(1, 1, @Addr, nil);
  if Enabled then
    Result := TQThreadHelperSet.NeedHelper(TThread.Current.ThreadId, '',
      AStackRef, Addr)
  else
    Result := nil;
end;
{$ENDIF}

class procedure TQProfile.Cleanup;
  procedure DoCleanup(AStack: PQProfileStack);
  var
    AChild, ANext: PQProfileStack;
    ARef, ANextRef: PQProfileReference;
  begin
    AChild := AStack.FirstChild;
    while Assigned(AChild) do
    begin
      ANext := AChild.Next;
      // 清空引用
      ARef := AChild.FirstRef;
      while Assigned(ARef) do
      begin
        ANextRef := ARef.Next;
        Dispose(ARef);
        ARef := ANextRef;
      end;
      if Assigned(AChild.FirstChild) then
        DoCleanup(AChild);
      if Assigned(AChild.Parent) then
        Dispose(AChild);
      AChild := ANext;
    end;
  end;

var
  I: Integer;
begin
  for I := 0 to High(TQThreadHelperSet.FHelpers) do
  begin
    if Assigned(TQThreadHelperSet.FHelpers[I]) then
    begin
      DoCleanup(@TQThreadHelperSet.FHelpers[I].FRoot);
      TQThreadHelperSet.FHelpers[I]._Release;
    end;
  end;
  SetLength(TQThreadHelperSet.FHelpers, 0);
end;

class constructor TQProfile.Create;
begin
  FEnabled :=
{$IFDEF DEBUG}true{$ELSE}FindCmdlineSwitch('EnableProfile'){$ENDIF};
  Translation.Start := SProfileDiagramStart;
  Translation.Thread := SProfileDiagramThread;
  AddressName := nil;
  FFileName := ExtractFilePath(ParamStr(0)) + 'profiles.json';
  FStartupTime := TStopWatch.GetTimeStamp;
  FLocker := TMREWSync.Create;
end;

class function TQProfile.GetStatics: TQProfileStatics;
var
  I, ACount: Integer;
  AComparer: IComparer<TQProfileFunctionStatics>;

  procedure DoBuild(AThread: PQProfileThreadStatics; AStack: PQProfileStack);
  var
    AItem: PQProfileStack;
    ANameArray: TArray<String>;
    ATemp: TQProfileFunctionStatics;
    I, J: Integer;
  begin
    AItem := AStack.FirstChild;
    while Assigned(AItem) do
    begin
      ANameArray := StackItemName(AItem).Split(['#']);
      for I := 0 to High(ANameArray) do
      begin
        ATemp.Name := ANameArray[I];
        if not TArray.BinarySearch<TQProfileFunctionStatics>(Result.Functions,
          ATemp, J, AComparer) then
        begin
          ATemp.Threads := [AThread];
          ATemp.MaxNestLevel := AItem.MaxNestLevel;
          ATemp.Runs := AItem.Runs;
          ATemp.MinTime := AItem.MinTime;
          ATemp.MaxTime := AItem.MaxTime;
          ATemp.TotalTime := AItem.TotalTime;
          Insert(ATemp, Result.Functions, J);
        end
        else
        begin
          with Result.Functions[J] do
          begin
            if MaxNestLevel < AItem.MaxNestLevel then
              MaxNestLevel := AItem.MaxNestLevel;
            if MinTime > AItem.MinTime then
              MinTime := AItem.MinTime;
            if MaxTime < AItem.MaxTime then
              MaxTime := AItem.MaxTime;
            Inc(Runs, AItem.Runs);
            Inc(TotalTime, AItem.TotalTime);
            if not TArray.BinarySearch<PQProfileThreadStatics>(Threads,
              AThread, J) then
              Insert(AThread, Threads, J);
          end;
        end;
        // 查找线程的函数列表
        if not TArray.BinarySearch<String>(Result.Threads[ACount].Functions,
          ATemp.Name, J) then
          Insert(ATemp.Name, Result.Threads[ACount].Functions, J);
      end;
      DoBuild(AThread, AItem);
      AItem := AItem.Next;
    end;
  end;

begin
  SetLength(Result.Functions, 0);
  SetLength(Result.Threads, Length(TQThreadHelperSet.FHelpers));
  ACount := 0;
  AComparer := TComparer<TQProfileFunctionStatics>.Construct(
    function(const L, R: TQProfileFunctionStatics): Integer
    begin
      Result := CompareStr(L.Name, R.Name);
    end);
  for I := 0 to High(TQThreadHelperSet.FHelpers) do
  begin
    if Assigned(TQThreadHelperSet.FHelpers[I]) then
    begin
      Result.Threads[ACount].ThreadId := TQThreadHelperSet.FHelpers[I].ThreadId;
      Result.Threads[ACount].FirstTime := TQThreadHelperSet.FHelpers[I]
        .FirstTime;
      Result.Threads[ACount].LatestTime := TQThreadHelperSet.FHelpers[I]
        .LatestTime;
      DoBuild(@Result.Threads[ACount], @TQThreadHelperSet.FHelpers[I].FRoot);
      Inc(ACount);
    end;
  end;
  SetLength(Result.Threads, ACount);
end;

class procedure TQProfile.SaveDiagrams(const AFileName: String);
var
  AStream: TStringStream;
begin
  AStream := TStringStream.Create(AsDiagrams, TEncoding.UTF8);
  try
    AStream.SaveToFile(AFileName);
  finally
    FreeAndNil(AStream);
  end;
end;

class procedure TQProfile.SaveProfiles;
var
  AStream: TStringStream;
begin
  if Enabled then
  begin
    AStream := TStringStream.Create(AsString, TEncoding.UTF8);
    try
      AStream.SaveToFile(FileName);
    finally
      FreeAndNil(AStream);
    end;
  end;
end;

class function TQProfile.StackItemName(AStack: PQProfileStack): String;
begin
  if (Length(AStack.Name) = 0) and Assigned(AStack.InvokeSource) then
  begin
    if Assigned(AddressName) then
      AStack.Name := AddressName(AStack.InvokeSource)
    else
      AStack.Name := IntToHex(IntPtr(AStack.InvokeSource));
  end;
  Result := AStack.Name;
end;

class function TQProfile.AsDiagrams: String;
var
  ABuilder: TStringBuilder;
  I: Integer;
  AStatics: TQProfileStatics;
  AComparer: IComparer<TQProfileFunctionStatics>;
  procedure AppendDiagram(AStack: PQProfileStack; AParentName: String);
  var
    ANameArray: TArray<String>;
    ARef: PQProfileReference;
    AItem: PQProfileStack;
    AFunctionEntry: TQProfileFunctionStatics;
    ASourceIdx, ATargetIdx, I: Integer;
    AFound: Boolean;
  begin
    ATargetIdx := 0;
    if Assigned(AStack.Parent) then
    begin
      // 我们以JSON格式来保存
      ANameArray := StackItemName(AStack).Split(['#']);
      AFunctionEntry.Name := ANameArray[0];
      if TArray.BinarySearch<TQProfileFunctionStatics>(AStatics.Functions,
        AFunctionEntry, ATargetIdx, AComparer) then
      begin
        ABuilder.Append(AParentName).Append('-->fn').Append(ATargetIdx)
          .Append(SLineBreak);
        for I := 1 to High(ANameArray) do
        begin
          AFunctionEntry.Name := ANameArray[I];
          if TArray.BinarySearch<TQProfileFunctionStatics>(AStatics.Functions,
            AFunctionEntry, ASourceIdx, AComparer) then
            ABuilder.Append('fn').Append(ASourceIdx).Append('-.->fn')
              .Append(ATargetIdx).Append(SLineBreak);
        end;
      end;
      ARef := AStack.FirstRef;
      while Assigned(ARef) do
      begin
        if Length(ANameArray) > 1 then
        begin
          AFound := false;
          for I := 1 to High(ANameArray) do
          begin
            if ANameArray[I] = ARef.Ref.Name then
            begin
              AFound := true;
              break;
            end;
          end;
          if AFound then
            continue;
        end;
        AFunctionEntry.Name := ARef.Ref.Name;
        if TArray.BinarySearch<TQProfileFunctionStatics>(AStatics.Functions,
          AFunctionEntry, ASourceIdx, AComparer) then
          ABuilder.Append('fn').Append(ASourceIdx).Append('-.->fn')
            .Append(ATargetIdx).Append(SLineBreak);
        ARef := ARef.Next;
      end;
      AParentName := 'fn' + IntToStr(ATargetIdx)
    end;
    AItem := AStack.FirstChild;
    while Assigned(AItem) do
    begin
      AppendDiagram(AItem, AParentName);
      AItem := AItem.Next;
    end;
  end;

begin
  ABuilder := TStringBuilder.Create;
  try
    AStatics := GetStatics;
    AComparer := TComparer<TQProfileFunctionStatics>.Construct(
      function(const L, R: TQProfileFunctionStatics): Integer
      begin
        Result := CompareText(L.Name, R.Name);
      end);
    ABuilder.Append('flowchart TB').Append(SLineBreak);
    ABuilder.Append('start(("').Append(Translation.Start).Append('"))')
      .Append(SLineBreak);
    // 插入线程结点
    for I := 0 to High(AStatics.Threads) do
    begin
      ABuilder.Append('thread').Append(AStatics.Threads[I].ThreadId)
        .Append('[["`').Append(Translation.Thread).Append(' ')
        .Append(AStatics.Threads[I].ThreadId).Append(SLineBreak)
        .Append(AStatics.Threads[I].FirstTime - FStartupTime).Append('->')
        .Append(AStatics.Threads[I].LatestTime - FStartupTime).Append('`"]]')
        .Append(SLineBreak);
      ABuilder.Append('start-->thread').Append(AStatics.Threads[I].ThreadId)
        .Append(SLineBreak);
    end;
    // 插入函数名结点
    for I := 0 to High(AStatics.Functions) do
    begin
      ABuilder.Append('fn').Append(I).Append('(')
        .Append(AnsiQuotedStr(AStatics.Functions[I].Name, '"')).Append(')')
        .Append(SLineBreak);
    end;
    for I := 0 to High(TQThreadHelperSet.FHelpers) do
    begin
      if Assigned(TQThreadHelperSet.FHelpers[I]) then
      begin
        with TQThreadHelperSet.FHelpers[I] do
          AppendDiagram(@FRoot, 'thread' + IntToStr(ThreadId));
      end;
    end;
    Result := ABuilder.ToString;
  finally
    FreeAndNil(ABuilder);
  end;

end;

class function TQProfile.AsString: String;
var
  ABuilder: TStringBuilder;

  procedure AppendProfile(AIndent: String; AStack: PQProfileStack);
  var
    ANextIndent, AChildIndent: String;
    AItem: PQProfileStack;
    ARef: PQProfileReference;
    ANameArray: TArray<String>;
    I: Integer;
  begin
    ANextIndent := AIndent + '  ';
    if Assigned(AStack.Parent) then
    begin
      // 我们以JSON格式来保存
      ABuilder.Append(AIndent).Append('{').Append(SLineBreak);
      ANameArray := StackItemName(AStack).Split(['#']);
      ABuilder.Append(ANextIndent).Append('"name":').Append('"')
        .Append(ANameArray[0]).Append('",').Append(SLineBreak);
      ABuilder.Append(ANextIndent).Append('"maxNestLevel":')
        .Append(AStack.MaxNestLevel).Append(',').Append(SLineBreak);
      ABuilder.Append(ANextIndent).Append('"runs":').Append(AStack.Runs)
        .Append(',').Append(SLineBreak);
      ABuilder.Append(ANextIndent).Append('"minTime":').Append(AStack.MinTime)
        .Append(',').Append(SLineBreak);
      ABuilder.Append(ANextIndent).Append('"maxTime":').Append(AStack.MaxTime)
        .Append(',').Append(SLineBreak);
      ABuilder.Append(ANextIndent).Append('"totalTime":')
        .Append(AStack.TotalTime).Append(',').Append(SLineBreak);
      ABuilder.Append(ANextIndent).Append('"avgTime":')
        .Append(FormatFloat('0.##', AStack.TotalTime / AStack.Runs));
      if Assigned(AStack.FirstChild) then
      begin
        ABuilder.Append(',').Append(SLineBreak);
        ABuilder.Append(ANextIndent).Append('"children":[').Append(SLineBreak);
        AChildIndent := ANextIndent + '  ';
        AItem := AStack.FirstChild;
        while Assigned(AItem) do
        begin
          AppendProfile(AChildIndent, AItem);
          AItem := AItem.Next;
          if Assigned(AItem) then
            ABuilder.Append(',').Append(SLineBreak)
          else
            ABuilder.Append(SLineBreak)
        end;
        ABuilder.Append(ANextIndent).Append(']');
      end;
      // 关联引用
      if Assigned(AStack.FirstRef) or (Length(ANameArray) > 1) then
      begin
        ABuilder.Append(',').Append(SLineBreak);
        ABuilder.Append(ANextIndent).Append('"refs":[').Append(SLineBreak);
        AChildIndent := ANextIndent + '  ';
        for I := 1 to High(ANameArray) do
        begin
          ABuilder.Append(AChildIndent).Append('"').Append(ANameArray[I])
            .Append('"');
          if (I < High(ANameArray)) or Assigned(AStack.FirstRef) then
            ABuilder.Append(',').Append(SLineBreak)
          else
            ABuilder.Append(SLineBreak);
        end;
        ARef := AStack.FirstRef;
        while Assigned(ARef) do
        begin
          ABuilder.Append(AChildIndent).Append('"').Append(ARef.Ref.Name)
            .Append('"');
          ARef := ARef.Next;
          if Assigned(ARef) then
            ABuilder.Append(',').Append(SLineBreak)
          else
            ABuilder.Append(SLineBreak)
        end;
        ABuilder.Append(ANextIndent).Append(']').Append(SLineBreak);
      end
      else
        ABuilder.Append(SLineBreak);
      ABuilder.Append(AIndent).Append('}');
    end
    else
    begin
      ABuilder.Append(AIndent).Append('{').Append(SLineBreak);
      with AStack.ThreadHelper do
      begin
        ABuilder.Append(ANextIndent).Append('"threadId":').Append(FThreadId)
          .Append(',').Append(SLineBreak);
        ABuilder.Append(ANextIndent).Append('"startTime":')
          .Append(FirstTime - FStartupTime).Append(',').Append(SLineBreak);
        ABuilder.Append(ANextIndent).Append('"latestTime":')
          .Append(LatestTime - FStartupTime).Append(',').Append(SLineBreak);
      end;
      ABuilder.Append(ANextIndent).Append('"chains":[').Append(SLineBreak);
      AChildIndent := ANextIndent + '  ';
      AItem := AStack.FirstChild;
      while Assigned(AItem) do
      begin
        AppendProfile(AChildIndent, AItem);
        AItem := AItem.Next;
        if Assigned(AItem) then
          ABuilder.Append(',').Append(SLineBreak)
        else
          ABuilder.Append(SLineBreak);
      end;
      ABuilder.Append(ANextIndent).Append(']').Append(SLineBreak);
      ABuilder.Append(AIndent).Append('}');
    end;
  end;

var
  I, ACount: Integer;
begin
  ACount := 0;
  ABuilder := TStringBuilder.Create;
  try
    ABuilder.Append('{').Append(SLineBreak);
    ABuilder.Append('"mainThreadId":').Append(MainThreadId).Append(',')
      .Append(SLineBreak);
    ABuilder.Append('"freq":').Append(TStopWatch.Frequency).Append(',')
      .Append(SLineBreak);
    ABuilder.Append('"threads":[').Append(SLineBreak);
    for I := 0 to High(TQThreadHelperSet.FHelpers) do
    begin
      if Assigned(TQThreadHelperSet.FHelpers[I]) then
      begin
        AppendProfile('  ', @TQThreadHelperSet.FHelpers[I].FRoot);
        Inc(ACount);
        if ACount < TQThreadHelperSet.FCount then
          ABuilder.Append(',').Append(SLineBreak)
        else
          ABuilder.Append(SLineBreak);
      end;
    end;
    ABuilder.Append('  ]').Append(SLineBreak);
    ABuilder.Append('}');
    Result := ABuilder.ToString;
  finally
    FreeAndNil(ABuilder);
  end;
end;

{ TQThreadProfileHelper }

constructor TQProfile.TQThreadProfileHelper.Create;
begin
  FThreadId := TThread.CurrentThread.ThreadId;
  FCurrent := @FRoot;
  FCurrent.LastStartTime := TStopWatch.GetTimeStamp;
  FCurrent.NestLevel := 1;
  FFirstTime := FCurrent.LastStartTime;
end;

function TQProfile.TQThreadProfileHelper.CurrentStack: Pointer;
begin
  Result := FCurrent;
end;

procedure TQProfile.TQThreadProfileHelper.Push(const AName: String;
AStackRef: PQProfileStack; const Addr: Pointer);
begin
  FCurrent := FCurrent.Push(AName, AStackRef, Addr);
end;

function TQProfile.TQThreadProfileHelper._Release: Integer;
begin
  Result := inherited _Release;
  if Result > 0 then
  begin
    // 如果是包含了额外的引用，则需要减少对应的计数后才真正移除
    if FCurrent.AddedRefCount > 0 then
      Dec(FCurrent.AddedRefCount);
    if FCurrent.AddedRefCount = 0 then
    begin
      Dec(FCurrent.NestLevel);
      if FCurrent.NestLevel = 0 then
      begin
        FCurrent := FCurrent.Pop;
        FLatestTime := TStopWatch.GetTimeStamp;
      end;
    end;
  end;
end;

{ TQProfileStackHelper }

function TQProfile.TQProfileStackHelper.Pop: PQProfileStack;
var
  ADelta: Int64;
begin
  if Assigned(Parent) then
    Result := Parent
  else
    // 匿名函数引用会增加额外的计数，造成统计不准，后面研究处理
    Result := @Self;
  LastStopTime := TStopWatch.GetTimeStamp;
  ADelta := LastStopTime - LastStartTime;
  if ADelta < 0 then
    ADelta := Int64($7FFFFFFFFFFFFFFF) - LastStartTime + LastStopTime;
  if ADelta > MaxTime then
    MaxTime := ADelta;
  if ADelta < MinTime then
    MinTime := ADelta;
  Inc(TotalTime, ADelta);
  Inc(Runs);
end;

function TQProfile.TQProfileStackHelper.Push(const AName: String;
AStackRef: PQProfileStack; const Addr: Pointer): PQProfileStack;
var
  AChild: PQProfileStack;
  procedure AddStackRef;
  var
    ARef: PQProfileReference;
  begin
    Inc(AChild.AddedRefCount);
    ARef := AChild.FirstRef;
    while Assigned(ARef) do
    begin
      if ARef.Ref = AStackRef then
        Exit;
      ARef := ARef.Next;
    end;
    New(ARef);
    ARef.Prior := AChild.LastRef;
    ARef.Ref := AStackRef;
    ARef.Next := nil;
    if Assigned(AChild.LastRef) then
      AChild.LastRef.Next := ARef
    else
      AChild.FirstRef := ARef;
    AChild.LastRef := ARef;
  end;

  function IsNest: Boolean;
  begin
    if Assigned(Addr) and (Addr = InvokeSource) then
      Exit(true)
    else if Length(AName) > 0 then
      Result := CompareStr(Name, AName) = 0
    else
      Result := false;
  end;

begin
  if IsNest then
  begin
    Inc(NestLevel);
    if NestLevel > MaxNestLevel then
      MaxNestLevel := NestLevel;
    Result := @Self;
  end
  else
  begin
    AChild := FirstChild;
    while Assigned(AChild) do
    begin
      if CompareText(AChild.Name, AName) = 0 then
      begin
        Inc(AChild.NestLevel);
        AChild.LastStartTime := TStopWatch.GetTimeStamp;
        AChild.LastStopTime := 0;
        if Assigned(AStackRef) then
          AddStackRef;
        Exit(AChild);
      end;
      AChild := AChild.Next;
    end;
    New(AChild);
    AChild.Name := AName;
    AChild.InvokeSource := Addr;
    UniqueString(AChild.Name);
    AChild.Parent := @Self;
    AChild.Prior := LastChild;
    if Assigned(LastChild) then
      LastChild.Next := AChild
    else
      FirstChild := AChild;
    LastChild := AChild;
    AChild.Next := nil;
    AChild.NestLevel := 1;
    AChild.MaxNestLevel := 0;
    AChild.Runs := 0;
    AChild.MinTime := 0;
    AChild.MaxTime := 0;
    AChild.TotalTime := 0;
    AChild.LastStartTime := TStopWatch.GetTimeStamp;
    AChild.LastStopTime := 0;
    AChild.FirstChild := nil;
    AChild.LastChild := nil;
    AChild.AddedRefCount := 0;
    if Assigned(AStackRef) then
      AddStackRef
    else
    begin
      AChild.FirstRef := nil;
      AChild.LastRef := nil;
    end;
    Result := AChild;
  end;
end;

function TQProfile.TQProfileStackHelper.ThreadHelper
  : TQProfile.TQThreadProfileHelper;
var
  ARoot: PQProfileStack;
begin
  ARoot := @Self;
  Result := nil;
  while Assigned(ARoot.Parent) do
    ARoot := ARoot.Parent;
  Result := TQProfile.TQThreadProfileHelper
    (IntPtr(ARoot) - (IntPtr(@Result.FRoot) - IntPtr(Result)));
end;

{ TQThreadHelperSet }

class constructor TQProfile.TQThreadHelperSet.Create;
begin
  FCount := 0;
  FHelpers := [];
end;

class function TQProfile.TQThreadHelperSet.NeedHelper(const AThreadId
  : TThreadId; const AName: String; AStackRef: PQProfileStack;
const Addr: Pointer): IQProfileHelper;
const
  BUCKET_MASK = Integer($80000000);
  BUCKET_INDEX_MASK = Integer($7FFFFFFF);
  function FindBucketIndex(const AHelpers: TArray<TQThreadProfileHelper>;
  AThreadId: TThreadId): Integer;
  var
    I, AHash: Integer;
    AItem: TQThreadProfileHelper;
  begin
    if Length(AHelpers) = 0 then
      Exit(BUCKET_MASK);
    AHash := Integer(AThreadId) mod Length(AHelpers);
    I := AHash;
    while I < Length(AHelpers) do
    begin
      AItem := AHelpers[I];
      if Assigned(AItem) then
      begin
        if AItem.ThreadId = AThreadId then
          Exit(I)
        else
          Inc(I);
      end
      else
        Exit(I or BUCKET_MASK);
    end;
    I := 0;
    while I < AHash do
    begin
      AItem := AHelpers[I];
      if Assigned(AItem) then
      begin
        if AItem.ThreadId = AThreadId then
          Exit(I)
        else
          Inc(I);
      end
      else
        break;
    end;
    Result := I or BUCKET_MASK;
  end;

  function IsPrime(V: Integer): Boolean;
  var
    I, J: Integer;
  begin
    if V > 1 then
    begin
      J := Trunc(sqrt(V));
      for I := 2 to J do
      begin
        if V mod I = 0 then
          Exit(false);
      end;
      Result := true;
    end
    else
      Result := false;
  end;

  procedure ReallocArray;
  var
    ANew: TArray<TQThreadProfileHelper>;
    I, L: Integer;
  begin
    case Length(FHelpers) of
      0:
        SetLength(ANew, 19);
      19:
        SetLength(ANew, 67);
      67:
        SetLength(ANew, 131);
      131:
        SetLength(ANew, 509);
      509:
        SetLength(ANew, 1021);
      1021:
        SetLength(ANew, 2039)
    else
      // 尽量质数，超过2039个线程的话，我们翻倍现算
      begin
        I := Length(FHelpers) + 1;
        L := Length(FHelpers) shl 1 - 1;
        while (L >= I) and (not IsPrime(L)) do
          Dec(L);
        if I >= L then
        begin
          L := (Length(FHelpers) shl 1) + 1;
          while not IsPrime(L) do
            Inc(L);
        end;
        SetLength(ANew, L);
      end;
    end;
    for I := 0 to High(FHelpers) do
      ANew[FindBucketIndex(ANew, FHelpers[I].ThreadId) and BUCKET_INDEX_MASK] :=
        FHelpers[I];
    FHelpers := ANew;
  end;

  function FindExists: TQThreadProfileHelper;
  var
    ABucketIndex: Integer;
  begin
    Result := nil;
    FLocker.BeginRead;
    ABucketIndex := FindBucketIndex(FHelpers, AThreadId);
    if ABucketIndex >= 0 then
      Result := FHelpers[ABucketIndex];
    FLocker.EndRead;
  end;

  function InsertHelper: TQThreadProfileHelper;
  var
    ABucketIndex: Integer;
  begin
    FLocker.BeginWrite;
    try
      if FCount = Length(FHelpers) then
        ReallocArray;
      ABucketIndex := FindBucketIndex(FHelpers, AThreadId);
      if ABucketIndex >= 0 then
        Result := FHelpers[ABucketIndex]
      else
      begin
        Result := TQThreadProfileHelper.Create;
        FHelpers[ABucketIndex and BUCKET_INDEX_MASK] := Result;
        Result._AddRef;
        Inc(FCount);
      end;
    finally
      FLocker.EndWrite;
    end;
  end;

var
  AHelper: TQThreadProfileHelper;
begin
  AHelper := FindExists;
  if not Assigned(AHelper) then
    AHelper := InsertHelper;
  AHelper.Push(AName, AStackRef, Addr);
  Result := AHelper;
end;

initialization

finalization

TQProfile.SaveProfiles;
TQProfile.Cleanup;

end.
