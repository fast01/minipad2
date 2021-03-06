unit UDictionary;

interface

uses Windows, UxlStrUtils, UxlMath, UxlFunctions, UxlClasses, UxlList, UxlExtClasses, UxlWindow, UxlMiscCtrls, UxlWinClasses;

type
   TDictOptions = record
      AllDictList: widestring;
      SelDictList: widestring;
      MultiDict: boolean;
      DebugMode: boolean;
   end;

   TCaseType = (ctNone, ctPureLower, ctFirstUpper, ctPureUpper);
   TDictType = (dtFit, dtRange);

   TDictionary = class
   private
//      FMultiDict: boolean;
      FDictList: TxlStrList;
      FDebugMode: boolean;
//      procedure f_raiseerror(const s_msg: widestring = 'not found!');
      function f_SearchDict (var s_expr, s_dict: widestring; i_searchtype: TDictType; var ct: TCaseType): widestring;
   public
      constructor Create ();
      destructor Destroy (); override;
      procedure SetOptions (const value: TDictOptions);
      procedure Calc (s_expr: widestring; o_result: TxlStrList; b_multidict: boolean);
   end;

   TTipQuery = class (TxlInterfacedObject, IOptionObserver, IHotkeyOwner)
   private
   	FParent: TxlWindow;
      FDictionary: TDictionary;
      FTip: TxlTrackingTip;
   public
   	constructor Create (WndParent: TxlWindow);
      destructor Destroy (); override;
      procedure OnHotkey (id: integer; hk: THotkey);
      procedure OptionChanged ();
   end;

implementation

uses SysUtils, UxlFile, UGlobalObj, UOptionManager, UxlCommDlgs, Resource;

constructor TDictionary.Create ();
begin
   FDictList := TxlStrList.Create ();
   FDictList.Separator := ',';
end;

destructor TDictionary.Destroy ();
begin
   FDictList.Free;
   inherited;
end;

procedure TDictionary.SetOptions (const value: TDictOptions);
begin
//   FMultiDict := value.MultiDict;
   FDictList.Text := value.SelDictList;
   FDebugMode := value.DebugMode;
end;

function GetDictType (var s: widestring): TDictType;
begin
	result := dtFit;
   if s = '' then exit;
	if s[1] = '@' then
   	s := MidStr (s, 2)
   else if s[1] = '$' then
   begin
   	result := dtRange;
      s := MidStr (s, 2);
   end;
end;

procedure TDictionary.Calc (s_expr: widestring; o_result: TxlStrList; b_multidict: boolean);
   function IsEnglishWord (const s: widestring): boolean;
   var i: integer;
   begin
      result := true;
      for i := 1 to length(s) do
         if not ( (Ord(s[i]) in [65..90]) or (Ord(s[i]) in [97..122]) ) then
         begin
            result := false;
            exit;
         end;
   end;
var i, j: integer;
//   o_result: TxlStrList;
   s, s_expr2, s_dict: widestring;
   ct, ct2: TCaseType;
   dt: TDictType;
   o_list: TxlStrList;
begin
	o_result.Clear;
   if FDictList.Count = 0 then
   begin
      o_result.Add ('no dictionary configured!');
      exit;
   end;

 	dt := GetDictType (s_expr);
	if s_expr = '' then exit;

   if not IsEnglishWord(s_expr) then  //非英文单词, 或英文词组
      ct := ctNone
   else if lowercase(s_expr) = s_expr then
      ct := ctPureLower    //纯小写
   else if uppercase(s_expr) = s_expr then
      ct := ctPureUpper     //纯大写
   else
   begin    //对于其它形态的英文单词，统一为首字母大写
      s_expr := uppercase (s_expr[1]) + lowercase (MidStr(s_expr, 2));
      ct := ctFirstUpper;
   end;

   o_list := TxlStrList.Create();
   for i := FDictList.Low to FDictList.High do
   begin
      s_expr2 := s_expr;
      ct2 := ct;
      s_dict := DictDir + FDictList[i];
      s := f_SearchDict (s_expr2, s_dict, dt, ct2);
      if s <> '' then
      begin
         if ct2 <> ct then s := '(' + s_expr2 + ') ' + s;
         if b_MUltiDict then s := '[' + s_dict + '] ' + s;
			o_list.Text := s;
         for j := o_list.Low to o_list.High do
         	o_result.Add(o_list[j]);
         if not b_Multidict then break;
      end;
   end;
   o_list.Free;

   if o_result.Count = 0 then
   	o_result.Add ('not found!');
