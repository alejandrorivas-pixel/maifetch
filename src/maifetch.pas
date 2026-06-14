program maifetch;

{$mode delphi}

uses
  Classes,
  FPImage,
  FPJSON,
  FPReadJPEG,
  FPReadPNG,
  FPHTTPClient,
  JSONParser,
  Math,
  OpenSSLSockets,
  StrUtils,
  SysUtils;

const
  BaseURL = 'https://maitea.app';
  ResetColour = #27'[0m';

type
  TStringArray = array of string;

  TConfig = record
    AccessToken: string;
    ConfigFile: string;
    LogoSize: Integer;
    ScoreCount: Integer;
    ProfileFixture: string;
    PlaysFixture: string;
  end;

  TProfile = record
    Id: Integer;
    Name: string;
    Rating: Integer;
    RatingHighest: Integer;
    Level: Integer;
    PlayTotal: Integer;
    IconPng: string;
  end;

  TPlay = record
    SongName: string;
    Difficulty: string;
    ScoreFormatted: string;
    AchievementFormatted: string;
    Rank: string;
    FullComboLabel: string;
  end;

  TPlayArray = array of TPlay;

function StartsWithText(const Value, Prefix: string): Boolean;
begin
  Result := CompareText(Copy(Value, 1, Length(Prefix)), Prefix) = 0;
end;