//   result := o_result.Text;
//   if result = '' then
//      result := 'not found!';
//   if FMultiDict then result := result + #13#10;
//    o_result.free;
end;

function TDictionary.f_SearchDict (var s_expr, s_dict: widestring; i_searchtype: TDictType; var ct: TCaseType): widestring;
   function f_Search (const s_expr: widestring; o_file: TxlTExtFile; dt: TDictType; var s_result: widestring): boolean;
   var i_low, i_high, i_start, i_cursor, i_pos: cardinal;
		w: widechar;
      s, s_word1, s_word2: widestring;
      b_returnpassed, b_tabpassed: boolean;
      cr: TCompareResult;
      s_log: widestring;
      p: widestring;
   label found_a_word;
   const cSmallRange = 61440;
   begin
      result := false;
      if o_file.TextCount <= 0 then exit;

      i_low := 0;
      i_high := o_file.TextCount - 1;
      s_log := '';
      repeat
         if i_high - i_low > cSmallRange then   // 在范围很小时不再折半，而是逐次查找。
      	   i_start := (i_high + i_low) div 2   // 确保不在双字节的中间
         else if dt = dtFit then   // 此部分算法增加对于中文词语不严格排序的容错性
         begin
//         	p := AllocMem (i_high - i_low + 2) * 2;
            o_file.CharIndex := i_low;
            o_file.ReadText (p, i_high - i_low);
            s := #13#10 + s_expr + #9;
           	i_pos := Pos (s, p);
            if i_pos > 0 then
            begin
               result := true;
               o_file.CharIndex := i_low + (i_pos + length(s) - 1);
               s_result := '';
               while not o_file.EOF do
               begin
                  o_file.Read(@w, 2);
                  if w = #13 then
                     break
                  else
                     s_result := s_result + w;
               end;
				end;
//            FreeMem (p, i_high - i_low + 2);
            if FDebugMode then ShowMessage (s_log);
				exit;
         end
         else
            i_start := i_low;

         o_file.CharIndex := i_start;
         b_returnpassed := false;
         b_tabpassed := false;
         s_word1 := '';
         s_word2 := '';
         i_cursor := i_start;
         repeat
         	o_file.Read(@w, 2);
            inc (i_cursor);
            case w of
            	#13, #10, #11:
                  begin
                     i_start := i_cursor;
                     b_returnpassed := true;
                  end;
            	#9:
               	if b_returnpassed then
                  begin
                     if b_tabpassed or (dt = dtFit) then
                        goto found_a_word
                     else
                        b_tabpassed := true;
                  end;
               else
                  if b_returnpassed then
                  begin
                     if b_tabpassed then
                        s_word2 := s_word2 + w
                     else
                        s_word1 := s_word1 + w;
                  end;
            end;
         until i_cursor > i_high;
         break;  // not found!     or (s_word1 = s_oldword1)
//         s_oldword1 := s_word1;

found_a_word:
         if dt = dtFit then
				cr := UxlStrUtils.CompareStr (s_expr, s_word1)
         else
         begin
         	if (s_expr >= s_word1) and (s_expr <= s_word2) then
            	cr := crEqual
            else if s_expr < s_word1 then
            	cr := crSmaller
            else
            	cr := crLarger;
         end;

         case cr of
         	crEqual:
               begin
               	result := true;
               	s_result := '';
                  while not o_file.EOF do
                  begin
                     o_file.Read(@w, 2);
                     if w = #13 then
                        break
                     else
                        s_result := s_result + w;
                  end;
               end;
         	crSmaller:
            	begin
            		i_high := i_start;
               	if FDebugMode then s_log := s_log + #13#10 + s_expr + ' < ' + s_word1 + ' ' + s_word2;
               end;
            crLarger:
            	begin
            		i_low := i_cursor;
               	if FDebugMode then s_log := s_log + #13#10 + s_expr + ' > ' + s_word1 + ' ' + s_word2;
            	end;
         end;
//         inc (i_count);
      until ((cr = crEqual) or (i_high - i_low <= 2));  // or (i_count > 100);

      if FDebugMode then ShowMessage (s_log);
   end;

   procedure f_SwitchCaseType (var s_expr: widestring; var ct: TCaseType);
   begin
      case ct of
         ctPureLower:
            begin
               s_expr := uppercase(s_expr[1]) + lowercase(MidStr(s_expr, 2));  //纯小写-->首字母大写
               ct := ctFirstUpper;
            end;
         ctFirstUpper:
            begin
               s_expr := uppercase (s_expr);
               ct := ctPureUpper;
            end;
         ctPureUpper:
            begin
               s_expr := lowercase (s_expr);
               ct := ctPureLower;
            end;
      end;
   end;

var o_file: TxlTextFile;
   ctOriginal: TCaseType;
   n: integer;
   dtDict: TDictType;
begin
   result := '';
   if not PathFileExists (s_dict) then exit;

   o_file := TxlTextFile.Create (s_dict, fmRead, enUTF16LE);
   o_file.ReadLn (s_dict);
   n := firstpos ('//', s_dict);
   if n > 0 then s_dict := leftstr (s_dict, n - 1);
   s_dict := trim (s_dict);
   dtDict := GetDictType (s_dict);
   if dtDict = i_searchtype then
	begin
      ctOriginal := ct;
      while not f_Search (s_expr, o_file, i_searchtype, result) do
      begin
         f_SwitchCaseType (s_expr, ct);
         if ct = ctOriginal then break;
      end;
      result := ReplaceStr (result, '\n', #13#10#9);
//      result := ReplaceStr (result, '|', '; ');
//      result := ReplaceStr (result, #9, ' ');
   end;
   o_file.free;
end;

//-----------------------

constructor TTipQuery.Create (WndParent: TxlWindow);
begin
	FParent := WndParent;
   FDictionary := TDictionary.Create ();

   FTip := TxlTrackingTip.Create (WndParent);
   FTip.TipWidth := 400;
   FTip.HideWhenCursorMove := true;

   OptionMan.AddObserver (self);
end;

destructor TTipQuery.Destroy ();
begin
   OptionMan.RemoveObserver (self);
   HotkeyCenter.RemoveOwner (self);
   FTip.Free;
	FDictionary.Free;
   inherited;
end;

procedure TTipQuery.OnHotkey (id: integer; hk: THotkey);
var s, s2: widestring;
   hfor: HWND;
   o_list: TxlStrList;
   o_clip: TxlClipboard;
begin
   ReleaseHotKey (hk);
   hfor := GetforegroundWindow;
   if hfor = FParent.handle then
   begin
      EventMan.EventNotify (e_GetEditorSelText);
      s := Trim(EventMan.Message);
   end
   else
   begin
   	o_clip := TxlClipboard.Create (hfor);
      o_clip.Text := '';
      ClipWatcher.PassNext;
      PressCombineKey ('C', VK_CONTROL);
      s := Trim(o_clip.Text);
   	o_clip.free;
   end;

   if (s = '') then
      FTip.HideTip
   else
   begin
      o_list := TxlStrList.Create;
      FDictionary.Calc (s, o_list, true);
      s2 := o_list.Text;
      o_list.Free;
      FTip.ShowTip (s2, s + ':');
      ClipWatcher.PassNext;
      Clipboard.Text := s + ':' + #13#10 + s2;
   end;
end;

procedure TTipQuery.OptionChanged ();
begin
	FDictionary.SetOptions (OptionMan.Options.DictOptions);
   FTip.Color := OptionMan.Options.TipQueryColor;
	HotkeyCenter.AddHotKey (self, 0, OptionMan.Options.TipQueryHotKey);
end;

end.