function AnsiFg(const Value: string; R, G, B: Integer): string;
begin
  Result := Format(#27'[38;2;%d;%d;%dm%s%s', [R, G, B, Value, ResetColour]);
end;

function AnsiBg(const Value: string; FR, FG, FB, BR, BG, BB: Integer): string;
begin
  Result := Format(#27'[38;2;%d;%d;%dm'#27'[48;2;%d;%d;%dm%s%s', [FR, FG, FB, BR, BG, BB, Value, ResetColour]);
end;

function Colour(const Value: string): string;
begin
  Result := AnsiFg(Value, 72, 184, 200);
end;

function DifficultyString(const Difficulty: string): string;
begin
  if SameText(Difficulty, 'easy') then
    Result := AnsiBg('Easy', 255, 255, 255, 69, 174, 255)
  else if SameText(Difficulty, 'basic') then
    Result := AnsiBg('Basic', 255, 255, 255, 111, 212, 61)
  else if SameText(Difficulty, 'advanced') then
    Result := AnsiBg('Advanced', 255, 255, 255, 248, 183, 9)
  else if SameText(Difficulty, 'expert') then
    Result := AnsiBg('Expert', 255, 255, 255, 255, 46, 66)
  else if SameText(Difficulty, 'master') then
    Result := AnsiBg('Master', 255, 255, 255, 171, 140, 233)
  else if SameText(Difficulty, 'remaster') or SameText(Difficulty, 're:master') then
    Result := AnsiBg('Re:Master', 255, 255, 255, 207, 114, 237)
  else if SameText(Difficulty, 'utage') then
    Result := AnsiBg('Utage', 255, 255, 255, 255, 68, 1)
  else
    Result := Difficulty;
end;

function RankString(const Rank: string): string;
begin
  if Rank = 'SSS+' then
    Result := AnsiFg('S', 255, 200, 54) + AnsiFg('S', 225, 38, 165) + AnsiFg('S', 73, 64, 233) + AnsiFg('+', 21, 203, 148)
  else if Rank = 'SSS' then
    Result := AnsiFg('S', 255, 200, 54) + AnsiFg('S', 232, 39, 148) + AnsiFg('S', 18, 195, 144)
  else if (Rank = 'SS+') or (Rank = 'SS') then
    Result := AnsiBg(Rank, 248, 200, 75, 143, 71, 33)
  else if (Rank = 'S+') or (Rank = 'S') then
    Result := AnsiBg(Rank, 248, 200, 75, 75, 82, 82)
  else if (Rank = 'AAA') or (Rank = 'AA') or (Rank = 'A') then
    Result := AnsiFg(Rank, 23, 163, 255)
  else
    Result := Rank;
end;

function ReadTextFile(const FileName: string): string;
var
  Stream: TStringStream;
begin
  Stream := TStringStream.Create('', TEncoding.UTF8);
  try
    Stream.LoadFromFile(FileName);
    Result := Stream.DataString;
  finally
    Stream.Free;
  end;
end;

function GetEnvFirst(const Names: array of string): string;
var
  I: Integer;
begin
  Result := '';
  for I := Low(Names) to High(Names) do
  begin
    Result := GetEnvironmentVariable(Names[I]);
    if Result <> '' then
      Exit;
  end;
end;

function DefaultConfigFile: string;
{$IFNDEF DARWIN}
var
  Base: string;
{$ENDIF}
begin
  {$IFDEF DARWIN}
  Result := IncludeTrailingPathDelimiter(GetUserDir) + 'Library/Application Support/maifetch.json';
  {$ELSE}
  {$IFDEF MSWINDOWS}
  Base := GetEnvironmentVariable('APPDATA');
  if Base = '' then
    Base := GetUserDir;
  Result := IncludeTrailingPathDelimiter(Base) + 'maifetch.json';
  {$ELSE}
  Base := GetEnvironmentVariable('XDG_CONFIG_HOME');
  if Base = '' then
    Base := IncludeTrailingPathDelimiter(GetUserDir) + '.config';
  Result := IncludeTrailingPathDelimiter(Base) + 'maifetch.json';
  {$ENDIF}
  {$ENDIF}
end;

function FindArgValue(const LongName, ShortName: string): string;
var
  I: Integer;
  Arg: string;
begin
  Result := '';
  I := 1;
  while I <= ParamCount do
  begin
    Arg := ParamStr(I);
    if StartsWithText(Arg, LongName + '=') then
      Exit(Copy(Arg, Length(LongName) + 2, MaxInt));
    if (Arg = LongName) or (Arg = ShortName) then
    begin
      if I = ParamCount then
        raise Exception.CreateFmt('%s requires a value', [Arg]);
      Exit(ParamStr(I + 1));
    end;
    Inc(I);
  end;
end;

function JSONObjField(Obj: TJSONObject; const Name: string): TJSONObject;
var
  Data: TJSONData;
begin
  Result := nil;
  if Obj = nil then
    Exit;
  Data := Obj.Find(Name);
  if (Data <> nil) and (Data is TJSONObject) then
    Result := TJSONObject(Data);
end;

function JSONStrField(Obj: TJSONObject; const Name, Default: string): string;
var
  Data: TJSONData;
begin
  Result := Default;
  if Obj = nil then
    Exit;
  Data := Obj.Find(Name);
  if (Data <> nil) and (Data.JSONType <> jtNull) then
    Result := Data.AsString;
end;

function JSONIntField(Obj: TJSONObject; const Name: string; Default: Integer): Integer;
var
  Data: TJSONData;
begin
  Result := Default;
  if Obj = nil then
    Exit;
  Data := Obj.Find(Name);
  if Data = nil then
    Exit;
  if Data.JSONType = jtNumber then
    Result := Data.AsInteger
  else if Data.JSONType = jtString then
    Result := StrToIntDef(Data.AsString, Default);
end;

procedure ApplyConfigFile(var Config: TConfig; const FileName: string; ExplicitFile: Boolean);
var
  Root: TJSONData;
  Obj: TJSONObject;
begin
  if FileName = '' then
    Exit;
  if not FileExists(FileName) then
  begin
    if ExplicitFile then
      raise Exception.CreateFmt('config file does not exist: %s', [FileName]);
    Exit;
  end;

  Root := GetJSON(ReadTextFile(FileName));
  try
    if not (Root is TJSONObject) then
      raise Exception.Create('config file must contain a JSON object');
    Obj := TJSONObject(Root);
    Config.AccessToken := JSONStrField(Obj, 'accessToken', Config.AccessToken);
    Config.LogoSize := JSONIntField(Obj, 'logoSize', Config.LogoSize);
    Config.ScoreCount := JSONIntField(Obj, 'scoreCount', Config.ScoreCount);
  finally
    Root.Free;
  end;
end;

procedure ApplyEnv(var Config: TConfig);
var
  Value: string;
begin
  Value := GetEnvFirst(['MAITEA_TOKEN', 'MAIFETCH_TOKEN']);
  if Value <> '' then
    Config.AccessToken := Value;

  Value := GetEnvFirst(['MAITEA_LOGO_SIZE', 'MAIFETCH_LOGO_SIZE']);
  if Value <> '' then
    Config.LogoSize := StrToIntDef(Value, Config.LogoSize);

  Value := GetEnvFirst(['MAITEA_SCORE_COUNT', 'MAIFETCH_SCORE_COUNT']);
  if Value <> '' then
    Config.ScoreCount := StrToIntDef(Value, Config.ScoreCount);
end;

procedure ApplyCommandLine(var Config: TConfig);
var
  I: Integer;
  Arg: string;

  function ReadValue: string;
  begin
    if I = ParamCount then
      raise Exception.CreateFmt('%s requires a value', [Arg]);
    Inc(I);
    Result := ParamStr(I);
  end;

begin
  I := 1;
  while I <= ParamCount do
  begin
    Arg := ParamStr(I);
    if (Arg = '--help') or (Arg = '-h') then
    begin
      WriteLn('Usage: maifetch [--access-token TOKEN] [--logo-size N] [--score-count N] [--config-file FILE]');
      WriteLn('       maifetch --profile-fixture FILE --plays-fixture FILE [--logo-size 0]');
      Halt(0);
    end
    else if StartsWithText(Arg, '--access-token=') then
      Config.AccessToken := Copy(Arg, 16, MaxInt)
    else if (Arg = '--access-token') or (Arg = '-a') or (Arg = '-t') then
      Config.AccessToken := ReadValue
    else if StartsWithText(Arg, '--logo-size=') then
      Config.LogoSize := StrToIntDef(Copy(Arg, 13, MaxInt), Config.LogoSize)
    else if (Arg = '--logo-size') or (Arg = '-l') then
      Config.LogoSize := StrToIntDef(ReadValue, Config.LogoSize)
    else if StartsWithText(Arg, '--score-count=') then
      Config.ScoreCount := StrToIntDef(Copy(Arg, 15, MaxInt), Config.ScoreCount)
    else if (Arg = '--score-count') or (Arg = '-s') then
      Config.ScoreCount := StrToIntDef(ReadValue, Config.ScoreCount)
    else if StartsWithText(Arg, '--config-file=') then
      Config.ConfigFile := Copy(Arg, 15, MaxInt)
    else if (Arg = '--config-file') or (Arg = '-c') then
      Config.ConfigFile := ReadValue
    else if StartsWithText(Arg, '--profile-fixture=') then
      Config.ProfileFixture := Copy(Arg, 19, MaxInt)
    else if Arg = '--profile-fixture' then
      Config.ProfileFixture := ReadValue
    else if StartsWithText(Arg, '--plays-fixture=') then
      Config.PlaysFixture := Copy(Arg, 17, MaxInt)
    else if Arg = '--plays-fixture' then
      Config.PlaysFixture := ReadValue
    else
      raise Exception.CreateFmt('unknown argument: %s', [Arg]);
    Inc(I);
  end;
end;

function LoadConfig: TConfig;
var
  ExplicitConfigFile: string;
  EnvConfigFile: string;
begin
  Result.AccessToken := '';
  Result.LogoSize := 20;
  Result.ScoreCount := 4;
  Result.ProfileFixture := '';
  Result.PlaysFixture := '';

  ExplicitConfigFile := FindArgValue('--config-file', '-c');
  EnvConfigFile := GetEnvFirst(['MAITEA_CONFIG_FILE', 'MAIFETCH_CONFIG_FILE']);
  if ExplicitConfigFile <> '' then
    Result.ConfigFile := ExplicitConfigFile
  else if EnvConfigFile <> '' then
    Result.ConfigFile := EnvConfigFile
  else
    Result.ConfigFile := DefaultConfigFile;

  ApplyConfigFile(Result, Result.ConfigFile, ExplicitConfigFile <> '');
  ApplyEnv(Result);
  ApplyCommandLine(Result);

  if Result.ScoreCount < 1 then
    Result.ScoreCount := 1;
  if Result.ScoreCount > 12 then
    raise Exception.Create('score count cannot be higher than 12');

  if (Result.ProfileFixture = '') and (Result.PlaysFixture = '') and (Result.AccessToken = '') then
    raise Exception.Create('access token is required');
end;

function HTTPGetText(const PathOrURL, Token: string): string;
var
  Client: TFPHTTPClient;
  URL: string;
begin
  if StartsWithText(PathOrURL, 'http://') or StartsWithText(PathOrURL, 'https://') then
    URL := PathOrURL
  else
    URL := BaseURL + PathOrURL;

  Client := TFPHTTPClient.Create(nil);
  try
    Client.ConnectTimeout := 30000;
    Client.IOTimeout := 30000;
    Client.AddHeader('Authorization', 'Bearer ' + Token);
    Client.AddHeader('Accept', 'application/json');
    Client.AddHeader('Content-Type', 'application/json');
    Result := Client.Get(URL);
  finally
    Client.Free;
  end;
end;

function ParseProfiles(const JSONText: string): TProfile;
var
  Root: TJSONData;
  Data: TJSONData;
  Profiles: TJSONArray;
  Obj: TJSONObject;
  PlayStats: TJSONObject;
  Options: TJSONObject;
  Icon: TJSONObject;
begin
  Root := GetJSON(JSONText);
  try
    if not (Root is TJSONObject) then
      raise Exception.Create('profile response must be a JSON object');
    Data := TJSONObject(Root).Find('data');
    if not (Data is TJSONArray) then
      raise Exception.Create('profile response missing data array');
    Profiles := TJSONArray(Data);
    if Profiles.Count = 0 then
      raise Exception.Create('No profiles found');

    Obj := TJSONObject(Profiles.Items[0]);
    Result.Id := JSONIntField(Obj, 'id', 0);
    Result.Name := JSONStrField(Obj, 'name', '');
    Result.Rating := JSONIntField(Obj, 'rating', 0);
    Result.RatingHighest := JSONIntField(Obj, 'rating_highest', 0);
    Result.Level := JSONIntField(Obj, 'level', 0);

    PlayStats := JSONObjField(Obj, 'play_stats');
    Result.PlayTotal := JSONIntField(PlayStats, 'total', 0);

    Options := JSONObjField(Obj, 'options');
    Icon := JSONObjField(Options, 'icon');
    Result.IconPng := JSONStrField(Icon, 'png', '');
  finally
    Root.Free;
  end;
end;

function ParsePlays(const JSONText: string): TPlayArray;
var
  Root: TJSONData;
  Data: TJSONData;
  Plays: TJSONArray;
  Obj: TJSONObject;
  Song: TJSONObject;
  SongName: TJSONObject;
  DifficultyLevel: TJSONObject;
  I: Integer;
  ParsedPlays: TPlayArray;
begin
  Root := GetJSON(JSONText);
  try
    if not (Root is TJSONObject) then
      raise Exception.Create('plays response must be a JSON object');
    Data := TJSONObject(Root).Find('data');
    if not (Data is TJSONArray) then
      raise Exception.Create('plays response missing data array');
    Plays := TJSONArray(Data);
    SetLength(ParsedPlays, Plays.Count);
    for I := 0 to Plays.Count - 1 do
    begin
      Obj := TJSONObject(Plays.Items[I]);
      Song := JSONObjField(Obj, 'song');
      SongName := JSONObjField(Song, 'name');
      DifficultyLevel := JSONObjField(Obj, 'difficulty_level');

      ParsedPlays[I].SongName := JSONStrField(SongName, 'en', '');
      ParsedPlays[I].Difficulty := JSONStrField(DifficultyLevel, 'value', '');
      ParsedPlays[I].ScoreFormatted := JSONStrField(Obj, 'score_formatted', '');
      ParsedPlays[I].AchievementFormatted := JSONStrField(Obj, 'achievement_formatted', '');
      ParsedPlays[I].Rank := JSONStrField(Obj, 'rank', '');
      ParsedPlays[I].FullComboLabel := JSONStrField(Obj, 'full_combo_label', '');
    end;
    Result := ParsedPlays;
  finally
    Root.Free;
  end;
end;

function ReadProfilesJSON(const Config: TConfig): string;
begin
  if Config.ProfileFixture <> '' then
    Result := ReadTextFile(Config.ProfileFixture)
  else
    Result := HTTPGetText('/api/v1/profiles', Config.AccessToken);
end;

function ReadPlaysJSON(const Config: TConfig): string;
begin
  if Config.PlaysFixture <> '' then
    Result := ReadTextFile(Config.PlaysFixture)
  else
    Result := HTTPGetText('/api/v1/plays', Config.AccessToken);
end;

function LogoToAscii(const URL: string; LogoSize: Integer; out Lines: TStringArray; out ErrorMessage: string): Boolean;
const
  Scale = '@%#*+=-:. ';
var
  Client: TFPHTTPClient;
  Stream: TMemoryStream;
  Image: TFPMemoryImage;
  ReaderPNG: TFPReaderPNG;
  ReaderJPEG: TFPReaderJPEG;
  Width: Integer;
  Height: Integer;
  X: Integer;
  Y: Integer;
  SrcX: Integer;
  SrcY: Integer;
  Lum: Integer;
  ScaleIndex: Integer;
  Pixel: TFPColor;
  Line: string;
begin
  Result := False;
  ErrorMessage := '';
  SetLength(Lines, 0);
  if (URL = '') or (LogoSize <= 0) then
    Exit;

  Width := LogoSize * 2;
  Height := LogoSize;
  Stream := TMemoryStream.Create;
  Client := TFPHTTPClient.Create(nil);
  Image := TFPMemoryImage.Create(0, 0);
  try
    try
      Client.ConnectTimeout := 30000;
      Client.IOTimeout := 30000;
      Client.Get(URL, Stream);
      Stream.Position := 0;

      ReaderPNG := TFPReaderPNG.Create;
      try
        try
          Image.LoadFromStream(Stream, ReaderPNG);
        except
          Stream.Position := 0;
          ReaderJPEG := TFPReaderJPEG.Create;
          try
            Image.LoadFromStream(Stream, ReaderJPEG);
          finally
            ReaderJPEG.Free;
          end;
        end;
      finally
        ReaderPNG.Free;
      end;

      SetLength(Lines, Height);
      for Y := 0 to Height - 1 do
      begin
        Line := '';
        for X := 0 to Width - 1 do
        begin
          SrcX := (X * Image.Width) div Width;
          SrcY := (Y * Image.Height) div Height;
          if SrcX >= Image.Width then
            SrcX := Image.Width - 1;
          if SrcY >= Image.Height then
            SrcY := Image.Height - 1;
          Pixel := Image.Colors[SrcX, SrcY];
          Lum := (Integer(Pixel.Red) * 30 + Integer(Pixel.Green) * 59 + Integer(Pixel.Blue) * 11) div 100;
          ScaleIndex := (Lum * (Length(Scale) - 1)) div 65535 + 1;
          Line := Line + Scale[ScaleIndex];
        end;
        Lines[Y] := Line;
      end;
      Result := True;
    except
      on E: Exception do
      begin
        ErrorMessage := E.Message;
        SetLength(Lines, 0);
      end;
    end;
  finally
    Image.Free;
    Client.Free;
    Stream.Free;
  end;
end;

function CreateInfoLines(const Profile: TProfile; const Plays: TPlayArray; ScoreCount: Integer): TStringArray;
var
  Count: Integer;
  I: Integer;
  FCLabel: string;
  Lines: TStringArray;
begin
  Count := Min(ScoreCount, Length(Plays));
  SetLength(Lines, 7 + Count * 3);
  Lines[0] := Colour(Profile.Name);
  Lines[1] := StringOfChar('-', Length(Profile.Name));
  Lines[2] := Format('%s: %d', [Colour('ID'), Profile.Id]);
  Lines[3] := Format('%s: %.2f / %.2f', [Colour('Rating'), Profile.Rating / 100.0, Profile.RatingHighest / 100.0]);
  Lines[4] := Format('%s: %d', [Colour('Level'), Profile.Level]);
  Lines[5] := Format('%s: %d', [Colour('Total Credits'), Profile.PlayTotal]);
  Lines[6] := Format('%s:', [Colour('Recent Scores')]);

  for I := 0 to Count - 1 do
  begin
    FCLabel := Plays[I].FullComboLabel;
    Lines[7 + I * 3] := Format('  %s  %s', [Plays[I].SongName, DifficultyString(Plays[I].Difficulty)]);
    Lines[7 + I * 3 + 1] := Format('  %s %s%% %s %s', [Plays[I].ScoreFormatted, Plays[I].AchievementFormatted, RankString(Plays[I].Rank), FCLabel]);
    Lines[7 + I * 3 + 2] := '';
  end;
  Result := Lines;
end;

procedure PrintCombined(const InfoLines, LogoLines: TStringArray; LogoSize: Integer);
var
  MaxLength: Integer;
  I: Integer;
  LogoStr: string;
  InfoStr: string;
begin
  MaxLength := Length(LogoLines);
  if Length(InfoLines) > MaxLength then
    MaxLength := Length(InfoLines);

  for I := 0 to MaxLength - 1 do
  begin
    LogoStr := StringOfChar(' ', LogoSize * 2);
    InfoStr := '';
    if I < Length(LogoLines) then
      LogoStr := LogoLines[I];
    if I < Length(InfoLines) then
      InfoStr := InfoLines[I];
    WriteLn(LogoStr, '  ', InfoStr);
  end;
end;

procedure OutputProfile(const Profile: TProfile; const Plays: TPlayArray; const Config: TConfig);
var
  InfoLines: TStringArray;
  LogoLines: TStringArray;
  ErrorMessage: string;
  I: Integer;
begin
  InfoLines := CreateInfoLines(Profile, Plays, Config.ScoreCount);
  if Config.LogoSize > 0 then
  begin
    if LogoToAscii(Profile.IconPng, Config.LogoSize, LogoLines, ErrorMessage) then
      PrintCombined(InfoLines, LogoLines, Config.LogoSize)
    else
    begin
      WriteLn('could not render logo: ', ErrorMessage);
      for I := 0 to Length(InfoLines) - 1 do
        WriteLn(InfoLines[I]);
    end;
  end
  else
  begin
    for I := 0 to Length(InfoLines) - 1 do
      WriteLn(InfoLines[I]);
  end;
end;

var
  Config: TConfig;
  Profile: TProfile;
  Plays: TPlayArray;

begin
  try
    Config := LoadConfig;
    Profile := ParseProfiles(ReadProfilesJSON(Config));
    Plays := ParsePlays(ReadPlaysJSON(Config));
    OutputProfile(Profile, Plays, Config);
  except
    on E: Exception do
    begin
      WriteLn(E.Message);
      Halt(1);
    end;
  end;
end.
